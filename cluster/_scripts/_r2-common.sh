#!/usr/bin/env bash
# Shared helpers for the R2 scripts. Sourced; not executed directly.
#
# Reads project-global R2 settings (account, bucket, default profile) from
# cluster/root.hcl and per-env profile override from cluster/<env>/env.hcl,
# matching what Terragrunt itself uses at plan/apply time.
#
# Usage:
#   source "$(dirname "$0")/_r2-common.sh"
#   ENV_DIR=cluster/dev r2_load_env       # exports R2_ACCOUNT_ID/R2_BUCKET/R2_SECRETS_KEY/R2_ENDPOINT/R2_AWS_PROFILE
#
# Auth: see r2_require_aws_creds below.
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

# Resolve project-global R2 settings from cluster/root.hcl and per-env overrides
# from cluster/<env>/env.hcl. Mirrors the precedence used by Terragrunt itself:
#   r2_account_id, r2_bucket  ⇐ env.hcl if set, else *_default in root.hcl
#   r2_aws_profile            ⇐ env.hcl if set, else r2_aws_profile_default in root.hcl
#   secrets key               ⇐ "secrets/<env-folder-name>/secrets.json"
#
# Requires hcl2json (brew install hcl2json) so we don't hand-parse HCL.
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

  # cluster/root.hcl is one level above the env folder.
  local root_file
  root_file="$(cd "$env_dir/.." && pwd)/root.hcl"
  if [[ ! -f "$root_file" ]]; then
    printf 'error: %q not found\n' "$root_file" >&2
    exit 1
  fi

  r2_require_cmd hcl2json jq

  local env_name
  env_name="$(basename "$(cd "$env_dir" && pwd)")"

  local root_parsed env_parsed
  root_parsed="$(hcl2json < "$root_file")"
  env_parsed="$(hcl2json < "$env_file")"

  local account_id_default bucket_default profile_default
  local account_id_override bucket_override profile_override
  local account_id bucket aws_profile

  account_id_default="$(jq -r '.locals[0].r2_account_id_default  // empty' <<<"$root_parsed")"
  bucket_default="$(jq -r     '.locals[0].r2_bucket_default      // empty' <<<"$root_parsed")"
  profile_default="$(jq -r    '.locals[0].r2_aws_profile_default // empty' <<<"$root_parsed")"

  account_id_override="$(jq -r '.locals[0].r2_account_id  // empty' <<<"$env_parsed")"
  bucket_override="$(jq -r     '.locals[0].r2_bucket      // empty' <<<"$env_parsed")"
  profile_override="$(jq -r    '.locals[0].r2_aws_profile // empty' <<<"$env_parsed")"

  account_id="${account_id_override:-$account_id_default}"
  bucket="${bucket_override:-$bucket_default}"
  aws_profile="${profile_override:-$profile_default}"

  if [[ -z "$account_id" || "$account_id" == "REPLACE_WITH_CF_ACCOUNT_ID" ]]; then
    printf 'error: r2_account_id is unset (no override in %q, no r2_account_id_default in %q)\n' \
      "$env_file" "$root_file" >&2
    exit 1
  fi
  if [[ -z "$bucket" ]]; then
    printf 'error: r2_bucket is unset (no override in %q, no r2_bucket_default in %q)\n' \
      "$env_file" "$root_file" >&2
    exit 1
  fi

  export R2_ACCOUNT_ID="$account_id"
  export R2_BUCKET="$bucket"
  export R2_SECRETS_KEY="secrets/${env_name}/secrets.json"
  export R2_ENDPOINT="https://${account_id}.r2.cloudflarestorage.com"
  export R2_ENV_NAME="$env_name"
  export R2_AWS_PROFILE="$aws_profile"
}

r2_aws() {
  aws --endpoint-url "$R2_ENDPOINT" "$@"
}
