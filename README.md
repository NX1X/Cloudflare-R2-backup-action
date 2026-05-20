# Cloudflare-R2-backup-action

[![GitHub Marketplace](https://img.shields.io/badge/Marketplace-Cloudflare%20R2%20Backup-blue?logo=github)](https://github.com/marketplace/actions/cloudflare-r2-backup)
[![Latest Release](https://img.shields.io/github/v/release/NX1X/Cloudflare-R2-backup-action?label=version&color=brightgreen)](https://github.com/NX1X/Cloudflare-R2-backup-action/releases/latest)
[![CI](https://github.com/NX1X/Cloudflare-R2-backup-action/actions/workflows/ci.yml/badge.svg)](https://github.com/NX1X/Cloudflare-R2-backup-action/actions/workflows/ci.yml)
[![Unit Tests](https://github.com/NX1X/Cloudflare-R2-backup-action/actions/workflows/unit-tests.yml/badge.svg)](https://github.com/NX1X/Cloudflare-R2-backup-action/actions/workflows/unit-tests.yml)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Status: Beta](https://img.shields.io/badge/status-beta-yellow)](#status)
[![NXTools](https://img.shields.io/badge/NXTools-Collection-orange)](https://nx1xlab.dev/nxtools)
![Views](https://komarev.com/ghpvc/?username=NX1X-Cloudflare-R2-backup-action&label=views&color=f66a0a)

> **Status: Beta.** This action is still maturing. The interface is stable for the v1 line, but you may encounter edge cases - please [open an issue](https://github.com/NX1X/Cloudflare-R2-backup-action/issues/new) if you do. Use in production with caution and pin to an exact tag (`@v1.0.0`) rather than the floating major if you need reproducibility.

Upload, verify, list, and prune backup objects in **Cloudflare R2** from GitHub Actions. Composite shell action plus a reusable workflow that orchestrates server backups end to end - source prep, transport, R2 upload, retention, integrity verification.

Part of the [NXTools Collection](https://nx1xlab.dev/nxtools) by [NX1X](https://github.com/NX1X).

---

## Quick Start - the action

```yaml
- uses: NX1X/Cloudflare-R2-backup-action@v1
  with:
    operation:         upload
    account-id:        ${{ secrets.CF_ACCOUNT_ID }}
    access-key-id:     ${{ secrets.R2_ACCESS_KEY_ID }}
    secret-access-key: ${{ secrets.R2_SECRET_ACCESS_KEY }}
    bucket:            my-backups
    prefix:            daily-backups/
    file:              ./myapp_backup.tar.gz
    retention-days:    '90'
```

This uploads the file to `s3://my-backups/daily-backups/myapp_backup.tar.gz` and deletes anything in `daily-backups/` older than 90 days.

---

## Quick Start - the reusable workflow

For a turn-key backup pipeline (archive -> upload -> optional verify), use the included reusable workflow with a built-in DB template:

```yaml
jobs:
  backup:
    uses: NX1X/Cloudflare-R2-backup-action/.github/workflows/backup.yml@v1
    with:
      source-mode: tunnel-ssh
      ssh-host:    ${{ vars.TUNNEL_HOSTNAME }}
      ssh-user:    deploy

      db-template:               mysql              # or postgres, mongodb, sqlite
      db-dump-binary:            mariadb-dump       # MariaDB variant
      db-user:                   root
      db-docker-compose-service: db                 # dump runs inside `docker compose exec`
      db-docker-compose-dir:     /home/deploy/myapp

      extra-paths: |
        /home/deploy/myapp/data/uploads

      bucket:           my-backups
      prefix:           daily/
      retention-days:   '90'
      verify-after-upload: true

    secrets:
      R2_ACCOUNT_ID:           ${{ secrets.CF_ACCOUNT_ID }}
      R2_ACCESS_KEY_ID:        ${{ secrets.R2_ACCESS_KEY_ID }}
      R2_SECRET_ACCESS_KEY:    ${{ secrets.R2_SECRET_ACCESS_KEY }}
      CF_ACCESS_CLIENT_ID:     ${{ secrets.CF_ACCESS_CLIENT_ID }}
      CF_ACCESS_CLIENT_SECRET: ${{ secrets.CF_ACCESS_CLIENT_SECRET }}
      SSH_PRIVATE_KEY:         ${{ secrets.SSH_PRIVATE_KEY }}
      DB_PASSWORD:             ${{ secrets.DATABASE_ROOT_PASSWORD }}
```

That single caller replaces ~190 lines of hand-rolled cloudflared + s3cmd + retention boilerplate.

---

## What's in the box

| Operation | Purpose |
|-----------|---------|
| `upload` | Upload a single file to a bucket/prefix. Optional inline retention prune. |
| `prune`  | Delete objects under a prefix by age (`retention-days`) and/or count (`retention-count`). |
| `verify` | Download an object and check integrity: `tar`, `zip`, or `sha256` against an expected digest. |
| `list`   | List objects under a prefix as a JSON array, plus `count` and `total-size`. |

| Source mode (reusable workflow) | Where the backup script runs |
|---|---|
| `local` | The GitHub runner |
| `ssh` | A remote server reached over plain SSH |
| `tunnel-ssh` | A server behind a Cloudflare Tunnel (wraps [`cloudflare-tunnel-ssh-action`](https://github.com/NX1X/cloudflare-tunnel-ssh-action)) |

| DB template | Engine | Tool |
|---|---|---|
| `mysql` | MySQL & MariaDB | `mysqldump` (or `mariadb-dump`) |
| `postgres` | PostgreSQL | `pg_dump` (single DB) or `pg_dumpall` |
| `mongodb` | MongoDB | `mongodump --archive --gzip` |
| `sqlite` | SQLite | `sqlite3 .backup` (hot backup) |

---

## Inputs (action)

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `operation` | **yes** | - | `upload`, `prune`, `verify`, or `list` |
| `account-id` | **yes** | - | Cloudflare account ID (used to derive the R2 endpoint) |
| `access-key-id` | **yes** | - | R2 API access key ID |
| `secret-access-key` | **yes** | - | R2 API secret access key |
| `bucket` | **yes** | - | R2 bucket name |
| `prefix` | no | `''` | Path prefix inside the bucket (e.g. `daily-backups/`). Trailing slash auto-added. |
| `file` | conditional | - | Local file path. Required for `upload`. |
| `object-key` | conditional | - | Explicit object key. For `upload`, defaults to `prefix + basename(file)`. Required for `verify`. |
| `retention-days` | no | - | Delete objects under prefix older than N days (`prune` / `upload`). |
| `retention-count` | no | - | Keep only the newest N objects under prefix (`prune` / `upload`). |
| `verify-mode` | conditional | - | `tar`, `zip`, or `sha256`. Required for `verify`. |
| `verify-checksum` | conditional | - | Expected sha256 hex digest. Required when `verify-mode: sha256`. |
| `max-keys` | no | - | Maximum objects to return (`list`). |
| `endpoint-url` | no | - | Override R2 endpoint. Default: `https://<account-id>.r2.cloudflarestorage.com`. |

## Outputs (action)

| Output | Op | Description |
|--------|----|-------------|
| `object-key` | upload, verify | Full object key written/verified. |
| `size` | upload, verify | Size in bytes. |
| `pruned-count` | upload, prune | Number of objects deleted by retention. |
| `verified` | verify | `true` if integrity check passed. |
| `objects` | list | JSON array of `{key, size, lastModified}`. |
| `count` | list | Number of objects returned. |
| `total-size` | list | Total bytes across all listed objects. |

---

## Pin the action for reproducibility

| Style | Tag | Behavior |
|-------|-----|----------|
| Major | `@v1` | Auto-receives minor + patch updates (recommended) |
| Exact | `@v1.0.0` | Pinned, no automatic updates |
| SHA | `@abc1234` | Maximum reproducibility |

The reusable workflow's hardcoded internal `uses:` references match the same major version as the workflow file you call.

---

## Permissions

Create an **R2 API token** in the Cloudflare dashboard, scoped to the bucket(s) you want to back up to. Save:

- `CF_ACCOUNT_ID` - your Cloudflare account ID
- `R2_ACCESS_KEY_ID` - the token's access key ID
- `R2_SECRET_ACCESS_KEY` - the token's secret access key

For the `tunnel-ssh` source mode you'll also need a Cloudflare Access service token; for `ssh` and `tunnel-ssh` modes you'll need an `SSH_PRIVATE_KEY`. See [`docs/source-modes.md`](docs/source-modes.md) for the full setup.

---

## Supported Runners

Ubuntu only - this action depends on the AWS CLI being pre-installed (it is on GitHub-hosted Ubuntu runners):

- `ubuntu-latest` (Ubuntu 24.04)
- `ubuntu-22.04`
- `ubuntu-20.04`

For self-hosted runners, install AWS CLI v2 (with `AWS_ENDPOINT_URL_S3` env var support, ~mid-2023 onward).

---

## Documentation

- **[Source modes](docs/source-modes.md)** - `local`, `ssh`, `tunnel-ssh`: where the backup runs and how the archive reaches R2
- **[DB templates](docs/db-templates.md)** - `mysql`, `postgres`, `mongodb`, `sqlite`: built-in dump recipes you can use instead of writing a custom backup-script
- **[Notifications](docs/notifications.md)** - Slack / Discord / generic-webhook pings on backup success or failure
- **[Architecture](docs/architecture.md)** - design rationale, password traversal model, archive layout per engine, comparison with hand-rolled patterns
- **[Roadmap](docs/ROADMAP.md)** - planned features
- **[Changelog](CHANGELOG.md)** - version history
- **[Security](SECURITY.md)** - vulnerability reporting and security practices
- **[Contributing](CONTRIBUTING.md)** - how to contribute
- **[Examples](examples/)** - complete caller workflows for common cases

---

## Privacy

This action collects no data. No telemetry, no analytics, no external calls. Network traffic from this action goes only to:

- The Cloudflare R2 endpoint (`https://<account-id>.r2.cloudflarestorage.com` or your override)
- For `tunnel-ssh` source mode: Cloudflare Access endpoints, via the wrapped action

The source is fully open - read every line in [`action.yml`](action.yml), [`scripts/`](scripts/), and [`templates/`](templates/).

---

## License

[Apache 2.0](LICENSE) - (c) 2026 [NX1X](https://github.com/NX1X)
