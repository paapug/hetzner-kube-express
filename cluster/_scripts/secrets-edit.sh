#!/usr/bin/env bash
# Edit the R2-stored secrets.json for an environment.
#
# Downloads to a mode-700 tempdir, opens $EDITOR, validates JSON, uploads back.
# Tempfile is wiped on exit (EXIT/INT/TERM/HUP).
#
# Usage:
#   ENV_DIR=cluster/dev cluster/_scripts/secrets-edit.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_r2-common.sh
source "$SCRIPT_DIR/_r2-common.sh"

r2_require_cmd aws jq
r2_load_env
r2_require_aws_creds

EDITOR="${EDITOR:-vi}"

TMPDIR_SEC="$(mktemp -d)"
chmod 700 "$TMPDIR_SEC"
trap 'rm -rf "$TMPDIR_SEC"' EXIT INT TERM HUP

LOCAL="$TMPDIR_SEC/secrets.json"

if r2_aws s3api head-object --bucket "$R2_BUCKET" --key "$R2_SECRETS_KEY" >/dev/null 2>&1; then
  printf 'Fetching s3://%s/%s ...\n' "$R2_BUCKET" "$R2_SECRETS_KEY" >&2
  r2_aws s3 cp "s3://${R2_BUCKET}/${R2_SECRETS_KEY}" "$LOCAL" >/dev/null
else
  printf 'No existing object at s3://%s/%s; starting from a template.\n' \
    "$R2_BUCKET" "$R2_SECRETS_KEY" >&2
  cat > "$LOCAL" <<'JSON'
{
  "hcloud_token": "",
  "cloudflare_api_token": "",
  "ssh_public_key": "",
  "ssh_private_key": ""
}
JSON
fi
chmod 600 "$LOCAL"

CHECKSUM_BEFORE="$(shasum -a 256 "$LOCAL" | awk '{print $1}')"
"$EDITOR" "$LOCAL"

if ! jq empty "$LOCAL" >/dev/null 2>&1; then
  echo "error: edited file is not valid JSON; aborting upload" >&2
  exit 1
fi

CHECKSUM_AFTER="$(shasum -a 256 "$LOCAL" | awk '{print $1}')"
if [[ "$CHECKSUM_BEFORE" == "$CHECKSUM_AFTER" ]]; then
  echo "No changes; nothing to upload." >&2
  exit 0
fi

printf 'Uploading to s3://%s/%s ...\n' "$R2_BUCKET" "$R2_SECRETS_KEY" >&2
r2_aws s3 cp "$LOCAL" "s3://${R2_BUCKET}/${R2_SECRETS_KEY}" \
  --content-type application/json >/dev/null
echo "Done." >&2
