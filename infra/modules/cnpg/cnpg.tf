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

  # The chart runs on its defaults, so these are the only values we pass.
  set = [
    for name, value in var.helm_set : {
      name  = name
      value = value
    }
  ]

  set_sensitive = [
    for name, value in var.helm_set_sensitive : {
      name  = name
      value = value
    }
  ]

  atomic          = true
  cleanup_on_fail = true
  wait            = true
  timeout         = 600
}
