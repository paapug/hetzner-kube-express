locals {
  acme_server = (
    var.acme_use_staging
    ? "https://acme-staging-v02.api.letsencrypt.org/directory"
    : "https://acme-v02.api.letsencrypt.org/directory"
  )

  acme_issuer_name = var.acme_use_staging ? "letsencrypt-staging" : "letsencrypt-prod"
}

resource "kubernetes_manifest" "letsencrypt_issuer" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = local.acme_issuer_name
    }
    spec = {
      acme = {
        email  = var.acme_email
        server = local.acme_server
        privateKeySecretRef = {
          name = "${local.acme_issuer_name}-account-key"
        }
        solvers = [
          {
            http01 = {
              ingress = {
                class = "traefik"
              }
            }
          }
        ]
      }
    }
  }
}
