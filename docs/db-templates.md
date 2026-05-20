# Database templates

Built-in dump recipes that let you skip writing a `backup-script` for common databases. You provide connection inputs; the workflow generates the right dump command, tars the result with any extra paths, and hands the archive to the upload step.

| Template | Engine | Dump tool | Notes |
|----------|--------|-----------|-------|
| `mysql` | MySQL & MariaDB | `mysqldump` (or `mariadb-dump`) | Set `db-dump-binary: mariadb-dump` for MariaDB |
| `postgres` | PostgreSQL | `pg_dump` (single DB) or `pg_dumpall` (no `db-name`) | |
| `mongodb` | MongoDB | `mongodump --archive --gzip` | Single-file output |
| `sqlite` | SQLite | `sqlite3 file '.backup ...'` | Hot backup; needs `db-path` |

---

## How it works

1. You set `db-template: <engine>` and provide the relevant `db-*` inputs.
2. The workflow checks out the templates from this repo at the same `@v1` ref.
3. A prepare step generates a runnable script: env-var prelude + the engine's template body.
4. The script runs on the source (local runner, plain SSH, or Cloudflare Tunnel SSH) - the same execution path as a custom `backup-script`.
5. The script outputs the archive's absolute path on its last stdout line; the rest of the workflow uploads, retains, and optionally verifies.

You can mix any `db-template` with any `source-mode`.

---

## Inputs

All `db-*` inputs are optional unless noted; defaults depend on the chosen template.

| Input | Used by | Default | Description |
|-------|---------|---------|-------------|
| `db-template` | - | - | One of `mysql`, `postgres`, `mongodb`, `sqlite`. Mutually exclusive with `backup-script`. |
| `db-host` | mysql, postgres, mongodb | `localhost` | DB host. |
| `db-port` | mysql, postgres, mongodb | `3306` / `5432` / `27017` | DB port. |
| `db-user` | mysql, postgres (required), mongodb | - | DB username. |
| `db-name` | mysql, postgres, mongodb | empty (= dump all) | Single DB to dump. Empty means all databases (`mysqldump --all-databases` / `pg_dumpall` / mongo all DBs). |
| `db-path` | sqlite (required) | - | Absolute path to the `.db` / `.sqlite` file on the source. |
| `db-auth-db` | mongodb | `admin` | Authentication database. |
| `db-dump-binary` | mysql, postgres | `mysqldump` / `pg_dump`/`pg_dumpall` | Override the dump binary (e.g. `mariadb-dump`). |
| `db-docker-compose-service` | mysql, postgres, mongodb | - | If set, runs the dump inside `docker compose exec -T <service>`. |
| `db-docker-compose-dir` | mysql, postgres, mongodb | current dir | Working directory for `docker compose`. |
| `archive-name-prefix` | all | `backup` | Prefix for the archive filename (the suffix is `_YYYYMMDD_HHMMSS.tar.gz`). |
| `archive-path` | all | `$HOME/backups` | Directory on the source where the archive is staged. |
| `extra-paths` | all | empty | Newline-separated paths to include in the archive alongside the dump. Each entry adds `-C dirname basename`. |

The `DB_PASSWORD` secret feeds the engine-specific env var:
- `mysql` → `MYSQL_PWD`
- `postgres` → `PGPASSWORD`
- `mongodb` → `--password` flag

---

## Examples

### MariaDB in docker compose, behind Cloudflare Tunnel

```yaml
jobs:
  backup:
    uses: NX1X/Cloudflare-R2-backup-action/.github/workflows/backup.yml@v1
    with:
      source-mode: tunnel-ssh
      ssh-host:    ${{ vars.TUNNEL_HOSTNAME }}
      ssh-user:    deploy

      db-template:               mysql
      db-dump-binary:            mariadb-dump
      db-user:                   root
      db-docker-compose-service: db
      db-docker-compose-dir:     /home/deploy/myapp

      extra-paths: |
        /home/deploy/myapp/data/uploads

      bucket: my-backups
      prefix: daily/
      retention-days: '90'

    secrets:
      R2_ACCOUNT_ID:           ${{ secrets.CF_ACCOUNT_ID }}
      R2_ACCESS_KEY_ID:        ${{ secrets.R2_ACCESS_KEY_ID }}
      R2_SECRET_ACCESS_KEY:    ${{ secrets.R2_SECRET_ACCESS_KEY }}
      CF_ACCESS_CLIENT_ID:     ${{ secrets.CF_ACCESS_CLIENT_ID }}
      CF_ACCESS_CLIENT_SECRET: ${{ secrets.CF_ACCESS_CLIENT_SECRET }}
      SSH_PRIVATE_KEY:         ${{ secrets.SSH_PRIVATE_KEY }}
      DB_PASSWORD:             ${{ secrets.DATABASE_ROOT_PASSWORD }}
```

### Postgres on a public-IP server (plain SSH)

```yaml
jobs:
  backup:
    uses: NX1X/Cloudflare-R2-backup-action/.github/workflows/backup.yml@v1
    with:
      source-mode:     ssh
      ssh-host:        prod.example.com
      ssh-user:        backup
      ssh-known-hosts: ${{ secrets.SSH_KNOWN_HOSTS }}

      db-template: postgres
      db-user:     postgres
      # No db-name -> pg_dumpall

      bucket: my-backups
      prefix: pg-daily/

    secrets:
      R2_ACCOUNT_ID:        ${{ secrets.CF_ACCOUNT_ID }}
      R2_ACCESS_KEY_ID:     ${{ secrets.R2_ACCESS_KEY_ID }}
      R2_SECRET_ACCESS_KEY: ${{ secrets.R2_SECRET_ACCESS_KEY }}
      SSH_PRIVATE_KEY:      ${{ secrets.SSH_PRIVATE_KEY }}
      DB_PASSWORD:          ${{ secrets.PG_PASSWORD }}
```

### SQLite hot backup (local runner, no remote source)

```yaml
jobs:
  backup:
    uses: NX1X/Cloudflare-R2-backup-action/.github/workflows/backup.yml@v1
    with:
      source-mode: local

      db-template: sqlite
      db-path:     /var/lib/myapp/app.db

      bucket: my-backups
      prefix: sqlite-daily/

    secrets:
      R2_ACCOUNT_ID:        ${{ secrets.CF_ACCOUNT_ID }}
      R2_ACCESS_KEY_ID:     ${{ secrets.R2_ACCESS_KEY_ID }}
      R2_SECRET_ACCESS_KEY: ${{ secrets.R2_SECRET_ACCESS_KEY }}
```

### MongoDB with auth

```yaml
jobs:
  backup:
    uses: NX1X/Cloudflare-R2-backup-action/.github/workflows/backup.yml@v1
    with:
      source-mode: ssh
      ssh-host:    db.example.com
      ssh-user:    backup

      db-template: mongodb
      db-user:     backup-user
      db-auth-db:  admin
      # db-name empty -> all databases

      bucket: my-backups
      prefix: mongo-daily/

    secrets:
      R2_ACCOUNT_ID:        ${{ secrets.CF_ACCOUNT_ID }}
      R2_ACCESS_KEY_ID:     ${{ secrets.R2_ACCESS_KEY_ID }}
      R2_SECRET_ACCESS_KEY: ${{ secrets.R2_SECRET_ACCESS_KEY }}
      SSH_PRIVATE_KEY:      ${{ secrets.SSH_PRIVATE_KEY }}
      DB_PASSWORD:          ${{ secrets.MONGO_PASSWORD }}
```

---

## What's inside the archive

The archive is always `<archive-name-prefix>_<UTC_TIMESTAMP>.tar.gz`. Contents:

| Template | Files at archive root |
|----------|----------------------|
| `mysql` | `database.sql` (+ any extra-paths basenames) |
| `postgres` | `database.sql` (+ any extra-paths basenames) |
| `mongodb` | `dump.archive.gz` (the `mongodump --archive --gzip` output, restorable with `mongorestore --gzip --archive=dump.archive.gz`) |
| `sqlite` | `<original-db-filename>` (the `.backup` copy of your DB) (+ any extra-paths basenames) |

Each `extra-paths` entry is added to the archive root using its basename. To preserve a deeper directory structure, write a custom `backup-script` instead.

---

## Security notes

- **`DB_PASSWORD` reaches the source via the script body.** GitHub masks the value in run logs (since it came from `secrets.*`), but it is present in the script that gets piped to the source's bash. For SSH/tunnel-ssh modes this means the password traverses the SSH connection encrypted, lands in a temp file pattern on the source, and is exposed to anyone with shell access on the source while the dump is running.
- For MySQL/MariaDB and PostgreSQL, the password is set as an env var (`MYSQL_PWD` / `PGPASSWORD`) - not as a CLI argument - so it doesn't show up in `ps`.
- For MongoDB, `--password` is passed as a CLI flag (limitation of `mongodump`); it can briefly appear in `ps` listings on the source.
- For sqlite, no password is needed (file-level access).

If you need stricter handling - for example reading the password from a `.env` file already on the server, never sending it from CI - write a custom `backup-script` instead of using a template.

---

## Custom dumps

If a template doesn't fit your case, drop down to a custom `backup-script`:

```yaml
db-template: ''   # or just omit
backup-script: |
  set -euo pipefail
  ARCHIVE="$HOME/backups/custom_$(date -u +%Y%m%d_%H%M%S).tar.gz"
  # ...your dump+tar commands here...
  echo "$ARCHIVE"
```

You can mix: pick a template for the easy 80% of cases, write a custom script for the weird ones.
