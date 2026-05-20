# Source modes

The reusable `backup.yml` workflow supports several **source modes** - where the backup script runs and how the resulting archive gets to R2.

| Mode | Available | Where the script runs | How the archive reaches R2 |
|------|-----------|------------------------|----------------------------|
| `local` | v1.1+ | GitHub-hosted runner | Direct upload from runner |
| `ssh` | v1.1+ | Remote server via plain SSH | SCP from server to runner, then upload |
| `tunnel-ssh` | v1.2+ | Remote server via Cloudflare Tunnel + Access | SCP through the tunnel, then upload |

All modes share the same archive-handoff contract.

---

## The backup-script contract

Every source mode runs your `backup-script` input and expects:

1. **Last line of stdout = absolute path to the archive file** on the source.
2. **All other output should go to stderr** - progress messages, warnings, etc.
3. The script should exit non-zero on failure; the workflow aborts on a non-zero exit.

A minimal script:

```bash
set -euo pipefail
TIMESTAMP=$(date -u +%Y%m%d_%H%M%S)
ARCHIVE="/tmp/backup_${TIMESTAMP}.tar.gz"

echo "Building archive..." >&2     # log to stderr
tar -czf "$ARCHIVE" /var/www

echo "$ARCHIVE"                    # ONLY the path on stdout (last line)
```

Why this contract? It's simple, language-agnostic, and lets you compose with any source-prep tool that prints a path. It also keeps logs visible in the runner UI without polluting the path-resolution.

---

## `local` mode

The script runs on the GitHub runner itself. Use this for:

- Backing up the contents of the repo or generated artifacts (build output, exported docs)
- Repackaging things you've already downloaded earlier in the workflow
- Anything where the data already lives on the runner

```yaml
jobs:
  backup:
    uses: NX1X/Cloudflare-R2-backup-action/.github/workflows/backup.yml@v1
    with:
      source-mode: local
      backup-script: |
        ARCHIVE=/tmp/dist.tar.gz
        tar -czf "$ARCHIVE" ./dist
        echo "$ARCHIVE"
      bucket: my-backups
    secrets:
      R2_ACCOUNT_ID:        ${{ secrets.CF_ACCOUNT_ID }}
      R2_ACCESS_KEY_ID:     ${{ secrets.R2_ACCESS_KEY_ID }}
      R2_SECRET_ACCESS_KEY: ${{ secrets.R2_SECRET_ACCESS_KEY }}
```

**Limits:** GitHub-hosted runners get ~14 GB of free disk, ~7 GB RAM. If your backup is larger, you need a self-hosted runner or `ssh` mode.

---

## `ssh` mode

The script runs on a remote server reached over plain SSH. The workflow:

1. Writes your `SSH_PRIVATE_KEY` secret to the runner
2. Configures `~/.ssh/config` for the host
3. Pipes your `backup-script` to `ssh user@host bash -s`
4. Reads the path from the script's last stdout line
5. SCPs the archive back to the runner
6. Uploads to R2
7. (Optional) Removes the temporary archive from the remote source

```yaml
jobs:
  backup:
    uses: NX1X/Cloudflare-R2-backup-action/.github/workflows/backup.yml@v1
    with:
      source-mode: ssh
      ssh-host:    ${{ vars.SSH_HOST }}
      ssh-user:    ${{ vars.SSH_USER }}
      ssh-known-hosts: ${{ secrets.SSH_KNOWN_HOSTS }}

      backup-script: |
        ARCHIVE="$HOME/backup_$(date -u +%Y%m%d_%H%M%S).tar.gz"
        tar -czf "$ARCHIVE" -C "$HOME/myapp" data
        echo "$ARCHIVE"

      bucket: my-backups
      prefix: daily/
      retention-days: '90'

    secrets:
      R2_ACCOUNT_ID:        ${{ secrets.CF_ACCOUNT_ID }}
      R2_ACCESS_KEY_ID:     ${{ secrets.R2_ACCESS_KEY_ID }}
      R2_SECRET_ACCESS_KEY: ${{ secrets.R2_SECRET_ACCESS_KEY }}
      SSH_PRIVATE_KEY:      ${{ secrets.SSH_PRIVATE_KEY }}
```

### Required secrets/inputs

| What | Where | Required? |
|------|-------|-----------|
| `SSH_PRIVATE_KEY` | secret | Yes - matching public key must be in the server's `~/.ssh/authorized_keys` |
| `ssh-host`, `ssh-user` | input | Yes |
| `ssh-port` | input | No - defaults to `22` |
| `ssh-known-hosts` | input | Strongly recommended - output of `ssh-keyscan -t ed25519 host`. Without it, the workflow falls back to TOFU (`StrictHostKeyChecking=no`), which works but is vulnerable to MITM. |

### Generating known-hosts

```bash
ssh-keyscan -t ed25519,rsa your-host.example.com
```

Paste the output into a repo secret (e.g. `SSH_KNOWN_HOSTS`) and pass it as `ssh-known-hosts:`.

### Server requirements

- A user account with SSH access (key-based auth)
- The user must be able to run your backup-script (read access to the data, write access to a temp directory for the archive)
- `bash` available (the script is piped to `bash -s`)
- `tar`, `gzip`, and any DB clients (`pg_dump`, `mysqldump`, `mongodump`) your script invokes

### Cleanup

By default, after a successful upload the workflow removes the archive from the remote source. Set `cleanup-source: false` to keep it (useful for backups you want to retain locally on the server too).

---

## `tunnel-ssh` mode

The script runs on a remote server reached through a **Cloudflare Tunnel**, authenticated by a Cloudflare Access service token. The server doesn't need a public IP, an open port 22, or any inbound firewall rule - only outbound HTTPS to Cloudflare.

Internally, the workflow delegates the tunnel setup to [`NX1X/cloudflare-tunnel-ssh-action`](https://github.com/NX1X/cloudflare-tunnel-ssh-action), which:

1. Installs `cloudflared`
2. Configures a `ProxyCommand` in `~/.ssh/config` that wraps `cloudflared access ssh`
3. Embeds the service token credentials in a wrapper script (`~/.cloudflared-ssh`)
4. Optionally tests the connection

After setup, plain `ssh user@host` and `scp` work transparently - the tunnel is invisible to the rest of the workflow.

```yaml
jobs:
  backup:
    uses: NX1X/Cloudflare-R2-backup-action/.github/workflows/backup.yml@v1
    with:
      source-mode: tunnel-ssh
      ssh-host:    ${{ vars.TUNNEL_HOSTNAME }}
      ssh-user:    ${{ vars.SSH_USER }}

      backup-script: |
        set -euo pipefail
        ARCHIVE="$HOME/backup_$(date -u +%Y%m%d_%H%M%S).tar.gz"
        cd "$HOME/myapp"
        docker compose exec -T db pg_dumpall -U postgres > /tmp/db.sql
        tar -czf "$ARCHIVE" -C /tmp db.sql -C "$HOME/myapp/data" .
        rm -f /tmp/db.sql
        echo "$ARCHIVE"

      bucket: my-backups
      prefix: daily/
      retention-days: '90'
      verify-after-upload: true

    secrets:
      R2_ACCOUNT_ID:           ${{ secrets.CF_ACCOUNT_ID }}
      R2_ACCESS_KEY_ID:        ${{ secrets.R2_ACCESS_KEY_ID }}
      R2_SECRET_ACCESS_KEY:    ${{ secrets.R2_SECRET_ACCESS_KEY }}
      CF_ACCESS_CLIENT_ID:     ${{ secrets.CF_ACCESS_CLIENT_ID }}
      CF_ACCESS_CLIENT_SECRET: ${{ secrets.CF_ACCESS_CLIENT_SECRET }}
      SSH_PRIVATE_KEY:         ${{ secrets.SSH_PRIVATE_KEY }}
```

### Required secrets/inputs

| What | Where | Required? |
|------|-------|-----------|
| `CF_ACCESS_CLIENT_ID` | secret | Yes - Cloudflare Access service token ID |
| `CF_ACCESS_CLIENT_SECRET` | secret | Yes - Cloudflare Access service token secret |
| `SSH_PRIVATE_KEY` | secret | Yes - public key on server's `~/.ssh/authorized_keys` |
| `ssh-host` | input | Yes - the hostname routed through the tunnel |
| `ssh-user` | input | Yes - SSH username on the server |
| `cloudflared-version` | input | No - defaults to `latest` |

### Setup checklist

1. **Cloudflare Tunnel** running on the server, exposing SSH (port 22). See [Cloudflare Tunnel docs](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/).
2. **Cloudflare Access application** protecting the SSH hostname. Policy: allow your service token.
3. **Service token** created in the Access dashboard. Save the Client ID and Client Secret as repo secrets.
4. **SSH key pair** - generate with `ssh-keygen -t ed25519`, put the public half in the server's `authorized_keys`, save the private half as `SSH_PRIVATE_KEY` secret.

### Why use it

- Server stays behind zero firewall holes - only outbound HTTPS needed
- Service token revocation is instant (no SSH key rotation across the fleet)
- Same backup script works whether the server is on the public internet or hidden behind a tunnel - just flip `source-mode`

---

## Choosing a mode

| If… | Use |
|-----|-----|
| The data is already on the runner (build output, repo contents) | `local` |
| The server has a public IP and SSH on a reachable port | `ssh` |
| The server is behind a firewall / has no public IP | `tunnel-ssh` |
