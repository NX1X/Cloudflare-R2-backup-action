# Contributing to Cloudflare-R2-backup-action

Thanks for your interest in contributing! Here's how to get started.

## How to Contribute

1. **Found a bug?** [Open an issue](https://github.com/NX1X/Cloudflare-R2-backup-action/issues/new?template=bug_report.yml)
2. **Have an idea?** [Request a feature](https://github.com/NX1X/Cloudflare-R2-backup-action/issues/new?template=feature_request.yml) or check the [Roadmap](docs/ROADMAP.md)
3. **Want to contribute code?** Fork the repo, make your changes, open a pull request

## Development Setup

```bash
# Clone the repo
git clone https://github.com/NX1X/Cloudflare-R2-backup-action.git
cd Cloudflare-R2-backup-action

# Install linting tools (optional - CI runs these automatically)
# actionlint: https://github.com/rhysd/actionlint
# shellcheck: https://github.com/koalaman/shellcheck
```

## Development Workflow

1. Create a branch from `main`
2. Make your changes - typically in:
   - `action.yml` (action interface)
   - `scripts/*.sh` (operation logic)
   - `templates/*.sh` (DB dump recipes)
   - `.github/workflows/backup.yml` (reusable workflow)
3. Run quality checks locally (if tools are installed):
   ```bash
   actionlint
   find scripts templates -name '*.sh' -print0 | xargs -0 shellcheck --severity=warning -x
   bash test/run_tests.sh
   ```
4. Update `CHANGELOG.md` under the `[Unreleased]` section
5. Open a pull request

## Code Standards

- **Shell**: All `run:` blocks use `bash`. Scripts use `set -euo pipefail`.
- **Linting**: Must pass `actionlint` and `shellcheck` (severity warning or higher)
- **Secrets**: Always use `env:` blocks - never inline `${{ secrets.* }}` in `run:` commands
- **Inputs in shell**: Never inline `${{ inputs.* }}` in shell scripts - route through `env:` to prevent injection
- **AWS CLI**: Pre-installed on GitHub-hosted runners; do not add an install step
- **No Node.js / no compiled binaries** - this is a composite shell action

## Tests

- Unit tests live in `test/` and use a mocked `aws` CLI (see `test/mocks/aws`)
- Each script script has a corresponding `*_test.sh` file
- Run with `bash test/run_tests.sh`
- New operations or branches must have at least one test case

## Changelog

- Follow [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) format
- Categorize: Added, Changed, Deprecated, Removed, Fixed, Security
- Add entries under `[Unreleased]`

## Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add zstd compression support to mysql template
fix: prune.sh handles 0-byte objects correctly
docs: clarify db-template precedence over backup-script
ci: pin actionlint to v1.7.7
test: add coverage for retention-count edge case
```

## Pull Requests

- Fill out the PR template completely
- Reference any related issues
- Keep PRs focused - one fix or feature per PR
- All CI checks must pass before merge

## Releasing (maintainers only)

1. Update `CHANGELOG.md` - add a `[X.Y.Z]` section under `[Unreleased]` with the release date
2. Go to **Actions** → **Release** → **Run workflow**
3. Enter the version (e.g. `1.1.0`)
4. The workflow validates, creates the tag, publishes the GitHub Release, and updates the floating major tag (`v1` → `v1.1.0`)
