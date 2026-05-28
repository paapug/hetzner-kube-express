# Secrets and helper scripts

The project keeps day-to-day secrets out of git by putting them in Cloudflare R2. The helper scripts in `infra/_scripts` are the bridge between your local machine, the environment files in git, and the R2 bucket.

The mental model is:

- `infra/<env>/env.hcl` stores non-secret choices, such as hostnames, node pools, and enablement flags.
- `secrets/<env>/secrets.json` in R2 stores sensitive inputs that Terraform needs.
- `secrets/<env>/kubeconfig.yaml` in R2 stores the kubeconfig rendered by the `cluster` unit.
- `state/<env>/<unit>/terraform.tfstate` in R2 stores Terraform state for each unit.

## What lives in R2

One R2 bucket does two jobs: remote Terraform state and per-environment secrets.

```text
s3://<r2-bucket>/
+-- state/
|   +-- <env>/
|       +-- <unit>/terraform.tfstate
+-- secrets/
    +-- <env>/
        +-- secrets.json
        +-- kubeconfig.yaml
```

The bucket, account, and profile defaults are configured in `infra/root.hcl`. An environment can override them from `infra/<env>/env.hcl`, but most environments use the project defaults.

## What is in secrets.json

`secrets.json` has four keys:

```json
{
  "hcloud_token": "<hetzner-api-token>",
  "cloudflare_api_token": "<cloudflare-api-token>",
  "ssh_public_key": "<cluster-ssh-public-key>",
  "ssh_private_key": "<cluster-ssh-private-key>"
}
```

Terraform reads this object during apply:

- The `cluster` module uses the Hetzner token and SSH key material.
- The `cloudflare-dns` module uses the Cloudflare API token.

Anyone with read access to this R2 object can retrieve infrastructure credentials and the cluster SSH key, so treat the R2 access keys like production secrets.

## ENV_DIR selects the environment

Most helper scripts require `ENV_DIR`:

```bash
ENV_DIR=infra/dev infra/_scripts/fetch-kubeconfig.sh
```

The script uses that path to find `env.hcl`, the matching `root.hcl`, the environment name, and the R2 object keys. For another environment, change only `ENV_DIR`:

```bash
ENV_DIR=infra/<env> infra/_scripts/fetch-kubeconfig.sh
```

## Bootstrap: create secrets.json

The cluster owner runs bootstrap once per environment:

```bash
ENV_DIR=infra/<env> infra/_scripts/env-bootstrap.sh
```

Bootstrap does several things:

1. Fills placeholder values in `env.hcl` and `root.hcl` if the files still contain placeholders.
2. Generates a new ed25519 SSH key pair for cluster nodes.
3. Prompts for the Hetzner Cloud API token and Cloudflare DNS API token, unless they are already provided through environment variables.
4. Builds `secrets.json` and uploads it to `secrets/<env>/secrets.json` in R2.
5. Builds the kube-hetzner MicroOS snapshot with Packer if the Hetzner project does not already have one.

Bootstrap refuses to overwrite an existing `secrets.json`. If you set `FORCE=1`, it overwrites the object and rotates the cluster SSH key material, which can lock out anyone relying on the old key.

## Edit secrets.json

Use `secrets-edit.sh` when you need to change a token or repair the R2 object:

```bash
ENV_DIR=infra/<env> infra/_scripts/secrets-edit.sh
```

The script downloads the current object, opens it in `$EDITOR` (or `vi` if `$EDITOR` is unset), validates the result with `jq`, and uploads it only if the file changed.

If the object does not exist yet, the script starts from an empty template. For a brand-new environment, prefer `env-bootstrap.sh` because it also creates the SSH key and handles the MicroOS snapshot.

## Fetch the kubeconfig

After the `cluster` unit applies, it uploads the rendered kubeconfig to R2. Fetch it with:

```bash
ENV_DIR=infra/<env> infra/_scripts/fetch-kubeconfig.sh
```

The script can either merge the downloaded kubeconfig into `~/.kube/config` or write a local file at `infra/<env>/.kube/config`. Use `AUTO_MERGE=1` or `AUTO_MERGE=0` for non-interactive runs.

The `cluster` Terragrunt unit also runs this script after `apply` with `AUTO_MERGE=0`, so a full environment apply writes a local environment kubeconfig without changing your global kubeconfig.

## Fetch the SSH key

Fetch the cluster SSH key only when you need direct `ssh` or `scp` access to nodes:

```bash
ENV_DIR=infra/<env> infra/_scripts/fetch-ssh-key.sh
```

The script reads `secrets.json` from R2 and writes the key pair under `infra/<env>/.cluster_ssh/` with local file permissions suitable for SSH.

## Other helper scripts

`install-git-hooks.sh` points this clone at the repo's git hooks. The pre-commit hook anonymizes staged copies of `infra/root.hcl` and `infra/<env>/env.hcl` so real account IDs, domains, and similar local values do not land in git history.

```bash
infra/_scripts/install-git-hooks.sh
```

`trust-le-staging.sh` is macOS-only. It can add or remove the Let's Encrypt staging roots from your keychain, which is useful when an environment uses staging certificates.

```bash
infra/_scripts/trust-le-staging.sh status
infra/_scripts/trust-le-staging.sh enable
```

## Owner and teammate flow

The cluster owner needs cloud credentials for Hetzner, Cloudflare DNS, and R2. They run `env-bootstrap.sh`, then apply the environment with Terragrunt.

Teammates usually need only the R2 access key, secret, and AWS profile name. With those, they can run Terragrunt, fetch the kubeconfig, or restore the SSH key without handling Hetzner or Cloudflare tokens directly.

In other words: the owner populates R2; everyone else uses R2 as the source of truth.