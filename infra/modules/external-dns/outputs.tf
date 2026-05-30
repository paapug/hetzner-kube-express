output "namespace" {
  description = "Namespace ExternalDNS runs in. Downstream units depend on this for timing (controller must be up before their Ingress is created)."
  value       = kubernetes_namespace.external_dns.metadata[0].name
}

output "release_name" {
  description = "Helm release name for ExternalDNS."
  value       = helm_release.external_dns.name
}
