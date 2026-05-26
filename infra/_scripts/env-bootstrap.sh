#!/usr/bin/env bash
# One-time bootstrap for a new environment (cluster owner only):
#   * prompts for non-secret identifying config (operator email, Cloudflare
#     zone/domain, R2 account id, R2 bucket) and writes it into env.hcl /
#     root.hcl in place of REPLACE_WITH_* placeholders (skipped if the file
#     already has real values; the pre-commit hook re-anonymizes on commit)
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
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=_r2-common.sh
source "$SCRIPT_DIR/_r2-common.sh"

r2_require_cmd aws jq ssh-keygen packer hcloud

# Fill in REPLACE_WITH_* placeholders BEFORE r2_load_env (it reads
# r2_account_id_default from root.hcl and will reject the placeholder).
ENV_FILE="${ENV_DIR:?ENV_DIR is required (e.g. ENV_DIR=infra/dev)}/env.hcl"
ROOT_FILE="$REPO_ROOT/infra/root.hcl"

# fill_placeholder <file> <placeholder> <prompt>
# Skips silently if the placeholder isn't present (real value already in place).
fill_placeholder() {
  local file="$1" placeholder="$2" prompt="$3" value
  if ! grep -q "$placeholder" "$file"; then
    return 0
  fi
  read -rp "$prompt" value
  if [[ -z "$value" ]]; then
    printf 'error: empty value for %s\n' "$placeholder" >&2
    exit 1
  fi
  # Escape sed delimiters in user input so emails / bucket names with `/` or `&` survive.
  local escaped
  escaped="$(printf '%s' "$value" | sed -e 's/[\/&]/\\&/g')"
  sed -i.bak -e "s/$placeholder/$escaped/g" "$file"
  rm -f "${file}.bak"
}

fill_placeholder "$ENV_FILE"  "REPLACE_WITH_OPERATOR_EMAIL"      "Enter operator email (Let's Encrypt + SigNoz admin): "
fill_placeholder "$ENV_FILE"  "REPLACE_WITH_CLOUDFLARE_DOMAIN"   "Enter Cloudflare domain (e.g. example.com): "
fill_placeholder "$ENV_FILE"  "REPLACE_WITH_CLOUDFLARE_ZONE_ID"  "Enter Cloudflare zone ID for that domain: "
fill_placeholder "$ROOT_FILE" "REPLACE_WITH_CF_ACCOUNT_ID"       "Enter Cloudflare account ID (for R2): "
fill_placeholder "$ROOT_FILE" "REPLACE_WITH_R2_BUCKET"           "Enter R2 bucket name: "

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
