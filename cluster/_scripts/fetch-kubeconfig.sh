#!/usr/bin/env bash
# Fetch the cluster kubeconfig from R2 and optionally merge into ~/.kube/config.
#
# Source object: s3://<r2_bucket>/secrets/<env>/kubeconfig.yaml
#   (uploaded by the `cluster` unit on apply; see cluster/modules/cluster/r2.tf)
#
# Usage:
#   ENV_DIR=cluster/dev cluster/_scripts/fetch-kubeconfig.sh
#   AUTO_MERGE=1 ENV_DIR=cluster/dev cluster/_scripts/fetch-kubeconfig.sh   # non-interactive yes
#   AUTO_MERGE=0 ENV_DIR=cluster/dev cluster/_scripts/fetch-kubeconfig.sh   # non-interactive no
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_r2-common.sh
source "$SCRIPT_DIR/_r2-common.sh"

r2_require_cmd aws kubectl
r2_load_env
r2_require_aws_creds

KUBECONFIG_KEY="secrets/${R2_ENV_NAME}/kubeconfig.yaml"

if ! r2_aws s3api head-object --bucket "$R2_BUCKET" --key "$KUBECONFIG_KEY" >/dev/null 2>&1; then
  cat >&2 <<EOF
error: s3://${R2_BUCKET}/${KUBECONFIG_KEY} not found.
  Has the cluster unit been applied for this env?
    cd ${ENV_DIR}/cluster && terragrunt apply
EOF
  exit 1
fi

TMPDIR_KCFG="$(mktemp -d)"
chmod 700 "$TMPDIR_KCFG"
trap 'rm -rf "$TMPDIR_KCFG"' EXIT INT TERM HUP

REMOTE="$TMPDIR_KCFG/kubeconfig.yaml"
printf 'Fetching s3://%s/%s ...\n' "$R2_BUCKET" "$KUBECONFIG_KEY" >&2
r2_aws s3 cp "s3://${R2_BUCKET}/${KUBECONFIG_KEY}" "$REMOTE" >/dev/null
chmod 600 "$REMOTE"

# Decide whether to merge. AUTO_MERGE overrides the interactive prompt.
DO_MERGE=""
case "${AUTO_MERGE:-}" in
  1|y|Y|yes|YES) DO_MERGE=1 ;;
  0|n|N|no|NO)  DO_MERGE=0 ;;
  "")
    if [[ -t 0 ]]; then
      read -rp "Merge into ~/.kube/config? [y/N]: " ans
      case "$ans" in
        y|Y|yes|YES) DO_MERGE=1 ;;
        *)           DO_MERGE=0 ;;
      esac
    else
      echo "stdin not a tty and AUTO_MERGE not set; assuming no merge." >&2
      DO_MERGE=0
    fi
    ;;
  *)
    printf 'error: invalid AUTO_MERGE=%q (use 1/0)\n' "$AUTO_MERGE" >&2
    exit 1
    ;;
esac

if [[ "$DO_MERGE" == "0" ]]; then
  ENV_DIR_ABS="$(cd "$ENV_DIR" && pwd)"
  KUBE_DIR="$ENV_DIR_ABS/.kube"
  KUBE_FILE="$KUBE_DIR/config"

  mkdir -p "$KUBE_DIR"
  chmod 700 "$KUBE_DIR"

  install -m 600 "$REMOTE" "$KUBE_FILE"

  cat >&2 <<EOF
Wrote $KUBE_FILE (mode 600).

To use it:
  export KUBECONFIG="$KUBE_FILE"
  kubectl get nodes
EOF
  exit 0
fi

# Merge path: flatten ~/.kube/config + downloaded kubeconfig via kubectl, keeping
# the original context/cluster/user names from the downloaded kubeconfig.
mkdir -p "$HOME/.kube"
chmod 700 "$HOME/.kube"

BACKUP=""
if [[ -f "$HOME/.kube/config" ]]; then
  BACKUP="$HOME/.kube/config.bak.$(date -u +%Y%m%dT%H%M%SZ)"
  cp -p "$HOME/.kube/config" "$BACKUP"
  printf 'Backed up existing ~/.kube/config to %s\n' "$BACKUP" >&2
  EXISTING="$HOME/.kube/config"
else
  EXISTING=""
fi

MERGED="$TMPDIR_KCFG/merged"
# KUBECONFIG with a single path is fine; with two it's the merge input list.
if [[ -n "$EXISTING" ]]; then
  KUBECONFIG="${EXISTING}:${REMOTE}" kubectl config view --flatten > "$MERGED"
else
  KUBECONFIG="$REMOTE" kubectl config view --flatten > "$MERGED"
fi

install -m 600 "$MERGED" "$HOME/.kube/config"

# Show what contexts are now available and switch kubectl to the one that came
# from the freshly-downloaded kubeconfig. If the downloaded file contains
# multiple contexts (unusual for kube-hetzner), pick the first one — same as
# what `kubectl config view` would surface as the "current" entry.
NEW_CONTEXTS="$(KUBECONFIG="$REMOTE" kubectl config get-contexts -o name || true)"
printf '\nMerged into ~/.kube/config.\n' >&2
if [[ -n "$NEW_CONTEXTS" ]]; then
  printf 'Context(s) from %s:\n' "$KUBECONFIG_KEY" >&2
  while IFS= read -r ctx; do
    [[ -z "$ctx" ]] && continue
    printf '  %s\n' "$ctx" >&2
  done <<<"$NEW_CONTEXTS"
  FIRST_CTX="$(printf '%s\n' "$NEW_CONTEXTS" | head -n1)"
  if [[ -n "$FIRST_CTX" ]]; then
    kubectl config use-context "$FIRST_CTX" >/dev/null
    printf '\nSwitched current context to: %s\n' "$FIRST_CTX" >&2
  fi
fi
