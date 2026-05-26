#!/usr/bin/env bash
# Point this clone's git hooks at infra/_scripts/git-hooks (which contains the
# pre-commit anonymizer for env.hcl / root.hcl). Idempotent: re-running is a
# no-op once core.hooksPath is set.
#
# Usage:
#   infra/_scripts/install-git-hooks.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_r2-common.sh
source "$SCRIPT_DIR/_r2-common.sh"

r2_require_cmd git

REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
HOOKS_REL="infra/_scripts/git-hooks"
HOOKS_ABS="$REPO_ROOT/$HOOKS_REL"

if [[ ! -d "$HOOKS_ABS" ]]; then
  printf 'error: %q not found\n' "$HOOKS_ABS" >&2
  exit 1
fi

CURRENT="$(git -C "$REPO_ROOT" config --local --get core.hooksPath || true)"
if [[ "$CURRENT" == "$HOOKS_REL" ]]; then
  echo "git hooks already pointing at $HOOKS_REL; nothing to do." >&2
  exit 0
fi

git -C "$REPO_ROOT" config --local core.hooksPath "$HOOKS_REL"
printf 'Set core.hooksPath = %s\n' "$HOOKS_REL" >&2
