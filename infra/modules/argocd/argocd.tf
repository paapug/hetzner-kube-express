resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version

  values = [file("${path.module}/values/argocd-values.yaml")]

  # Applied after `values`, so these win over the file above.
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

data "kubernetes_secret" "argocd_initial_admin" {
  metadata {
    name      = "argocd-initial-admin-secret"
    namespace = kubernetes_namespace.argocd.metadata[0].name
  }

  depends_on = [helm_release.argocd]
}
