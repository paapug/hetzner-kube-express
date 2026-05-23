#!/usr/bin/env bash
# Run terraform with SOPS-decrypted -var-file (secrets never touch disk unencrypted).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SECRETS_ENC="${SECRETS_ENC:-$ROOT/secrets.enc.json}"
export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$ROOT/.age/key.txt}"

if [[ ! -f "$SECRETS_ENC" ]]; then
  echo "error: $SECRETS_ENC not found. Run: make sops-setup" >&2
  exit 1
fi

if [[ ! -f "$SOPS_AGE_KEY_FILE" ]]; then
  echo "error: age private key not found at $SOPS_AGE_KEY_FILE" >&2
  echo "  Run: make sops-setup" >&2
  exit 1
fi

cd "$ROOT"
if [[ $# -lt 1 ]]; then
  echo "usage: tf-sops.sh <terraform-subcommand> [args...]" >&2
  exit 1
fi
exec sops exec-file "$SECRETS_ENC" "terraform $* -var-file={}"
