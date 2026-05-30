# Decommissioned in 0.2.0: DNS moved to the external-dns unit. This module has
# no resources, but it KEEPS the cloudflare + aws providers configured so that
# `terragrunt run --all apply` can authenticate the destroy of the A records
# still in this unit's state. Removing the provider config would break the
# destroy with "Missing Authorization headers". The unit folder stays for one
# release so 0.1.0 -> 0.2.0 upgrades don't orphan state; a later release removes
# it entirely.

terraform {
  required_version = ">= 1.10.1"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }
}
