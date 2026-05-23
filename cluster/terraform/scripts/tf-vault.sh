#!/usr/bin/env bash
# Decrypt secrets.vault.json to a short-lived tempfile named *.tfvars.json
# (Terraform parses var-files as JSON only when the extension matches),
# then run terraform with -var-file=<tempfile>. The tempfile is wiped on exit.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VAULT_FILE="${VAULT_FILE:-$ROOT/secrets.vault.json}"
VAULT_PASS_FILE="${VAULT_PASSWORD_FILE:-$ROOT/.vault_pass}"

if [[ ! -f "$VAULT_FILE" ]]; then
  echo "error: $VAULT_FILE not found. Run: make vault-setup" >&2
  exit 1
fi
if [[ ! -f "$VAULT_PASS_FILE" ]]; then
  echo "error: $VAULT_PASS_FILE not found." >&2
  echo "  Create it (mode 600) with the shared passphrase, or run: make vault-setup" >&2
  exit 1
fi

if [[ $# -lt 1 ]]; then
  echo "usage: tf-vault.sh <terraform-subcommand> [args...]" >&2
  exit 1
fi

TMPDIR_SEC="$(mktemp -d)"
chmod 700 "$TMPDIR_SEC"
VARFILE="${TMPDIR_SEC}/secrets.auto.tfvars.json"
trap 'rm -rf "$TMPDIR_SEC"' EXIT INT TERM HUP

ansible-vault view --vault-password-file "$VAULT_PASS_FILE" "$VAULT_FILE" > "$VARFILE"
chmod 600 "$VARFILE"

terraform "$@" -var-file="$VARFILE"
