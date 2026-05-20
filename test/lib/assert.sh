#!/usr/bin/env bash
# Tiny assertion library for shell-based unit tests.
# Sets PASSES / FAILS counters in the calling shell.

PASSES=${PASSES:-0}
FAILS=${FAILS:-0}

_pass() {
  PASSES=$((PASSES + 1))
  printf '  \033[32mPASS\033[0m %s\n' "$1"
}

_fail() {
  FAILS=$((FAILS + 1))
  printf '  \033[31mFAIL\033[0m %s\n' "$1"
  if [ -n "${2:-}" ]; then
    printf '       %s\n' "$2"
  fi
}

assert_eq() {
  local actual="$1" expected="$2" msg="${3:-equal}"
  if [ "$actual" = "$expected" ]; then
    _pass "$msg"
  else
    _fail "$msg" "expected='${expected}' actual='${actual}'"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-contains}"
  case "$haystack" in
    *"$needle"*) _pass "$msg" ;;
    *)           _fail "$msg" "missing='${needle}' in '${haystack}'" ;;
  esac
}

assert_not_contains() {
  local haystack="$1" needle="$2" msg="${3:-not contains}"
  case "$haystack" in
    *"$needle"*) _fail "$msg" "found='${needle}' in '${haystack}'" ;;
    *)           _pass "$msg" ;;
  esac
}

assert_exit_zero() {
  local rc="$1" msg="${2:-exit zero}"
  if [ "$rc" -eq 0 ]; then
    _pass "$msg"
  else
    _fail "$msg" "exit code was ${rc}"
  fi
}

assert_exit_nonzero() {
  local rc="$1" msg="${2:-exit nonzero}"
  if [ "$rc" -ne 0 ]; then
    _pass "$msg"
  else
    _fail "$msg" "exit code was 0"
  fi
}

# Read a single output value from $GITHUB_OUTPUT (line-style only).
gh_output() {
  local name="$1"
  awk -F= -v key="$name" '$1 == key { sub(/^[^=]+=/, ""); print; exit }' "$GITHUB_OUTPUT" 2>/dev/null || true
}
