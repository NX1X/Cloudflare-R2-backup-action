# Architecture & design notes

How `Cloudflare-R2-backup-action` is put together, and why. Useful for contributors and for advanced users who need to reason about edge cases (failure modes, security, restoration).

---

## The pipeline

Every backup, regardless of source mode or template, flows through three phases:

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│ 1. SOURCE PREP  │ →  │ 2. TRANSPORT     │ →  │ 3. SINK (R2)    │
│  dump + tar     │    │  scp / runner-   │    │  upload + prune │
│  on the source  │    │  local move      │    │  + verify       │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

The **action** (`action.yml` + `scripts/`) only owns phase 3 - that's the R2-specific part. The **reusable workflow** (`.github/workflows/backup.yml`) orchestrates all three phases and delegates phase 3 to the action.

This split is deliberate: phase 3 is reusable for any "push a file to R2" use case (artifact uploads, deploy assets, log archival), while the workflow is opinionated about backup semantics.

---

## Where templates run

DB templates (`templates/<engine>.sh`) **run on the source, not on the GitHub runner**.

The runner only:
1. Picks the template file
2. Prepends an env-var prelude with the user's `db-*` inputs
3. Pipes the resulting script to `bash` - locally for `source-mode: local`, or to `ssh user@host bash -s` for ssh/tunnel-ssh modes

### Implication: the source needs the dump binaries installed

| Template | Required on source |
|---|---|
| `mysql` | `mysqldump` or `mariadb-dump`, `tar`, `gzip`, optionally `docker` |
| `postgres` | `pg_dump` and/or `pg_dumpall`, `tar`, `gzip`, optionally `docker` |
| `mongodb` | `mongodump`, `tar`, `gzip`, optionally `docker` |
| `sqlite` | `sqlite3`, `tar`, `gzip` |

The action does not install these - that's the source's responsibility. We made this choice because:

- **Versions matter.** A `pg_dump` on the runner doesn't necessarily match the server's Postgres major version, and mixed versions can produce dumps that fail to restore. Running on the source guarantees binary↔database version parity.
- **Network locality.** Dumps over the network are slower and stress the DB connection. Running locally (or over a Unix socket inside `docker compose exec`) is faster and more reliable.
- **Auth simplicity.** Many DBs are configured for trust auth or socket-based auth from `localhost`. Running on the source means we don't need to widen network ACLs or provision a CI-only DB user.

### Alternative considered

Running dumps on the runner (with the DB exposed via SSH tunnel or direct connection). Rejected for the reasons above. Users who need this can write a custom `backup-script` that uses `cloudflare-tunnel-tcp-action` (planned) or a direct connection - the workflow's `local` source-mode supports this.

---

## Password traversal model

`DB_PASSWORD` (when used by a template) follows this path:

```
GitHub Secrets ──┐
                 ▼
  Workflow env var (DB_PASSWORD) ── masked in logs ──┐
                                                     ▼
  Prepare step writes script with literal password
  (printf %q escaping) to $RUNNER_TEMP/r2-backup-script.sh
                                                     │
                          ┌──────────────────────────┘
                          ▼
  local mode:           bash $SCRIPT_PATH      (password stays on runner)
  ssh / tunnel-ssh:     ssh ... bash -s < $SCRIPT_PATH   (password sent over SSH connection,
                                                          encrypted in transit, exists in
                                                          memory of the bash process on source)
```

### What's safe

- GitHub masks the password in run logs (any line containing the secret value is replaced with `***`).
- The transport from runner to source is encrypted (SSH, plus Cloudflare Tunnel + Access for `tunnel-ssh`).
- For `mysql` and `postgres`, the password is passed to the dump binary via env var (`MYSQL_PWD` / `PGPASSWORD`) - never as a CLI argument. So it doesn't appear in `ps`/`/proc/*/cmdline` on the source.

### What's not

- For `mongodb`, the password is passed as `--password <value>` (limitation of `mongodump` - there is no `MONGO_PASSWORD` env var). It can briefly appear in `ps` listings on the source while `mongodump` is running.
- The password sits as a literal string in the bash process's memory and stack on the source for the duration of the dump. Anyone with `root` or `ptrace` capability on the source during the run can read it.
- The script is not written to disk on the source (we use `bash -s <stdin>`), but it does pass through bash's argv/env on the source briefly.

### Stricter alternative

If you can't accept the source ever seeing the password as a literal - for example because the source has untrusted users or aggressive runtime introspection - drop the template and use a custom `backup-script` that reads the password from a file already on the server:

```yaml
backup-script: |
  set -euo pipefail
  cd /home/deploy/myapp
  DB_PASS=$(grep -E '^DATABASE_ROOT_PASSWORD=' .env | cut -d= -f2-)
  ARCHIVE="$HOME/backups/db_$(date -u +%Y%m%d_%H%M%S).tar.gz"
  MYSQL_PWD="$DB_PASS" mariadb-dump -u root --all-databases > /tmp/db.sql
  tar -czf "$ARCHIVE" -C /tmp db.sql
  echo "$ARCHIVE"
```

This is the pattern the IvritPedia hand-rolled workflows used. The password never leaves the server; CI never sees it.

---

## The env prelude pattern

When `db-template` is set, the prepare step builds the script that ultimately runs on the source like this:

```bash
#!/usr/bin/env bash
export DB_HOST=db.internal
export DB_PORT=3306
export DB_USER=root
export DB_NAME=
export DB_PASSWORD=hunter2\ with\ a\ space
export DUMP_BIN=mariadb-dump
# ... other vars ...

# (template body appended here)
set -euo pipefail
DB_HOST="${DB_HOST:-localhost}"
# ... mysql.sh body ...
```

The prelude is generated with:

```bash
printf 'export %s=%q\n' "$var" "$val"
```

`printf %q` is the right primitive because:

- It safely quotes any string for re-use as shell input. Spaces, `$`, backticks, single and double quotes - all escaped.
- It produces output that `bash` (when re-evaluating the script) interprets back to the original value. This is the same mechanism `ssh -o SendEnv` uses under the hood.
- It's a bash builtin (no fork/exec), so it's fast even when prepending a dozen variables.
- Alternative approaches (manual `'...'` quoting, base64 encoding, here-docs) all have edge cases or worse readability.

### Why not pass via `-o SendEnv`?

We considered using `ssh -o SendEnv=DB_HOST,DB_USER,...` to ship variables instead of inlining them. Rejected because:

- Requires `AcceptEnv` in the server's `sshd_config`, which most production servers don't have configured for arbitrary names.
- For tunnel-ssh mode, the SSH connection is wrapped by `cloudflared access ssh`, and we don't want to fight with how it propagates env.
- The `printf %q` prelude works identically in `local` mode (no SSH at all) and ssh modes - uniform code path is a feature.

---

## Archive layout per template

Every template produces a single `.tar.gz` whose filename is `<archive-name-prefix>_<UTC_TIMESTAMP>.tar.gz`. The contents at the archive root are:

| Template | Files at archive root | Restoration command |
|---|---|---|
| `mysql` | `database.sql` | `mysql -u root < database.sql` |
| `postgres` | `database.sql` | `psql -U postgres -f database.sql` (or `pg_restore` for custom-format dumps if user customizes) |
| `mongodb` | `dump.archive.gz` | `mongorestore --gzip --archive=dump.archive.gz` |
| `sqlite` | `<original-db-filename>` (e.g. `app.db`) | Just place the file back where it was; no restore command needed |

Each entry in `extra-paths` is added with `-C dirname basename`, so its **basename** sits at the archive root next to the dump file. Example: `extra-paths: /var/www/myapp/uploads` puts `uploads/` at the archive root.

### Why basename-flattening?

To keep restoration paths predictable and avoid `tar`'s default behavior of warning about absolute paths (`tar: Removing leading '/' from member names`). Users who need deeper structure preserved can write a custom `backup-script` and call `tar` themselves with whatever flags they prefer.

### MongoDB note

The mongo template's archive contains an already-gzipped file (`dump.archive.gz`) inside a gzipped tarball. The double-compression overhead is <1% (gzip compresses already-gzipped data poorly), and using `-czf` keeps the file extension consistent with the other templates so downstream consumers (verify, list, custom scripts) don't need engine-specific handling.

---

## Compared with hand-rolled workflows

The IvritPedia daily/weekly/monthly/manual backup workflows that motivated this action shared a common structure that was duplicated four times:

```
┌── ~25 lines: install cloudflared
│
├── ~25 lines: configure SSH-over-tunnel (id_ed25519, ~/.ssh/config, wrapper script)
│
├── ~30 lines: SSH to server, mariadb-dump inside docker compose, tar, scp back
│
├── ~25 lines: install s3cmd, configure ~/.s3cfg, s3cmd put
│
├── ~15 lines: retention loop parsing s3cmd ls output
│
├── ~20 lines: SSH back to server to remove temp file
│
├── ~25 lines: integrity check job (verify-integrity workflow only)
│
└── ~25 lines: Slack notification job

Total: ~190 lines per workflow file × 4 files = ~760 lines of duplicated boilerplate
```

After migrating to this action, the equivalent of all four workflows looks like:

```yaml
# 30 lines, repeated 4× with different cron + retention
jobs:
  backup:
    uses: NX1X/Cloudflare-R2-backup-action/.github/workflows/backup.yml@v1
    with:
      source-mode: tunnel-ssh
      db-template: mysql
      db-dump-binary: mariadb-dump
      ...
      retention-days: '90'
      verify-after-upload: true
    secrets: inherit
```

That's roughly a **5× reduction** in caller code, and the duplicated boilerplate (SSH, s3cmd, retention loop, verify, notify) lives once inside the action/workflow where it gets reviewed, tested, and versioned.

The downside: the action is its own thing to learn, and version-pinning the action is now part of users' deploy hygiene. We think the tradeoff is worth it because the boilerplate was already getting copy-pasted between repos in production setups - it just wasn't versioned anywhere.

---

## Repo layout

```
Cloudflare-R2-backup-action/
├── action.yml                    # Composite action: upload | prune | verify | list
├── scripts/
│   ├── run.sh                    # Action entry point, dispatches by $OPERATION
│   ├── upload.sh                 # `aws s3 cp` + optional inline prune
│   ├── prune.sh                  # Retention by age and/or count
│   ├── verify.sh                 # Download + tar/zip/sha256 check
│   ├── list.sh                   # JSON listing + count + total-size
│   └── lib/
│       ├── common.sh             # Logging, set_output, normalize_prefix, etc.
│       └── r2-config.sh          # AWS_ENDPOINT_URL_S3 derivation
│
├── templates/                    # DB dump recipes (run on source)
│   ├── mysql.sh
│   ├── postgres.sh
│   ├── mongodb.sh
│   └── sqlite.sh
│
├── .github/workflows/
│   ├── backup.yml                # Reusable workflow (workflow_call)
│   ├── ci.yml                    # actionlint + shellcheck + unit tests
│   └── release.yml               # (planned) tag + floating major
│
├── test/
│   ├── mocks/aws                 # Mock AWS CLI for unit tests
│   ├── lib/{assert,setup}.sh
│   ├── run_tests.sh              # Test harness
│   └── *_test.sh                 # Per-script tests
│
├── examples/                     # Caller workflows
│   ├── backup-local.yml
│   ├── backup-ssh.yml
│   ├── backup-tunnel-ssh.yml
│   ├── backup-mariadb-tunnel.yml
│   └── backup-postgres-ssh.yml
│
└── docs/
    ├── source-modes.md
    ├── db-templates.md
    └── architecture.md           # ← you are here
```
