#!/usr/bin/env bash
# Tests for notify.sh: status derivation, gating (on-success/on-failure),
# per-format payload shape, missing-URL skip, webhook failure isolation.

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${TEST_DIR}/lib/setup.sh"

chmod +x "${TEST_DIR}/mocks/curl" 2>/dev/null || true

# Skip everything if jq is unavailable (CI installs it; local dev may not).
if ! command -v jq >/dev/null 2>&1; then
  printf 'jq not found on PATH - skipping notify tests.\n' >&2
  printf 'TEST_RESULT pass=0 fail=0\n'
  exit 0
fi

CURL_PAYLOAD_FILE="$(mktemp -t r2_notify_payload.XXXXXX)"
export R2_MOCK_CURL_PAYLOAD="$CURL_PAYLOAD_FILE"

run_notify() {
  bash "${REPO_DIR}/scripts/notify.sh"
}

reset_notify_state() {
  reset_state
  : > "$CURL_PAYLOAD_FILE"
  unset NOTIFY_WEBHOOK_URL NOTIFY_FORMAT NOTIFY_ON_SUCCESS NOTIFY_ON_FAILURE
  unset BACKUP_RESULT VERIFY_RESULT
  unset NOTIFY_REPOSITORY NOTIFY_WORKFLOW NOTIFY_REF NOTIFY_RUN_URL
  unset NOTIFY_BUCKET NOTIFY_OBJECT_KEY NOTIFY_SIZE NOTIFY_PRUNED_COUNT NOTIFY_VERIFIED
  unset R2_MOCK_CURL_CODE R2_MOCK_CURL_FAIL
}

# --- Case: empty URL → skip cleanly, no curl invoked
reset_notify_state
export BACKUP_RESULT="failure"
output=$(run_notify 2>&1); rc=$?
assert_exit_zero "$rc" "empty URL: exit 0"
assert_contains "$output" "skipped" "empty URL: logs skip"
assert_not_contains "$(cat "$R2_MOCK_LOG")" "curl" "empty URL: no curl invocation"

# --- Case: missing BACKUP_RESULT → error
reset_notify_state
export NOTIFY_WEBHOOK_URL="https://example.com/hook"
output=$(run_notify 2>&1); rc=$?
assert_exit_nonzero "$rc" "missing BACKUP_RESULT: nonzero exit"
assert_contains "$output" "BACKUP_RESULT" "missing BACKUP_RESULT: useful error message"

# --- Case: invalid format → error
reset_notify_state
export NOTIFY_WEBHOOK_URL="https://example.com/hook" BACKUP_RESULT="success"
export NOTIFY_FORMAT="teams" NOTIFY_ON_SUCCESS="true"
output=$(run_notify 2>&1); rc=$?
assert_exit_nonzero "$rc" "invalid format: nonzero exit"
assert_contains "$output" "NOTIFY_FORMAT" "invalid format: error mentions format"

# --- Case: success + on-success=false → skip (default behavior)
reset_notify_state
export NOTIFY_WEBHOOK_URL="https://example.com/hook" BACKUP_RESULT="success"
output=$(run_notify 2>&1); rc=$?
assert_exit_zero "$rc" "success+on-success-false: exit 0"
assert_contains "$output" "skipped" "success+on-success-false: skipped log"
assert_not_contains "$(cat "$R2_MOCK_LOG")" "curl" "success+on-success-false: no curl"

# --- Case: success + on-success=true → curl called, generic payload
reset_notify_state
export NOTIFY_WEBHOOK_URL="https://example.com/hook" BACKUP_RESULT="success"
export NOTIFY_ON_SUCCESS="true" NOTIFY_FORMAT="generic"
export NOTIFY_REPOSITORY="owner/repo" NOTIFY_OBJECT_KEY="daily/backup_x.tar.gz"
export NOTIFY_SIZE="12345" NOTIFY_VERIFIED="skipped"
output=$(run_notify 2>&1); rc=$?
assert_exit_zero "$rc" "success+on-success-true: exit 0"
assert_contains "$(cat "$R2_MOCK_LOG")" "curl" "success+on-success-true: curl invoked"
assert_contains "$(cat "$CURL_PAYLOAD_FILE")" '"status":"success"' "generic payload: status field"
assert_contains "$(cat "$CURL_PAYLOAD_FILE")" '"repository":"owner/repo"' "generic payload: repository field"
assert_contains "$(cat "$CURL_PAYLOAD_FILE")" '"object_key":"daily/backup_x.tar.gz"' "generic payload: object_key field"
assert_contains "$(cat "$CURL_PAYLOAD_FILE")" '"verified":"skipped"' "generic payload: verified field"

# --- Case: failure (default on-failure=true) → curl called
reset_notify_state
export NOTIFY_WEBHOOK_URL="https://example.com/hook" BACKUP_RESULT="failure"
output=$(run_notify 2>&1); rc=$?
assert_exit_zero "$rc" "failure default: exit 0"
assert_contains "$(cat "$R2_MOCK_LOG")" "curl" "failure default: curl invoked"
assert_contains "$(cat "$CURL_PAYLOAD_FILE")" '"status":"failure"' "failure payload: status"
assert_contains "$(cat "$CURL_PAYLOAD_FILE")" '"failed_step":"backup (failure)"' "failure payload: failed_step identifies backup"

# --- Case: failure + on-failure=false → skip
reset_notify_state
export NOTIFY_WEBHOOK_URL="https://example.com/hook" BACKUP_RESULT="failure"
export NOTIFY_ON_FAILURE="false"
output=$(run_notify 2>&1); rc=$?
assert_exit_zero "$rc" "failure+on-failure-false: exit 0"
assert_not_contains "$(cat "$R2_MOCK_LOG")" "curl" "failure+on-failure-false: no curl"

# --- Case: backup success + verify failure → overall=failure with verify failed_step
reset_notify_state
export NOTIFY_WEBHOOK_URL="https://example.com/hook"
export BACKUP_RESULT="success" VERIFY_RESULT="failure"
output=$(run_notify 2>&1); rc=$?
assert_exit_zero "$rc" "verify failure: exit 0"
assert_contains "$(cat "$CURL_PAYLOAD_FILE")" '"status":"failure"' "verify failure: status=failure"
assert_contains "$(cat "$CURL_PAYLOAD_FILE")" '"failed_step":"verify (failure)"' "verify failure: failed_step=verify"

# --- Case: backup success + verify skipped → overall=success (skipped not a failure)
reset_notify_state
export NOTIFY_WEBHOOK_URL="https://example.com/hook"
export BACKUP_RESULT="success" VERIFY_RESULT="skipped" NOTIFY_ON_SUCCESS="true"
output=$(run_notify 2>&1); rc=$?
assert_exit_zero "$rc" "verify skipped: exit 0"
assert_contains "$(cat "$CURL_PAYLOAD_FILE")" '"status":"success"' "verify skipped: still success"

# --- Case: slack format payload shape
reset_notify_state
export NOTIFY_WEBHOOK_URL="https://hooks.slack.com/services/T/B/X"
export BACKUP_RESULT="success" NOTIFY_ON_SUCCESS="true" NOTIFY_FORMAT="slack"
export NOTIFY_REPOSITORY="owner/repo" NOTIFY_WORKFLOW="Daily Backup"
export NOTIFY_OBJECT_KEY="daily/backup.tar.gz"
output=$(run_notify 2>&1); rc=$?
assert_exit_zero "$rc" "slack format: exit 0"
assert_contains "$(cat "$CURL_PAYLOAD_FILE")" '"text":"R2 backup succeeded' "slack: text field present"
assert_contains "$(cat "$CURL_PAYLOAD_FILE")" '"attachments"' "slack: attachments field present"
assert_contains "$(cat "$CURL_PAYLOAD_FILE")" '"color":"good"' "slack: color=good for success"
assert_contains "$(cat "$CURL_PAYLOAD_FILE")" '"value":"daily/backup.tar.gz"' "slack: object key in fields"

# --- Case: slack format on failure → color=danger
reset_notify_state
export NOTIFY_WEBHOOK_URL="https://hooks.slack.com/services/T/B/X"
export BACKUP_RESULT="failure" NOTIFY_FORMAT="slack"
output=$(run_notify 2>&1); rc=$?
assert_exit_zero "$rc" "slack failure format: exit 0"
assert_contains "$(cat "$CURL_PAYLOAD_FILE")" '"color":"danger"' "slack: color=danger for failure"
assert_contains "$(cat "$CURL_PAYLOAD_FILE")" '"text":"R2 backup FAILED' "slack: failure text"

# --- Case: discord format payload shape
reset_notify_state
export NOTIFY_WEBHOOK_URL="https://discord.com/api/webhooks/X/Y"
export BACKUP_RESULT="success" NOTIFY_ON_SUCCESS="true" NOTIFY_FORMAT="discord"
export NOTIFY_REPOSITORY="owner/repo" NOTIFY_WORKFLOW="Daily Backup"
output=$(run_notify 2>&1); rc=$?
assert_exit_zero "$rc" "discord format: exit 0"
assert_contains "$(cat "$CURL_PAYLOAD_FILE")" '"content":"R2 backup succeeded"' "discord: content field"
assert_contains "$(cat "$CURL_PAYLOAD_FILE")" '"embeds"' "discord: embeds field"
assert_contains "$(cat "$CURL_PAYLOAD_FILE")" '"color":3066993' "discord: color=green for success"

# --- Case: discord format on failure → red color
reset_notify_state
export NOTIFY_WEBHOOK_URL="https://discord.com/api/webhooks/X/Y"
export BACKUP_RESULT="failure" NOTIFY_FORMAT="discord"
output=$(run_notify 2>&1); rc=$?
assert_exit_zero "$rc" "discord failure: exit 0"
assert_contains "$(cat "$CURL_PAYLOAD_FILE")" '"color":15158332' "discord: color=red for failure"

# --- Case: webhook returns 500 → script still exits 0, logs warning
reset_notify_state
export NOTIFY_WEBHOOK_URL="https://example.com/hook" BACKUP_RESULT="failure"
export R2_MOCK_CURL_CODE="500"
output=$(run_notify 2>&1); rc=$?
assert_exit_zero "$rc" "webhook 500: exit 0 (failure isolated)"
assert_contains "$output" "HTTP 500" "webhook 500: logs the HTTP code"

# --- Case: curl itself fails (connection refused) → script still exits 0
reset_notify_state
export NOTIFY_WEBHOOK_URL="https://example.com/hook" BACKUP_RESULT="failure"
export R2_MOCK_CURL_FAIL="1"
output=$(run_notify 2>&1); rc=$?
assert_exit_zero "$rc" "curl connection failure: exit 0"

# --- Case: payload omits empty optional fields gracefully (no nulls everywhere)
reset_notify_state
export NOTIFY_WEBHOOK_URL="https://example.com/hook" BACKUP_RESULT="success"
export NOTIFY_ON_SUCCESS="true" NOTIFY_FORMAT="slack"
output=$(run_notify 2>&1); rc=$?
assert_exit_zero "$rc" "minimal slack payload: exit 0"
# With no NOTIFY_REPOSITORY set, slack 'text' should still be sensible (no
# trailing " ()" or stray empty parens).
assert_not_contains "$(cat "$CURL_PAYLOAD_FILE")" '" ()"' "slack: no empty parens when context is blank"

rm -f "$CURL_PAYLOAD_FILE"
