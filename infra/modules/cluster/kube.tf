# Dev cluster in Falkenstein (fsn1), public nodes, Cilium + Hubble, Klipper LB.
# Latest module release at time of authoring: v2.19.3 — check https://registry.terraform.io/modules/kube-hetzner/kube-hetzner/hcloud

module "kube-hetzner" {
  source  = "kube-hetzner/kube-hetzner/hcloud"
  version = "2.19.3"

  providers = {
    hcloud = hcloud
  }

  hcloud_token = local.secrets.hcloud_token

  ssh_public_key  = local.secrets.ssh_public_key
  ssh_private_key = local.secrets.ssh_private_key

  cluster_name   = var.cluster_name
  network_region = var.network_region

  # --- Cilium: kube-proxy replacement + Hubble ---
  cni_plugin            = "cilium"
  disable_kube_proxy    = true
  cilium_hubble_enabled = true

  cilium_routing_mode                   = "native"
  cilium_loadbalancer_acceleration_mode = "best-effort"

  # Klipper (k3s ServiceLB): ingress uses node public IPs — no extra Hetzner ingress LB cost
  enable_klipper_metal_lb = true
  load_balancer_location  = "fsn1"

  control_plane_nodepools = var.control_plane_nodepools
  agent_nodepools         = var.agent_nodepools

  automatically_upgrade_os  = false
  automatically_upgrade_k3s = false

  firewall_ssh_source      = var.firewall_ssh_source
  firewall_kube_api_source = var.firewall_kube_api_source
}

output "kubeconfig" {
  value     = module.kube-hetzner.kubeconfig
  sensitive = true
}

output "k3s_endpoint" {
  value = module.kube-hetzner.k3s_endpoint
}

output "control_planes_public_ipv4" {
  description = "Public IPs of control plane nodes (kubectl/API when use_control_plane_lb is false)"
  value       = module.kube-hetzner.control_planes_public_ipv4
}

output "agents_public_ipv4" {
  value = module.kube-hetzner.agents_public_ipv4
}
