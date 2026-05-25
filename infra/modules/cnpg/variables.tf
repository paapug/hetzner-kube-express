variable "kubeconfig" {
  type        = string
  description = "Raw kubeconfig YAML for the target cluster (typically dependency.cluster.outputs.kubeconfig)."
  sensitive   = true
}

variable "cnpg_chart_version" {
  type        = string
  description = "cloudnative-pg Helm chart version (https://github.com/cloudnative-pg/charts/releases)."
  default     = "0.28.2"
}

variable "cnpg_namespace" {
  type        = string
  description = "Namespace for the CloudNativePG operator. The operator is cluster-scoped; this only controls where its own workload runs."
  default     = "cnpg-system"
}
