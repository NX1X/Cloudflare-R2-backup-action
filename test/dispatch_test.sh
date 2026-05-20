#!/usr/bin/env bash
# Tests for run.sh dispatcher: validates input, dispatches operation, errors on bad input.

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${TEST_DIR}/lib/setup.sh"

run_dispatch() {
  bash "${REPO_DIR}/scripts/run.sh"
}

# --- Case: unknown operation exits non-zero
reset_state
export OPERATION="bogus" R2_BUCKET="fake-bucket"
output=$(run_dispatch 2>&1); rc=$?
assert_exit_nonzero "$rc" "unknown op exits non-zero"
assert_contains "$output" "Unknown operation" "unknown op error message"

# --- Case: missing OPERATION exits non-zero
reset_state
unset OPERATION
export R2_BUCKET="fake-bucket"
output=$(run_dispatch 2>&1); rc=$?
assert_exit_nonzero "$rc" "missing OPERATION exits non-zero"
assert_contains "$output" "OPERATION" "missing OPERATION error mentions input"

# --- Case: missing R2_BUCKET exits non-zero
reset_state
export OPERATION="upload"
unset R2_BUCKET
output=$(run_dispatch 2>&1); rc=$?
assert_exit_nonzero "$rc" "missing R2_BUCKET exits non-zero"

# --- Case: dispatch to upload (will fail at file check, but that proves dispatch worked)
reset_state
export OPERATION="upload" R2_BUCKET="fake-bucket"
unset R2_FILE
output=$(run_dispatch 2>&1); rc=$?
assert_exit_nonzero "$rc" "upload dispatch errors on missing file input"
assert_contains "$output" "R2_FILE" "upload validates R2_FILE"
