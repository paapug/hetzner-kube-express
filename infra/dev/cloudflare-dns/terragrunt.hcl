# One A record per (host, agent_ip) pair: Klipper exposes Traefik on every
# node, so DNS round-robin across agent IPs fans ingress out cheaply.

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

terraform {
  source = "${get_repo_root()}/infra/modules/cloudflare-dns"
}

dependency "cluster" {
  config_path = "../cluster"

  mock_outputs = {
    agents_public_ipv4 = ["198.51.100.10", "198.51.100.11"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init", "destroy"]
}

inputs = {
  cloudflare_zone_id            = local.env.locals.cloudflare.zone_id
  cloudflare_domain             = local.env.locals.cloudflare.domain
  additional_ingress_subdomains = try(local.env.locals.cloudflare.additional_ingress_subdomains, [])
  agents_public_ipv4            = dependency.cluster.outputs.agents_public_ipv4

  records = merge(
    try(local.env.locals.argocd.enabled, true) ? try({ (local.env.locals.argocd.host) = dependency.cluster.outputs.agents_public_ipv4 }, {}) : {},
    try(local.env.locals.signoz.enabled, true) ? try({ (local.env.locals.signoz.host) = dependency.cluster.outputs.agents_public_ipv4 }, {}) : {},
    try(local.env.locals.harbor.enabled, false) ? try({ (local.env.locals.harbor.host) = dependency.cluster.outputs.agents_public_ipv4 }, {}) : {},
  )

  r2_account_id  = include.root.locals.r2_account_id
  r2_bucket      = include.root.locals.r2_bucket
  r2_secrets_key = include.root.locals.r2_secrets_key
  r2_aws_profile = include.root.locals.r2_aws_profile
}
