#!/usr/bin/env bash
# One-time (or per-machine) setup: age key, cluster SSH key, encrypted secrets.enc.json
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

AGE_KEY="${SOPS_AGE_KEY_FILE:-$ROOT/.age/key.txt}"
SSH_KEY="${SSH_KEY:-$ROOT/.age/cluster_ed25519}"
SECRETS_PLAIN="${SECRETS_PLAIN:-$ROOT/secrets.json}"
SECRETS_ENC="$ROOT/secrets.enc.json"
SOPS_CONFIG="$ROOT/.sops.yaml"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: '$1' not found." >&2
    case "$1" in
      age | age-keygen)
        echo "  Install: brew install age   (or your distro package)" >&2
        ;;
      sops)
        echo "  Install: brew install sops" >&2
        ;;
      jq)
        echo "  Install: brew install jq" >&2
        ;;
      ssh-keygen)
        echo "  Install: openssh client (ssh-keygen)" >&2
        ;;
    esac
    exit 1
  fi
}

require_cmd sops
require_cmd age-keygen
require_cmd jq
require_cmd ssh-keygen

mkdir -p "$(dirname "$AGE_KEY")"

if [[ ! -f "$AGE_KEY" ]]; then
  echo "Generating age key: $AGE_KEY"
  age-keygen -o "$AGE_KEY" >/dev/null
  chmod 600 "$AGE_KEY"
fi

PUBKEY="$(grep '^# public key:' "$AGE_KEY" | awk '{print $4}')"
if [[ -z "$PUBKEY" ]]; then
  echo "error: could not read public key from $AGE_KEY" >&2
  exit 1
fi

if grep -q 'REPLACE_WITH_PUBLIC_KEY' "$SOPS_CONFIG" 2>/dev/null; then
  sed "s/REPLACE_WITH_PUBLIC_KEY/${PUBKEY}/" "$SOPS_CONFIG" > "${SOPS_CONFIG}.tmp"
  mv "${SOPS_CONFIG}.tmp" "$SOPS_CONFIG"
  echo "Updated .sops.yaml with public key ${PUBKEY}"
elif ! grep -q "$PUBKEY" "$SOPS_CONFIG"; then
  echo "warning: .sops.yaml already has a different public key." >&2
  echo "  Your key: ${PUBKEY}" >&2
  echo "  Add it manually to creation_rules if you need multi-key access." >&2
fi

if [[ ! -f "$SECRETS_PLAIN" ]]; then
  cp "$ROOT/secrets.example.json" "$SECRETS_PLAIN"
  echo "Created $SECRETS_PLAIN — set hcloud_token, then re-run: make sops-setup"
  exit 0
fi

if [[ ! -f "$SSH_KEY" ]]; then
  echo "Generating cluster SSH key: ${SSH_KEY}"
  ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "k8s-playground-dev" >/dev/null
  chmod 600 "$SSH_KEY"
  chmod 644 "${SSH_KEY}.pub"
fi

# Merge SSH key material into secrets.json (preserves existing hcloud_token, firewall, etc.)
TMP="$(mktemp)"
jq \
  --arg pub "$(cat "${SSH_KEY}.pub")" \
  --arg priv "$(cat "$SSH_KEY")" \
  '.ssh_public_key = $pub | .ssh_private_key = $priv' \
  "$SECRETS_PLAIN" > "$TMP"
mv "$TMP" "$SECRETS_PLAIN"

cp "$SECRETS_PLAIN" "$SECRETS_ENC"
SOPS_AGE_KEY_FILE="$AGE_KEY" sops --encrypt --input-type json --output-type json --in-place "$SECRETS_ENC"
echo "Wrote encrypted $SECRETS_ENC (includes cluster SSH key; keep $SECRETS_PLAIN out of git)"

echo ""
echo "Cluster SSH public key fingerprint:"
ssh-keygen -lf "${SSH_KEY}.pub"
echo ""
echo "Local key files (gitignored): ${SSH_KEY}{,.pub}"
echo "  ssh -i ${SSH_KEY} root@<node-ip>"
echo ""
echo "Done. Use:  export SOPS_AGE_KEY_FILE=$AGE_KEY"
echo "            make plan   # or make apply"
echo ""
echo "Edit secrets:  make secrets-edit"
