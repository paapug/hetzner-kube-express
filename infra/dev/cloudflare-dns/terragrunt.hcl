# Decommissioned in 0.2.0: DNS moved to the external-dns unit. This unit points
# at a now-resource-free module, so `terragrunt run --all apply` destroys the
# old A records it created and empties its state — no manual destroy needed. The
# R2 inputs stay because the destroy still needs the cloudflare provider
# authenticated (Terraform must configure a resource's provider to delete it).
# The dependency on external-dns is timing only: the old records are removed
# after ExternalDNS is up and has published its own (TXT-owned) copies, so
# there's no DNS gap. The folder stays for one release; a later release deletes
# it.

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/infra/modules/cloudflare-dns"
}

dependency "external_dns" {
  config_path = "../external-dns"

  mock_outputs = {
    namespace = "external-dns"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init", "destroy"]
}

inputs = {
  r2_account_id  = include.root.locals.r2_account_id
  r2_bucket      = include.root.locals.r2_bucket
  r2_secrets_key = include.root.locals.r2_secrets_key
  r2_aws_profile = include.root.locals.r2_aws_profile
}
