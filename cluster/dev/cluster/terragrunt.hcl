# Hetzner + k3s cluster via kube-hetzner.
#
# Sensitive inputs (hcloud_token, ssh keys, firewall CIDRs) are read at
# plan/apply time from R2 by data.aws_s3_object.secrets in the module
# (see cluster/modules/cluster/r2.tf). Auth: AWS_ACCESS_KEY_ID and
# AWS_SECRET_ACCESS_KEY in the shell env.

include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  env_hcl_path = find_in_parent_folders("env.hcl")
  env          = read_terragrunt_config(local.env_hcl_path)

  environment    = basename(dirname(local.env_hcl_path))
  r2_secrets_key = "secrets/${local.environment}/secrets.json"
}

terraform {
  source = "${get_repo_root()}/cluster/modules/cluster"
}

inputs = {
  cluster_name   = local.env.locals.cluster_name
  r2_account_id  = local.env.locals.r2_account_id
  r2_bucket      = local.env.locals.r2_bucket
  r2_secrets_key = local.r2_secrets_key
  r2_aws_profile = local.env.locals.r2_aws_profile
}
