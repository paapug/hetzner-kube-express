resource "kubernetes_namespace" "signoz" {
  metadata {
    name = var.signoz_namespace
  }
}

locals {
  otel_collector_host          = "signoz-otel-collector.${kubernetes_namespace.signoz.metadata[0].name}.svc.cluster.local"
  otel_collector_endpoint      = "http://${local.otel_collector_host}:4318" # OTLP/HTTP
  otel_collector_grpc_endpoint = "${local.otel_collector_host}:4317"        # OTLP/gRPC (no scheme; use otel_insecure on the client)
}

resource "helm_release" "signoz" {
  name       = "signoz"
  namespace  = kubernetes_namespace.signoz.metadata[0].name
  repository = "https://charts.signoz.io"
  chart      = "signoz"
  version    = var.signoz_chart_version

  values = [
    templatefile("${path.module}/values/signoz.yaml.tpl", {
      storage_class = var.storage_class
      pvc_sizes     = var.pvc_sizes
    })
  ]

  atomic          = true
  cleanup_on_fail = true
  wait            = true
  timeout         = 1200
}

resource "helm_release" "k8s_infra" {
  name       = "k8s-infra"
  namespace  = kubernetes_namespace.signoz.metadata[0].name
  repository = "https://charts.signoz.io"
  chart      = "k8s-infra"
  version    = var.k8s_infra_chart_version

  values = [
    templatefile("${path.module}/values/k8s-infra.yaml.tpl", {
      cluster_name            = var.cluster_name
      deployment_environment  = var.deployment_environment
      otel_collector_endpoint = local.otel_collector_endpoint
    })
  ]

  atomic          = true
  cleanup_on_fail = true
  wait            = true
  timeout         = 600

  depends_on = [helm_release.signoz]
}

# Pre-destroy hook for the operator-vs-CHI race: helm uninstall removes the
# clickhouse-operator alongside the CHI, leaving its finalizer dangling and
# Helm hung. Delete CHIs while the operator is alive, then strip leftover
# finalizers (defence in depth) and orphan PVCs the chart never owned.
# depends_on forces Terraform to run this first on destroy.
resource "null_resource" "signoz_destroy_prep" {
  triggers = {
    namespace  = kubernetes_namespace.signoz.metadata[0].name
    kubeconfig = var.kubeconfig
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set -euo pipefail
      tmp="$(mktemp -d)"
      trap 'rm -rf "$tmp"' EXIT
      printf '%s' "${self.triggers.kubeconfig}" > "$tmp/kubeconfig"
      chmod 600 "$tmp/kubeconfig"
      export KUBECONFIG="$tmp/kubeconfig"
      ns="${self.triggers.namespace}"

      if ! kubectl get ns "$ns" >/dev/null 2>&1; then
        exit 0
      fi

      # Graceful path: let the running operator finalize the CHI.
      kubectl -n "$ns" delete clickhouseinstallation --all --ignore-not-found --timeout=120s || true

      # Strip finalizers from anything still around so the API server can GC it.
      for chi in $(kubectl -n "$ns" get clickhouseinstallation -o name 2>/dev/null || true); do
        kubectl -n "$ns" patch "$chi" --type=merge -p '{"metadata":{"finalizers":[]}}' || true
      done

      kubectl -n "$ns" delete pvc --all --ignore-not-found --wait=false || true
    EOT
  }

  depends_on = [
    helm_release.signoz,
    helm_release.k8s_infra,
  ]
}
