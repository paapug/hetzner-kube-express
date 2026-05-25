output "namespace" {
  description = "Namespace SigNoz was installed into."
  value       = kubernetes_namespace.signoz.metadata[0].name
}

output "otel_collector_endpoint" {
  description = "In-cluster OTLP HTTP endpoint exposed by the bundled SigNoz collector. Use it from other workloads to ship traces/metrics/logs."
  value       = "http://signoz-otel-collector.${kubernetes_namespace.signoz.metadata[0].name}.svc.cluster.local:4318"
}

output "initial_admin_email" {
  description = "Email seeded into signoz-initial-admin-secret on first apply (sourced from operator_email)."
  value       = var.admin_email
  sensitive   = true
}

output "initial_admin_password" {
  description = "Generated admin password for the first SigNoz user. Mirrored to R2 at r2_signoz_credentials_key. Rotate after first login by changing the password in the UI; the importer Job will keep working via the long-lived Service Account key."
  value       = random_password.signoz_admin.result
  sensitive   = true
}
