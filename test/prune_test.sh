#!/usr/bin/env bash
# Tests for prune.sh: age-based, count-based, combined, validation, no-op cases.

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${TEST_DIR}/lib/setup.sh"

run_prune() {
  bash "${REPO_DIR}/scripts/run.sh"
}

mk_listing() {
  # Args: pairs of "ISO_TIMESTAMP key" lines
  local f
  f="$(mktemp)"
  while [ $# -gt 0 ]; do
    printf '%s\n' "$1" >> "$f"
    shift
  done
  printf '%s' "$f"
}

# --- Case: requires at least one retention input
reset_state
export OPERATION="prune" R2_BUCKET="b"
output=$(run_prune 2>&1); rc=$?
assert_exit_nonzero "$rc" "prune errors with no retention"
assert_contains "$output" "retention" "error mentions retention"

# --- Case: count-based, keep newest 2 of 4
reset_state
export OPERATION="prune" R2_BUCKET="b" R2_PREFIX="d/" R2_RETENTION_COUNT="2"
LISTING="$(mk_listing \
  "$(printf '2026-01-01T00:00:00.000Z\td/a.tgz')" \
  "$(printf '2026-02-01T00:00:00.000Z\td/b.tgz')" \
  "$(printf '2026-03-01T00:00:00.000Z\td/c.tgz')" \
  "$(printf '2026-04-01T00:00:00.000Z\td/d.tgz')")"
export R2_MOCK_LISTING_TEXT="$LISTING"
output=$(run_prune 2>&1); rc=$?
assert_exit_zero "$rc" "count-based prune succeeds"
assert_eq "$(gh_output pruned-count)" "2" "deleted 2 oldest (kept newest 2 of 4)"
assert_contains "$(cat "$R2_MOCK_LOG")" "d/a.tgz" "deleted oldest"
assert_contains "$(cat "$R2_MOCK_LOG")" "d/b.tgz" "deleted second oldest"
assert_not_contains "$(cat "$R2_MOCK_LOG")" "d/d.tgz" "did not delete newest"
rm -f "$LISTING"

# --- Case: age-based, cutoff at 30 days ago
reset_state
export OPERATION="prune" R2_BUCKET="b" R2_PREFIX="d/" R2_RETENTION_DAYS="30"
RECENT="$(date -u -d '5 days ago' +%Y-%m-%dT%H:%M:%S.000Z 2>/dev/null || date -u -v-5d +%Y-%m-%dT%H:%M:%S.000Z)"
OLD="$(date -u -d '90 days ago' +%Y-%m-%dT%H:%M:%S.000Z 2>/dev/null || date -u -v-90d +%Y-%m-%dT%H:%M:%S.000Z)"
LISTING="$(mk_listing \
  "$(printf '%s\td/old.tgz' "$OLD")" \
  "$(printf '%s\td/recent.tgz' "$RECENT")")"
export R2_MOCK_LISTING_TEXT="$LISTING"
output=$(run_prune 2>&1); rc=$?
assert_exit_zero "$rc" "age-based prune succeeds"
assert_eq "$(gh_output pruned-count)" "1" "deleted only the old object"
assert_contains "$(cat "$R2_MOCK_LOG")" "d/old.tgz" "deleted old"
assert_not_contains "$(cat "$R2_MOCK_LOG")" "d/recent.tgz" "kept recent"
rm -f "$LISTING"

# --- Case: invalid retention-days value
reset_state
export OPERATION="prune" R2_BUCKET="b" R2_RETENTION_DAYS="not-a-number"
output=$(run_prune 2>&1); rc=$?
assert_exit_nonzero "$rc" "invalid retention-days errors"
assert_contains "$output" "non-negative integer" "error mentions integer requirement"

# --- Case: empty bucket = no deletions
reset_state
export OPERATION="prune" R2_BUCKET="b" R2_PREFIX="empty/" R2_RETENTION_DAYS="30"
EMPTY_LISTING="$(mktemp)"
: > "$EMPTY_LISTING"
export R2_MOCK_LISTING_TEXT="$EMPTY_LISTING"
output=$(run_prune 2>&1); rc=$?
assert_exit_zero "$rc" "empty-bucket prune is a no-op"
assert_eq "$(gh_output pruned-count)" "0" "pruned-count = 0 on empty bucket"
rm -f "$EMPTY_LISTING"

# --- Case: combined rules dedupe deletions
reset_state
export OPERATION="prune" R2_BUCKET="b" R2_PREFIX="d/" R2_RETENTION_DAYS="30" R2_RETENTION_COUNT="1"
OLD="$(date -u -d '90 days ago' +%Y-%m-%dT%H:%M:%S.000Z 2>/dev/null || date -u -v-90d +%Y-%m-%dT%H:%M:%S.000Z)"
RECENT="$(date -u -d '5 days ago' +%Y-%m-%dT%H:%M:%S.000Z 2>/dev/null || date -u -v-5d +%Y-%m-%dT%H:%M:%S.000Z)"
LISTING="$(mk_listing \
  "$(printf '%s\td/old.tgz' "$OLD")" \
  "$(printf '%s\td/recent.tgz' "$RECENT")")"
export R2_MOCK_LISTING_TEXT="$LISTING"
output=$(run_prune 2>&1); rc=$?
assert_exit_zero "$rc" "combined prune succeeds"
# Age rule selects: old.tgz; count rule (keep 1) selects: old.tgz; union = 1 unique
assert_eq "$(gh_output pruned-count)" "1" "deduped to 1 deletion"
rm -f "$LISTING"
