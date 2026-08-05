variable "kubeconfig" {
  type        = string
  description = "Raw kubeconfig YAML for the target cluster (typically dependency.cluster.outputs.kubeconfig)."
  sensitive   = true
}

variable "argocd_chart_version" {
  type        = string
  description = "argo-cd Helm chart version (https://github.com/argoproj/argo-helm/releases)."
  default     = "7.7.10"
}

variable "argocd_host" {
  type        = string
  description = "FQDN for Argo CD UI/API. Must resolve to a cluster node public IP (Klipper exposes Traefik on every node)."
}

variable "acme_issuer_name" {
  type        = string
  description = "Name of the cert-manager ClusterIssuer to annotate on the Argo CD Ingress (typically dependency.acme.outputs.issuer_name)."
}

variable "helm_set" {
  type        = map(string)
  description = "Extra chart values as Helm dot-path keys, applied over this module's values. Same semantics as `helm --set`."
  default     = {}
}

variable "helm_set_sensitive" {
  type        = map(string)
  description = "Same as helm_set, but values are kept out of plan and apply output."
  default     = {}
  sensitive   = true
}
