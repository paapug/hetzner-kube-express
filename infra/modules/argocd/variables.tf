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

variable "r2_account_id" {
  type        = string
  description = "Cloudflare account ID. Used to build the R2 S3 endpoint host for uploading argocd-initial-admin credentials."
}

variable "r2_bucket" {
  type        = string
  description = "Cloudflare R2 bucket that receives the rendered argocd credentials JSON."
}

variable "r2_aws_profile" {
  type        = string
  description = "AWS shared-credentials profile name holding the R2 access key. AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY in the env override this per the SDK's standard precedence."
  default     = ""
}

variable "r2_argocd_credentials_key" {
  type        = string
  description = "Object key (within r2_bucket) for the JSON-encoded Argo CD credentials blob. Conventionally secrets/<env>/argocd.json."
}
