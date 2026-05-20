#!/usr/bin/env bash
# PostgreSQL dump template.
#
# Required env (set by the calling workflow):
#   DB_USER
# Optional env:
#   DB_HOST                 (default: localhost)
#   DB_PORT                 (default: 5432)
#   DB_NAME                 (if set: pg_dump that DB; if unset: pg_dumpall)
#   DB_PASSWORD             (passed via PGPASSWORD env var)
#   DUMP_BIN                (override pg_dump or pg_dumpall path; rarely needed)
#   DOCKER_COMPOSE_SERVICE  (if set, runs the dump inside `docker compose exec -T <service>`)
#   DOCKER_COMPOSE_DIR      (default: current dir; only used with DOCKER_COMPOSE_SERVICE)
#   ARCHIVE_PATH            (default: $HOME/backups)
#   ARCHIVE_NAME_PREFIX     (default: backup)
#   EXTRA_PATHS             (newline-separated paths to include alongside the dump)

set -euo pipefail

DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
ARCHIVE_DIR="${ARCHIVE_PATH:-$HOME/backups}"
NAME_PREFIX="${ARCHIVE_NAME_PREFIX:-backup}"
TIMESTAMP=$(date -u +%Y%m%d_%H%M%S)
ARCHIVE="${ARCHIVE_DIR}/${NAME_PREFIX}_${TIMESTAMP}.tar.gz"
STAGING="${ARCHIVE_DIR}/upload"

if [ -z "${DB_USER:-}" ]; then
  echo "::error::postgres template requires DB_USER" >&2
  exit 1
fi

mkdir -p "$ARCHIVE_DIR" "$STAGING"

# Pick binary
if [ -n "${DUMP_BIN:-}" ]; then
  BIN="$DUMP_BIN"
elif [ -n "${DB_NAME:-}" ]; then
  BIN="pg_dump"
else
  BIN="pg_dumpall"
fi

run_local_dump() {
  if [ -n "${DB_PASSWORD:-}" ]; then
    export PGPASSWORD="$DB_PASSWORD"
  fi
  if [ -n "${DB_NAME:-}" ]; then
    "$BIN" -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" "$DB_NAME"
  else
    "$BIN" -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER"
  fi
}

run_docker_dump() {
  cd "${DOCKER_COMPOSE_DIR:-.}"
  local env_args=()
  if [ -n "${DB_PASSWORD:-}" ]; then
    env_args+=(-e "PGPASSWORD=$DB_PASSWORD")
  fi
  if [ -n "${DB_NAME:-}" ]; then
    docker compose exec -T "${env_args[@]}" "$DOCKER_COMPOSE_SERVICE" \
      "$BIN" -U "$DB_USER" "$DB_NAME"
  else
    docker compose exec -T "${env_args[@]}" "$DOCKER_COMPOSE_SERVICE" \
      "$BIN" -U "$DB_USER"
  fi
}

echo "Dumping PostgreSQL ($BIN)..." >&2
if [ -n "${DOCKER_COMPOSE_SERVICE:-}" ]; then
  run_docker_dump > "$STAGING/database.sql"
else
  run_local_dump > "$STAGING/database.sql"
fi

echo "Creating archive..." >&2
TAR_ARGS=(-czf "$ARCHIVE" -C "$STAGING" database.sql)
if [ -n "${EXTRA_PATHS:-}" ]; then
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    TAR_ARGS+=(-C "$(dirname "$path")" "$(basename "$path")")
  done <<< "$EXTRA_PATHS"
fi

tar "${TAR_ARGS[@]}"
rm -rf "$STAGING"

echo "$ARCHIVE"
