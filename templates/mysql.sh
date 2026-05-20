#!/usr/bin/env bash
# MySQL / MariaDB dump template.
#
# Required env (set by the calling workflow):
#   DB_USER
# Optional env:
#   DB_HOST                 (default: localhost)
#   DB_PORT                 (default: 3306)
#   DB_NAME                 (default: dump --all-databases)
#   DB_PASSWORD             (passed via MYSQL_PWD env var)
#   DUMP_BIN                (default: mysqldump; set to mariadb-dump for MariaDB)
#   DOCKER_COMPOSE_SERVICE  (if set, runs the dump inside `docker compose exec -T <service>`)
#   DOCKER_COMPOSE_DIR      (default: current dir; only used with DOCKER_COMPOSE_SERVICE)
#   ARCHIVE_PATH            (default: $HOME/backups)
#   ARCHIVE_NAME_PREFIX     (default: backup)
#   EXTRA_PATHS             (newline-separated paths to include alongside the dump)

set -euo pipefail

DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-3306}"
DUMP_BIN="${DUMP_BIN:-mysqldump}"
ARCHIVE_DIR="${ARCHIVE_PATH:-$HOME/backups}"
NAME_PREFIX="${ARCHIVE_NAME_PREFIX:-backup}"
TIMESTAMP=$(date -u +%Y%m%d_%H%M%S)
ARCHIVE="${ARCHIVE_DIR}/${NAME_PREFIX}_${TIMESTAMP}.tar.gz"
STAGING="${ARCHIVE_DIR}/upload"

if [ -z "${DB_USER:-}" ]; then
  echo "::error::mysql template requires DB_USER" >&2
  exit 1
fi

mkdir -p "$ARCHIVE_DIR" "$STAGING"

DUMP_ARGS=(--single-transaction --quick --lock-tables=false --default-character-set=utf8mb4)
if [ -z "${DB_NAME:-}" ]; then
  DUMP_ARGS+=(--all-databases)
fi

run_local_dump() {
  if [ -n "${DB_PASSWORD:-}" ]; then
    export MYSQL_PWD="$DB_PASSWORD"
  fi
  if [ -n "${DB_NAME:-}" ]; then
    "$DUMP_BIN" -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" "${DUMP_ARGS[@]}" "$DB_NAME"
  else
    "$DUMP_BIN" -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" "${DUMP_ARGS[@]}"
  fi
}

run_docker_dump() {
  cd "${DOCKER_COMPOSE_DIR:-.}"
  local env_args=()
  if [ -n "${DB_PASSWORD:-}" ]; then
    env_args+=(-e "MYSQL_PWD=$DB_PASSWORD")
  fi
  if [ -n "${DB_NAME:-}" ]; then
    docker compose exec -T "${env_args[@]}" "$DOCKER_COMPOSE_SERVICE" \
      "$DUMP_BIN" -u "$DB_USER" "${DUMP_ARGS[@]}" "$DB_NAME"
  else
    docker compose exec -T "${env_args[@]}" "$DOCKER_COMPOSE_SERVICE" \
      "$DUMP_BIN" -u "$DB_USER" "${DUMP_ARGS[@]}"
  fi
}

echo "Dumping MySQL/MariaDB ($DUMP_BIN)..." >&2
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

# Last line of stdout = path to the archive
echo "$ARCHIVE"
