#!/usr/bin/env bash
# Tests for list.sh: empty prefix, populated prefix, count/total-size, JSON output.

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${TEST_DIR}/lib/setup.sh"

run_list() {
  bash "${REPO_DIR}/scripts/run.sh"
}

# --- Case: empty bucket
reset_state
export OPERATION="list" R2_BUCKET="b" R2_PREFIX="empty/"
EMPTY_JSON="$(mktemp)"
printf 'null' > "$EMPTY_JSON"
export R2_MOCK_LISTING_JSON="$EMPTY_JSON"
export R2_MOCK_COUNT="0" R2_MOCK_TOTAL_SIZE="0"
output=$(run_list 2>&1); rc=$?
assert_exit_zero "$rc" "list on empty prefix succeeds"
assert_eq "$(gh_output count)" "0" "count = 0 when empty"
assert_eq "$(gh_output total-size)" "0" "total-size = 0 when empty"
rm -f "$EMPTY_JSON"

# --- Case: populated listing
reset_state
export OPERATION="list" R2_BUCKET="b" R2_PREFIX="d/"
LIST_JSON="$(mktemp)"
cat > "$LIST_JSON" <<'JSON'
[
  {"key": "d/a.tgz", "size": 100, "lastModified": "2026-01-01T00:00:00.000Z"},
  {"key": "d/b.tgz", "size": 200, "lastModified": "2026-02-01T00:00:00.000Z"}
]
JSON
export R2_MOCK_LISTING_JSON="$LIST_JSON"
export R2_MOCK_COUNT="2" R2_MOCK_TOTAL_SIZE="300"
output=$(run_list 2>&1); rc=$?
assert_exit_zero "$rc" "list with content succeeds"
assert_eq "$(gh_output count)" "2" "count = 2"
assert_eq "$(gh_output total-size)" "300" "total-size = 300"
# Multi-line output read: re-read raw GITHUB_OUTPUT and check the JSON keys appear
raw=$(cat "$GITHUB_OUTPUT")
assert_contains "$raw" "d/a.tgz" "objects output contains key a"
assert_contains "$raw" "d/b.tgz" "objects output contains key b"
rm -f "$LIST_JSON"

# --- Case: invalid max-keys errors
reset_state
export OPERATION="list" R2_BUCKET="b" R2_MAX_KEYS="not-a-number"
output=$(run_list 2>&1); rc=$?
assert_exit_nonzero "$rc" "invalid max-keys errors"
assert_contains "$output" "max-keys" "error mentions max-keys"
