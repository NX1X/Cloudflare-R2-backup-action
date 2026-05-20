#!/usr/bin/env bash
# MongoDB dump template (mongodump --archive --gzip).
#
# Optional env:
#   DB_HOST                 (default: localhost)
#   DB_PORT                 (default: 27017)
#   DB_USER                 (optional)
#   DB_PASSWORD             (optional; passed to --password)
#   DB_NAME                 (if set, dump only that DB; else dump all)
#   DB_AUTH_DB              (default: admin; auth database)
#   DOCKER_COMPOSE_SERVICE  (if set, runs the dump inside `docker compose exec -T <service>`)
#   DOCKER_COMPOSE_DIR      (default: current dir; only used with DOCKER_COMPOSE_SERVICE)
#   ARCHIVE_PATH            (default: $HOME/backups)
#   ARCHIVE_NAME_PREFIX     (default: backup)
#   EXTRA_PATHS             (newline-separated paths to include alongside the dump)

set -euo pipefail

DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-27017}"
DB_AUTH_DB="${DB_AUTH_DB:-admin}"
ARCHIVE_DIR="${ARCHIVE_PATH:-$HOME/backups}"
NAME_PREFIX="${ARCHIVE_NAME_PREFIX:-backup}"
TIMESTAMP=$(date -u +%Y%m%d_%H%M%S)
ARCHIVE="${ARCHIVE_DIR}/${NAME_PREFIX}_${TIMESTAMP}.tar.gz"
STAGING="${ARCHIVE_DIR}/upload"

mkdir -p "$ARCHIVE_DIR" "$STAGING"

# Build mongodump args (without --archive - handled below).
MD_ARGS=(--host "$DB_HOST" --port "$DB_PORT")
if [ -n "${DB_USER:-}" ]; then
  MD_ARGS+=(--username "$DB_USER" --authenticationDatabase "$DB_AUTH_DB")
fi
if [ -n "${DB_NAME:-}" ]; then
  MD_ARGS+=(--db "$DB_NAME")
fi

run_local_dump() {
  local pw_args=()
  if [ -n "${DB_PASSWORD:-}" ]; then
    pw_args+=(--password "$DB_PASSWORD")
  fi
  mongodump "${MD_ARGS[@]}" "${pw_args[@]}" --archive --gzip
}

run_docker_dump() {
  cd "${DOCKER_COMPOSE_DIR:-.}"
  local pw_args=()
  if [ -n "${DB_PASSWORD:-}" ]; then
    pw_args+=(--password "$DB_PASSWORD")
  fi
  docker compose exec -T "$DOCKER_COMPOSE_SERVICE" \
    mongodump "${MD_ARGS[@]}" "${pw_args[@]}" --archive --gzip
}

echo "Dumping MongoDB..." >&2
if [ -n "${DOCKER_COMPOSE_SERVICE:-}" ]; then
  run_docker_dump > "$STAGING/dump.archive.gz"
else
  run_local_dump > "$STAGING/dump.archive.gz"
fi

echo "Creating archive..." >&2
# Use -czf for consistency with other templates and so the .tar.gz extension
# matches the actual file format. The inner dump.archive.gz is already gzipped
# (mongodump --gzip), so re-gzipping adds <1% overhead - accepted for uniform
# downstream handling (verify, list, scripts that assume .tar.gz).
TAR_ARGS=(-czf "$ARCHIVE" -C "$STAGING" dump.archive.gz)
if [ -n "${EXTRA_PATHS:-}" ]; then
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    TAR_ARGS+=(-C "$(dirname "$path")" "$(basename "$path")")
  done <<< "$EXTRA_PATHS"
fi

tar "${TAR_ARGS[@]}"
rm -rf "$STAGING"

echo "$ARCHIVE"
