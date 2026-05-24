# Per-environment locals (non-secret).
#
# Project defaults for R2 bucket / account id / AWS profile live in
# cluster/root.hcl as `r2_*_default`. Override any of them here only if this
# env needs different values (e.g. prod with a separate bucket and IAM token).

locals {
  cluster_name       = "k8s-playground"
  cluster_domain     = "REPLACE_WITH_CLOUDFLARE_DOMAIN"
  cloudflare_zone_id = "REPLACE_WITH_CLOUDFLARE_ZONE_ID" # Cloudflare zone that owns ${cluster_domain}.

  argocd_chart_version = "9.5.15"
  argocd_host          = "argocd.${local.cluster_domain}"

  acme_email       = "jakub@papug.sh"
  acme_use_staging = true

  # Hetzner Cloud Firewall source CIDRs.
  # Tighten per-env (e.g. office/VPN ranges) before going prod.
  firewall_ssh_source      = ["0.0.0.0/0", "::/0"]
  firewall_kube_api_source = ["0.0.0.0/0", "::/0"]

  # Optional: override project defaults from root.hcl.
  # r2_account_id  = "<another-cf-account-id>"
  # r2_bucket      = "<another-bucket>"
  # r2_aws_profile = "r2-hetzner-k8s-playground-prod"
}
