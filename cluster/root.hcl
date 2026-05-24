# Environment-agnostic Terragrunt root.
#
# Project-global R2 settings (account, bucket, default AWS profile) live here
# so they can't drift across environments. Per-env values stay in env.hcl.
#
# State key:   state/<env>/<unit_path>/terraform.tfstate
# Secrets key: secrets/<env>/secrets.json
# Locking:     native S3 conditional-write lockfile (Terraform >= 1.10).

locals {
  project_name = "hetzner-k8s-playground"

  # Project-global R2 settings. Bucket + account id + default profile are the
  # same for every env. An env can override r2_aws_profile by re-defining it
  # in env.hcl (e.g. for prod with a different IAM token).
  r2_account_id          = "REPLACE_WITH_CF_ACCOUNT_ID"
  r2_bucket              = "REPLACE_WITH_R2_BUCKET"
  r2_aws_profile_default = "r2-hetzner-k8s-playground"

  # Per-env values (cluster_name, argocd_*, acme_*, optional r2_aws_profile).
  env_hcl_path = find_in_parent_folders("env.hcl")
  env          = read_terragrunt_config(local.env_hcl_path)

  # `environment` derived from the folder holding env.hcl.
  environment    = basename(dirname(local.env_hcl_path))
  r2_secrets_key = "secrets/${local.environment}/secrets.json"

  # Honor per-env override of r2_aws_profile if set; otherwise use the default.
  r2_aws_profile = lookup(local.env.locals, "r2_aws_profile", local.r2_aws_profile_default)
}

remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket = local.r2_bucket
    # path_relative_to_include() returns "<env>/<unit>" (e.g. "dev/cluster")
    # because root.hcl lives one level above the env folder. That's already
    # env-namespaced, so don't prepend `local.environment` again.
    key     = "state/${path_relative_to_include()}/terraform.tfstate"
    region  = "auto"
    profile = local.r2_aws_profile

    endpoints = {
      s3 = "https://${local.r2_account_id}.r2.cloudflarestorage.com"
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
