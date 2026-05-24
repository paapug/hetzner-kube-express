# Hetzner + k3s cluster via kube-hetzner.
#
# Sensitive inputs (hcloud_token, ssh keys) are read at plan/apply time from R2
# by data.aws_s3_object.secrets in the module (see cluster/modules/cluster/r2.tf).
# Non-secret per-env config (firewall CIDRs, etc.) comes from env.hcl. R2
# settings come from cluster/root.hcl; we expose its locals here so we can pass
# them as inputs to the module.

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

terraform {
  source = "${get_repo_root()}/cluster/modules/cluster"
}

inputs = {
  cluster_name      = local.env.locals.cluster_name
  r2_account_id     = include.root.locals.r2_account_id
  r2_bucket         = include.root.locals.r2_bucket
  r2_secrets_key    = include.root.locals.r2_secrets_key
  r2_kubeconfig_key = include.root.locals.r2_kubeconfig_key
  r2_aws_profile    = include.root.locals.r2_aws_profile

  firewall_ssh_source      = local.env.locals.firewall_ssh_source
  firewall_kube_api_source = local.env.locals.firewall_kube_api_source
}
