#!/usr/bin/env bash
# Download an object from R2 and verify its integrity.
#
# Modes:
#   tar     - gzip/bzip/uncompressed tarball; runs `tar -tzf` (or auto by extension)
#   zip     - runs `unzip -t`
#   sha256  - compares sha256sum to R2_VERIFY_CHECKSUM
#
# Required env: R2_BUCKET, R2_OBJECT_KEY, R2_VERIFY_MODE
# Optional env: R2_FILE (download target; default: temp file)
#               R2_VERIFY_CHECKSUM (required when mode=sha256)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh"

require_env R2_BUCKET
require_env R2_OBJECT_KEY
require_env R2_VERIFY_MODE

case "$R2_VERIFY_MODE" in
  tar|zip|sha256) ;;
  *) die "verify-mode must be one of: tar, zip, sha256 (got '${R2_VERIFY_MODE}')" ;;
esac

if [ "$R2_VERIFY_MODE" = "sha256" ] && [ -z "${R2_VERIFY_CHECKSUM:-}" ]; then
  die "verify-mode=sha256 requires verify-checksum input"
fi

# Resolve download target.
if [ -n "${R2_FILE:-}" ]; then
  TARGET="$R2_FILE"
  CLEANUP=""
else
  TARGET="$(mktemp -t r2verify.XXXXXX)"
  CLEANUP="$TARGET"
fi
# shellcheck disable=SC2064
trap "[ -n '${CLEANUP}' ] && rm -f '${CLEANUP}' || true" EXIT

S3_URI="s3://${R2_BUCKET}/${R2_OBJECT_KEY}"
log_info "Downloading ${S3_URI} -> ${TARGET}"

aws s3 cp "$S3_URI" "$TARGET" --only-show-errors

SIZE=$(wc -c < "$TARGET" | tr -d ' ')
log_info "Downloaded: size=${SIZE} bytes"

VERIFIED="false"

case "$R2_VERIFY_MODE" in
  tar)
    log_info "Running tar integrity check"
    if tar -tf "$TARGET" >/dev/null 2>&1; then
      VERIFIED="true"
      log_info "tar archive OK"
    else
      log_error "tar archive is corrupt or unreadable"
    fi
    ;;
  zip)
    if ! command -v unzip >/dev/null 2>&1; then
      die "unzip not found (required for verify-mode=zip)"
    fi
    log_info "Running zip integrity check"
    if unzip -t "$TARGET" >/dev/null 2>&1; then
      VERIFIED="true"
      log_info "zip archive OK"
    else
      log_error "zip archive is corrupt or unreadable"
    fi
    ;;
  sha256)
    if ! command -v sha256sum >/dev/null 2>&1; then
      die "sha256sum not found (required for verify-mode=sha256)"
    fi
    log_info "Comparing sha256 against expected checksum"
    ACTUAL=$(sha256sum "$TARGET" | awk '{print $1}')
    EXPECTED=$(printf '%s' "$R2_VERIFY_CHECKSUM" | tr '[:upper:]' '[:lower:]' | awk '{print $1}')
    if [ "$ACTUAL" = "$EXPECTED" ]; then
      VERIFIED="true"
      log_info "sha256 matches: ${ACTUAL}"
    else
      log_error "sha256 mismatch: expected=${EXPECTED} actual=${ACTUAL}"
    fi
    ;;
esac

set_output "verified" "$VERIFIED"
set_output "size" "$SIZE"
set_output "object-key" "$R2_OBJECT_KEY"

if [ "$VERIFIED" != "true" ]; then
  die "Integrity check FAILED (mode=${R2_VERIFY_MODE}, key=${R2_OBJECT_KEY})"
fi
