# Reads secrets.json from R2 via the S3-compatible AWS provider. Creds come
# from the SDK default chain, same as the Terragrunt backend in root.hcl.

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

data "aws_s3_object" "secrets" {
  provider = aws.r2

  bucket = var.r2_bucket
  key    = var.r2_secrets_key
}

locals {
  secrets = jsondecode(data.aws_s3_object.secrets.body)
}

# Mirror the rendered kubeconfig to R2 so teammates can fetch it without terraform.
locals {
  _kubeconfig_yaml = yamldecode(module.kube-hetzner.kubeconfig)

  # k3s always emits exactly one cluster entry; index 0 is safe.
  kubeconfig_ca_sha256 = sha256(
    base64decode(local._kubeconfig_yaml.clusters[0].cluster["certificate-authority-data"])
  )
}

resource "aws_s3_object" "kubeconfig" {
  provider = aws.r2

  bucket       = var.r2_bucket
  key          = var.r2_kubeconfig_key
  content      = module.kube-hetzner.kubeconfig
  content_type = "application/yaml"

  # source_hash, not etag: R2's ETag isn't a content MD5, so etag-driven
  # refresh produces drift every plan. CA fingerprint folded in to surface
  # CA rotation as a content change.
  source_hash = md5("${module.kube-hetzner.kubeconfig}\n${local.kubeconfig_ca_sha256}")

  metadata = {
    "k3s-server-ca-sha256" = local.kubeconfig_ca_sha256
  }
}
