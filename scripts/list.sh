#!/usr/bin/env bash
# List objects under R2_PREFIX in the bucket. Emits a JSON array as the
# `objects` output, plus `count` and `total-size`.
#
# Required env: R2_BUCKET
# Optional env: R2_PREFIX, R2_MAX_KEYS

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh"

require_env R2_BUCKET

PREFIX_NORM="$(normalize_prefix "${R2_PREFIX:-}")"

MAX_KEYS_FLAG=()
if [ -n "${R2_MAX_KEYS:-}" ]; then
  if ! [[ "$R2_MAX_KEYS" =~ ^[0-9]+$ ]]; then
    die "max-keys must be a non-negative integer, got: '${R2_MAX_KEYS}'"
  fi
  MAX_KEYS_FLAG=(--max-items "$R2_MAX_KEYS")
fi

log_info "Listing s3://${R2_BUCKET}/${PREFIX_NORM}"

PREFIX_FLAG=()
if [ -n "$PREFIX_NORM" ]; then
  PREFIX_FLAG=(--prefix "$PREFIX_NORM")
fi

# JMESPath produces {"key": ..., "size": ..., "lastModified": ...} per object.
# When Contents is empty, AWS returns null; coerce to [] for stable JSON output.
RAW=$(aws s3api list-objects-v2 \
  --bucket "$R2_BUCKET" \
  "${PREFIX_FLAG[@]}" \
  "${MAX_KEYS_FLAG[@]}" \
  --query 'Contents[].{key: Key, size: Size, lastModified: LastModified}' \
  --output json)

# Normalize null -> []
if [ -z "$RAW" ] || [ "$RAW" = "null" ]; then
  RAW="[]"
fi

# Compute count and total-size without requiring jq.
COUNT=$(aws s3api list-objects-v2 \
  --bucket "$R2_BUCKET" \
  "${PREFIX_FLAG[@]}" \
  "${MAX_KEYS_FLAG[@]}" \
  --query 'length(Contents[] || `[]`)' \
  --output text 2>/dev/null || echo 0)

TOTAL_SIZE=$(aws s3api list-objects-v2 \
  --bucket "$R2_BUCKET" \
  "${PREFIX_FLAG[@]}" \
  "${MAX_KEYS_FLAG[@]}" \
  --query 'sum(Contents[].Size) || `0`' \
  --output text 2>/dev/null || echo 0)

# Strip a trailing ".0" that AWS sometimes returns for sums.
TOTAL_SIZE="${TOTAL_SIZE%.*}"

log_info "Found ${COUNT} object(s), total ${TOTAL_SIZE} bytes"

set_output_multiline "objects" "$RAW"
set_output "count" "$COUNT"
set_output "total-size" "$TOTAL_SIZE"
