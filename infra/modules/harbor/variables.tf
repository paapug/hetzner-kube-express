variable "kubeconfig" {
  type        = string
  description = "Raw kubeconfig YAML for the target cluster (typically dependency.cluster.outputs.kubeconfig)."
  sensitive   = true
}

variable "harbor_chart_version" {
  type        = string
  description = "harbor Helm chart version (https://github.com/goharbor/harbor-helm/releases)."
}

variable "harbor_host" {
  type        = string
  description = "FQDN for the Harbor UI/registry. Must resolve to a cluster node public IP (Klipper exposes Traefik on every node)."
}

variable "harbor_namespace" {
  type        = string
  description = "Namespace to install Harbor into. Created by this module."
  default     = "harbor"
}

variable "acme_issuer_name" {
  type        = string
  description = "Name of the cert-manager ClusterIssuer to annotate on the Harbor Ingress (typically dependency.acme.outputs.issuer_name)."
}

variable "storage_class" {
  type        = string
  description = "Storage class used by Harbor PVCs (registry, jobservice, database, redis, trivy)."
  default     = "hcloud-volumes"
}

variable "admin_email" {
  type        = string
  description = "Operator email surfaced as Harbor's admin contact. Wired from the env-level operator_email."
}

variable "pvc_sizes" {
  type = object({
    registry   = string
    jobservice = string
    database   = string
    redis      = string
    trivy      = string
  })
  description = "Sizes for the five Harbor PVCs. Registry holds image/chart blobs and is the only one that really grows."
  default = {
    registry   = "50Gi"
    jobservice = "5Gi"
    database   = "5Gi"
    redis      = "2Gi"
    trivy      = "10Gi"
  }
}
