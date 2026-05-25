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

locals {
  signoz_credentials_json = jsonencode({
    email    = var.admin_email
    password = random_password.signoz_admin.result
    org_name = local.admin_org_name
    host     = var.signoz_host
  })
}

resource "aws_s3_object" "signoz_credentials" {
  provider = aws.r2

  bucket       = var.r2_bucket
  key          = var.r2_signoz_credentials_key
  content      = local.signoz_credentials_json
  content_type = "application/json"

  etag = md5(local.signoz_credentials_json)
}
