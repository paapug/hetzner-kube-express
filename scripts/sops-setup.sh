#!/usr/bin/env bash
# One-time (or per-machine) setup: age key + encrypted secrets.enc.json
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

AGE_KEY="${SOPS_AGE_KEY_FILE:-$ROOT/.age/key.txt}"
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
    esac
    exit 1
  fi
}

require_cmd sops
require_cmd age-keygen

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

# Update .sops.yaml with this machine's public key (safe to commit for solo use;
# for teams, add multiple age: lines or run setup once and commit the result).
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
  echo "Created $SECRETS_PLAIN — edit it, then re-run: make sops-setup"
  exit 0
fi

cp "$SECRETS_PLAIN" "$SECRETS_ENC"
SOPS_AGE_KEY_FILE="$AGE_KEY" sops --encrypt --input-type json --output-type json --in-place "$SECRETS_ENC"
echo "Wrote encrypted $SECRETS_ENC (safe to commit; keep $SECRETS_PLAIN out of git)"

echo ""
echo "Done. Use:  export SOPS_AGE_KEY_FILE=$AGE_KEY"
echo "            make plan   # or make apply"
echo ""
echo "Edit secrets:  make secrets-edit   (opens secrets.enc.json in \$EDITOR)"
