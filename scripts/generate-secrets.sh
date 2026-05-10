#!/usr/bin/env bash

set -euo pipefail

# Emit fresh random values for the two LiteLLM secrets used in this setup.
# Output is formatted as `KEY=value` lines so it can be copied into `.env`
# and into the password vault entry for the deployment.
#
# This helper uses `openssl rand -hex` to avoid punctuation/whitespace issues
# in `.env` files while still producing high-entropy secrets.

if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl is required" >&2
  exit 1
fi

# `LITELLM_MASTER_KEY` protects admin/control-plane access.
echo "LITELLM_MASTER_KEY=$(openssl rand -hex 32)"
# `LITELLM_SALT_KEY` is used for DB-encrypted values; do not rotate it casually
# after credentials/models have been stored.
echo "LITELLM_SALT_KEY=$(openssl rand -hex 32)"
