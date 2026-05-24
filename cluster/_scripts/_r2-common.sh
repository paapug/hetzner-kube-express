#!/usr/bin/env bash
# Shared helpers for the R2 scripts. Sourced; not executed directly.
#
# Reads the same env.hcl that Terragrunt reads, so there is exactly one source
# of truth for r2_bucket, r2_account_id, r2_secrets_key and environment.
#
# Usage:
#   source "$(dirname "$0")/_r2-common.sh"
#   ENV_DIR=cluster/dev r2_load_env       # exports R2_ACCOUNT_ID/R2_BUCKET/R2_SECRETS_KEY/R2_ENDPOINT
#
# Auth: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY must be set in the caller's env.
set -euo pipefail

r2_require_cmd() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      printf 'error: %q not found in PATH\n' "$cmd" >&2
      case "$cmd" in
        aws) echo "  Install: brew install awscli" >&2 ;;
        jq)  echo "  Install: brew install jq" >&2 ;;
        hcl2json) echo "  Install: brew install hcl2json" >&2 ;;
      esac
      exit 1
    fi
  done
}

# Source a dotenv file (KEY=VALUE per line, # comments allowed) and export every
# assignment it makes. No-op if the file doesn't exist. Uses `set -a` so we
# don't have to parse the file ourselves; simple-quoted values are fine, but
# don't put shell expansions in there.
r2_load_dotenv() {
  local file="$1"
  if [[ -f "$file" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$file"
    set +a
  fi
}

# Auto-load credentials from .env files, in order of increasing specificity:
#   1. <repo-root>/.env          (one credential set for the whole repo)
#   2. $ENV_DIR/.env             (per-env override; wins because it's last)
# Already-set process env vars take precedence over files because we never
# overwrite an export that was already set in the shell — `set -a; source` only
# re-assigns; the caller can pre-export to override. To force a file value
# regardless of caller env, unset the var first.
r2_autoload_env_files() {
  local repo_root
  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  r2_load_dotenv "$repo_root/.env"
  if [[ -n "${ENV_DIR:-}" && -d "${ENV_DIR}" ]]; then
    r2_load_dotenv "${ENV_DIR}/.env"
  fi
}

# Verify SOME way of authenticating to R2 is configured. Acceptable, in order
# of precedence (matches the AWS SDK's own resolution chain):
#   1. AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY in the env (or .env)
#   2. AWS_PROFILE in the env (caller-named profile)
#   3. R2_AWS_PROFILE from cluster/<env>/env.hcl (loaded by r2_load_env), with
#      a matching [<profile>] entry in ~/.aws/credentials
#
# Call r2_load_env BEFORE this so R2_AWS_PROFILE is populated.
r2_require_aws_creds() {
  r2_autoload_env_files

  if [[ -n "${AWS_ACCESS_KEY_ID:-}" && -n "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
    : # static keys win; the AWS SDK will use them everywhere
  elif [[ -n "${AWS_PROFILE:-}" ]]; then
    : # caller pinned a profile explicitly
  elif [[ -n "${R2_AWS_PROFILE:-}" ]]; then
    export AWS_PROFILE="$R2_AWS_PROFILE"
    if ! aws configure get aws_access_key_id --profile "$AWS_PROFILE" >/dev/null 2>&1; then
      cat >&2 <<EOF
error: AWS profile "$AWS_PROFILE" (from env.hcl r2_aws_profile) is not
  configured. Add it to ~/.aws/credentials:
    [$AWS_PROFILE]
    aws_access_key_id     = <r2-access-key-id>
    aws_secret_access_key = <r2-secret-access-key>
  ...or override with AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY (e.g. via .env).
EOF
      exit 1
    fi
  else
    cat >&2 <<'EOF'
error: no R2 credentials found. Provide one of:
  1. AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY (shell export, .env file, or direnv)
  2. AWS_PROFILE pointing at a profile in ~/.aws/credentials
  3. r2_aws_profile in cluster/<env>/env.hcl + matching [profile] in ~/.aws/credentials
See .env.example and README.md for setup details.
EOF
    exit 1
  fi

  export AWS_REGION="${AWS_REGION:-auto}"
  export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-auto}"
}

# Parse cluster/<env>/env.hcl into the R2_* env vars used by every script.
# Requires hcl2json (brew install hcl2json) so we don't reimplement HCL parsing.
r2_load_env() {
  local env_dir="${ENV_DIR:-}"
  if [[ -z "$env_dir" ]]; then
    echo "error: ENV_DIR is required (e.g. ENV_DIR=cluster/dev)" >&2
    exit 1
  fi
  if [[ ! -d "$env_dir" ]]; then
    printf 'error: ENV_DIR=%q is not a directory\n' "$env_dir" >&2
    exit 1
  fi
  local env_file="$env_dir/env.hcl"
  if [[ ! -f "$env_file" ]]; then
    printf 'error: %q not found\n' "$env_file" >&2
    exit 1
  fi

  r2_require_cmd hcl2json jq

  local env_name
  env_name="$(basename "$(cd "$env_dir" && pwd)")"

  local parsed
  parsed="$(hcl2json < "$env_file")"

  local account_id bucket secrets_key aws_profile
  account_id="$(jq -r '.locals[0].r2_account_id // empty' <<<"$parsed")"
  bucket="$(jq -r '.locals[0].r2_bucket // empty' <<<"$parsed")"
  secrets_key="$(jq -r '.locals[0].r2_secrets_key // empty' <<<"$parsed")"
  aws_profile="$(jq -r '.locals[0].r2_aws_profile // empty' <<<"$parsed")"

  if [[ -z "$account_id" || "$account_id" == "REPLACE_WITH_CF_ACCOUNT_ID" ]]; then
    printf 'error: r2_account_id is unset in %q\n' "$env_file" >&2
    exit 1
  fi
  if [[ -z "$bucket" ]]; then
    printf 'error: r2_bucket is unset in %q\n' "$env_file" >&2
    exit 1
  fi

  # secrets_key uses HCL interpolation (${local.environment}); resolve it manually.
  secrets_key="${secrets_key//\$\{local.environment\}/$env_name}"
  if [[ -z "$secrets_key" ]]; then
    secrets_key="secrets/$env_name/secrets.json"
  fi

  export R2_ACCOUNT_ID="$account_id"
  export R2_BUCKET="$bucket"
  export R2_SECRETS_KEY="$secrets_key"
  export R2_ENDPOINT="https://${account_id}.r2.cloudflarestorage.com"
  export R2_ENV_NAME="$env_name"
  export R2_AWS_PROFILE="$aws_profile"
}

r2_aws() {
  aws --endpoint-url "$R2_ENDPOINT" "$@"
}
