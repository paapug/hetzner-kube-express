locals {
  admin_org_name = var.admin_org_name != "" ? var.admin_org_name : var.cluster_name
}

# SigNoz requires >=12 upper/lower/digit/symbol. override_special excludes chars
# that would need escaping in the importer Job (quotes, backslash, $, &, `).
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

# Empty placeholder. The dashboards-import Job patches `data.api_key` after
# minting the SA key; lifecycle.ignore_changes prevents apply from clobbering it.
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
