#!/usr/bin/env bash
# One-time bootstrap for a new environment (cluster owner only):
#   * generates an ed25519 cluster SSH key
#   * prompts for the Hetzner Cloud API token
#   * builds secrets.json
#   * uploads it to R2 at secrets/<env>/secrets.json
#
# Refuses to overwrite an existing R2 object unless FORCE=1.
#
# Usage:
#   ENV_DIR=infra/dev infra/_scripts/r2-bootstrap.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_r2-common.sh
source "$SCRIPT_DIR/_r2-common.sh"

r2_require_cmd aws jq ssh-keygen
r2_load_env
r2_require_aws_creds

if r2_aws s3api head-object --bucket "$R2_BUCKET" --key "$R2_SECRETS_KEY" >/dev/null 2>&1; then
  if [[ "${FORCE:-0}" != "1" ]]; then
    cat >&2 <<EOF
error: s3://${R2_BUCKET}/${R2_SECRETS_KEY} already exists.
  Use infra/_scripts/secrets-edit.sh to modify it, or rerun with FORCE=1
  to overwrite (rotates the cluster SSH key — irreversible).
EOF
    exit 1
  fi
  echo "warn: FORCE=1 set; will overwrite the existing R2 object." >&2
fi

TMPDIR_SEC="$(mktemp -d)"
chmod 700 "$TMPDIR_SEC"
trap 'rm -rf "$TMPDIR_SEC"' EXIT INT TERM HUP

SSH_KEY="$TMPDIR_SEC/cluster_ed25519"
ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" \
  -C "k8s-playground-${R2_ENV_NAME}" >/dev/null
chmod 600 "$SSH_KEY"
chmod 644 "${SSH_KEY}.pub"

HCLOUD_TOKEN="${HCLOUD_TOKEN:-}"
if [[ -z "$HCLOUD_TOKEN" ]]; then
  read -rsp "Enter Hetzner Cloud API token (input hidden): " HCLOUD_TOKEN; echo
fi
if [[ -z "$HCLOUD_TOKEN" ]]; then
  echo "error: empty hcloud token" >&2
  exit 1
fi

# Cloudflare API token is optional at bootstrap time — the cloudflare-dns
# unit will fail to apply until it's set, but the cluster/acme units don't
# need it. Leave blank to fill in later via secrets-edit.sh.
CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:-}"
if [[ -z "$CLOUDFLARE_API_TOKEN" ]]; then
  read -rsp "Enter Cloudflare API token (Zone:DNS:Edit; blank to skip): " CLOUDFLARE_API_TOKEN; echo
fi

SECRETS="$TMPDIR_SEC/secrets.json"
jq -n \
  --arg token    "$HCLOUD_TOKEN" \
  --arg cf_token "$CLOUDFLARE_API_TOKEN" \
  --arg pub      "$(cat "${SSH_KEY}.pub")" \
  --arg priv     "$(cat "$SSH_KEY")" \
  '{
     hcloud_token:         $token,
     cloudflare_api_token: $cf_token,
     ssh_public_key:       $pub,
     ssh_private_key:      $priv
   }' > "$SECRETS"
chmod 600 "$SECRETS"

unset HCLOUD_TOKEN CLOUDFLARE_API_TOKEN

printf 'Uploading to s3://%s/%s ...\n' "$R2_BUCKET" "$R2_SECRETS_KEY" >&2
r2_aws s3 cp "$SECRETS" "s3://${R2_BUCKET}/${R2_SECRETS_KEY}" \
  --content-type application/json >/dev/null

cat <<EOF

Bootstrapped s3://${R2_BUCKET}/${R2_SECRETS_KEY}.

Next steps:
  ENV_DIR=$ENV_DIR infra/_scripts/fetch-ssh-key.sh   # restore SSH key locally
  cd $ENV_DIR && terragrunt run --all plan
EOF
