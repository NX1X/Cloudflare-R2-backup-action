#!/usr/bin/env bash
# SQLite hot backup template (uses sqlite3 .backup for safe online copy).
#
# Required env (set by the calling workflow):
#   DB_PATH     - absolute path to the .db / .sqlite file on the source
# Optional env:
#   ARCHIVE_PATH         (default: $HOME/backups)
#   ARCHIVE_NAME_PREFIX  (default: backup)
#   EXTRA_PATHS          (newline-separated paths to include alongside the dump)

set -euo pipefail

if [ -z "${DB_PATH:-}" ]; then
  echo "::error::sqlite template requires DB_PATH (absolute path to the database file)" >&2
  exit 1
fi
if [ ! -f "$DB_PATH" ]; then
  echo "::error::sqlite database file not found at: $DB_PATH" >&2
  exit 1
fi
if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "::error::sqlite3 binary not found on the source" >&2
  exit 1
fi

ARCHIVE_DIR="${ARCHIVE_PATH:-$HOME/backups}"
NAME_PREFIX="${ARCHIVE_NAME_PREFIX:-backup}"
TIMESTAMP=$(date -u +%Y%m%d_%H%M%S)
ARCHIVE="${ARCHIVE_DIR}/${NAME_PREFIX}_${TIMESTAMP}.tar.gz"
STAGING="${ARCHIVE_DIR}/upload"
DB_FILENAME="$(basename "$DB_PATH")"

mkdir -p "$ARCHIVE_DIR" "$STAGING"

echo "Backing up SQLite database $DB_PATH..." >&2
# .backup is the safe online-backup form (acquires a shared lock briefly,
# survives concurrent writes, produces a consistent point-in-time copy).
sqlite3 "$DB_PATH" ".backup '$STAGING/$DB_FILENAME'"

echo "Creating archive..." >&2
TAR_ARGS=(-czf "$ARCHIVE" -C "$STAGING" "$DB_FILENAME")
if [ -n "${EXTRA_PATHS:-}" ]; then
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    TAR_ARGS+=(-C "$(dirname "$path")" "$(basename "$path")")
  done <<< "$EXTRA_PATHS"
fi

tar "${TAR_ARGS[@]}"
rm -rf "$STAGING"

echo "$ARCHIVE"
