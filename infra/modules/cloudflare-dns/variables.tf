# Only the R2 inputs needed to configure the providers for the destroy. The old
# DNS-shaping variables (zone_id, records, ...) are gone with the resources.

variable "r2_account_id" {
  type        = string
  description = "Cloudflare account ID. Used to build the R2 S3 endpoint host for reading secrets.json."
}

variable "r2_bucket" {
  type        = string
  description = "Cloudflare R2 bucket holding secrets/<env>/secrets.json."
}

variable "r2_secrets_key" {
  type        = string
  description = "Object key (within r2_bucket) for the JSON-encoded secrets blob. Expected key consumed here: cloudflare_api_token."
}

variable "r2_aws_profile" {
  type        = string
  description = "AWS shared-credentials profile name (in ~/.aws/credentials) holding the R2 access key. AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY in the env override this per the SDK's standard precedence."
  default     = ""
}
