# Dev cluster: 3× cx23 in Falkenstein (fsn1), public nodes, Cilium + Hubble, Klipper LB.
# Latest module release at time of authoring: v2.19.3 — check https://registry.terraform.io/modules/kube-hetzner/kube-hetzner/hcloud

module "kube-hetzner" {
  source  = "kube-hetzner/kube-hetzner/hcloud"
  version = "2.19.3"

  providers = {
    hcloud = hcloud
  }

  hcloud_token = var.hcloud_token

  ssh_public_key  = file(pathexpand(var.ssh_public_key_path))
  ssh_private_key = file(pathexpand(var.ssh_private_key_path))

  cluster_name   = "k8s-playground-dev"
  network_region = "eu-central"

  # Pod network (must stay inside network_ipv4_cidr default 10.0.0.0/8; do not change after first apply)
  cluster_ipv4_cidr = "10.116.0.0/16"

  # --- Cilium: kube-proxy replacement + Hubble ---
  cni_plugin            = "cilium"
  disable_kube_proxy    = true
  cilium_hubble_enabled = true

  cilium_routing_mode                   = "native"
  cilium_ipv4_native_routing_cidr       = "10.116.0.0/16"
  cilium_loadbalancer_acceleration_mode = "best-effort"

  # Klipper (k3s ServiceLB): ingress uses node public IPs — no extra Hetzner ingress LB cost
  enable_klipper_metal_lb = true
  load_balancer_location  = "fsn1"

  # Single control plane + 2 workers = 3 cx23 nodes, each with public IPv4
  control_plane_nodepools = [
    {
      name        = "control-plane-fsn1"
      server_type = "cx23"
      location    = "fsn1"
      labels      = []
      taints      = []
      count       = 1
    },
  ]

  agent_nodepools = [
    {
      name        = "worker-fsn1"
      server_type = "cx23"
      location    = "fsn1"
      labels      = []
      taints      = []
      count       = 2
    },
  ]

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

output "ingress_public_ipv4" {
  description = "Ingress endpoint (Klipper: one of the node public IPs)"
  value       = module.kube-hetzner.ingress_public_ipv4
}
