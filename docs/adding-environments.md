# Adding environments

An environment is one folder under `infra/`. The provided example is `infra/dev`, but the same pattern can be copied for `staging`, `prod`, or any other isolated cluster.

Each environment folder has:

- its own `env.hcl` for non-secret settings;
- one Terragrunt unit folder per module, such as `cluster`, `acme`, and `argocd`;
- its own Terraform state path in R2, under `state/<env>/...`;
- its own secrets object in R2, under `secrets/<env>/secrets.json`;
- its own kubeconfig object in R2, under `secrets/<env>/kubeconfig.yaml`.

The environment name comes from the folder name. If you create `infra/staging`, Terragrunt and the scripts treat the environment as `staging`.

## Before you start

Decide a few things before copying the folder:

- Environment name: short names such as `staging` or `prod` keep R2 paths and kubeconfig contexts readable.
- Domain strategy: each environment should use hostnames that do not collide with another environment.
- R2 strategy: most environments can share the project R2 bucket, but `env.hcl` can override the R2 account, bucket, or AWS profile if needed.

## Copy the environment folder

Start by copying the existing environment:

```bash
cp -R infra/dev infra/<new-env>
```

For example:

```bash
cp -R infra/dev infra/staging
```

If your source environment already has local generated files, such as `.kube/` or `.cluster_ssh/`, remove those from the new folder. They are local access artifacts, not part of the reusable environment template.

## Edit env.hcl

Edit `infra/<new-env>/env.hcl`. This file is intentionally the main place for per-environment choices.

Review at least:

| Setting | What to change |
| --- | --- |
| `cluster_name` | Use the new environment name or another unique cluster name. |
| `operator_email` | Email for Let's Encrypt and the bundled SigNoz admin user. |
| `cloudflare.zone_id` | Zone ID for the domain this environment will manage. |
| `cloudflare.domain` | Base domain or subdomain for this environment. |
| `hetzner.*_nodepools` | Server types, locations, labels, taints, and counts. |
| `hetzner_firewall.*` | SSH and Kubernetes API source CIDRs. Tighten these for serious environments. |
| `cert_manager.acme_use_staging` | Keep `true` for testing; set `false` when you want production Let's Encrypt certs. |
| `argocd.host` and `signoz.host` | Hostnames must be unique across environments. |
| `argocd.enabled`, `cnpg.enabled`, `signoz.enabled` | Disable optional units before the first apply if you do not want them installed. |
| `r2_*` overrides | Only set these if this environment should use a different R2 account, bucket, or AWS profile. |

Do not put tokens, SSH keys, kubeconfigs, or passwords in `env.hcl`. Those belong in R2 and are created by the bootstrap script.

## Do not fork module code

Avoid copying or editing `infra/modules/<name>/` just to make an environment different. Modules are shared implementation. Environment-specific choices should usually become variables that are set from `infra/<env>/env.hcl`.

If you are unsure whether a change belongs in a module or in `env.hcl`, start with `env.hcl`. The module should change only when the reusable capability changes.

## Bootstrap secrets for the new environment

Run bootstrap with `ENV_DIR` pointing at the new folder:

```bash
ENV_DIR=infra/<new-env> infra/_scripts/env-bootstrap.sh
```

Bootstrap creates or uploads `secrets/<new-env>/secrets.json` in R2. That object contains the Hetzner token, Cloudflare API token, and generated cluster SSH key material for this environment.

Bootstrap may also build the kube-hetzner MicroOS snapshot in the Hetzner project if no suitable snapshot exists yet.

If `secrets.json` already exists, bootstrap refuses to overwrite it. `FORCE=1` overwrites the object and rotates the cluster SSH key material for that environment, so use it carefully.

## Inspect and apply

From the new environment folder, inspect the Terragrunt graph:

```bash
cd infra/<new-env>
terragrunt dag graph
```

Then apply the environment:

```bash
terragrunt run --all apply
```

The apply order is the same as the example environment: `cluster` first, then the units that need the cluster, then the UI and observability units that need DNS and ACME to be ready.

## Fetch access

After the `cluster` unit has applied, fetch the kubeconfig:

```bash
ENV_DIR=infra/<new-env> infra/_scripts/fetch-kubeconfig.sh
```

Fetch the SSH key only if you need direct node access:

```bash
ENV_DIR=infra/<new-env> infra/_scripts/fetch-ssh-key.sh
```

The kubeconfig is stored at `secrets/<new-env>/kubeconfig.yaml` in R2. The SSH key is restored from `secrets/<new-env>/secrets.json`.

## Common caveats

R2 paths are based on the environment folder name. Renaming `infra/staging` later effectively changes where Terragrunt looks for state and secrets.

Cloudflare hostnames must not collide across environments. If both dev and staging try to own the same hostname, the DNS unit will fight over the same records.

If you apply only `cluster` after changing node pools, apply `cloudflare-dns` afterwards so DNS points at the current worker IPs.

Production certificates require `cert_manager.acme_use_staging = false`. Make that change deliberately, and remember that staging certificates are not trusted by normal browsers unless you trust the staging roots locally.

For the deeper mental model, read [How it fits together](how-it-fits-together.md). For details on `secrets.json`, R2 paths, and helper scripts, read [Secrets and helper scripts](secrets-and-scripts.md).

