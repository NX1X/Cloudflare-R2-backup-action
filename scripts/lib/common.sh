#!/usr/bin/env bash
# Shared helpers for Cloudflare-R2-backup-action scripts.
# Source this file from each operation script:
#   . "${SCRIPT_DIR}/lib/common.sh"

set -euo pipefail

log_info() {
  printf '[r2-backup] %s\n' "$*"
}

log_warn() {
  printf '[r2-backup] WARN: %s\n' "$*" >&2
}

log_error() {
  printf '[r2-backup] ERROR: %s\n' "$*" >&2
}

die() {
  log_error "$*"
  exit 1
}

require_env() {
  local name="$1"
  local value="${!name:-}"
  if [ -z "$value" ]; then
    die "Required input missing: $name"
  fi
}

set_output() {
  local name="$1"
  local value="$2"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    printf '%s=%s\n' "$name" "$value" >> "$GITHUB_OUTPUT"
  fi
}

# Set a GHA output that may contain newlines (e.g. JSON). Uses heredoc form.
# Safe even when value contains the delimiter - picks a unique one per call.
set_output_multiline() {
  local name="$1"
  local value="$2"
  local delim
  delim="EOF_$(date +%s%N 2>/dev/null || date +%s)_$$"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
      printf '%s<<%s\n' "$name" "$delim"
      printf '%s\n' "$value"
      printf '%s\n' "$delim"
    } >> "$GITHUB_OUTPUT"
  fi
}

# Normalize a prefix so it ends with exactly one '/' (or is empty).
normalize_prefix() {
  local p="${1:-}"
  if [ -z "$p" ]; then
    printf ''
    return
  fi
  printf '%s/' "${p%/}"
}
