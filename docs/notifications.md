# Notifications

The reusable `backup.yml` workflow can POST a JSON payload to a webhook when a backup completes - succeeded or failed. Useful for Slack/Discord pings or feeding a generic monitoring endpoint.

| Format | Compatible with |
|--------|-----------------|
| `slack` | Slack incoming webhooks, plus any consumer that understands `{text, attachments}` |
| `discord` | Discord webhooks, plus any consumer that understands `{content, embeds}` |
| `generic` | Anything you control - flat JSON with named fields, easy to parse |

---

## Inputs and secret

| Where | Name | Default | Purpose |
|-------|------|---------|---------|
| `secrets:` | `NOTIFY_WEBHOOK_URL` | - | The webhook URL. When unset, notifications are silently disabled. |
| `inputs:` | `notify-webhook-format` | `generic` | Payload schema: `slack`, `discord`, or `generic`. |
| `inputs:` | `notify-on-success` | `false` | Post a notification when the backup succeeds. Off by default - most teams want failures only. |
| `inputs:` | `notify-on-failure` | `true` | Post a notification when the backup or verify step fails. |

`NOTIFY_WEBHOOK_URL` is a secret because Slack/Discord webhook URLs contain an embedded auth token. Never pass it as a plain input.

---

## Slack example

1. Create an [incoming webhook](https://api.slack.com/messaging/webhooks) for the target channel.
2. Save the webhook URL as a repo secret named `NOTIFY_WEBHOOK_URL`.

```yaml
jobs:
  backup:
    uses: NX1X/Cloudflare-R2-backup-action/.github/workflows/backup.yml@v1
    with:
      source-mode: tunnel-ssh
      db-template: mysql
      db-user:     root
      ssh-host:    ${{ vars.TUNNEL_HOSTNAME }}
      ssh-user:    deploy
      bucket:      my-backups
      prefix:      daily/

      notify-webhook-format: slack
      notify-on-success:     true
      notify-on-failure:     true

    secrets:
      R2_ACCOUNT_ID:           ${{ secrets.CF_ACCOUNT_ID }}
      R2_ACCESS_KEY_ID:        ${{ secrets.R2_ACCESS_KEY_ID }}
      R2_SECRET_ACCESS_KEY:    ${{ secrets.R2_SECRET_ACCESS_KEY }}
      CF_ACCESS_CLIENT_ID:     ${{ secrets.CF_ACCESS_CLIENT_ID }}
      CF_ACCESS_CLIENT_SECRET: ${{ secrets.CF_ACCESS_CLIENT_SECRET }}
      SSH_PRIVATE_KEY:         ${{ secrets.SSH_PRIVATE_KEY }}
      DB_PASSWORD:             ${{ secrets.DATABASE_ROOT_PASSWORD }}
      NOTIFY_WEBHOOK_URL:      ${{ secrets.SLACK_WEBHOOK_URL }}
```

Sample payload:

```json
{
  "text": "R2 backup succeeded (owner/repo - Daily Backup)",
  "attachments": [{
    "color": "good",
    "fields": [
      {"title": "Status",  "value": "success",                      "short": true},
      {"title": "Ref",     "value": "refs/heads/main",              "short": true},
      {"title": "Bucket",  "value": "my-backups",                   "short": true},
      {"title": "Verify",  "value": "true",                         "short": true},
      {"title": "Object",  "value": "daily/backup_20260520_021500.tar.gz", "short": false},
      {"title": "Size",    "value": "14823294",                     "short": true},
      {"title": "Pruned",  "value": "1",                            "short": true},
      {"title": "Run",     "value": "https://github.com/owner/repo/actions/runs/123", "short": false}
    ]
  }]
}
```

The `color` is `good` (green) on success, `danger` (red) on failure.

---

## Discord example

1. In channel settings, **Integrations → Webhooks → New Webhook**, copy the URL.
2. Save the URL as a repo secret named `NOTIFY_WEBHOOK_URL`.

```yaml
notify-webhook-format: discord
notify-on-success:     false   # quieter - only ping on failures
notify-on-failure:     true
```

Sample payload (failure):

```json
{
  "content": "R2 backup FAILED",
  "embeds": [{
    "title": "owner/repo - Daily Backup",
    "url": "https://github.com/owner/repo/actions/runs/123",
    "color": 15158332,
    "fields": [
      {"name": "Status", "value": "failure", "inline": true},
      {"name": "Ref",    "value": "refs/heads/main", "inline": true},
      {"name": "Failed step", "value": "backup (failure)", "inline": false}
    ]
  }]
}
```

The `color` is `3066993` (green) on success, `15158332` (red) on failure.

---

## Generic example

For Opsgenie, PagerDuty, a homegrown monitor, or any consumer you can shape yourself:

```yaml
notify-webhook-format: generic
```

Payload shape (all fields always present, empty strings when not applicable):

```json
{
  "status":       "success",
  "repository":   "owner/repo",
  "workflow":     "Daily Backup",
  "ref":          "refs/heads/main",
  "run_url":      "https://github.com/owner/repo/actions/runs/123",
  "bucket":       "my-backups",
  "object_key":   "daily/backup_20260520_021500.tar.gz",
  "size":         "14823294",
  "pruned_count": "1",
  "verified":     "true",
  "failed_step":  ""
}
```

`status` is `success` or `failure`. `failed_step` is `""` on success, and identifies which job didn't succeed otherwise (e.g. `"backup (failure)"`, `"verify (failure)"`).

---

## Status derivation

The notification job runs after both `backup` and `verify`, with `if: always() && !cancelled()`. It checks the result of each:

| `backup.result` | `verify.result` | Overall status |
|-----------------|------------------|----------------|
| `success` | `success` | `success` |
| `success` | `skipped` (verify-after-upload was false) | `success` |
| `success` | `failure` | `failure` (failed_step: `verify`) |
| `failure` / `cancelled` | anything | `failure` (failed_step: `backup`) |

Cancelled runs never trigger a notification - cancellation is treated as user-initiated, not a backup outcome to report.

---

## Failure isolation

Webhook delivery problems (5xx response, connection refused, DNS timeout) never fail the workflow run. The script:

- Times out after 10 seconds (`curl --max-time 10`)
- Logs the HTTP status or connection error at warning level
- Exits 0 regardless

The reason: a flaky chat service should not flip a successful backup's status to "failed." The R2 state is authoritative.

---

## Disabling notifications

Three ways:

1. Don't set `NOTIFY_WEBHOOK_URL` - the notify job runs but exits early.
2. Set both `notify-on-success: false` and `notify-on-failure: false` - the script will skip every status.
3. Override the workflow without the notify job by writing your own caller workflow.

---

## Notes

- `jq` and `curl` are pre-installed on GitHub-hosted Ubuntu runners. Self-hosted runners need both available on PATH.
- The webhook URL is masked in run logs because it's passed via `secrets.*`.
- The script does not implement retries - a transient failure simply means no notification for that run. If you need reliable delivery, point the webhook at a queue (e.g., an SQS endpoint) and retry from there.
