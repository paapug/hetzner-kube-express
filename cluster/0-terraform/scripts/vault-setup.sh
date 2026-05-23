#!/usr/bin/env bash
# First-time setup:
#   * prompt for / accept a vault passphrase
#   * generate cluster SSH key
#   * write encrypted secrets.vault.json (Ansible Vault, JSON payload)
#
# The encrypted file IS committed. The passphrase is what you share (1Password,
# Bitwarden, etc.). Optionally cache it locally in .vault_pass (gitignored).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VAULT_FILE="${VAULT_FILE:-$ROOT/secrets.vault.json}"
VAULT_PASS_FILE="${VAULT_PASSWORD_FILE:-$ROOT/.vault_pass}"
SSH_KEY="${SSH_KEY:-$ROOT/.cluster_ssh/cluster_ed25519}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: '$1' not found." >&2
    case "$1" in
      ansible-vault) echo "  Install: brew install ansible" >&2 ;;
      jq)            echo "  Install: brew install jq" >&2 ;;
      ssh-keygen)    echo "  Install: openssh client" >&2 ;;
    esac
    exit 1
  fi
}
require_cmd ansible-vault
require_cmd jq
require_cmd ssh-keygen

if [[ ! -f "$VAULT_PASS_FILE" ]]; then
  echo "No $VAULT_PASS_FILE found."
  read -rsp "Enter a NEW vault passphrase (share via password manager): " P1; echo
  read -rsp "Confirm passphrase: " P2; echo
  if [[ "$P1" != "$P2" ]]; then
    echo "error: passphrases do not match" >&2
    exit 1
  fi
  if [[ -z "$P1" ]]; then
    echo "error: empty passphrase" >&2
    exit 1
  fi
  umask 077
  printf '%s' "$P1" > "$VAULT_PASS_FILE"
  unset P1 P2
  echo "Saved passphrase to $VAULT_PASS_FILE (gitignored, mode 600)."
fi
chmod 600 "$VAULT_PASS_FILE"

mkdir -p "$(dirname "$SSH_KEY")"
chmod 700 "$(dirname "$SSH_KEY")"
if [[ ! -f "$SSH_KEY" ]]; then
  echo "Generating cluster SSH key: $SSH_KEY"
  ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "k8s-playground-dev" >/dev/null
  chmod 600 "$SSH_KEY"
  chmod 644 "${SSH_KEY}.pub"
fi

# Prepare plaintext secrets (JSON Terraform var-file payload).
HCLOUD_TOKEN="${HCLOUD_TOKEN:-}"
if [[ -z "$HCLOUD_TOKEN" ]]; then
  if [[ -f "$VAULT_FILE" ]]; then
    # Reuse existing token from the current vault if available.
    HCLOUD_TOKEN="$(ansible-vault view --vault-password-file "$VAULT_PASS_FILE" "$VAULT_FILE" 2>/dev/null \
                      | jq -r '.hcloud_token // empty' || true)"
  fi
fi
if [[ -z "$HCLOUD_TOKEN" || "$HCLOUD_TOKEN" == "your-hetzner-cloud-api-token" ]]; then
  read -rsp "Enter Hetzner Cloud API token (input hidden): " HCLOUD_TOKEN; echo
fi

TMP_PLAIN="$(mktemp)"
trap 'rm -f "$TMP_PLAIN"' EXIT INT TERM HUP

jq -n \
  --arg token "$HCLOUD_TOKEN" \
  --arg pub  "$(cat "${SSH_KEY}.pub")" \
  --arg priv "$(cat "$SSH_KEY")" \
  '{
     hcloud_token: $token,
     ssh_public_key: $pub,
     ssh_private_key: $priv,
     firewall_ssh_source: ["0.0.0.0/0", "::/0"],
     firewall_kube_api_source: ["0.0.0.0/0", "::/0"]
   }' > "$TMP_PLAIN"

if [[ -f "$VAULT_FILE" ]]; then
  rm -f "$VAULT_FILE"
fi
ansible-vault encrypt \
  --vault-password-file "$VAULT_PASS_FILE" \
  --output "$VAULT_FILE" \
  "$TMP_PLAIN"

echo ""
echo "Wrote encrypted $VAULT_FILE (commit this)"
echo "Cluster SSH key (gitignored): $SSH_KEY"
ssh-keygen -lf "${SSH_KEY}.pub"
echo ""
echo "Edit later:  make secrets-edit"
echo "Run TF:      make plan / make apply"
