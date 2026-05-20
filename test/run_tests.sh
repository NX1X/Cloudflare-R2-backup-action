#!/usr/bin/env bash
# Run all unit tests for Cloudflare-R2-backup-action.
# Each *_test.sh file must end with a line: "TEST_RESULT pass=N fail=M"
# Usage: bash test/run_tests.sh [test/*_test.sh]

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${TEST_DIR}/.." && pwd)"

export REPO_DIR
export PATH="${TEST_DIR}/mocks:${PATH}"

chmod +x "${TEST_DIR}/mocks/aws" 2>/dev/null || true

if [ $# -gt 0 ]; then
  TESTS=("$@")
else
  TESTS=()
  while IFS= read -r f; do TESTS+=("$f"); done < <(find "$TEST_DIR" -maxdepth 1 -name '*_test.sh' | sort)
fi

TOTAL_PASS=0
TOTAL_FAIL=0
FAILED_FILES=()

for t in "${TESTS[@]}"; do
  printf '\n--- %s ---\n' "$(basename "$t")"
  output=$(bash "$t" 2>&1) || true
  printf '%s\n' "$output"
  while IFS= read -r line; do
    case "$line" in
      "TEST_RESULT pass="*)
        p=$(printf '%s' "$line" | sed -E 's/TEST_RESULT pass=([0-9]+) fail=([0-9]+).*/\1/')
        f=$(printf '%s' "$line" | sed -E 's/TEST_RESULT pass=([0-9]+) fail=([0-9]+).*/\2/')
        TOTAL_PASS=$((TOTAL_PASS + p))
        TOTAL_FAIL=$((TOTAL_FAIL + f))
        if [ "$f" -gt 0 ]; then FAILED_FILES+=("$(basename "$t")"); fi
        ;;
    esac
  done <<< "$output"
done

printf '\n=================================\n'
printf 'PASS: %d  FAIL: %d\n' "$TOTAL_PASS" "$TOTAL_FAIL"
if [ "$TOTAL_FAIL" -gt 0 ]; then
  printf 'Failed files: %s\n' "${FAILED_FILES[*]}"
  exit 1
fi
exit 0
