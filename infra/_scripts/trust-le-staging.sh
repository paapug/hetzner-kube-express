#!/usr/bin/env bash
# Add or remove Let's Encrypt *staging* root CAs in the macOS trust store.
#
# Pairs with infra/modules/acme: when an env runs `acme_use_staging = true`,
# Safari / curl-on-macOS / anything that consults the system keychain rejects
# every cert until the staging roots below are explicitly trusted.
#
# Roots tracked (https://letsencrypt.org/docs/staging-environment/):
#   - (STAGING) Pretend Pear X1          RSA   4096
#   - (STAGING) Bogus Broccoli X2        ECDSA P-384
#   - (STAGING) Yearning Yucca Root YE   ECDSA P-384
#   - (STAGING) Yonder Yam Root YR       RSA   4096
#
# Usage:
#   infra/_scripts/trust-le-staging.sh enable
#   infra/_scripts/trust-le-staging.sh disable
#   infra/_scripts/trust-le-staging.sh status
#
# Env:
#   SCOPE=user    (default) login keychain. No sudo. macOS will prompt for the
#                 login password to authorize the trust-settings change.
#   SCOPE=system  /Library/Keychains/System.keychain via sudo. Trusted for
#                 every user on this Mac.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_r2-common.sh
source "$SCRIPT_DIR/_r2-common.sh"

r2_require_cmd security curl openssl

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'error: macOS only (uname=%s)\n' "$(uname -s)" >&2
  exit 1
fi

# URL[i] downloads the root whose subject CN equals CN[i]; the two arrays are
# index-aligned so `disable`/`status` can work fully offline.
STAGING_URL=(
  "https://letsencrypt.org/certs/staging/letsencrypt-stg-root-x1.pem"
  "https://letsencrypt.org/certs/staging/letsencrypt-stg-root-x2.pem"
  "https://letsencrypt.org/certs/staging/gen-y/root-ye.pem"
  "https://letsencrypt.org/certs/staging/gen-y/root-yr.pem"
)
STAGING_CN=(
  "(STAGING) Pretend Pear X1"
  "(STAGING) Bogus Broccoli X2"
  "(STAGING) Yearning Yucca Root YE"
  "(STAGING) Yonder Yam Root YR"
)

SCOPE="${SCOPE:-user}"
case "$SCOPE" in
  user)
    KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
    ;;
  system)
    KEYCHAIN="/Library/Keychains/System.keychain"
    ;;
  *)
    printf 'error: SCOPE=%q (use "user" or "system")\n' "$SCOPE" >&2
    exit 1
    ;;
esac

# Tempdir for downloaded PEMs. Lives at script scope (not inside cmd_enable)
# because the EXIT trap fires AFTER the function returns: a `local tmp` would
# already be out of scope by then and `set -u` would trip on the expansion.
TMPDIR_LE=""
cleanup_tmp() {
  if [[ -n "$TMPDIR_LE" && -d "$TMPDIR_LE" ]]; then
    rm -rf "$TMPDIR_LE"
  fi
}
trap cleanup_tmp EXIT INT TERM HUP

usage() {
  cat >&2 <<EOF
Usage: $(basename "$0") <enable|disable|status>

  enable   Download LE staging roots and add as trusted in the macOS keychain.
  disable  Remove every previously-trusted LE staging root from the keychain.
  status   Show which LE staging roots are currently present / trusted.

Env:
  SCOPE=user|system   (default: user)
EOF
}

# Wrap `security` with sudo only when mutating the system keychain. Reads
# (find-certificate, dump-trust-settings) work unprivileged in both scopes.
sec_write() {
  if [[ "$SCOPE" == "system" ]]; then
    sudo security "$@"
  else
    security "$@"
  fi
}

ensure_keychain() {
  if [[ ! -e "$KEYCHAIN" ]]; then
    printf 'error: keychain not found: %s\n' "$KEYCHAIN" >&2
    exit 1
  fi
}

keychain_has_cert() {
  local cn="$1"
  security find-certificate -c "$cn" "$KEYCHAIN" >/dev/null 2>&1
}

# `dump-trust-settings` exits non-zero when no settings exist for the scope;
# swallow that so we can grep the (possibly empty) output without tripping
# pipefail.
trust_dump() {
  if [[ "$SCOPE" == "system" ]]; then
    security dump-trust-settings -d 2>/dev/null || true
  else
    security dump-trust-settings 2>/dev/null || true
  fi
}

is_trusted() {
  local cn="$1"
  trust_dump | grep -Fq "$cn"
}

cmd_enable() {
  ensure_keychain

  TMPDIR_LE="$(mktemp -d)"
  chmod 700 "$TMPDIR_LE"

  local i url cn pem
  for i in "${!STAGING_URL[@]}"; do
    url="${STAGING_URL[$i]}"
    cn="${STAGING_CN[$i]}"
    pem="$TMPDIR_LE/$(basename "$url")"

    printf 'Fetching %s ...\n' "$url" >&2
    curl --fail --silent --show-error --location "$url" -o "$pem"
    chmod 600 "$pem"
    if ! openssl x509 -in "$pem" -noout >/dev/null 2>&1; then
      printf 'error: %s did not return a valid PEM cert\n' "$url" >&2
      exit 1
    fi

    if is_trusted "$cn"; then
      printf '  already trusted: %s\n' "$cn" >&2
      continue
    fi

    printf '  adding: %s\n' "$cn" >&2
    if [[ "$SCOPE" == "system" ]]; then
      sec_write add-trusted-cert -d -r trustRoot -k "$KEYCHAIN" "$pem"
    else
      sec_write add-trusted-cert    -r trustRoot -k "$KEYCHAIN" "$pem"
    fi
  done

  printf '\nDone. Scope: %s   keychain: %s\n' "$SCOPE" "$KEYCHAIN" >&2
}

cmd_disable() {
  ensure_keychain
  local cn removed
  for cn in "${STAGING_CN[@]}"; do
    # Loop: delete-certificate removes one match per call. Drains duplicates
    # if a previous run somehow added the same root twice.
    removed=0
    while sec_write delete-certificate -c "$cn" "$KEYCHAIN" >/dev/null 2>&1; do
      removed=$((removed + 1))
    done
    if (( removed > 0 )); then
      printf '  removed (x%d): %s\n' "$removed" "$cn" >&2
    else
      printf '  not present:  %s\n' "$cn" >&2
    fi
  done
  printf '\nScope: %s   keychain: %s\n' "$SCOPE" "$KEYCHAIN" >&2
}

cmd_status() {
  local cn state
  printf 'Scope: %s   keychain: %s\n\n' "$SCOPE" "$KEYCHAIN" >&2
  for cn in "${STAGING_CN[@]}"; do
    if keychain_has_cert "$cn" && is_trusted "$cn"; then
      state="trusted"
    elif keychain_has_cert "$cn"; then
      state="imported (not trusted)"
    else
      state="absent"
    fi
    printf '  %-25s %s\n' "$state" "$cn"
  done
}

case "${1:-}" in
  enable)    cmd_enable ;;
  disable)   cmd_disable ;;
  status)    cmd_status ;;
  -h|--help) usage ;;
  "")        usage; exit 1 ;;
  *)         printf 'error: unknown command %q\n\n' "$1" >&2; usage; exit 1 ;;
esac
