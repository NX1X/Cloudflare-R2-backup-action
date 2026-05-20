#!/usr/bin/env bash
# Post a backup-completion notification to a webhook (Slack, Discord, or generic JSON).
# Invoked by the reusable workflow's notify job; designed to never fail the run
# on webhook errors (a flaky chat service should not mask the backup state).
#
# Required env:
#   NOTIFY_WEBHOOK_URL  - webhook to POST to. If empty, the script logs and exits 0.
#   NOTIFY_FORMAT       - slack | discord | generic (default: generic)
#   BACKUP_RESULT       - needs.backup.result (success|failure|cancelled|skipped)
#
# Optional env:
#   NOTIFY_ON_SUCCESS   - "true" to notify on success (default: false)
#   NOTIFY_ON_FAILURE   - "true" to notify on failure (default: true)
#   VERIFY_RESULT       - needs.verify.result. Treated as success if "skipped".
#   NOTIFY_REPOSITORY, NOTIFY_WORKFLOW, NOTIFY_REF, NOTIFY_RUN_URL
#   NOTIFY_BUCKET, NOTIFY_OBJECT_KEY, NOTIFY_SIZE, NOTIFY_PRUNED_COUNT
#   NOTIFY_VERIFIED - "true" | "false" | "skipped"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh"

URL="${NOTIFY_WEBHOOK_URL:-}"
FORMAT="${NOTIFY_FORMAT:-generic}"
ON_SUCCESS="${NOTIFY_ON_SUCCESS:-false}"
ON_FAILURE="${NOTIFY_ON_FAILURE:-true}"
BACKUP_RESULT="${BACKUP_RESULT:-}"
VERIFY_RESULT="${VERIFY_RESULT:-skipped}"

if [ -z "$URL" ]; then
  log_info "NOTIFY_WEBHOOK_URL is empty - notification skipped"
  exit 0
fi

case "$FORMAT" in
  slack|discord|generic) ;;
  *) die "NOTIFY_FORMAT must be one of: slack, discord, generic (got '${FORMAT}')" ;;
esac

if [ -z "$BACKUP_RESULT" ]; then
  die "BACKUP_RESULT is required (one of: success, failure, cancelled, skipped)"
fi

# Derive overall status. Verify "skipped" is treated as success-equivalent
# because the user chose not to verify, not because verification failed.
if [ "$BACKUP_RESULT" = "success" ] && \
   { [ "$VERIFY_RESULT" = "success" ] || [ "$VERIFY_RESULT" = "skipped" ]; }; then
  STATUS="success"
else
  STATUS="failure"
fi

# Failed-step heuristic: the first job that didn't succeed.
FAILED_STEP=""
if [ "$STATUS" = "failure" ]; then
  if [ "$BACKUP_RESULT" != "success" ]; then
    FAILED_STEP="backup (${BACKUP_RESULT})"
  else
    FAILED_STEP="verify (${VERIFY_RESULT})"
  fi
fi

# Gating: skip if the user opted out of this status class.
if [ "$STATUS" = "success" ] && [ "$ON_SUCCESS" != "true" ]; then
  log_info "status=success and notify-on-success=false - skipped"
  exit 0
fi
if [ "$STATUS" = "failure" ] && [ "$ON_FAILURE" != "true" ]; then
  log_info "status=failure and notify-on-failure=false - skipped"
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  die "jq not found (required for webhook payload construction)"
fi
if ! command -v curl >/dev/null 2>&1; then
  die "curl not found (required for webhook POST)"
fi

REPO="${NOTIFY_REPOSITORY:-}"
WORKFLOW="${NOTIFY_WORKFLOW:-}"
REF="${NOTIFY_REF:-}"
RUN_URL="${NOTIFY_RUN_URL:-}"
BUCKET="${NOTIFY_BUCKET:-}"
OBJECT_KEY="${NOTIFY_OBJECT_KEY:-}"
SIZE="${NOTIFY_SIZE:-}"
PRUNED_COUNT="${NOTIFY_PRUNED_COUNT:-}"
VERIFIED="${NOTIFY_VERIFIED:-skipped}"

TITLE_PREFIX="R2 backup"
if [ "$STATUS" = "success" ]; then
  SUMMARY="${TITLE_PREFIX} succeeded"
else
  SUMMARY="${TITLE_PREFIX} FAILED"
fi
CONTEXT="${REPO}${WORKFLOW:+ - ${WORKFLOW}}"

case "$FORMAT" in
  slack)
    # Slack incoming-webhook schema. color: "good" (green) / "danger" (red).
    COLOR="good"
    [ "$STATUS" = "failure" ] && COLOR="danger"
    PAYLOAD=$(jq -nc \
      --arg summary "$SUMMARY" \
      --arg context "$CONTEXT" \
      --arg color "$COLOR" \
      --arg status "$STATUS" \
      --arg ref "$REF" \
      --arg bucket "$BUCKET" \
      --arg key "$OBJECT_KEY" \
      --arg size "$SIZE" \
      --arg pruned "$PRUNED_COUNT" \
      --arg verified "$VERIFIED" \
      --arg failed_step "$FAILED_STEP" \
      --arg run_url "$RUN_URL" \
      '{
        text: ($summary + ($context | if . == "" then "" else " (\(.))" end)),
        attachments: [{
          color: $color,
          fields: ([
            {title: "Status",       value: $status,   short: true},
            ($ref      | select(. != "") | {title: "Ref",     value: ., short: true}),
            ($bucket   | select(. != "") | {title: "Bucket",  value: ., short: true}),
            ($verified | select(. != "") | {title: "Verify",  value: ., short: true}),
            ($key      | select(. != "") | {title: "Object",  value: ., short: false}),
            ($size     | select(. != "") | {title: "Size",    value: ., short: true}),
            ($pruned   | select(. != "") | {title: "Pruned",  value: ., short: true}),
            ($failed_step | select(. != "") | {title: "Failed step", value: ., short: false}),
            ($run_url  | select(. != "") | {title: "Run",     value: ., short: false})
          ] | map(select(. != null)))
        }]
      }')
    ;;

  discord)
    # Discord webhook schema. color: integer (decimal). Green=3066993, Red=15158332.
    COLOR_INT=3066993
    [ "$STATUS" = "failure" ] && COLOR_INT=15158332
    PAYLOAD=$(jq -nc \
      --arg summary "$SUMMARY" \
      --arg context "$CONTEXT" \
      --argjson color "$COLOR_INT" \
      --arg status "$STATUS" \
      --arg ref "$REF" \
      --arg bucket "$BUCKET" \
      --arg key "$OBJECT_KEY" \
      --arg size "$SIZE" \
      --arg pruned "$PRUNED_COUNT" \
      --arg verified "$VERIFIED" \
      --arg failed_step "$FAILED_STEP" \
      --arg run_url "$RUN_URL" \
      '{
        content: $summary,
        embeds: [({
          title: (if $context == "" then $summary else $context end),
          url:   (if $run_url == "" then null else $run_url end),
          color: $color,
          fields: ([
            {name: "Status",       value: $status,   inline: true},
            ($ref      | select(. != "") | {name: "Ref",     value: ., inline: true}),
            ($bucket   | select(. != "") | {name: "Bucket",  value: ., inline: true}),
            ($verified | select(. != "") | {name: "Verify",  value: ., inline: true}),
            ($key      | select(. != "") | {name: "Object",  value: ., inline: false}),
            ($size     | select(. != "") | {name: "Size",    value: ., inline: true}),
            ($pruned   | select(. != "") | {name: "Pruned",  value: ., inline: true}),
            ($failed_step | select(. != "") | {name: "Failed step", value: ., inline: false})
          ] | map(select(. != null)))
        } | with_entries(select(.value != null)))]
      }')
    ;;

  generic)
    PAYLOAD=$(jq -nc \
      --arg status "$STATUS" \
      --arg repository "$REPO" \
      --arg workflow "$WORKFLOW" \
      --arg ref "$REF" \
      --arg run_url "$RUN_URL" \
      --arg bucket "$BUCKET" \
      --arg object_key "$OBJECT_KEY" \
      --arg size "$SIZE" \
      --arg pruned_count "$PRUNED_COUNT" \
      --arg verified "$VERIFIED" \
      --arg failed_step "$FAILED_STEP" \
      '{
        status: $status,
        repository: $repository,
        workflow: $workflow,
        ref: $ref,
        run_url: $run_url,
        bucket: $bucket,
        object_key: $object_key,
        size: $size,
        pruned_count: $pruned_count,
        verified: $verified,
        failed_step: $failed_step
      }')
    ;;
esac

log_info "Posting ${FORMAT} notification (status=${STATUS}) to webhook"

HTTP_CODE=$(curl --silent --show-error --output /dev/null \
  --write-out '%{http_code}' \
  --max-time 10 \
  --request POST \
  --header 'Content-Type: application/json' \
  --data "$PAYLOAD" \
  "$URL" || echo "000")

case "$HTTP_CODE" in
  2[0-9][0-9])
    log_info "Webhook delivered: HTTP ${HTTP_CODE}"
    exit 0
    ;;
esac

# Don't fail the workflow on webhook delivery problems - log a warning.
log_warn "Webhook delivery returned HTTP ${HTTP_CODE} (status=${STATUS}). Not failing the run."
exit 0
