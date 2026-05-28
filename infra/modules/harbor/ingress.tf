resource "kubernetes_ingress_v1" "harbor" {
  metadata {
    name      = "harbor"
    namespace = kubernetes_namespace.harbor.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer"                   = var.acme_issuer_name
      "traefik.ingress.kubernetes.io/router.tls"         = "true"
      "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure"
    }
  }

  spec {
    ingress_class_name = "traefik"

    tls {
      hosts       = [var.harbor_host]
      secret_name = "harbor-tls"
    }

    rule {
      host = var.harbor_host
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "harbor"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.harbor]
}
