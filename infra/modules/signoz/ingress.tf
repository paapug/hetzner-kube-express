resource "kubernetes_ingress_v1" "signoz" {
  metadata {
    name      = "signoz"
    namespace = kubernetes_namespace.signoz.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer"                   = var.acme_issuer_name
      "traefik.ingress.kubernetes.io/router.tls"         = "true"
      "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure"
    }
  }

  spec {
    ingress_class_name = "traefik"

    tls {
      hosts       = [var.signoz_host]
      secret_name = "signoz-tls"
    }

    rule {
      host = var.signoz_host
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = helm_release.signoz.name
              port {
                number = 8080
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.signoz]
}
