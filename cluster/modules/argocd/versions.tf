terraform {
  required_version = ">= 1.10.1"

  required_providers {
    helm = {
      source = "hashicorp/helm"
      # Pinned to 2.x because providers.tf uses the nested `kubernetes {}` block
      # syntax that was removed in helm provider v3.0.0. Bump to "~> 3.0" only
      # if/when providers.tf is migrated to `kubernetes = { ... }` form.
      version = "~> 2.17"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.33"
    }
  }
}
