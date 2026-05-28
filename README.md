# 📖 About the project

An opinionated, batteries-included, startup-ready Kubernetes platform on Hetzner Cloud driven by Terragrunt.

Documentation: [click here](https://paapug.github.io/hetzner-kube-express/)

## 📦 Features

- Out-of-the-box GitOps with [Argo CD](https://argo-cd.readthedocs.io/en/stable/)
- Automatic Let's Encrypt TLS certificates via [Cert-Manager](https://cert-manager.io/)
- Ingress via [Traefik](https://traefik.io/), exposed on every node IP by [Klipper](https://klipper.sh/)
- Cloudflare [DNS](https://developers.cloudflare.com/dns/) records wired up automatically
- Remote state and secrets stored in Cloudflare [R2](https://developers.cloudflare.com/r2/)
- PostgreSQL operator via [CloudNativePG](https://cloudnative-pg.io/) ready for declarative DB clusters
- Out-of-the-box observability via [SigNoz](https://signoz.io/) with auto-instrumented Kubernetes infrastructure metrics and auto-imported dashboards
- Out-of-the-box container registry with [Harbor](https://goharbor.io/), including bundled [Trivy](https://github.com/aquasecurity/trivy) image scanning

## 🧱 Built on

- [kube-hetzner](https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner) - k3s on Hetzner Cloud
- [Terragrunt](https://terragrunt.gruntwork.io/) - orchestrates the Terraform units

# 🚀 Usage

## 🛠️ Initial setup (cluster owner, once)

You need:

- a Hetzner API token with `Read` and `Write` on the project you want to use
- a Cloudflare R2 bucket and an R2 API token with read+write
- a domain on Cloudflare you control, plus a Cloudflare API token with DNS Read and DNS Write on that zone, and the zone's ID (do not mistake it for the account ID often visible in the URL!)

1. Install tools.
    ```bash
    brew install hashicorp/tap/terraform terragrunt awscli jq hcl2json hashicorp/tap/packer hcloud
    ```
2. Set R2 details in [infra/root.hcl](infra/root.hcl): `r2_account_id_default`, `r2_bucket_default`, `r2_aws_profile_default`. These apply to every environment unless an `env.hcl` overrides them.
3. Configure the AWS profile in `~/.aws/credentials` using the name from `r2_aws_profile_default`.
    ```ini
    [r2-hetzner-kube-express]
    aws_access_key_id     = <r2-access-key-id>
    aws_secret_access_key = <r2-secret-access-key>
    ```
4. Set `cloudflare_zone_id` in [infra/dev/env.hcl](infra/dev/env.hcl) to the zone ID of the domain you control.
5. Set `cert_manager.acme_email` in [infra/dev/env.hcl](infra/dev/env.hcl) to the email address to use for Let's Encrypt certificates.
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

Bootstrap takes ~5–10 min on first run (packer builds the MicroOS snapshot). Apply itself is then ~5–10 min.

Share with teammates: the AWS profile keys (via password manager).

---

## 🤝 Joining as a teammate

1. Install tools.
    ```bash
    brew install hashicorp/tap/terraform terraform terragrunt awscli jq hcl2json hashicorp/tap/packer hcloud
    ```
2. Get the R2 keys from the cluster owner. Add them to `~/.aws/credentials` under the profile name from [infra/root.hcl](infra/root.hcl) (`r2_aws_profile_default`):
    ```ini
    [r2-hetzner-kube-express]
    aws_access_key_id     = <from-owner>
    aws_secret_access_key = <from-owner>
    ```
3. (Optional) Restore the cluster SSH key locally if you need `ssh`/`scp` to nodes.
    ```bash
    ENV_DIR=infra/dev infra/_scripts/fetch-ssh-key.sh
    ```
4. (Optional) Fetch the kubeconfig from R2.
    ```bash
    ENV_DIR=infra/dev infra/_scripts/fetch-kubeconfig.sh
    ```
5. You're done. Run terragrunt as needed.
    ```bash
    cd infra/dev
    terragrunt run --all plan
    ```

## 🆕 Adding a new environment

1. Copy the `infra/dev` folder to a new environment folder.
2. (Optional) Create a new R2 bucket and new Hetzner project
3. Edit the `infra/<new-env>/env.hcl` file to set the new environment values.
4. Re-run `ENV_DIR=infra/<new-env> infra/_scripts/env-bootstrap.sh` to bootstrap new `secrets.json`. The packer snapshot build is auto-skipped if the Hetzner project already has one (e.g. when the new env shares a Hetzner token with an existing env).
5. Run `terragrunt run --all apply` inside the new environment folder to apply the new environment.

---

## 📅 Daily use

From `infra/dev/`:

| Command                                                | What                                                                     |
| ------------------------------------------------------ | ------------------------------------------------------------------------ |
| `terragrunt run --all plan`                            | Plan all units                                                           |
| `terragrunt run --all apply`                           | Apply all units                                                          |
| `terragrunt run --all destroy`                         | Tear down                                                                |
| `terragrunt dag graph`                                 | Show unit dependency graph                                               |
| `ENV_DIR=infra/dev infra/_scripts/secrets-edit.sh`     | Edit `secrets.json` in `$EDITOR` (downloads, validates JSON, re-uploads) |
| `ENV_DIR=infra/dev infra/_scripts/fetch-ssh-key.sh`    | Restore SSH key locally                                                  |
| `ENV_DIR=infra/dev infra/_scripts/fetch-kubeconfig.sh` | Fetch kubeconfig from R2; prompts whether to merge into `~/.kube/config` |

Per unit: `cd infra/dev/<unit> && terragrunt apply`.

### 🔑 Get the kubeconfig

The `cluster` unit uploads the rendered kubeconfig to `s3://<r2_bucket>/secrets/<env>/kubeconfig.yaml` on every apply. Fetch it with:

```bash
ENV_DIR=infra/dev infra/_scripts/fetch-kubeconfig.sh
```

The script asks whether to merge the new context into `~/.kube/config` (backs up the existing file first via `kubectl config view --flatten`, then switches `kubectl` to the new context). Decline and it writes `infra/dev/.kube/config` (mode 600) — `export KUBECONFIG=...` to use it. Set `AUTO_MERGE=1` (or `0`) to skip the prompt.

### 🔑 Argo CD admin password

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

### 🔑 SigNoz password

Username is the `operator_email` from [env.hcl](infra/dev/env.hcl). Password is generated by Terraform and seeded into the cluster.

```bash
kubectl -n signoz get secret signoz-initial-admin-secret \
  -o jsonpath='{.data.email}' | base64 -d; echo
```

```bash
kubectl -n signoz get secret signoz-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

The dashboards-import Job creates a long-lived Service Account API key on first run and stores it in `signoz-service-account-secret` (cluster-only, not in R2). Subsequent re-applies use that key, so changing the admin password through the SigNoz UI won't break the pipeline. Get the API key with:

```bash
kubectl -n signoz get secret signoz-service-account-secret \
  -o jsonpath='{.data.api_key}' | base64 -d; echo
```

### 📊 Importing SigNoz dashboards

Drop dashboard JSON files into [infra/modules/signoz/dashboards/](infra/modules/signoz/dashboards/) and re-apply:

```bash
cd infra/dev/signoz && terragrunt apply
```

The Job's name is suffixed with a content hash, so it re-runs only when JSON files change. Imports are not de-duplicated server-side; if you want updates instead of duplicates, set stable `uuid`/`title` fields in the JSON.

To force a fresh Service Account key (e.g. after a manual revoke):

```bash
kubectl -n signoz patch secret signoz-service-account-secret \
  --type='json' -p='[{"op":"remove","path":"/data/api_key"}]'
cd infra/dev/signoz && terragrunt apply
```

### 🔑 Harbor admin password

Username is `admin`. Password is generated by Terraform and seeded into the `harbor-admin-secret` Kubernetes Secret.

```bash
kubectl -n harbor get secret harbor-admin-secret \
  -o jsonpath='{.data.HARBOR_ADMIN_PASSWORD}' | base64 -d; echo
```

Rotating the password through the Harbor UI is safe; the chart keeps reading the existing secret, so future applies are not affected.

## 📝 Trade-offs (read before going to prod)

- Secrets (SSH keys, Hetzner token, Cloudflare API tokens, admin kubeconfig etc.) are stored in R2. Be very mindful who has access to the R2 as rotating all secrets will be time-consuming.
- `cloudflare-dns` records are created with `proxied = false` so cert-manager's HTTP-01 challenge reaches Traefik directly. Don't flip it to `true` without switching the issuer to DNS-01 (currently not supported).
- SigNoz is heavy on `cx23` (no resource limits on the busy components). If you enable it on a small cluster and pods get OOMKilled, scale `agent_nodepools[].count` rather than tuning Helm requests blind.

## 🐛 Troubleshooting

| Symptom                                           | Fix                                               |
| ------------------------------------------------- | ------------------------------------------------- |
| `no R2 credentials found`                         | Set up `~/.aws/credentials` (step 2)              |
| `403 AccessDenied` on init                        | R2 token lacks read+write on the bucket.          |
| Object (.../secrets.json): couldn't find resource | Owner hasn't run `env-bootstrap.sh` for this env. |

## Roadmap

- [x] ArgoCD
- [x] CloudNativePG operator
- [x] SigNoz observability stack
- [ ] Authentik / Zitadel
- [x] Harbor
- [ ] External DNS
- [ ] Allow additional Helm values to be passed to the modules
- [x] Documentation (lol)
- [ ] CI Tests
- [ ] ...
- [ ] Modular cluster provider?

## Contributing

See [Contributing](https://paapug.github.io/hetzner-kube-express/contributing/) for the repo layout, conventions, how to wire a new unit, and the Cursor DevOps skills setup.

## License

Apache License 2.0 — see [LICENSE](LICENSE).
