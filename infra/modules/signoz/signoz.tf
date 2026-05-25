resource "kubernetes_namespace" "signoz" {
  metadata {
    name = var.signoz_namespace
  }
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
      otel_collector_endpoint = "http://signoz-otel-collector.${kubernetes_namespace.signoz.metadata[0].name}.svc.cluster.local:4318"
    })
  ]

  atomic          = true
  cleanup_on_fail = true
  wait            = true
  timeout         = 600

  depends_on = [helm_release.signoz]
}
