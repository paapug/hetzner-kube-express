resource "kubernetes_namespace" "harbor" {
  metadata {
    name = var.harbor_namespace
  }
}

resource "helm_release" "harbor" {
  name       = "harbor"
  namespace  = kubernetes_namespace.harbor.metadata[0].name
  repository = "https://helm.goharbor.io"
  chart      = "harbor"
  version    = var.harbor_chart_version

  values = [
    templatefile("${path.module}/values/harbor.yaml.tpl", {
      storage_class     = var.storage_class
      external_url      = "https://${var.harbor_host}"
      admin_secret_name = kubernetes_secret_v1.harbor_admin.metadata[0].name
      pvc_sizes         = var.pvc_sizes
    })
  ]

  # Applied after `values`, so these win over the template above.
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
  timeout         = 900
}
