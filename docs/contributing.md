# Contributing

Design priority: a single `terragrunt run --all apply` should take you from zero to a batteries-included cluster with good practices: ingress, TLS, GitOps, DNS, observability, container registry, and secrets kept out of git.

## Repo layout

```
infra/
├── root.hcl                       # Terragrunt root: R2 s3 backend, global R2 settings, retry policy
├── modules/                       # Plain Terraform modules (the "how")
│   ├── cluster/                   # kube-hetzner + reads secrets from R2 + uploads kubeconfig
│   ├── acme/                      # Let's Encrypt ClusterIssuer
│   ├── cloudflare-dns/            # Cloudflare A records (e.g. argocd_host -> node IPs)
│   ├── argocd/                    # Argo CD Helm release + Traefik Ingress
│   ├── cnpg/                      # CloudNativePG operator
│   ├── harbor/                    # Harbor (container registry) Helm release + Traefik Ingress
│   └── signoz/                    # SigNoz observability stack
├── _scripts/                      # R2 ops helpers (bootstrap, secrets-edit, fetch-kubeconfig, ...)
└── dev/                           # An environment (copy to add staging/prod)
    ├── env.hcl                    # Non-secret per-env config
    └── <unit>/terragrunt.hcl      # Wires module + dependencies + inputs

docs/                              # MkDocs site (this page lives here)
.cursor/skills/                    # Cursor agent skills (devops-skills submodule, see below)
```

The mental model is: `infra/modules/<name>/` is the **how** (reusable, env-agnostic Terraform), `infra/<env>/<name>/terragrunt.hcl` is the **wiring** (per-env inputs, dependencies, on/off switch). One environment = one folder under `infra/`.

## Apply DAG

```
cluster → acme, cloudflare-dns, cnpg → argocd, signoz, harbor
```

Things to the right of an arrow run in parallel once everything to their left has applied. `cluster` is always first (it produces the kubeconfig). To see the live graph for an environment:

```bash
cd infra/dev && terragrunt dag graph
```

If you add a unit, update the DAG description above and check `terragrunt dag graph` shows it in the right place.

## Best practices

### Modules

- **Don't fork modules per environment.** If a module needs to behave differently in `prod` vs `dev`, add a variable in `variables.tf` and set it from `env.hcl`.
- **Pin every provider.** Match the versions used by sibling modules so units don't disagree on what to install.
- **Mark secrets as such.** `sensitive = true` on any variable or output that carries a token, key, or password. Use `nonsensitive()` only when you have a reason and a comment explaining it.
- **Keep providers in the module.** Modules that talk to the cluster should decode `var.kubeconfig` once in `providers.tf` and wire `kubernetes` + `helm` from it — never take a kubeconfig file path.

### Terragrunt units

- **`include "root"` everywhere** with `expose = true` so `include.root.locals.*` is available.
- **Always provide `mock_outputs`** plus `mock_outputs_allowed_terraform_commands = ["validate", "plan", "init", "destroy"]` on every `dependency`. Without this, a `plan` on a fresh clone fails.
- **Drive on/off switches from `env.hcl`.** The pattern is `try(local.env.locals.<name>.enabled, false)` + an `exclude { if = !local.enabled, actions = ["all"] }` block.
- **Don't hardcode account IDs, buckets, hostnames, or zone IDs.** They come from `include.root.locals.*` and `local.env.locals.*`.

### Secrets

- **Never commit secrets.** Hetzner / Cloudflare tokens, SSH keys, kubeconfigs all live in R2 (`secrets/<env>/...`) and are read at apply time via the `aws.r2` provider. `secrets.json` keys are documented in [`infra/_scripts/env-bootstrap.sh`](https://github.com/paapug/hetzner-kube-express/blob/main/infra/_scripts/env-bootstrap.sh).
- **Install the pre-commit hook** (one-time, per clone). It re-anonymizes `infra/<env>/env.hcl` and `infra/root.hcl` in the **staged** blob on every commit, so real values never reach git history while your worktree keeps the real values.

    ```bash
    infra/_scripts/install-git-hooks.sh
    ```

    Side effect: after a commit, `git status` will show those two files as modified (worktree real ≠ HEAD anonymized). That's intentional.

### Security defaults — don't quietly regress

- `enable_klipper_metal_lb = true` (no Hetzner LB cost). Don't switch to a managed LB without a reason.
- Cloudflare DNS records stay `proxied = false` while HTTP-01 is the ACME solver.
- `firewall_ssh_source` / `firewall_kube_api_source` default to open; tighten per env in `env.hcl`, never widen in modules.
- New egress / ingress: prefer in-cluster (`ClusterIP` + Traefik `Ingress`) over `LoadBalancer` / `NodePort`.

### Shell scripts (`infra/_scripts/`)

- `set -euo pipefail`, source `_r2-common.sh`, use `r2_require_cmd` / `r2_load_env` / `r2_require_aws_creds` for setup.
- Use `$EDITOR`, `mktemp -d`, mode 600/700 perms, and a `trap … EXIT INT TERM HUP` cleanup for anything touching secrets.
- **Don't add new dependencies.** The stack today is `bash`, `aws`, `jq`, `hcl2json`, `kubectl`, `ssh-keygen`, `openssl`, `packer`, `hcloud`. Anything else needs justification.

### Comments

Existing comments are intentionally terse. Match that.

- Explain **why** or non-obvious **trade-offs / gotchas** only.
- One short line is the default; a 3–5-line block is fine for genuine subtleties.
- **Don't narrate code** (`# create the bucket`, `# loop over hosts`).
- **Don't restate variable names or HCL semantics.** `description = "..."` on variables is where that belongs.
- When in doubt, delete the comment.

## Wiring a new unit

A unit = `infra/modules/<name>/` (Terraform) + `infra/<env>/<name>/terragrunt.hcl` (wiring). Use [`argocd`](https://github.com/paapug/hetzner-kube-express/tree/main/infra/modules/argocd) as the reference.

**Module side (`infra/modules/<name>/`):**

| File | What goes in it |
|------|-----------------|
| `versions.tf` | Pin `required_version` and every provider (match sibling modules). |
| `variables.tf` | One variable per input. Group: cluster access (`kubeconfig`), feature config (`*_host`, `*_chart_version`, ...), R2 (`r2_account_id`, `r2_bucket`, `r2_aws_profile`, `r2_<name>_key`). Mark secrets `sensitive = true`. |
| `providers.tf` | If the module talks to the cluster, decode `var.kubeconfig` once and wire `kubernetes` + `helm` from it. |
| `outputs.tf` | Expose only what downstream units need. Mark secrets `sensitive`. |

**Terragrunt side (`infra/<env>/<name>/terragrunt.hcl`):**

- `include "root" { ... expose = true }` + `local.env = read_terragrunt_config(find_in_parent_folders("env.hcl"))`.
- Optional on/off switch via `try(local.env.locals.<name>.enabled, false)` + `exclude { if = !local.enabled, actions = ["all"] }`.
- `terraform { source = "${get_repo_root()}/infra/modules/<name>" }`.
- One `dependency "<other_unit>"` per upstream output you consume. Always provide realistic `mock_outputs` + `mock_outputs_allowed_terraform_commands`.
- `inputs = {}`: feature config from `local.env.locals.<name>.*`, cluster/issuer/etc. from `dependency.*.outputs.*`, R2 from `include.root.locals.r2_*`.

**Threading it through R2 / env.hcl:**

- New R2 object keys go in [`infra/root.hcl`](https://github.com/paapug/hetzner-kube-express/blob/main/infra/root.hcl) as `r2_<name>_<thing>_key = "secrets/${local.environment}/<name>.json"`, then read via `include.root.locals.*`.
- New env config goes under `local.<name> = { ... }` in each `infra/<env>/env.hcl`.
- After adding the unit, update the [Apply DAG](#apply-dag) above and confirm `terragrunt dag graph` shows it in the right place.

## Cursor skills (DevOps generators / validators)

If you use [Cursor](https://cursor.sh/), this repo vendors a set of DevOps skills as a git submodule at `.cursor/skills/.vendor/cc-devops-skills` ([upstream](https://github.com/akin-ozer/cc-devops-skills)). The most relevant one for this repo — `terragrunt-generator` — is symlinked at `.cursor/skills/terragrunt-generator` so it's prominent in skill discovery. The full submodule also exposes `terragrunt-validator`, `terraform-generator` / `validator`, `k8s-yaml-generator` / `validator`, `helm-generator` / `validator`, `dockerfile-validator`, `bash-script-validator`, and more.

### Enable the skills (one-time, per clone)

The submodule is **opt-in** — a fresh `git clone` leaves it empty. Pull it in with:

```bash
git submodule update --init --recursive
```

To always pull submodules on `git pull` going forward, set this once per clone:

```bash
git config submodule.recurse true
```

Restart Cursor after the first `git submodule update --init` so it picks up the new `SKILL.md` files.

### When the skills earn their keep

- **Scaffolding a new unit** — ask Cursor for "a new Terragrunt unit for `<name>` that depends on `cluster` and `acme`" and the `terragrunt-generator` skill produces a `terragrunt.hcl` with the right `include`, `dependency` + `mock_outputs`, and `inputs` structure. Cross-check against [`infra/dev/argocd/terragrunt.hcl`](https://github.com/paapug/hetzner-kube-express/blob/main/infra/dev/argocd/terragrunt.hcl) before committing — the skill is generic, our conventions (env-agnostic root, R2 backend, `exclude { if = ... }` on/off switch) are more specific.
- **Validating before a `terragrunt run --all plan`** — `terragrunt-validator` runs `terragrunt hcl fmt --check` + dependency-graph checks and flags missing `mock_outputs`, deprecated `skip` / `retryable_errors`, etc.
- **Helm / k8s manifests** added under `infra/modules/<name>/values/` or rendered into the cluster — `helm-validator` and `k8s-yaml-validator` catch the usual schema mistakes before they hit `kubectl apply`.

The skills are **suggestions, not gospel**. If a generator output conflicts with conventions on this page (e.g. it wants to read `env.hcl` from `root.hcl`), this page wins.

### Updating the submodule

```bash
cd .cursor/skills/.vendor/cc-devops-skills
git fetch && git checkout <tag-or-sha>
cd -
git add .cursor/skills/.vendor/cc-devops-skills
git commit -m "bump cc-devops-skills to <tag-or-sha>"
```

## Local-dev tips

### Use Let's Encrypt staging

The default `infra/dev/env.hcl` ships with `cert_manager.acme_use_staging = true` so you don't burn through the production LE rate limit while iterating. On macOS, trust the staging roots once:

```bash
infra/_scripts/trust-le-staging.sh enable    # add LE staging roots to login keychain
infra/_scripts/trust-le-staging.sh status    # check
infra/_scripts/trust-le-staging.sh disable   # remove
```

Only flip `acme_use_staging = false` once everything is working end-to-end.

### Test both apply *and* destroy

Cluster lifecycle bugs (lingering finalizers, dangling Hetzner LBs, R2 objects left over) typically surface on `terragrunt run --all destroy`, not on `apply`. Before opening a PR for anything that touches `infra/modules/`, run a full apply + destroy cycle in `infra/dev`:

```bash
cd infra/dev
terragrunt run --all apply
# poke at the cluster, verify the change
terragrunt run --all destroy
```

### Preview the docs

This site is built with [MkDocs Material](https://squidfunk.github.io/mkdocs-material/) and deployed to GitHub Pages by [`.github/workflows/docs.yml`](https://github.com/paapug/hetzner-kube-express/blob/main/.github/workflows/docs.yml) on every push to `main` that touches `docs/`, `mkdocs.yml`, or the workflow itself.

To preview locally:

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r docs/requirements.txt
mkdocs serve            # http://127.0.0.1:8000
mkdocs build --strict   # what CI runs; fails on warnings (broken links, etc.)
```

`.venv/` and `/site/` are already in `.gitignore`.

## License

Apache License 2.0 — see [LICENSE](https://github.com/paapug/hetzner-kube-express/blob/main/LICENSE).
