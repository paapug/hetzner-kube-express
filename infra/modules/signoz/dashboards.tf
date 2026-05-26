locals {
  dashboards_dir          = var.dashboards_dir != "" ? var.dashboards_dir : "${path.module}/dashboards"
  dashboard_files         = fileset(local.dashboards_dir, "*.json")
  dashboard_files_content = { for f in local.dashboard_files : f => file("${local.dashboards_dir}/${f}") }

  bootstrap_script = file("${path.module}/scripts/dashboards_import.py")

  # Re-run the Job whenever the script or any dashboard JSON changes.
  job_hash = substr(sha1(jsonencode({
    dashboards = local.dashboard_files_content
    script     = local.bootstrap_script
  })), 0, 8)
}

resource "kubernetes_config_map_v1" "signoz_dashboards" {
  metadata {
    name      = "signoz-dashboards"
    namespace = kubernetes_namespace.signoz.metadata[0].name

    labels = {
      "signoz.io/dashboard" = "true"
    }
  }

  # Always create — even when empty — so the Job's volume mount is always valid.
  data = local.dashboard_files_content
}

resource "kubernetes_config_map_v1" "signoz_bootstrap_script" {
  metadata {
    name      = "signoz-bootstrap-script"
    namespace = kubernetes_namespace.signoz.metadata[0].name
  }

  data = {
    "dashboards_import.py" = local.bootstrap_script
  }
}

# Idempotent post-install Job:
#   1) reuse the SA api_key from /sa/api_key if present;
#   2) otherwise register the first admin (or fall back to login) using
#      /admin/{email,password,org_name}, mint a long-lived Service Account +
#      API key, then PATCH the api_key into signoz-service-account-secret via
#      the in-cluster API (no kubectl);
#   3) POST every /dashboards/*.json with header SigNoz-Api-Key.
# Re-runs after a UI password change still succeed because the SA key is the
# only credential needed once it's been minted.
#
# Implementation lives in scripts/dashboards_import.py (stdlib-only Python
# 3.12, mounted via the signoz-bootstrap-script ConfigMap).
resource "kubernetes_job_v1" "dashboards_import" {
  metadata {
    name      = "signoz-dashboards-import-${local.job_hash}"
    namespace = kubernetes_namespace.signoz.metadata[0].name
  }

  spec {
    backoff_limit              = 5
    ttl_seconds_after_finished = 600

    template {
      metadata {
        labels = {
          app = "signoz-dashboards-import"
        }
      }

      spec {
        restart_policy       = "OnFailure"
        service_account_name = kubernetes_service_account_v1.signoz_bootstrap.metadata[0].name

        container {
          name              = "import"
          image             = "python:3.12-alpine"
          image_pull_policy = "IfNotPresent"

          command = ["python", "-u", "/scripts/dashboards_import.py"]

          env {
            name  = "SIGNOZ_BASE"
            value = "http://signoz:8080"
          }
          env {
            name  = "NAMESPACE"
            value = kubernetes_namespace.signoz.metadata[0].name
          }

          volume_mount {
            name       = "scripts"
            mount_path = "/scripts"
            read_only  = true
          }
          volume_mount {
            name       = "dashboards"
            mount_path = "/dashboards"
            read_only  = true
          }
          volume_mount {
            name       = "admin"
            mount_path = "/admin"
            read_only  = true
          }
          volume_mount {
            name       = "sa"
            mount_path = "/sa"
            read_only  = true
          }
        }

        volume {
          name = "scripts"
          config_map {
            name = kubernetes_config_map_v1.signoz_bootstrap_script.metadata[0].name
          }
        }
        volume {
          name = "dashboards"
          config_map {
            name = kubernetes_config_map_v1.signoz_dashboards.metadata[0].name
          }
        }
        volume {
          name = "admin"
          secret {
            secret_name = kubernetes_secret_v1.signoz_initial_admin.metadata[0].name
          }
        }
        volume {
          name = "sa"
          secret {
            secret_name = kubernetes_secret_v1.signoz_service_account.metadata[0].name
            optional    = false
          }
        }
      }
    }
  }

  wait_for_completion = false

  depends_on = [
    helm_release.signoz,
    kubernetes_config_map_v1.signoz_dashboards,
    kubernetes_config_map_v1.signoz_bootstrap_script,
    kubernetes_secret_v1.signoz_initial_admin,
    kubernetes_secret_v1.signoz_service_account,
    kubernetes_role_binding_v1.signoz_bootstrap,
  ]
}
