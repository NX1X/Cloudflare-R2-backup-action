#!/usr/bin/env bash
# Configures the AWS CLI environment for Cloudflare R2.
# Expects to be sourced after common.sh is sourced.
#
# Required env: CF_ACCOUNT_ID, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
# Optional env: R2_ENDPOINT_URL
#
# Sets/exports: AWS_DEFAULT_REGION, AWS_ENDPOINT_URL_S3, R2_ENDPOINT (for callers)

require_env CF_ACCOUNT_ID
require_env AWS_ACCESS_KEY_ID
require_env AWS_SECRET_ACCESS_KEY

if [ -n "${R2_ENDPOINT_URL:-}" ]; then
  R2_ENDPOINT="$R2_ENDPOINT_URL"
else
  R2_ENDPOINT="https://${CF_ACCOUNT_ID}.r2.cloudflarestorage.com"
fi

export AWS_DEFAULT_REGION="auto"
export AWS_ENDPOINT_URL_S3="$R2_ENDPOINT"
export R2_ENDPOINT

if ! command -v aws >/dev/null 2>&1; then
  die "aws CLI not found. This action requires aws to be installed (pre-installed on GitHub-hosted runners)."
fi
