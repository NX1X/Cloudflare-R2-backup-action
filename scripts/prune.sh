#!/usr/bin/env bash
# Prune objects under R2_PREFIX by age (R2_RETENTION_DAYS) or by count
# (R2_RETENTION_COUNT). Both may be set; both are applied. Pruned-count is
# the union of deletions.
#
# Required env: R2_BUCKET
# Optional env: R2_PREFIX, R2_RETENTION_DAYS, R2_RETENTION_COUNT
# Inherited:    common.sh helpers (sourced by run.sh OR upload.sh)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh"

require_env R2_BUCKET

PREFIX_NORM="$(normalize_prefix "${R2_PREFIX:-}")"

if [ -z "${R2_RETENTION_DAYS:-}" ] && [ -z "${R2_RETENTION_COUNT:-}" ]; then
  die "prune requires at least one of: retention-days, retention-count"
fi

# Build a tab-separated listing of objects under the prefix:
#   <iso-timestamp>\t<key>
# Sorted oldest -> newest.
LISTING="$(mktemp)"
trap 'rm -f "$LISTING"' EXIT

log_info "Listing s3://${R2_BUCKET}/${PREFIX_NORM}"

# Use list-objects-v2 with --query for a stable, machine-readable shape.
# Empty prefix is allowed (lists the whole bucket).
aws s3api list-objects-v2 \
  --bucket "$R2_BUCKET" \
  ${PREFIX_NORM:+--prefix "$PREFIX_NORM"} \
  --query 'Contents[].[LastModified,Key]' \
  --output text \
  | sort > "$LISTING" || true

TOTAL=$(wc -l < "$LISTING" | tr -d ' ')
log_info "Found ${TOTAL} object(s) under prefix"

# Set of keys to delete (deduped via sort -u below).
TO_DELETE="$(mktemp)"
trap 'rm -f "$LISTING" "$TO_DELETE"' EXIT

# --- Age-based prune -------------------------------------------------------
if [ -n "${R2_RETENTION_DAYS:-}" ]; then
  if ! [[ "$R2_RETENTION_DAYS" =~ ^[0-9]+$ ]]; then
    die "retention-days must be a non-negative integer, got: '${R2_RETENTION_DAYS}'"
  fi
  CUTOFF_EPOCH=$(date -u -d "${R2_RETENTION_DAYS} days ago" +%s)
  log_info "Age prune: deleting objects older than ${R2_RETENTION_DAYS} days (cutoff epoch ${CUTOFF_EPOCH})"

  while IFS=$'\t' read -r ts key; do
    [ -z "${key:-}" ] && continue
    obj_epoch=$(date -u -d "$ts" +%s 2>/dev/null || echo 0)
    if [ "$obj_epoch" -gt 0 ] && [ "$obj_epoch" -lt "$CUTOFF_EPOCH" ]; then
      printf '%s\n' "$key" >> "$TO_DELETE"
    fi
  done < "$LISTING"
fi

# --- Count-based prune (keep newest N) -------------------------------------
if [ -n "${R2_RETENTION_COUNT:-}" ]; then
  if ! [[ "$R2_RETENTION_COUNT" =~ ^[0-9]+$ ]]; then
    die "retention-count must be a non-negative integer, got: '${R2_RETENTION_COUNT}'"
  fi
  KEEP="$R2_RETENTION_COUNT"
  log_info "Count prune: keeping newest ${KEEP} object(s)"

  if [ "$TOTAL" -gt "$KEEP" ]; then
    DROP_COUNT=$((TOTAL - KEEP))
    # LISTING is sorted oldest->newest; the first DROP_COUNT entries are oldest.
    head -n "$DROP_COUNT" "$LISTING" | awk -F'\t' '{print $2}' >> "$TO_DELETE"
  fi
fi

# --- Execute deletes -------------------------------------------------------
PRUNED=0
if [ -s "$TO_DELETE" ]; then
  # Dedupe in case both rules selected the same key.
  UNIQ_DELETE="$(mktemp)"
  trap 'rm -f "$LISTING" "$TO_DELETE" "$UNIQ_DELETE"' EXIT
  sort -u "$TO_DELETE" > "$UNIQ_DELETE"

  while IFS= read -r key; do
    [ -z "$key" ] && continue
    log_info "Deleting s3://${R2_BUCKET}/${key}"
    aws s3api delete-object --bucket "$R2_BUCKET" --key "$key" >/dev/null
    PRUNED=$((PRUNED + 1))
  done < "$UNIQ_DELETE"
fi

log_info "Pruned ${PRUNED} object(s)"
set_output "pruned-count" "$PRUNED"
