provider "aws" {
  alias  = "r2"
  region = "auto"

  profile = var.r2_aws_profile != "" ? var.r2_aws_profile : null

  endpoints {
    s3 = "https://${var.r2_account_id}.r2.cloudflarestorage.com"
  }

  skip_credentials_validation = true
  skip_region_validation      = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  s3_use_path_style           = true
}

data "kubernetes_secret" "argocd_initial_admin" {
  metadata {
    name      = "argocd-initial-admin-secret"
    namespace = kubernetes_namespace.argocd.metadata[0].name
  }

  depends_on = [helm_release.argocd]
}

locals {
  argocd_credentials_json = jsonencode({
    initial_admin_password = data.kubernetes_secret.argocd_initial_admin.data["password"]
  })
}

resource "aws_s3_object" "argocd_credentials" {
  provider = aws.r2

  bucket       = var.r2_bucket
  key          = var.r2_argocd_credentials_key
  content      = local.argocd_credentials_json
  content_type = "application/json"

  etag = md5(local.argocd_credentials_json)
}
