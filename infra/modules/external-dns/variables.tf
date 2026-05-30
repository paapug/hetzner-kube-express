variable "kubeconfig" {
  type        = string
  description = "Raw kubeconfig YAML for the target cluster (typically dependency.cluster.outputs.kubeconfig)."
  sensitive   = true
}

variable "external_dns_chart_version" {
  type        = string
  description = "external-dns Helm chart version (https://github.com/kubernetes-sigs/external-dns/releases)."
}

variable "external_dns_namespace" {
  type        = string
  description = "Namespace ExternalDNS runs in."
  default     = "external-dns"
}

variable "cloudflare_domain" {
  type        = string
  description = "Cloudflare zone domain ExternalDNS is allowed to manage records under (--domain-filter)."
}

variable "cloudflare_zone_id" {
  type        = string
  description = "Cloudflare zone ID ExternalDNS scopes API calls to (--zone-id-filter)."
}

variable "txt_owner_id" {
  type        = string
  description = "Unique owner ID written into ExternalDNS TXT registry records so this cluster only manages records it created."
}

variable "proxied" {
  type        = bool
  description = "Whether ExternalDNS routes records through the Cloudflare proxy. Keep false so cert-manager HTTP-01 challenges reach Traefik directly."
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
