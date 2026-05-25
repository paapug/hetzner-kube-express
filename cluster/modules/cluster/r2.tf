# Read secrets.json from Cloudflare R2 via the S3-compatible AWS provider.
#
# Auth: AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY are read from the shell env
# automatically (no static creds in code). The same env vars also feed the
# Terragrunt s3 backend in cluster/root.hcl, so one credential set covers
# both state and secrets.

provider "aws" {
  alias  = "r2"
  region = "auto"

  # Empty profile means "use the SDK default chain" (env vars, then default
  # profile, etc.). Passing the explicit profile name pins it; AWS_ACCESS_KEY_ID
  # in the env still overrides (standard SDK precedence).
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

# Persist the rendered kubeconfig to R2 so teammates can fetch it without
# running terraform.
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

  # Folding the CA fingerprint into the etag means any server-CA rotation is
  # surfaced as a content change, even if other bytes of the kubeconfig YAML
  # happen to round-trip identically through kube-hetzner's renderer.
  etag = md5("${module.kube-hetzner.kubeconfig}\n${local.kubeconfig_ca_sha256}")

  metadata = {
    "k3s-server-ca-sha256" = local.kubeconfig_ca_sha256
  }
}
