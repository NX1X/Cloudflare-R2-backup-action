#!/usr/bin/env bash
# Common setup for unit tests. Each *_test.sh sources this:
#   . "${TEST_DIR}/lib/setup.sh"
#
# Provides: PASSES/FAILS counters, GITHUB_OUTPUT, R2_MOCK_LOG, baseline env,
# `reset_state` helper for multi-case test files, and an EXIT trap that
# prints `TEST_RESULT pass=N fail=M` for the harness.

# Resolve dirs relative to the calling test file.
TEST_DIR="${TEST_DIR:-$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)}"
REPO_DIR="${REPO_DIR:-$(cd "${TEST_DIR}/.." && pwd)}"
export TEST_DIR REPO_DIR

# Ensure mocks come first on PATH.
export PATH="${TEST_DIR}/mocks:${PATH}"

# shellcheck source=assert.sh
. "${TEST_DIR}/lib/assert.sh"

# Tempfiles for outputs and mock log.
GITHUB_OUTPUT="$(mktemp -t r2_gha_out.XXXXXX)"
R2_MOCK_LOG="$(mktemp -t r2_mock_log.XXXXXX)"
export GITHUB_OUTPUT R2_MOCK_LOG

# Baseline credentials (mocked - never sent anywhere).
export CF_ACCOUNT_ID="${CF_ACCOUNT_ID:-mockaccount}"
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-AKIAMOCK}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-mocksecret}"
export AWS_DEFAULT_REGION="auto"

# Reset state between cases in the same file.
reset_state() {
  : > "$GITHUB_OUTPUT"
  : > "$R2_MOCK_LOG"
  unset R2_PREFIX R2_FILE R2_OBJECT_KEY R2_RETENTION_DAYS R2_RETENTION_COUNT
  unset R2_VERIFY_MODE R2_VERIFY_CHECKSUM R2_MAX_KEYS R2_ENDPOINT_URL
  unset R2_MOCK_SIZE R2_MOCK_LISTING_TEXT R2_MOCK_LISTING_JSON
  unset R2_MOCK_COUNT R2_MOCK_TOTAL_SIZE R2_MOCK_FAIL
}

# Trap exit: report results and clean tempfiles.
_setup_cleanup() {
  printf 'TEST_RESULT pass=%d fail=%d\n' "${PASSES:-0}" "${FAILS:-0}"
  rm -f "$GITHUB_OUTPUT" "$R2_MOCK_LOG" 2>/dev/null || true
}
trap _setup_cleanup EXIT
