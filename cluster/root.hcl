# Environment-agnostic Terragrunt root.
#
# State key:   state/<env>/<unit_path>/terraform.tfstate
# Secrets key: secrets/<env>/secrets.json

locals {
  project_name = "hetzner-k8s-playground"

  # Project-global R2 settings. Bucket + account id + AWS profile defaults live
  # here and are the same for every env unless an env opts to override them.
  r2_account_id_default  = "REPLACE_WITH_CF_ACCOUNT_ID"
  r2_bucket_default      = "REPLACE_WITH_R2_BUCKET"
  r2_aws_profile_default = "r2-hetzner-k8s-playground"

  # Per-env values (cluster_name, argocd_*, acme_*, optional r2_* overrides).
  env_hcl_path = find_in_parent_folders("env.hcl")
  env          = read_terragrunt_config(local.env_hcl_path)

  # `environment` derived from the folder holding env.hcl.
  environment       = basename(dirname(local.env_hcl_path))
  r2_secrets_key    = "secrets/${local.environment}/secrets.json"
  r2_kubeconfig_key = "secrets/${local.environment}/kubeconfig.yaml"

  # Honor per-env overrides if set; otherwise fall back to the project defaults.
  r2_account_id  = lookup(local.env.locals, "r2_account_id", local.r2_account_id_default)
  r2_bucket      = lookup(local.env.locals, "r2_bucket", local.r2_bucket_default)
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
