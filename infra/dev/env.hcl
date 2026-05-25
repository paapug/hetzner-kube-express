# Per-environment locals (non-secret).
#
# Project defaults for R2 bucket / account id / AWS profile live in
# infra/root.hcl as `r2_*_default`. Override any of them here only if this
# env needs different values (e.g. prod with a separate bucket and IAM token).

locals {
  cluster_name = "dev"

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
        count       = 2
      },
    ]
  }

  hetzner_firewall = {
    ssh_source      = ["0.0.0.0/0", "::/0"]
    kube_api_source = ["0.0.0.0/0", "::/0"]
  }

  cert_manager = {
    acme_email       = "jakub@papug.sh"
    acme_use_staging = false
  }

  argocd = {
    enabled       = true
    chart_version = "9.5.15"
    host          = "argocd.${local.cloudflare.domain}"
  }

  # Optional: override project defaults from root.hcl.
  # r2_account_id  = "<another-cf-account-id>"
  # r2_bucket      = "<another-bucket>"
  # r2_aws_profile = "r2-hetzner-kube-express-prod"
}
