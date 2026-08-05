# Per-environment locals (non-secret). R2 defaults live in infra/root.hcl;
# override per-env only when this env needs different values.
#
# Every service block takes optional helm_set / helm_set_sensitive maps of Helm
# dot-path keys, applied over the module's own values. The pre-commit hook
# redacts helm_set_sensitive values, so they stay out of git. See
# docs/helm-values.md.

locals {
  cluster_name = "dev"

  # Used by cert-manager AND by SigNoz as the initial admin email.
  operator_email = "REPLACE_WITH_OPERATOR_EMAIL"

  cloudflare = {
    zone_id = "REPLACE_WITH_CLOUDFLARE_ZONE_ID"
    domain  = "REPLACE_WITH_CLOUDFLARE_DOMAIN"
  }

  external_dns = {
    enabled       = true
    chart_version = "1.21.1" # https://github.com/kubernetes-sigs/external-dns/releases (appVersion 0.21.0)
    namespace     = "external-dns"

    # helm_set           = { "interval" = "1m" }
    # helm_set_sensitive = { "some.chart.key" = "REPLACE_WITH_HELM_SECRET" }
  }

  hetzner = {
    network_region = "eu-central"

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
        # enablelb flips Klipper to allow-list mode so only agents are exposed
        labels = ["svccontroller.k3s.cattle.io/enablelb=true"]
        taints = []
        count  = 3
      },
    ]
  }

  hetzner_firewall = {
    ssh_source      = ["0.0.0.0/0", "::/0"]
    kube_api_source = ["0.0.0.0/0", "::/0"]
  }

  cert_manager = {
    acme_email       = local.operator_email
    acme_use_staging = false
  }

  argocd = {
    enabled       = true
    chart_version = "9.5.15"
    host          = "argocd.${local.cloudflare.domain}"

    # helm_set           = { "server.replicas" = "2" }
    # helm_set_sensitive = { "some.chart.key" = "REPLACE_WITH_HELM_SECRET" }
  }

  cnpg = {
    enabled       = true
    chart_version = "0.28.2"

    # helm_set           = { "replicaCount" = "2" }
    # helm_set_sensitive = { "some.chart.key" = "REPLACE_WITH_HELM_SECRET" }
  }

  signoz = {
    enabled                 = true
    chart_version           = "0.125.0" # https://github.com/SigNoz/charts/releases
    k8s_infra_chart_version = "0.16.0"
    host                    = "signoz.${local.cloudflare.domain}"
    deployment_environment  = "dev"
    storage_class           = "hcloud-volumes"
    pvc_sizes = {
      clickhouse = "20Gi"
      zookeeper  = "8Gi"
      signoz     = "1Gi"
    }

    # helm_set targets the signoz chart; k8s_infra_helm_set targets k8s-infra.
    # helm_set           = { "signoz.replicaCount" = "2" }
    # helm_set_sensitive = { "some.chart.key" = "REPLACE_WITH_HELM_SECRET" }
    # k8s_infra_helm_set = { "presets.logsCollection.enabled" = "false" }
  }

  harbor = {
    enabled       = true
    chart_version = "1.19.1" # https://github.com/goharbor/harbor-helm/releases
    host          = "harbor.${local.cloudflare.domain}"
    storage_class = "hcloud-volumes"
    pvc_sizes = {
      registry   = "50Gi"
      jobservice = "5Gi"
      database   = "5Gi"
      redis      = "2Gi"
      trivy      = "10Gi"
    }

    # helm_set           = { "trivy.enabled" = "false" }
    # helm_set_sensitive = { "some.chart.key" = "REPLACE_WITH_HELM_SECRET" }
  }

  # Optional R2 overrides (see root.hcl):
  # r2_account_id  = "<another-cf-account-id>"
  # r2_bucket      = "<another-bucket>"
  # r2_aws_profile = "r2-hetzner-kube-express-prod"
}
