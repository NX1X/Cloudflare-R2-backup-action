#!/usr/bin/env bash
# Tests for upload.sh: file copy, object-key derivation, size output, prune-on-upload.

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${TEST_DIR}/lib/setup.sh"

run_upload() {
  bash "${REPO_DIR}/scripts/run.sh"
}

# --- Case: simple upload, no prefix, no prune
reset_state
TMP_FILE="$(mktemp -t r2up.XXXXXX).tar.gz"
printf 'test-payload' > "$TMP_FILE"
export OPERATION="upload" R2_BUCKET="my-bucket" R2_FILE="$TMP_FILE"
export R2_MOCK_SIZE="42"
output=$(run_upload 2>&1); rc=$?
assert_exit_zero "$rc" "upload succeeds"
assert_eq "$(gh_output object-key)" "$(basename "$TMP_FILE")" "object-key = basename when no prefix"
assert_eq "$(gh_output size)" "42" "size output set from head-object"
assert_eq "$(gh_output pruned-count)" "0" "pruned-count is 0 with no retention"
assert_contains "$(cat "$R2_MOCK_LOG")" "s3 cp" "aws s3 cp was invoked"
rm -f "$TMP_FILE"

# --- Case: upload with prefix
reset_state
TMP_FILE="$(mktemp -t r2up.XXXXXX).tar.gz"
printf 'x' > "$TMP_FILE"
BASENAME="$(basename "$TMP_FILE")"
export OPERATION="upload" R2_BUCKET="my-bucket" R2_FILE="$TMP_FILE"
export R2_PREFIX="daily-backups"
export R2_MOCK_SIZE="100"
output=$(run_upload 2>&1); rc=$?
assert_exit_zero "$rc" "upload with prefix succeeds"
assert_eq "$(gh_output object-key)" "daily-backups/${BASENAME}" "object-key includes normalized prefix"
rm -f "$TMP_FILE"

# --- Case: explicit object-key overrides derived
reset_state
TMP_FILE="$(mktemp -t r2up.XXXXXX).tar.gz"
printf 'x' > "$TMP_FILE"
export OPERATION="upload" R2_BUCKET="my-bucket" R2_FILE="$TMP_FILE"
export R2_PREFIX="daily/" R2_OBJECT_KEY="custom/path/archive.tgz" R2_MOCK_SIZE="9"
output=$(run_upload 2>&1); rc=$?
assert_exit_zero "$rc" "upload with explicit key succeeds"
assert_eq "$(gh_output object-key)" "custom/path/archive.tgz" "explicit object-key overrides prefix derivation"
rm -f "$TMP_FILE"

# --- Case: missing file errors out
reset_state
export OPERATION="upload" R2_BUCKET="my-bucket" R2_FILE="/nonexistent/path.tgz"
output=$(run_upload 2>&1); rc=$?
assert_exit_nonzero "$rc" "upload errors on missing local file"
assert_contains "$output" "File not found" "missing file error message"

# --- Case: upload triggers inline prune when retention set
reset_state
TMP_FILE="$(mktemp -t r2up.XXXXXX).tar.gz"
printf 'x' > "$TMP_FILE"
export OPERATION="upload" R2_BUCKET="my-bucket" R2_FILE="$TMP_FILE"
export R2_PREFIX="daily/" R2_RETENTION_COUNT="1" R2_MOCK_SIZE="9"

# Mock listing: 3 objects, oldest first
LISTING_TEXT="$(mktemp)"
{
  printf '2026-01-01T00:00:00.000Z\tdaily/old-1.tgz\n'
  printf '2026-02-01T00:00:00.000Z\tdaily/old-2.tgz\n'
  printf '2026-05-01T00:00:00.000Z\tdaily/new.tgz\n'
} > "$LISTING_TEXT"
export R2_MOCK_LISTING_TEXT="$LISTING_TEXT"

output=$(run_upload 2>&1); rc=$?
assert_exit_zero "$rc" "upload+prune succeeds"
# Keep newest 1 means delete the 2 oldest
assert_eq "$(gh_output pruned-count)" "2" "pruned-count = 2 (kept newest 1 of 3)"
assert_contains "$(cat "$R2_MOCK_LOG")" "delete-object" "delete-object was invoked"

rm -f "$TMP_FILE" "$LISTING_TEXT"
