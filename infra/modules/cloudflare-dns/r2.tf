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
  # NOTE: secrets land in tfstate. State itself is encrypted-at-rest in R2 and
  # access is gated by the R2 token; rotate the token to revoke read access.
  secrets = jsondecode(data.aws_s3_object.secrets.body)
}
