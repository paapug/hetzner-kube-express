locals {
  admin_org_name = var.admin_org_name != "" ? var.admin_org_name : var.cluster_name
}

# SigNoz requires >=12 chars with upper, lower, digit AND symbol. We pin all
# four classes (min_* constraints) and pick an override_special set that
# survives shell/curl/jq round-trips inside the importer Job without escaping
# (no quotes, backslash, backtick, $ or &).
resource "random_password" "signoz_admin" {
  length           = 24
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
  override_special = "!@#%^*()-_=+[]{}:?."
}

resource "kubernetes_secret_v1" "signoz_initial_admin" {
  metadata {
    name      = "signoz-initial-admin-secret"
    namespace = kubernetes_namespace.signoz.metadata[0].name
  }

  type = "Opaque"

  data = {
    email    = var.admin_email
    password = random_password.signoz_admin.result
    org_name = local.admin_org_name
  }
}

# Pre-created empty Secret. The dashboards-import Job patches `data.api_key`
# in here on first run (after minting the Service Account key); subsequent
# applies must not stomp on it, hence the lifecycle ignore.
resource "kubernetes_secret_v1" "signoz_service_account" {
  metadata {
    name      = "signoz-service-account-secret"
    namespace = kubernetes_namespace.signoz.metadata[0].name
  }

  type = "Opaque"

  lifecycle {
    ignore_changes = [data, metadata[0].annotations]
  }
}
