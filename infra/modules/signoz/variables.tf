variable "kubeconfig" {
  type        = string
  description = "Raw kubeconfig YAML for the target cluster (typically dependency.cluster.outputs.kubeconfig)."
  sensitive   = true
}

variable "signoz_chart_version" {
  type        = string
  description = "signoz Helm chart version (https://github.com/SigNoz/charts/releases)."
}

variable "k8s_infra_chart_version" {
  type        = string
  description = "k8s-infra Helm chart version (https://github.com/SigNoz/charts/releases)."
}

variable "signoz_namespace" {
  type        = string
  description = "Namespace to install SigNoz into. Created by this module."
  default     = "signoz"
}

variable "signoz_host" {
  type        = string
  description = "FQDN for the SigNoz UI. Must resolve to a cluster node public IP (Klipper exposes Traefik on every node)."
}

variable "acme_issuer_name" {
  type        = string
  description = "Name of the cert-manager ClusterIssuer to annotate on the SigNoz Ingress (typically dependency.acme.outputs.issuer_name)."
}

variable "cluster_name" {
  type        = string
  description = "Cluster name; surfaced as global.clusterName in the k8s-infra chart."
}

variable "deployment_environment" {
  type        = string
  description = "Deployment environment label (dev/staging/prod); surfaced as global.deploymentEnvironment in the k8s-infra chart."
}

variable "storage_class" {
  type        = string
  description = "Storage class used by SigNoz PVCs (ClickHouse, Zookeeper, frontend)."
  default     = "hcloud-volumes"
}

variable "dashboards_dir" {
  type        = string
  description = "Filesystem path holding dashboard JSON files to auto-import. Defaults to the module's bundled dashboards/ folder."
  default     = ""
}

variable "admin_email" {
  type        = string
  description = "Initial SigNoz admin email. Wired from the env-level operator_email; also used to seed signoz-initial-admin-secret and the R2 credentials mirror."
}

variable "admin_org_name" {
  type        = string
  description = "Initial organization name shown in SigNoz. Defaults to the cluster name."
  default     = ""
}

variable "r2_account_id" {
  type        = string
  description = "Cloudflare account ID. Used to build the R2 S3 endpoint host for uploading signoz initial-admin credentials."
}

variable "r2_bucket" {
  type        = string
  description = "Cloudflare R2 bucket that receives the rendered signoz credentials JSON."
}

variable "r2_aws_profile" {
  type        = string
  description = "AWS shared-credentials profile name holding the R2 access key. AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY in the env override this per the SDK's standard precedence."
  default     = ""
}

variable "r2_signoz_credentials_key" {
  type        = string
  description = "Object key (within r2_bucket) for the JSON-encoded SigNoz credentials blob. Conventionally secrets/<env>/signoz.json."
}
