output "namespace" {
  description = "Namespace running the CloudNativePG operator. The operator itself watches all namespaces; downstream DB Cluster CRs can live anywhere."
  value       = kubernetes_namespace.cnpg.metadata[0].name
}
