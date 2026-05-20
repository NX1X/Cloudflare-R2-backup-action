# Roadmap

Planned features for `Cloudflare-R2-backup-action`.

Community votes and contributions are welcome - [open an issue](https://github.com/NX1X/Cloudflare-R2-backup-action/issues/new) or PR!

---

## Planned

- [ ] **Multi-path archives with structure preservation** - extend `extra-paths` to optionally preserve directory structure or use named sections (e.g. `config: /etc/myapp` -> `config/...` inside the tarball)
- [ ] **`s3cmd` -> `aws-cli` migration guide** - dedicated doc for users migrating hand-rolled backup workflows
- [ ] **macOS / Windows runner support** - currently optimized for Ubuntu/Debian (AWS CLI is pre-installed there)
- [ ] **Compression options** - `compression: gzip | zstd | none` input on templates for users who already have a fast network and want lower CPU
- [ ] **Encryption-at-rest before upload** - `encrypt-key` / `encrypt-key-id` inputs to age- or gpg-encrypt the archive before uploading
- [ ] **Multipart upload tuning** - inputs to control AWS CLI's multipart thresholds for very large archives
- [ ] **Restore helper action** - `operation: restore` that downloads + extracts an archive, optionally back through SSH/tunnel-ssh

---

## Completed

- [x] `upload` operation - push file to R2 with optional inline retention prune
- [x] `prune` operation - retention by age and/or count
- [x] `verify` operation - download + tar/zip/sha256 integrity check
- [x] `list` operation - JSON listing with count and total-size
- [x] AWS CLI under the hood with auto-derived R2 endpoint
- [x] Unit tests with mocked AWS CLI
- [x] CI: actionlint + shellcheck (pinned versions)
- [x] Reusable workflow `backup.yml` with `local`, `ssh`, `tunnel-ssh` source modes
- [x] DB templates: `mysql`, `postgres`, `mongodb`, `sqlite`
- [x] Optional `docker compose exec` wrapping for templates
- [x] `extra-paths` input for including arbitrary files alongside the dump
- [x] Manual release workflow with floating major version tag
- [x] Manual smoke-test workflow against real R2
- [x] Issue templates, PR template, CODEOWNERS, Dependabot
- [x] Documentation: source modes, DB templates, architecture/design notes
- [x] Notification hooks - `notify-webhook-format` / `notify-on-success` / `notify-on-failure` workflow inputs + `NOTIFY_WEBHOOK_URL` secret for Slack/Discord/generic webhook delivery on backup completion or failure
