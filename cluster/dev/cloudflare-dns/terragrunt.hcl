# Cloudflare DNS records for cluster ingress hostnames.
#
# Reads agent node public IPs from the cluster unit and creates one A record
# per (host, ip) pair. Klipper exposes Traefik on every node, so DNS
# round-robin across agent IPs is the simplest fan-out.
#
# Cloudflare API token comes from R2 secrets.json (cloudflare_api_token).
# Zone ID is non-secret and lives in env.hcl.

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

terraform {
  source = "${get_repo_root()}/cluster/modules/cloudflare-dns"
}

dependency "cluster" {
  config_path = "../cluster"

  mock_outputs = {
    agents_public_ipv4 = ["198.51.100.10", "198.51.100.11"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init", "destroy"]
}

inputs = {
  cloudflare_zone_id = local.env.locals.cloudflare_zone_id

  records = {
    (local.env.locals.argocd_host) = dependency.cluster.outputs.agents_public_ipv4
  }

  r2_account_id  = include.root.locals.r2_account_id
  r2_bucket      = include.root.locals.r2_bucket
  r2_secrets_key = include.root.locals.r2_secrets_key
  r2_aws_profile = include.root.locals.r2_aws_profile
}
