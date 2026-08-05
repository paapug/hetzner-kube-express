# ExternalDNS watches Ingress objects and publishes Cloudflare A records from
# their status IPs. Runs before argocd/signoz/harbor so records appear shortly
# after each Ingress is created.

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

locals {
  env     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  enabled = try(local.env.locals.external_dns.enabled, false)
}

exclude {
  if      = !local.enabled
  actions = ["all"]
}

terraform {
  source = "${get_repo_root()}/infra/modules/external-dns"
}

dependency "cluster" {
  config_path = "../cluster"

  mock_outputs = {
    kubeconfig = "apiVersion: v1\nkind: Config\nclusters:\n- name: mock\n  cluster:\n    server: https://127.0.0.1:6443\n    certificate-authority-data: \"\"\nusers:\n- name: mock\n  user:\n    client-certificate-data: \"\"\n    client-key-data: \"\"\ncontexts: []\n"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init", "destroy"]
}

inputs = {
  kubeconfig = dependency.cluster.outputs.kubeconfig

  external_dns_chart_version = local.env.locals.external_dns.chart_version
  external_dns_namespace     = try(local.env.locals.external_dns.namespace, "external-dns")

  cloudflare_domain  = local.env.locals.cloudflare.domain
  cloudflare_zone_id = local.env.locals.cloudflare.zone_id
  txt_owner_id       = local.env.locals.cluster_name

  helm_set           = try(local.env.locals.external_dns.helm_set, {})
  helm_set_sensitive = try(local.env.locals.external_dns.helm_set_sensitive, {})

  r2_account_id  = include.root.locals.r2_account_id
  r2_bucket      = include.root.locals.r2_bucket
  r2_secrets_key = include.root.locals.r2_secrets_key
  r2_aws_profile = include.root.locals.r2_aws_profile
}
