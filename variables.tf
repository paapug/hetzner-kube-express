variable "hcloud_token" {
  type        = string
  description = "Hetzner Cloud API token (Read & Write). Set via SOPS secrets.enc.json (make plan) or TF_VAR_hcloud_token."
  sensitive   = true
}

variable "ssh_public_key_path" {
  type        = string
  description = "Path to SSH public key registered with Hetzner / used for node access."
  default     = "~/.ssh/id_ed25519.pub"
}

variable "ssh_private_key_path" {
  type        = string
  description = "Path to SSH private key (use null with ssh-agent if preferred)."
  default     = "~/.ssh/id_ed25519"
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
