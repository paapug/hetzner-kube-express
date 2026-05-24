# Environment-agnostic Terragrunt root.
#
# State + secrets both live in Cloudflare R2 (S3-compatible). Authentication
# is via standard AWS env vars — same vars feed the s3 backend here AND the
# aliased aws.r2 provider in cluster/modules/cluster/r2.tf:
#
#   export AWS_ACCESS_KEY_ID='<r2-access-key-id>'
#   export AWS_SECRET_ACCESS_KEY='<r2-secret-access-key>'
#   export AWS_REGION=auto
#
# The `environment` name (used for both R2 state path and R2 secrets key) is
# derived from the folder containing env.hcl: cluster/dev/env.hcl -> "dev",
# cluster/staging/env.hcl -> "staging". No edits needed when adding an env.
#
# State key:   state/<env>/<unit_path>/terraform.tfstate
# Secrets key: secrets/<env>/secrets.json
# Locking:     native S3 conditional-write lockfile (Terraform >= 1.10).

locals {
  project_name = "hetzner-k8s-playground"

  env_hcl_path = find_in_parent_folders("env.hcl")
  env          = read_terragrunt_config(local.env_hcl_path)

  environment    = basename(dirname(local.env_hcl_path))
  r2_secrets_key = "secrets/${local.environment}/secrets.json"
}

remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket = local.env.locals.r2_bucket
    # path_relative_to_include() returns "<env>/<unit>" (e.g. "dev/cluster")
    # because root.hcl lives one level above the env folder. That's already
    # env-namespaced, so don't prepend `local.environment` again.
    key     = "state/${path_relative_to_include()}/terraform.tfstate"
    region  = "auto"
    profile = local.env.locals.r2_aws_profile

    endpoints = {
      s3 = "https://${local.env.locals.r2_account_id}.r2.cloudflarestorage.com"
    }

    use_lockfile                = true
    encrypt                     = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    skip_metadata_api_check     = true
  }
}

# Transient errors during provider downloads / Hetzner API calls.
errors {
  retry "transient" {
    retryable_errors = [
      "(?s).*timeout.*",
      "(?s).*connection reset.*",
      "(?s).*Failed to retrieve.*",
      "(?s).*TLS handshake timeout.*",
    ]
    max_attempts       = 3
    sleep_interval_sec = 5
  }
}
