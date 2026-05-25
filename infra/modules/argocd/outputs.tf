output "initial_admin_username" {
  description = "Default Argo CD admin username created by the argo-cd Helm chart."
  value       = "admin"
}

output "initial_admin_password" {
  description = "Argo CD initial admin password from the chart-generated argocd-initial-admin-secret. Rotate (and delete the secret) after first login per Argo CD guidance."
  value       = data.kubernetes_secret.argocd_initial_admin.data["password"]
  sensitive   = true
}
