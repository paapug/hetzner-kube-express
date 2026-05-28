# CLAUDE.md

Guidance for AI agents working in this repo. Keep edits aligned with the conventions below.

## What this project is

An opinionated, cheap, startup-ready Kubernetes platform on Hetzner Cloud:

- **Compute:** k3s on Hetzner via the [`kube-hetzner`](https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner) Terraform module (cx23 nodes in `fsn1`).
- **Network:** Cilium as CNI with kube-proxy replacement + Hubble. Klipper (k3s ServiceLB) exposes Traefik on every node's public IP — no paid Hetzner LB.
- **TLS / DNS:** cert-manager (bundled by `kube-hetzner`) + Let's Encrypt HTTP-01 via Traefik. Cloudflare DNS A records point hostnames to agent node IPs (DNS round-robin, `proxied = false` so HTTP-01 reaches Traefik).
- **GitOps:** Argo CD via Helm with a Traefik Ingress.
- **State + secrets:** Cloudflare R2 (S3-compatible) — one bucket holds both `state/<env>/<unit>/terraform.tfstate` and `secrets/<env>/secrets.json`.
- **Driver:** Terragrunt orchestrates units with a DAG (no Make / Ansible Vault / shared passphrases).

Design priority: a single `terragrunt run --all apply` should take the user from zero to a batteries-included cluster with good practices.

## Repo layout

```
infra/
├── root.hcl                # Terragrunt root: R2 s3 backend, global R2 settings, retry policy
├── modules/                # Plain Terraform modules (the "how")
│   ├── cluster/            # kube-hetzner + reads secrets from R2 + uploads kubeconfig
│   ├── acme/               # Let's Encrypt ClusterIssuer
│   ├── cloudflare-dns/     # Cloudflare A records (e.g. argocd_host -> node IPs)
│   └── argocd/             # Argo CD Helm release + Traefik Ingress
├── _scripts/               # R2 ops helpers (bootstrap, secrets-edit, fetch-kubeconfig, fetch-ssh-key)
└── dev/                    # An environment (copy to add staging/prod)
    ├── env.hcl             # Non-secret per-env config
    └── <unit>/terragrunt.hcl   # Wires module + dependencies + inputs
```

Apply DAG: `cluster` → (`acme`, `cloudflare-dns`, `cnpg` in parallel) → (`argocd`, `signoz`, `harbor` in parallel).

## Conventions to follow

### Terraform / Terragrunt
- New shared logic goes in `infra/modules/<name>/` as a normal TF module. New per-env wiring goes in `infra/<env>/<name>/terragrunt.hcl`.
- Read R2 / env values via `include.root.locals.*` and `read_terragrunt_config(find_in_parent_folders("env.hcl"))`. Don't hardcode account IDs, buckets, or hostnames in modules.
- Cross-unit values flow through `dependency "<unit>"`. Always provide `mock_outputs` + `mock_outputs_allowed_terraform_commands = ["validate", "plan", "init", "destroy"]` so `plan` works on a fresh clone.
- Sensitive inputs (Hetzner token, SSH keys, Cloudflare API token) come from `secrets.json` in R2 via the `aws.r2` provider — never from variables, env vars in HCL, or git. Acceptable secret keys are documented in `infra/_scripts/env-bootstrap.sh`.
- Adding a new env = `cp -r infra/dev infra/<new-env>` and edit `env.hcl`. Don't fork module code per env.

### Wiring a new module

A unit = `infra/modules/<name>/` (TF) + `infra/<env>/<name>/terragrunt.hcl` (wiring). Use `argocd` as the reference.

Module side (`infra/modules/<name>/`):
- `versions.tf` — pin `required_version` and every provider (match versions used by sibling modules).
- `variables.tf` — one variable per input. Mark secrets `sensitive = true`. Group: cluster access (`kubeconfig`), feature config (`*_host`, `*_chart_version`, ...), R2 (`r2_account_id`, `r2_bucket`, `r2_aws_profile`, `r2_<name>_key`).
- `providers.tf` — if the module talks to the cluster, decode `var.kubeconfig` once and wire `kubernetes` + `helm` from it (don't take a kubeconfig file path).
- `r2.tf` — if the module reads/writes R2, declare `provider "aws" { alias = "r2" ... }` (copy from `argocd/r2.tf`). Use `etag = md5(...)` on `aws_s3_object` so generated content uploads on change.
- `outputs.tf` — expose only what downstream units need. Mark secrets `sensitive`.

Terragrunt side (`infra/<env>/<name>/terragrunt.hcl`):
- `include "root" { ... expose = true }` + `local.env = read_terragrunt_config(find_in_parent_folders("env.hcl"))`.
- Optional on/off switch: read `try(local.env.locals.<name>.enabled, false)` and wrap with `exclude { if = !local.enabled, actions = ["all"] }`.
- `terraform { source = "${get_repo_root()}/infra/modules/<name>" }`.
- One `dependency "<other_unit>"` per upstream output you consume. Always provide realistic `mock_outputs` + `mock_outputs_allowed_terraform_commands = ["validate", "plan", "init", "destroy"]`.
- `inputs = {}`: feature config from `local.env.locals.<name>.*`, cluster/issuer/etc. from `dependency.*.outputs.*`, R2 from `include.root.locals.r2_*`.
- New R2 object keys go in `infra/root.hcl` as `r2_<name>_<thing>_key = "secrets/${local.environment}/<name>.json"`, then read via `include.root.locals.*`.
- New env config goes under `local.<name> = { ... }` in each `infra/<env>/env.hcl`.
- After adding the unit, update the apply DAG note above and confirm `terragrunt dag graph` from the env folder shows it in the right place.

### Shell scripts (`infra/_scripts/`)
- All scripts: `set -euo pipefail`, source `_r2-common.sh`, and use `r2_require_cmd`, `r2_load_env`, `r2_require_aws_creds` for setup.
- Use `$EDITOR`, `mktemp -d`, mode 600/700 perms, and a `trap … EXIT INT TERM HUP` cleanup for anything touching secrets.
- Don't add new dependencies. The stack today: `bash`, `aws`, `jq`, `hcl2json`, `kubectl`, `ssh-keygen`, `openssl`, plus `packer` + `hcloud` (bootstrap-only, used by `env-bootstrap.sh` to build the MicroOS snapshot — not invoked by any day-to-day script). Anything else needs justification.

### Security / cost defaults (don't quietly regress)
- `enable_klipper_metal_lb = true` (no Hetzner LB cost). Don't switch to a managed LB without a clear reason.
- Cloudflare DNS records stay `proxied = false` while HTTP-01 is the ACME solver. Flip to `true` only when also moving cert-manager to DNS-01.
- Firewall CIDRs (`firewall_ssh_source`, `firewall_kube_api_source`) default to open; tighten per env in `env.hcl`, never widen in modules.
- New egress / ingress: prefer in-cluster (ClusterIP + Traefik Ingress) over `LoadBalancer`/`NodePort`.

## Code style

### Documentation
User-facing docs are for a technically curious newcomer: someone who may know the basics, but should not need deep Kubernetes, Terragrunt, Hetzner, cert-manager, or Cloudflare context to understand the page.

- Keep the tone practical, calm, and friendly. Explain the mental model first, then the command or config path.
- Be newbie-friendly without becoming tutorial-heavy. Define project-specific wiring and gotchas, but skip generic background readers can find elsewhere.
- Don't be overly specific. Avoid copying concrete values from `infra/<env>/env.hcl`; say that hostnames, enablement flags, node pools, and similar settings are configured there.
- Prefer broad, durable explanations over environment-specific examples. Use `infra/<env>/...` paths and placeholder commands when possible.
- Call out operational caveats that prevent surprises, especially when a partial apply needs a follow-up unit apply.
- For diagrams, keep labels short and show the main data/control flow. Add a short paragraph after the graph for the details that do not belong in the graph.

### Comments: keep them short
Existing comments in this repo are intentionally terse. Match that.

- Explain **why** or non-obvious **trade-offs / gotchas** only.
- One short line is the default. A short block (3–5 lines) is fine for genuine subtleties (e.g. CA shadowing in `fetch-kubeconfig.sh`, etag-with-CA in `infra/modules/cluster/r2.tf`).
- **Don't narrate code.** No `# create the bucket`, `# loop over hosts`, `# return result`.
- **Don't restate variable names or HCL semantics.** `description = "..."` on variables is the right place for that.
- **Don't write tutorial-style prose.** This isn't docs; `README.md` is.
- When in doubt, delete the comment.

### Misc
- Match the existing HCL/YAML/bash formatting (`terraform fmt`, 2-space YAML, lowercase kebab-case file names).
- Prefer additive changes to modules over forks. If a module needs to behave differently per env, expose a variable in `variables.tf` and set it from `env.hcl`.

## Common tasks (cheat sheet)

From `infra/dev/` (or any env folder):

| Goal | Command |
|---|---|
| Plan everything | `terragrunt run --all plan` |
| Apply everything | `terragrunt run --all apply` |
| Plan/apply one unit | `cd <unit> && terragrunt plan` |
| Show DAG | `terragrunt dag graph` |
| Edit secrets in R2 | `ENV_DIR=infra/<env> infra/_scripts/secrets-edit.sh` |
| Fetch kubeconfig | `ENV_DIR=infra/<env> infra/_scripts/fetch-kubeconfig.sh` |
| Restore SSH key | `ENV_DIR=infra/<env> infra/_scripts/fetch-ssh-key.sh` |

First `apply` is ~10–20 min (MicroOS snapshot build). Don't kill it.

## Where to look first
- `README.md` — user-facing setup, daily use, trade-offs, troubleshooting.
- `infra/root.hcl` — backend config, R2 precedence, retry policy.
- `infra/dev/env.hcl` — concrete example of per-env config shape.
- `infra/_scripts/_r2-common.sh` — auth/credential resolution chain (matches what Terragrunt does).
