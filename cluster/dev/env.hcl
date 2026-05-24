# Per-environment locals (non-secret). Secret values (hcloud_token, ssh keys,
# firewall CIDRs) live in R2 at secrets/<env>/secrets.json and are read at
# plan/apply time by data.aws_s3_object.secrets in cluster/modules/cluster/r2.tf.

locals {
  cluster_name   = "k8s-playground"
  cluster_domain = "REPLACE_WITH_CLOUDFLARE_DOMAIN"

  argocd_chart_version = "9.5.15"
  argocd_host          = "argocd.${local.cluster_domain}"

  # acme (Let's Encrypt) inputs
  acme_email       = "jakub@papug.sh"
  acme_use_staging = true

  # Cloudflare R2 (non-secret addresses; bucket+account id alone are not creds).
  #
  # Authentication uses the standard AWS SDK credential chain. By default we
  # name a profile in ~/.aws/credentials (committable; the profile name is
  # not a secret). Override by exporting AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY
  # in your shell or via a .env file — env vars win over the profile per the
  # SDK's standard precedence rules.
  r2_account_id  = "REPLACE_WITH_CF_ACCOUNT_ID"
  r2_bucket      = "REPLACE_WITH_R2_BUCKET"
  r2_aws_profile = "r2-hetzner-k8s-playground"
}
