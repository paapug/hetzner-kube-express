# SigNoz: Helm releases (signoz + k8s-infra) + namespace + Traefik Ingress
# with cert-manager TLS + auto-imported dashboards.
#
# Three dependencies:
#   - cluster:        kubeconfig for the kubernetes/helm providers
#   - acme:           issuer_name to annotate the Ingress with
#   - cloudflare_dns: signoz_host must resolve to a node IP before HTTP-01 fires

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

locals {
  env     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  enabled = try(local.env.locals.signoz.enabled, false)
}

exclude {
  if      = !local.enabled
  actions = ["all"]
}

terraform {
  source = "${get_repo_root()}/infra/modules/signoz"
}

dependency "cluster" {
  config_path = "../cluster"

  mock_outputs = {
    kubeconfig = "apiVersion: v1\nkind: Config\nclusters:\n- name: mock\n  cluster:\n    server: https://127.0.0.1:6443\n    certificate-authority-data: \"\"\nusers:\n- name: mock\n  user:\n    client-certificate-data: \"\"\n    client-key-data: \"\"\ncontexts: []\n"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init", "destroy"]
}

dependency "acme" {
  config_path = "../acme"

  mock_outputs = {
    issuer_name = "letsencrypt-staging"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init", "destroy"]
}

# DNS must exist before signoz applies: cert-manager's HTTP-01 solver needs
# signoz_host to resolve to a node IP so Let's Encrypt can reach Traefik.
dependency "cloudflare_dns" {
  config_path = "../cloudflare-dns"

  mock_outputs = {
    records_created = []
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init", "destroy"]
}

inputs = {
  kubeconfig       = dependency.cluster.outputs.kubeconfig
  acme_issuer_name = dependency.acme.outputs.issuer_name

  signoz_chart_version    = local.env.locals.signoz.chart_version
  k8s_infra_chart_version = local.env.locals.signoz.k8s_infra_chart_version
  signoz_host             = local.env.locals.signoz.host
  storage_class           = local.env.locals.signoz.storage_class
  deployment_environment  = local.env.locals.signoz.deployment_environment

  cluster_name = local.env.locals.cluster_name
  admin_email  = local.env.locals.operator_email

  r2_account_id             = include.root.locals.r2_account_id
  r2_bucket                 = include.root.locals.r2_bucket
  r2_aws_profile            = include.root.locals.r2_aws_profile
  r2_signoz_credentials_key = include.root.locals.r2_signoz_credentials_key
}
