variable "kubeconfig" {
  type        = string
  description = "Raw kubeconfig YAML for the target cluster (typically dependency.cluster.outputs.kubeconfig)."
  sensitive   = true
}

variable "acme_email" {
  type        = string
  description = "Email used to register the Let's Encrypt ACME account."
}

variable "acme_use_staging" {
  type        = bool
  description = "If true, point at the Let's Encrypt staging directory (avoids prod rate limits while iterating)."
  default     = true
}
