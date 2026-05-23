#!/usr/bin/env bash
# Restore cluster SSH key files from secrets.vault.json (for use on a new machine).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VAULT_FILE="${VAULT_FILE:-$ROOT/secrets.vault.json}"
VAULT_PASS_FILE="${VAULT_PASSWORD_FILE:-$ROOT/.vault_pass}"
SSH_KEY="${SSH_KEY:-$ROOT/.cluster_ssh/cluster_ed25519}"

if [[ ! -f "$VAULT_FILE" ]]; then
  echo "error: $VAULT_FILE not found." >&2
  exit 1
fi
if [[ ! -f "$VAULT_PASS_FILE" ]]; then
  echo "error: $VAULT_PASS_FILE not found." >&2
  exit 1
fi

mkdir -p "$(dirname "$SSH_KEY")"
chmod 700 "$(dirname "$SSH_KEY")"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT INT TERM HUP

ansible-vault view --vault-password-file "$VAULT_PASS_FILE" "$VAULT_FILE" > "$TMP"
jq -r '.ssh_private_key' "$TMP" > "$SSH_KEY"
jq -r '.ssh_public_key'  "$TMP" > "${SSH_KEY}.pub"
chmod 600 "$SSH_KEY"
chmod 644 "${SSH_KEY}.pub"

echo "Wrote $SSH_KEY and ${SSH_KEY}.pub"
ssh-keygen -lf "${SSH_KEY}.pub"
