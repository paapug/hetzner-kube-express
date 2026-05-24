# Per-environment locals (non-secret).
#
# R2 bucket / account id / default AWS profile are project-global and live in
# cluster/root.hcl. Override `r2_aws_profile` here only if this env needs a
# different AWS profile (e.g. prod with a separate IAM token).

locals {
  cluster_name   = "k8s-playground"
  cluster_domain = "REPLACE_WITH_CLOUDFLARE_DOMAIN"

  argocd_chart_version = "9.5.15"
  argocd_host          = "argocd.${local.cluster_domain}"

  acme_email       = "jakub@papug.sh"
  acme_use_staging = true

  # Optional: override the project default from root.hcl.
  # r2_aws_profile = "r2-hetzner-k8s-playground-prod"
}
