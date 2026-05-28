# Harbor requires the admin password as an existing secret. Generate it here so
# the value survives helm rollbacks; override_special excludes chars that would
# need escaping in URLs / docker login (quotes, backslash, $, &, `, /).
resource "random_password" "harbor_admin" {
  length           = 24
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
  override_special = "!@#%^*()-_=+[]{}:?."
}

resource "kubernetes_secret_v1" "harbor_admin" {
  metadata {
    name      = "harbor-admin-secret"
    namespace = kubernetes_namespace.harbor.metadata[0].name
  }

  type = "Opaque"

  data = {
    HARBOR_ADMIN_PASSWORD = random_password.harbor_admin.result
  }
}
