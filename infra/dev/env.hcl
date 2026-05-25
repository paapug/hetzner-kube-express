# Per-environment locals (non-secret).
#
# Project defaults for R2 bucket / account id / AWS profile live in
# infra/root.hcl as `r2_*_default`. Override any of them here only if this
# env needs different values (e.g. prod with a separate bucket and IAM token).

locals {
  cluster_name = "dev"

  # Used by cert-manager (Let's Encrypt) AND by SigNoz as the initial admin email.
  operator_email = "REPLACE_WITH_OPERATOR_EMAIL"

  cloudflare = {
    zone_id = "REPLACE_WITH_CLOUDFLARE_ZONE_ID"
    domain  = "REPLACE_WITH_CLOUDFLARE_DOMAIN"
  }

  hetzner = {
    network_region = "eu-central"

    control_plane_nodepools = [
      {
        name        = "control-plane-fsn1"
        server_type = "cx23"
        location    = "fsn1"
        labels      = []
        taints      = []
        count       = 1
      },
    ]

    agent_nodepools = [
      {
        name        = "worker-fsn1"
        server_type = "cx23"
        location    = "fsn1"
        labels      = []
        taints      = []
        count       = 3
      },
    ]
  }

  hetzner_firewall = {
    ssh_source      = ["0.0.0.0/0", "::/0"]
    kube_api_source = ["0.0.0.0/0", "::/0"]
  }

  cert_manager = {
    acme_email       = local.operator_email
    acme_use_staging = false
  }

  argocd = {
    enabled       = true
    chart_version = "9.5.15"
    host          = "argocd.${local.cloudflare.domain}"
  }

  cnpg = {
    enabled       = true
    chart_version = "0.28.2"
  }

  signoz = {
    enabled                 = true
    chart_version           = "0.125.0" # https://github.com/SigNoz/charts/releases
    k8s_infra_chart_version = "0.16.0"
    host                    = "signoz.${local.cloudflare.domain}"
    deployment_environment  = "dev"
    storage_class           = "hcloud-volumes"
  }

  # Optional: override project defaults from root.hcl.
  # r2_account_id  = "<another-cf-account-id>"
  # r2_bucket      = "<another-bucket>"
  # r2_aws_profile = "r2-hetzner-kube-express-prod"
}
