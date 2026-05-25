# Let's Encrypt ClusterIssuer (uses cert-manager already installed by kube-hetzner).
#
# Depends on the cluster unit for kubeconfig. Exposes outputs.issuer_name,
# consumed by the argocd unit's Ingress annotation.

include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

terraform {
  source = "${get_repo_root()}/cluster/modules/acme"
}

dependency "cluster" {
  config_path = "../cluster"

  mock_outputs = {
    kubeconfig = "apiVersion: v1\nkind: Config\nclusters:\n- name: mock\n  cluster:\n    server: https://127.0.0.1:6443\n    certificate-authority-data: \"\"\nusers:\n- name: mock\n  user:\n    client-certificate-data: \"\"\n    client-key-data: \"\"\ncontexts: []\n"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init", "destroy"]
}

inputs = {
  kubeconfig       = dependency.cluster.outputs.kubeconfig
  acme_email       = local.env.locals.cert_manager.acme_email
  acme_use_staging = local.env.locals.cert_manager.acme_use_staging
}
