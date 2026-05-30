resource "kubernetes_namespace" "external_dns" {
  metadata {
    name = var.external_dns_namespace
  }
}

# Preconfigure ExternalDNS with the Cloudflare token from R2 so the operator
# never has to create a secret by hand.
resource "kubernetes_secret_v1" "cloudflare_api_token" {
  metadata {
    name      = "cloudflare-api-token"
    namespace = kubernetes_namespace.external_dns.metadata[0].name
  }

  type = "Opaque"

  data = {
    cloudflare_api_token = local.secrets.cloudflare_api_token
  }
}

resource "helm_release" "external_dns" {
  name       = "external-dns"
  namespace  = kubernetes_namespace.external_dns.metadata[0].name
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  version    = var.external_dns_chart_version

  values = [templatefile("${path.module}/values/external-dns-values.yaml.tpl", {
    cloudflare_domain     = var.cloudflare_domain
    cloudflare_zone_id    = var.cloudflare_zone_id
    txt_owner_id          = var.txt_owner_id
    proxied               = var.proxied
    api_token_secret_name = kubernetes_secret_v1.cloudflare_api_token.metadata[0].name
  })]

  atomic          = true
  cleanup_on_fail = true
  wait            = true
  timeout         = 600
}
