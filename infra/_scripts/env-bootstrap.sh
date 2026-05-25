#!/usr/bin/env bash
# One-time bootstrap for a new environment (cluster owner only):
#   * generates an ed25519 cluster SSH key
#   * prompts for the Hetzner Cloud + Cloudflare API tokens
#   * builds secrets.json and uploads it to R2 at secrets/<env>/secrets.json
#   * builds the kube-hetzner MicroOS snapshot via packer (skipped if one
#     already exists in the Hetzner project; FORCE_PACKER=1 to rebuild)
#
# Refuses to overwrite an existing R2 object unless FORCE=1.
#
# Usage:
#   ENV_DIR=infra/dev infra/_scripts/env-bootstrap.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_r2-common.sh
source "$SCRIPT_DIR/_r2-common.sh"

r2_require_cmd aws jq ssh-keygen packer hcloud
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

CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:-}"
if [[ -z "$CLOUDFLARE_API_TOKEN" ]]; then
  read -rsp "Enter Cloudflare API token (DNS Read & Write; zone-scoped): " CLOUDFLARE_API_TOKEN; echo
fi
if [[ -z "$CLOUDFLARE_API_TOKEN" ]]; then
  echo "error: empty cloudflare api token" >&2
  exit 1
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

unset CLOUDFLARE_API_TOKEN

printf 'Uploading to s3://%s/%s ...\n' "$R2_BUCKET" "$R2_SECRETS_KEY" >&2
r2_aws s3 cp "$SECRETS" "s3://${R2_BUCKET}/${R2_SECRETS_KEY}" \
  --content-type application/json >/dev/null

# kube-hetzner data-references an existing MicroOS snapshot; build it once per
# Hetzner project. Snapshots carry the label microos-snapshot=yes (set by the
# packer template), so we probe by label rather than by name.
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PACKER_DIR="$REPO_ROOT/infra/packer"
PACKER_TEMPLATE="hcloud-microos-snapshots.pkr.hcl"

export HCLOUD_TOKEN
EXISTING_SNAPSHOT="$(hcloud image list -t snapshot -l microos-snapshot=yes -o noheader -o columns=id 2>/dev/null | head -n1 || true)"

if [[ -n "$EXISTING_SNAPSHOT" && "${FORCE_PACKER:-0}" != "1" ]]; then
  printf 'MicroOS snapshot already present in Hetzner project (id=%s); skipping packer. Set FORCE_PACKER=1 to rebuild.\n' \
    "$EXISTING_SNAPSHOT" >&2
else
  if [[ -n "$EXISTING_SNAPSHOT" ]]; then
    echo "warn: FORCE_PACKER=1 set; will build a new MicroOS snapshot alongside existing id=$EXISTING_SNAPSHOT." >&2
  fi
  printf 'Building MicroOS snapshot via packer (this takes ~5-10 min)...\n' >&2
  (
    cd "$PACKER_DIR"
    packer init "$PACKER_TEMPLATE"
    packer build "$PACKER_TEMPLATE"
  )
fi

unset HCLOUD_TOKEN

cat <<EOF

Bootstrapped s3://${R2_BUCKET}/${R2_SECRETS_KEY}.

Next steps:
  ENV_DIR=$ENV_DIR infra/_scripts/fetch-ssh-key.sh   # restore SSH key locally
  cd $ENV_DIR && terragrunt run --all apply
EOF
