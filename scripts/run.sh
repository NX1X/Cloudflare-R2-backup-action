#!/usr/bin/env bash
# Entry point for Cloudflare-R2-backup-action.
# Dispatches to the operation script based on $OPERATION.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh"

require_env OPERATION
require_env R2_BUCKET

# shellcheck source=lib/r2-config.sh
. "${SCRIPT_DIR}/lib/r2-config.sh"

log_info "operation=${OPERATION} bucket=${R2_BUCKET} endpoint=${R2_ENDPOINT}"

case "$OPERATION" in
  upload)
    bash "${SCRIPT_DIR}/upload.sh"
    ;;
  prune)
    bash "${SCRIPT_DIR}/prune.sh"
    ;;
  verify)
    bash "${SCRIPT_DIR}/verify.sh"
    ;;
  list)
    bash "${SCRIPT_DIR}/list.sh"
    ;;
  *)
    die "Unknown operation: '${OPERATION}'. Expected one of: upload, verify, list, prune."
    ;;
esac
