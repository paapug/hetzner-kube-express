# Getting started

An opinionated, batteries-included, startup-ready Kubernetes platform on Hetzner Cloud driven by Terragrunt. This page walks a cluster owner through the one-time setup.

## Prerequisites

You need:

- a Hetzner API token with `Read` and `Write` on the project you want to use
- a Cloudflare R2 bucket and an R2 API token with read+write
- a domain on Cloudflare you control, plus a Cloudflare API token with DNS Read and DNS Write on that zone, and the zone's ID (do not mistake it for the account ID often visible in the URL!)

## Initial setup (cluster owner, once)

1. Install tools.

    ```bash
    brew install hashicorp/tap/terraform terragrunt awscli jq hcl2json hashicorp/tap/packer hcloud
    ```

2. Set R2 details in [`infra/root.hcl`](https://github.com/paapug/hetzner-kube-express/blob/main/infra/root.hcl): `r2_account_id_default`, `r2_bucket_default`, `r2_aws_profile_default`. These apply to every environment unless an `env.hcl` overrides them.

3. Configure the AWS profile in `~/.aws/credentials` using the name from `r2_aws_profile_default`.

    ```ini
    [r2-hetzner-kube-express]
    aws_access_key_id     = <r2-access-key-id>
    aws_secret_access_key = <r2-secret-access-key>
    ```

4. Set `cloudflare_zone_id` in [`infra/dev/env.hcl`](https://github.com/paapug/hetzner-kube-express/blob/main/infra/dev/env.hcl) to the zone ID of the domain you control.

5. Set `cert_manager.acme_email` in [`infra/dev/env.hcl`](https://github.com/paapug/hetzner-kube-express/blob/main/infra/dev/env.hcl) to the email address to use for Let's Encrypt certificates.

6. Bootstrap the environment (this will generate the cluster SSH key, ask for Hetzner + Cloudflare tokens, upload `secrets.json` to R2, and build the kube-hetzner MicroOS snapshot via packer if one isn't already present in the Hetzner project).

    ```bash
    ENV_DIR=infra/dev infra/_scripts/env-bootstrap.sh
    ```

7. Apply.

    ```bash
    cd infra/dev
    terragrunt run --all apply
    ```

8. Fetch the kubeconfig from R2.

    ```bash
    ENV_DIR=infra/dev infra/_scripts/fetch-kubeconfig.sh
    ```

    For the mental model behind bootstrap, R2, and the fetch scripts, see [Secrets and helper scripts](secrets-and-scripts.md).

!!! info "Timing"
    Bootstrap takes ~5–10 min on first run (packer builds the MicroOS snapshot). Apply itself is then ~5–10 min.

Share with teammates: the AWS profile keys (via password manager).

## Next steps

To invite someone onto the cluster, send them to [Joining as a teammate](joining.md). For the full Terragrunt/module dependency map, read [How it fits together](how-it-fits-together.md).