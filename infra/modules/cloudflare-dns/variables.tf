variable "cloudflare_zone_id" {
  type        = string
  description = "Cloudflare zone ID that owns the hostnames being managed."
}

variable "cloudflare_domain" {
  type        = string
  description = "Cloudflare zone domain used to expand additional ingress subdomains into hostnames."
}

variable "records" {
  type        = map(list(string))
  description = "Map of FQDN -> list of IPv4 addresses. One A record is created per (fqdn, ip) pair, enabling DNS round-robin across multiple targets."
}

variable "additional_ingress_subdomains" {
  type        = list(string)
  description = "Additional ingress subdomains under cloudflare_domain that should point at all agent public IPv4 addresses."
  default     = []

  validation {
    condition = alltrue([
      for subdomain in var.additional_ingress_subdomains :
      trimspace(subdomain) == subdomain &&
      can(regex("^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$", subdomain)) &&
      lower(subdomain) != lower(var.cloudflare_domain) &&
      !endswith(lower(subdomain), ".${lower(var.cloudflare_domain)}")
    ])
    error_message = "Each additional ingress subdomain must be relative to cloudflare_domain, for example \"app\" or \"api.v1\", not a URL or FQDN."
  }
}

variable "agents_public_ipv4" {
  type        = list(string)
  description = "Agent node public IPv4 addresses used as targets for additional ingress domains."
}

variable "ttl" {
  type        = number
  description = "TTL for the A records, in seconds. 1 = automatic. Must be 60-86400 otherwise (30 minimum on Enterprise zones)."
  default     = 300
}

variable "proxied" {
  type        = bool
  description = "Whether records flow through the Cloudflare proxy. Keep false for ingress hostnames so cert-manager HTTP-01 challenges reach the origin directly."
  default     = false
}

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
