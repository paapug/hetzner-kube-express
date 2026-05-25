# 📖 About the project

An opinionated, batteries-included, startup-ready Kubernetes platform on Hetzner Cloud driven by Terragrunt.

## 📦 Features

- Out-of-the-box GitOps with [Argo CD](https://argo-cd.readthedocs.io/en/stable/)
- Automatic Let's Encrypt TLS certificates via [Cert-Manager](https://cert-manager.io/)
- Ingress via [Traefik](https://traefik.io/), exposed on every node IP by [Klipper](https://klipper.sh/)
- Cloudflare [DNS](https://developers.cloudflare.com/dns/) records wired up automatically
- Remote state and secrets stored in Cloudflare [R2](https://developers.cloudflare.com/r2/)

## 🧱 Built on

- [kube-hetzner](https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner) - k3s on Hetzner Cloud
- [Terragrunt](https://terragrunt.gruntwork.io/) - orchestrates the Terraform units

# 🚀 Usage

## 🛠️ Initial setup (cluster owner, once)

You need:

- a Hetzner API token with `Read` and `Write` on the project you want to use
- a Cloudflare R2 bucket and an R2 API token with read+write
- a Cloudflare API token with `DNS Read` and `DNS Write` on the zone that owns `cluster_domain`, and that zone's ID (do not mistake it for the account ID often visible in the URL!)

1. Install tools.
   ```bash
   brew install terraform terragrunt awscli jq hcl2json
   ```
2. Set R2 details in [infra/root.hcl](infra/root.hcl): `r2_account_id_default`, `r2_bucket_default`, `r2_aws_profile_default`. These apply to every environment unless an `env.hcl` overrides them.
3. Configure the AWS profile in `~/.aws/credentials` using the name from `r2_aws_profile_default`.
   ```ini
   [r2-hetzner-kube-express]
   aws_access_key_id     = <r2-access-key-id>
   aws_secret_access_key = <r2-secret-access-key>
   ```
4. Set `cloudflare_zone_id` in [infra/dev/env.hcl](infra/dev/env.hcl) to the zone ID that owns `cluster_domain`.
5. Create `secrets.json` in R2 (generates the cluster SSH key, asks for your Hetzner token and Cloudflare API token).
   ```bash
   ENV_DIR=infra/dev infra/_scripts/r2-bootstrap.sh
   ```
6. Apply.
   ```bash
   cd infra/dev
   terragrunt run --all apply
   ```

First apply is ~10–20 min (kube-hetzner builds a MicroOS snapshot).

Share with teammates: the AWS profile keys (via password manager).

---

## 🤝 Joining as a teammate

1. Install tools.
   ```bash
   brew install terraform terragrunt awscli jq hcl2json
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
2. Edit the `infra/<new-env>/env.hcl` file to set the new environment name and values.
3. Re-run `ENV_DIR=infra/<new-env> infra/_scripts/r2-bootstrap.sh` to bootsrap new secrets.json.
4. Run `terragrunt run --all apply` inside the new environment folder to apply the new environment.

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

## 📝 Trade-offs (read before going to prod)

- Secrets (SSH keys, Hetzner token, Cloudflare API tokens, admin kubeconfig etc.) are stored in R2. Be very mindful who has access to the R2 as rotating all secrets will be time-consuming.
- `cloudflare-dns` records are created with `proxied = false` so cert-manager's HTTP-01 challenge reaches Traefik directly. Don't flip it to `true` without switching the issuer to DNS-01 (currently not supported).

## 🐛 Troubleshooting

| Symptom                                           | Fix                                                   |
| ------------------------------------------------- | ----------------------------------------------------- |
| `no R2 credentials found`                         | Set up `~/.aws/credentials` (step 2) or use a `.env`. |
| `403 AccessDenied` on init                        | R2 token lacks read+write on the bucket.              |
| Object (.../secrets.json): couldn't find resource | Owner hasn't run `r2-bootstrap.sh` for this env.      |
