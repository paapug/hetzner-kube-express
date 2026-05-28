include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

locals {
  env     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  enabled = try(local.env.locals.argocd.enabled, false)
}

exclude {
  if      = !local.enabled
  actions = ["all"]
}

terraform {
  source = "${get_repo_root()}/infra/modules/argocd"
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

# DNS must exist before apply: cert-manager HTTP-01 needs argocd_host
# resolving to a node IP for Let's Encrypt to reach Traefik.
dependency "cloudflare_dns" {
  config_path = "../cloudflare-dns"

  mock_outputs = {
    records_created = []
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init", "destroy"]
}

inputs = {
  kubeconfig           = dependency.cluster.outputs.kubeconfig
  acme_issuer_name     = dependency.acme.outputs.issuer_name
  argocd_chart_version = local.env.locals.argocd.chart_version
  argocd_host          = local.env.locals.argocd.host
}
