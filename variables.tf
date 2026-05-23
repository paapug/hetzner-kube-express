variable "hcloud_token" {
  type        = string
  description = "Hetzner Cloud API token (Read & Write). Stored in secrets.vault.json (Ansible Vault)."
  sensitive   = true
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key content for Hetzner and cluster nodes. Stored in secrets.vault.json."
}

variable "ssh_private_key" {
  type        = string
  description = "SSH private key content for Terraform provisioning. Stored in secrets.vault.json."
  sensitive   = true
}

variable "firewall_ssh_source" {
  type        = list(string)
  description = "CIDRs allowed to SSH directly to nodes."
  default     = ["0.0.0.0/0", "::/0"]
}

variable "firewall_kube_api_source" {
  type        = list(string)
  description = "CIDRs allowed to reach the Kubernetes API (control-plane LB)."
  default     = ["0.0.0.0/0", "::/0"]
}
