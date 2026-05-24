variable "cluster_name" {
  type        = string
  description = "Name of the kube-hetzner cluster (also used for resource naming/labels)."
  default     = "k8s-playground"
}

variable "r2_account_id" {
  type        = string
  description = "Cloudflare account ID. Used to build the R2 S3 endpoint host."
}

variable "r2_bucket" {
  type        = string
  description = "Cloudflare R2 bucket holding secrets/<env>/secrets.json."
}

variable "r2_secrets_key" {
  type        = string
  description = "Object key (within r2_bucket) for the JSON-encoded secrets blob. Expected keys: hcloud_token, ssh_public_key, ssh_private_key."
}

variable "r2_aws_profile" {
  type        = string
  description = "AWS shared-credentials profile name (in ~/.aws/credentials) holding the R2 access key. AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY in the env override this per the SDK's standard precedence."
  default     = ""
}

variable "firewall_ssh_source" {
  type        = list(string)
  description = "Source CIDRs allowed to reach SSH (port 22) on cluster nodes via the Hetzner Cloud Firewall. Not a secret; lives in env.hcl."
  default     = ["0.0.0.0/0", "::/0"]
}

variable "firewall_kube_api_source" {
  type        = list(string)
  description = "Source CIDRs allowed to reach the Kubernetes API (port 6443) via the Hetzner Cloud Firewall. Not a secret; lives in env.hcl."
  default     = ["0.0.0.0/0", "::/0"]
}
