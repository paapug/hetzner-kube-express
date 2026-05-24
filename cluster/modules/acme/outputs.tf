output "issuer_name" {
  description = "Name of the Let's Encrypt ClusterIssuer (consumed by downstream Ingress resources via cert-manager.io/cluster-issuer annotation)."
  value       = local.acme_issuer_name
}

output "acme_server" {
  description = "ACME directory URL the issuer is configured against (staging vs prod)."
  value       = local.acme_server
}
