# Joining as a teammate

Once a cluster owner has done the [Getting started](getting-started.md) setup, other teammates can come in with a much shorter onboarding.

## What you need from the cluster owner

- The R2 access key + secret.
- The name of the AWS profile they used (tip: it's the `r2_aws_profile_default` value in [`infra/root.hcl`](https://github.com/paapug/hetzner-kube-express/blob/main/infra/root.hcl)).

That's it. Everything else (Hetzner token, Cloudflare token, cluster SSH key, kubeconfig) lives in R2 and is fetched on demand.

## Steps

1. Install tools.

    ```bash
    brew install hashicorp/tap/terraform terragrunt awscli jq hcl2json hashicorp/tap/packer hcloud
    ```

2. Add the R2 keys to `~/.aws/credentials` under the profile name from [`infra/root.hcl`](https://github.com/paapug/hetzner-kube-express/blob/main/infra/root.hcl) (`r2_aws_profile_default`).

    ```ini
    [r2-hetzner-kube-express]
    aws_access_key_id     = <from-owner>
    aws_secret_access_key = <from-owner>
    ```

3. (Optional) Restore the cluster SSH key locally if you need `ssh` / `scp` to nodes.

    ```bash
    ENV_DIR=infra/dev infra/_scripts/fetch-ssh-key.sh
    ```

4. (Optional) Fetch the kubeconfig from R2.

    ```bash
    ENV_DIR=infra/dev infra/_scripts/fetch-kubeconfig.sh
    ```

    The script asks whether to merge the new context into `~/.kube/config`. Decline and it writes `infra/dev/.kube/config` (mode 600) — `export KUBECONFIG=...` to use it. Set `AUTO_MERGE=1` (or `0`) to skip the prompt.

5. You're done. Run Terragrunt as needed.

    ```bash
    cd infra/dev
    terragrunt run --all plan
    ```

!!! tip "Multiple environments"
    Every fetch script takes `ENV_DIR=infra/<env>`. Swap `dev` for whichever environment the owner has bootstrapped.

## Next steps

- See the project [README](https://github.com/paapug/hetzner-kube-express#readme) for daily commands, trade-offs, and troubleshooting.
