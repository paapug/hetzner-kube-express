resource "kubernetes_service_account_v1" "signoz_bootstrap" {
  metadata {
    name      = "signoz-bootstrap"
    namespace = kubernetes_namespace.signoz.metadata[0].name
  }
}

resource "kubernetes_role_v1" "signoz_bootstrap" {
  metadata {
    name      = "signoz-bootstrap"
    namespace = kubernetes_namespace.signoz.metadata[0].name
  }

  rule {
    api_groups     = [""]
    resources      = ["secrets"]
    resource_names = ["signoz-service-account-secret"]
    verbs          = ["get", "patch"]
  }
}

resource "kubernetes_role_binding_v1" "signoz_bootstrap" {
  metadata {
    name      = "signoz-bootstrap"
    namespace = kubernetes_namespace.signoz.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.signoz_bootstrap.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.signoz_bootstrap.metadata[0].name
    namespace = kubernetes_namespace.signoz.metadata[0].name
  }
}
