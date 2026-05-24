#!/usr/bin/env bash
# Restore the cluster SSH key locally from R2 secrets.json (for ssh(1)/scp).
#
# Usage:
#   ENV_DIR=cluster/dev cluster/_scripts/fetch-ssh-key.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_r2-common.sh
source "$SCRIPT_DIR/_r2-common.sh"

r2_require_cmd aws jq
r2_load_env
r2_require_aws_creds

ENV_DIR_ABS="$(cd "$ENV_DIR" && pwd)"
SSH_DIR="$ENV_DIR_ABS/.cluster_ssh"
SSH_KEY="$SSH_DIR/cluster_ed25519"

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

TMPDIR_SEC="$(mktemp -d)"
chmod 700 "$TMPDIR_SEC"
trap 'rm -rf "$TMPDIR_SEC"' EXIT INT TERM HUP

LOCAL="$TMPDIR_SEC/secrets.json"
r2_aws s3 cp "s3://${R2_BUCKET}/${R2_SECRETS_KEY}" "$LOCAL" >/dev/null
chmod 600 "$LOCAL"

jq -r '.ssh_private_key' "$LOCAL" > "$SSH_KEY"
jq -r '.ssh_public_key'  "$LOCAL" > "${SSH_KEY}.pub"
chmod 600 "$SSH_KEY"
chmod 644 "${SSH_KEY}.pub"

printf 'Wrote %s and %s.pub\n' "$SSH_KEY" "$SSH_KEY"
ssh-keygen -lf "${SSH_KEY}.pub"
