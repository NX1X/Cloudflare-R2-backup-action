#!/usr/bin/env bash
# Tests for verify.sh: tar/zip/sha256 modes, validation, failure paths.

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${TEST_DIR}/lib/setup.sh"

run_verify() {
  bash "${REPO_DIR}/scripts/run.sh"
}

# --- Case: missing verify-mode
reset_state
export OPERATION="verify" R2_BUCKET="b" R2_OBJECT_KEY="d/a.tgz"
output=$(run_verify 2>&1); rc=$?
assert_exit_nonzero "$rc" "missing verify-mode errors"

# --- Case: invalid verify-mode
reset_state
export OPERATION="verify" R2_BUCKET="b" R2_OBJECT_KEY="d/a.tgz" R2_VERIFY_MODE="bogus"
output=$(run_verify 2>&1); rc=$?
assert_exit_nonzero "$rc" "invalid verify-mode errors"
assert_contains "$output" "verify-mode" "error mentions verify-mode"

# --- Case: tar mode, valid archive
reset_state
# Create a real tar.gz so the tar -tf check actually passes after the mock copies it.
TMP_DIR="$(mktemp -d)"
echo "hello" > "${TMP_DIR}/file1.txt"
TAR_FILE="${TMP_DIR}/archive.tgz"
tar -czf "$TAR_FILE" -C "$TMP_DIR" file1.txt
export OPERATION="verify" R2_BUCKET="b" R2_OBJECT_KEY="d/a.tgz" R2_VERIFY_MODE="tar"
# Point R2_FILE so verify.sh uses our tar file as the "downloaded" target;
# the mock `s3 cp` will copy our SRC=R2_FILE to DST=R2_FILE (no-op rewrite).
# Simpler: have the mock create the file at TARGET. But verify.sh uses mktemp
# when R2_FILE empty, then aws s3 cp <s3_uri> <target>. Mock: src=s3://...,
# isn't a real file, so it writes "mock-r2-content" - not a tar.
# Workaround: pre-stage a tar at a known target and pass it as R2_FILE.
# But verify.sh runs `aws s3 cp s3_uri R2_FILE` which our mock then *overwrites*
# with "mock-r2-content". So we need to handle this differently.
#
# Approach: monkey-patch by setting R2_MOCK_DOWNLOAD_FROM to copy a real file.
# Simpler - extend the mock to honor R2_MOCK_DOWNLOAD_FROM env var.
export R2_MOCK_DOWNLOAD_FROM="$TAR_FILE"
export R2_FILE="${TMP_DIR}/downloaded.tgz"
output=$(run_verify 2>&1); rc=$?
assert_exit_zero "$rc" "tar verify on valid archive succeeds"
assert_eq "$(gh_output verified)" "true" "verified=true for valid tar"
unset R2_MOCK_DOWNLOAD_FROM
rm -rf "$TMP_DIR"

# --- Case: tar mode, corrupt archive
reset_state
TMP_DIR="$(mktemp -d)"
CORRUPT="${TMP_DIR}/corrupt.tgz"
printf 'this is not a tar' > "$CORRUPT"
export OPERATION="verify" R2_BUCKET="b" R2_OBJECT_KEY="d/c.tgz" R2_VERIFY_MODE="tar"
export R2_MOCK_DOWNLOAD_FROM="$CORRUPT"
export R2_FILE="${TMP_DIR}/downloaded.tgz"
output=$(run_verify 2>&1); rc=$?
assert_exit_nonzero "$rc" "tar verify on corrupt archive fails"
assert_eq "$(gh_output verified)" "false" "verified=false for corrupt tar"
unset R2_MOCK_DOWNLOAD_FROM
rm -rf "$TMP_DIR"

# --- Case: sha256 mode, matching checksum
reset_state
TMP_DIR="$(mktemp -d)"
PAYLOAD="${TMP_DIR}/payload.bin"
printf 'hello-world' > "$PAYLOAD"
EXPECTED=$(sha256sum "$PAYLOAD" | awk '{print $1}')
export OPERATION="verify" R2_BUCKET="b" R2_OBJECT_KEY="d/p.bin" R2_VERIFY_MODE="sha256"
export R2_VERIFY_CHECKSUM="$EXPECTED"
export R2_MOCK_DOWNLOAD_FROM="$PAYLOAD"
export R2_FILE="${TMP_DIR}/downloaded.bin"
output=$(run_verify 2>&1); rc=$?
assert_exit_zero "$rc" "sha256 verify with matching checksum succeeds"
assert_eq "$(gh_output verified)" "true" "verified=true on sha256 match"
unset R2_MOCK_DOWNLOAD_FROM
rm -rf "$TMP_DIR"

# --- Case: sha256 mode, mismatched checksum
reset_state
TMP_DIR="$(mktemp -d)"
PAYLOAD="${TMP_DIR}/payload.bin"
printf 'hello-world' > "$PAYLOAD"
export OPERATION="verify" R2_BUCKET="b" R2_OBJECT_KEY="d/p.bin" R2_VERIFY_MODE="sha256"
export R2_VERIFY_CHECKSUM="0000000000000000000000000000000000000000000000000000000000000000"
export R2_MOCK_DOWNLOAD_FROM="$PAYLOAD"
export R2_FILE="${TMP_DIR}/downloaded.bin"
output=$(run_verify 2>&1); rc=$?
assert_exit_nonzero "$rc" "sha256 mismatch fails"
assert_eq "$(gh_output verified)" "false" "verified=false on sha256 mismatch"
unset R2_MOCK_DOWNLOAD_FROM
rm -rf "$TMP_DIR"

# --- Case: sha256 mode without checksum input errors
reset_state
export OPERATION="verify" R2_BUCKET="b" R2_OBJECT_KEY="d/p.bin" R2_VERIFY_MODE="sha256"
output=$(run_verify 2>&1); rc=$?
assert_exit_nonzero "$rc" "sha256 without checksum errors"
assert_contains "$output" "verify-checksum" "error mentions checksum input"
