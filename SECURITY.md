# Security Policy

## Supported Versions

| Version | Supported          |
|---------|--------------------|
| latest  | :white_check_mark: |
| < latest| :x:                |

## Reporting a Vulnerability

**Do not open a public issue for security vulnerabilities.**

Instead, please report vulnerabilities privately:

1. Go to the [Security Advisories](https://github.com/NX1X/Cloudflare-R2-backup-action/security/advisories) page
2. Click **Report a vulnerability**
3. Provide a clear description and reproduction steps

You will receive a response within 72 hours. If confirmed, a fix will be released as a patch version and credited in the changelog.

## Security Practices

### Action surface

- CI runs `actionlint` and `shellcheck` on every push and PR
- All `${{ inputs.* }}` and `${{ secrets.* }}` references in shell scripts are routed through `env:` blocks (masked by GitHub Actions) - never inlined in `run:` commands. This prevents script injection from a malicious input value.
- Input validation: numeric inputs (`retention-days`, `retention-count`, `max-keys`) reject non-integer values
- AWS CLI is invoked with explicit endpoint URL, region `auto`, and credentials passed via env vars - never as CLI arguments

### Reusable workflow surface

- Permissions are scoped to `contents: read` for all jobs except the release workflow, which has `contents: write` only on the tagging step
- For `ssh` mode, the workflow recommends `ssh-known-hosts` (strict host key checking). When omitted, the workflow emits a `::warning::` annotation explaining the TOFU fallback.
- For `tunnel-ssh` mode, authentication is handled by Cloudflare Access service tokens via [`NX1X/cloudflare-tunnel-ssh-action`](https://github.com/NX1X/cloudflare-tunnel-ssh-action). Service tokens can be revoked instantly in the Cloudflare dashboard without rotating SSH keys.
- DB template env-var prelude is generated with `printf '%q'` so password values containing shell metacharacters (`$`, backticks, quotes, newlines) are safely escaped before reaching `bash -s` on the source.
- For `mysql`/`postgres` templates, the password is exported as an env var (`MYSQL_PWD` / `PGPASSWORD`) - never as a CLI argument. So it doesn't appear in `ps`/`/proc/*/cmdline` on the source.
- For `mongodb`, `--password` is a CLI flag (limitation of `mongodump`); it can briefly appear in `ps` listings on the source while `mongodump` is running. See [docs/architecture.md](docs/architecture.md#password-traversal-model) for the full traversal model and stricter alternatives.
- The `NOTIFY_WEBHOOK_URL` secret (when set) carries the Slack/Discord/generic webhook token in the URL path - GitHub masks it in run logs. The notify job uses a 10s `curl --max-time` and intentionally swallows non-2xx responses so a flaky chat endpoint cannot flip a successful backup to "failed".

### Release supply chain

- Releases are created manually via the `Release` workflow (`workflow_dispatch`)
- The release workflow validates the version format, refuses duplicate tags, extracts release notes from `CHANGELOG.md`, and updates the floating major version tag
- `softprops/action-gh-release` is pinned to a commit SHA in the release workflow to prevent supply chain attacks
- `actionlint` is pinned to `v1.7.7` in CI and release workflows
- Dependabot is configured for weekly GitHub Actions version updates

### What this action collects

**Nothing.** No telemetry, no analytics, no external calls. Network traffic from this action goes only to:

- The Cloudflare R2 endpoint (`https://<account-id>.r2.cloudflarestorage.com` or your override)
- For `tunnel-ssh` source mode: Cloudflare Access endpoints, via the wrapped action

The source is fully open - read every line in [`action.yml`](action.yml), [`scripts/`](scripts/), and [`templates/`](templates/).

## Security Changelog

| Date | Change |
|------|--------|
| 2026-05-09 | v1.0.0 - Initial release with `env:`-block secret passing, `printf %q` env-prelude for templates, MYSQL_PWD/PGPASSWORD env-var injection (no CLI password leakage for MySQL/Postgres), explicit workflow permissions, pinned third-party actions |
