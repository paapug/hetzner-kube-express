resource "kubernetes_namespace" "cnpg" {
  metadata {
    name = var.cnpg_namespace
  }
}

resource "helm_release" "cnpg" {
  name       = "cnpg"
  namespace  = kubernetes_namespace.cnpg.metadata[0].name
  repository = "https://cloudnative-pg.github.io/charts"
  chart      = "cloudnative-pg"
  version    = var.cnpg_chart_version

  atomic          = true
  cleanup_on_fail = true
  wait            = true
  timeout         = 600
}
