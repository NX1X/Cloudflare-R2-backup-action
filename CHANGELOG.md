# Changelog

All notable changes to this action are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

### Added

- `assets/social-preview.svg` and `assets/social-preview.png` - 1280x640 social preview image for the repository's Settings - Social preview field
- Release workflow validates the `branding:` block in `action.yml` (icon + color) as a GitHub Marketplace prerequisite, with header docs explaining the one-time UI step required to publish the listing

---

## [1.0.0] - 2026-05-20

### Added

- Initial release - part of the [NXTools Collection](https://nx1xlab.dev/nxtools) by [NX1X](https://github.com/NX1X)
- Composite shell action with four operations:
  - `upload` - push a file to R2 with optional inline retention prune
  - `prune` - retention by age (`retention-days`) and/or count (`retention-count`)
  - `verify` - download + integrity check via `tar`, `zip`, or `sha256`
  - `list` - JSON listing with `count` and `total-size`
- AWS CLI under the hood (pre-installed on GitHub-hosted runners, no extra installs)
- R2 endpoint auto-derived from `account-id`; override available via `endpoint-url`
- Reusable workflow (`.github/workflows/backup.yml`) that orchestrates source prep, transport, upload, and optional verify
- Three source modes:
  - `local` - runs the backup script on the GitHub runner
  - `ssh` - runs the script on a remote server via plain SSH (with optional `ssh-known-hosts` for strict host key verification)
  - `tunnel-ssh` - wraps [`NX1X/cloudflare-tunnel-ssh-action`](https://github.com/NX1X/cloudflare-tunnel-ssh-action) for zero-trust access to servers behind Cloudflare Tunnel
- Built-in DB templates so users can skip writing dump commands:
  - `mysql` (also handles MariaDB via `db-dump-binary: mariadb-dump`)
  - `postgres` (single DB via `pg_dump`, all DBs via `pg_dumpall`)
  - `mongodb` (`mongodump --archive --gzip`)
  - `sqlite` (hot backup via `sqlite3 .backup`)
- Optional `docker compose exec -T <service>` wrapping for templates
- `extra-paths` input to include arbitrary files/directories alongside the dump
- Outputs for chaining: `object-key`, `size`, `pruned-count`, `verified`, `objects` (JSON), `count`, `total-size`
- Webhook notifications for the reusable workflow:
  - Inputs `notify-webhook-format` (`slack` | `discord` | `generic`), `notify-on-success` (default `false`), `notify-on-failure` (default `true`)
  - Secret `NOTIFY_WEBHOOK_URL` - when unset, notifications are silently disabled
  - `notify` job runs with `if: always() && !cancelled()` so failures are reported even when the backup or verify step errors
  - Notification delivery failures (webhook 5xx, connection refused) never fail the run - the backup state is the source of truth
  - `scripts/notify.sh` - payload builder and webhook poster, reused via sparse-checkout
- Unit tests (107 cases) with mocked `aws` and `curl` CLIs covering upload, prune, verify, list, dispatch, and notifications
- CI: pinned `actionlint` v1.7.7 + `shellcheck`, runs on every push and PR
- CodeQL Advanced workflow (`.github/workflows/codeql.yml`) - static analysis on workflow YAML using CodeQL's `actions` queries, runs on every push/PR and weekly via cron
- Renovate config (`.github/renovate.json`) for automated dependency updates - daily check window, 3-day cooldown on normal updates, 7-day cooldown on majors, instant PRs for security vulnerabilities, OSV alerts, custom regex manager tracking the pinned `actionlint` version
- Manual release workflow (`workflow_dispatch`) with version validation, duplicate tag check, CHANGELOG extraction, and floating major version tag
- Manual smoke-test workflow (`test.yml`) for verifying against real R2 infrastructure
- Issue templates, PR template, CODEOWNERS
- Documentation: source modes, DB templates, notifications, architecture/design notes, roadmap

### Security

- All `${{ inputs.* }}` and `${{ secrets.* }}` expressions in shell scripts routed through `env:` blocks to prevent script injection
- Input validation for `retention-days`, `retention-count`, `max-keys` - non-negative integers only
- DB template env-var prelude generated with `printf '%q'` so passwords/paths with shell metacharacters are safely escaped
- For `mysql` and `postgres`, password is set via env var (`MYSQL_PWD` / `PGPASSWORD`) - never as a CLI argument
- Explicit `permissions` blocks on all workflows (least-privilege `contents: read`; `contents: write` only on the release job that creates tags)
- `softprops/action-gh-release` pinned to commit SHA in the release workflow
- `actions/checkout@v5` (Node.js 24) across all workflows
- No telemetry, no analytics, no external calls - traffic only to R2 endpoint and (for tunnel-ssh) Cloudflare Access
- Apache License 2.0
