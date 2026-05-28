output "namespace" {
  description = "Namespace Harbor was installed into."
  value       = kubernetes_namespace.harbor.metadata[0].name
}

output "host" {
  description = "External Harbor hostname (matches the Ingress + externalURL)."
  value       = var.harbor_host
}

output "initial_admin_username" {
  description = "Default Harbor admin username."
  value       = "admin"
}

output "initial_admin_password" {
  description = "Generated Harbor admin password seeded into harbor-admin-secret. Rotate via the Harbor UI after first login; the chart will keep using the secret value."
  value       = random_password.harbor_admin.result
  sensitive   = true
}
