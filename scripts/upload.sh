#!/usr/bin/env bash
# Upload a single file to R2 under prefix. Optionally runs an inline prune
# after a successful upload (when retention-days or retention-count is set).
#
# Required env: R2_BUCKET, R2_FILE
# Optional env: R2_PREFIX, R2_OBJECT_KEY, R2_RETENTION_DAYS, R2_RETENTION_COUNT
# Inherited:    common.sh helpers, R2 endpoint env from r2-config.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh"

require_env R2_BUCKET
require_env R2_FILE

if [ ! -f "$R2_FILE" ]; then
  die "File not found: ${R2_FILE}"
fi

PREFIX_NORM="$(normalize_prefix "${R2_PREFIX:-}")"

if [ -n "${R2_OBJECT_KEY:-}" ]; then
  OBJECT_KEY="$R2_OBJECT_KEY"
else
  OBJECT_KEY="${PREFIX_NORM}$(basename "$R2_FILE")"
fi

S3_URI="s3://${R2_BUCKET}/${OBJECT_KEY}"

log_info "Uploading ${R2_FILE} -> ${S3_URI}"

aws s3 cp "$R2_FILE" "$S3_URI" --only-show-errors

# Resolve final size from the uploaded object (cross-platform; avoids stat differences).
SIZE=$(aws s3api head-object \
  --bucket "$R2_BUCKET" \
  --key "$OBJECT_KEY" \
  --query 'ContentLength' \
  --output text)

log_info "Uploaded: key=${OBJECT_KEY} size=${SIZE} bytes"

set_output "object-key" "$OBJECT_KEY"
set_output "size" "$SIZE"

# Optional inline prune. Defer to prune.sh so the logic lives in one place.
if [ -n "${R2_RETENTION_DAYS:-}" ] || [ -n "${R2_RETENTION_COUNT:-}" ]; then
  log_info "Running retention prune under prefix='${PREFIX_NORM}'"
  bash "${SCRIPT_DIR}/prune.sh"
else
  set_output "pruned-count" "0"
fi
