# Hetzner + k3s cluster via kube-hetzner.
#
# Sensitive inputs (hcloud_token, ssh keys) are read at plan/apply time from R2
# by data.aws_s3_object.secrets in the module (see infra/modules/cluster/r2.tf).
# Non-secret per-env config (firewall CIDRs, etc.) comes from env.hcl. R2
# settings come from infra/root.hcl; we expose its locals here so we can pass
# them as inputs to the module.

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

locals {
  env     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  env_dir = dirname(find_in_parent_folders("env.hcl"))
}

terraform {
  source = "${get_repo_root()}/infra/modules/cluster"

  # Refresh the env-local kubeconfig snapshot after every successful apply.
  # AUTO_MERGE=0 keeps the hook from silently mutating ~/.kube/config under
  # `run --all apply`; the script writes infra/<env>/.kube/config (mode 600).
  after_hook "fetch_kubeconfig" {
    commands = ["apply"]
    execute = [
      "bash", "-c",
      "ENV_DIR='${local.env_dir}' AUTO_MERGE=0 '${get_repo_root()}/infra/_scripts/fetch-kubeconfig.sh'",
    ]
    run_on_error = false
  }
}

inputs = {
  cluster_name      = local.env.locals.cluster_name
  r2_account_id     = include.root.locals.r2_account_id
  r2_bucket         = include.root.locals.r2_bucket
  r2_secrets_key    = include.root.locals.r2_secrets_key
  r2_kubeconfig_key = include.root.locals.r2_kubeconfig_key
  r2_aws_profile    = include.root.locals.r2_aws_profile

  network_region          = local.env.locals.hetzner.network_region
  control_plane_nodepools = local.env.locals.hetzner.control_plane_nodepools
  agent_nodepools         = local.env.locals.hetzner.agent_nodepools

  firewall_ssh_source      = local.env.locals.hetzner_firewall.ssh_source
  firewall_kube_api_source = local.env.locals.hetzner_firewall.kube_api_source
}
