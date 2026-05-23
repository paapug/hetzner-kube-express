#!/usr/bin/env bash
# Write cluster SSH key from SOPS to .age/ for ssh(1) / scp on this machine.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SECRETS_ENC="${SECRETS_ENC:-$ROOT/secrets.enc.json}"
SSH_KEY="${SSH_KEY:-$ROOT/.age/cluster_ed25519}"
export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$ROOT/.age/key.txt}"

if [[ ! -f "$SECRETS_ENC" ]]; then
  echo "error: $SECRETS_ENC not found. Run: make sops-setup" >&2
  exit 1
fi

mkdir -p "$(dirname "$SSH_KEY")"
DECRYPTED="$(mktemp)"
trap 'rm -f "$DECRYPTED"' EXIT

SOPS_AGE_KEY_FILE="$SOPS_AGE_KEY_FILE" sops -d "$SECRETS_ENC" > "$DECRYPTED"
jq -r '.ssh_private_key' "$DECRYPTED" > "$SSH_KEY"
jq -r '.ssh_public_key' "$DECRYPTED" > "${SSH_KEY}.pub"
chmod 600 "$SSH_KEY"
chmod 644 "${SSH_KEY}.pub"

echo "Wrote ${SSH_KEY} and ${SSH_KEY}.pub"
ssh-keygen -lf "${SSH_KEY}.pub"
