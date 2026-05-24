# hetzner-k8s-playground

A dev Kubernetes cluster on Hetzner Cloud.

- **Provisioning:** Terraform via [kube-hetzner](https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner), driven by [Terragrunt](https://terragrunt.gruntwork.io/).
- **State + secrets:** Cloudflare R2 (S3-compatible).
- **No** Make, Ansible Vault, or shared passphrases.

## Layout

```
cluster/
├── root.hcl            # Terragrunt root (R2 s3 backend)
├── modules/            # Terraform modules
│   ├── cluster/        # kube-hetzner + reads secrets from R2
│   ├── acme/           # Let's Encrypt ClusterIssuer
│   ├── cloudflare-dns/ # Cloudflare A records (e.g. argocd_host -> node IPs)
│   └── argocd/         # Argo CD + Traefik Ingress
├── _scripts/           # one-shot ops (R2 helpers)
└── dev/                # the dev environment
    ├── env.hcl         # non-secret per-env values
    ├── cluster/        # -> modules/cluster
    ├── acme/           # -> modules/acme           (depends on cluster)
    ├── cloudflare-dns/ # -> modules/cloudflare-dns (depends on cluster)
    └── argocd/         # -> modules/argocd         (depends on cluster + acme + cloudflare-dns)
```

R2 holds:

```
<bucket>/state/<env>/<unit>/terraform.tfstate
<bucket>/secrets/<env>/secrets.json
```

`<env>` is the env folder name. Add a new env with `cp -r cluster/dev cluster/staging`; paths follow.

Apply order: `cluster` → (`acme` and `cloudflare-dns` in parallel) → `argocd`.

---

## Initial setup (cluster owner, once)

You need:

- a Cloudflare R2 bucket and an R2 API token with read+write
- a Cloudflare API token with `Zone:DNS:Edit` on the zone that owns `cluster_domain` (for the `cloudflare-dns` unit), and that zone's ID

1. Install tools.
   ```bash
   brew install terraform terragrunt awscli jq hcl2json
   ```
2. Set R2 details in [cluster/root.hcl](cluster/root.hcl): `r2_account_id_default`, `r2_bucket_default`, `r2_aws_profile_default`. These apply to every environment unless an `env.hcl` overrides them.
3. Configure the AWS profile in `~/.aws/credentials` using the name from `r2_aws_profile_default`.
   ```ini
   [r2-hetzner-k8s-playground]
   aws_access_key_id     = <r2-access-key-id>
   aws_secret_access_key = <r2-secret-access-key>
   ```
4. Set `cloudflare_zone_id` in [cluster/dev/env.hcl](cluster/dev/env.hcl) to the zone ID that owns `cluster_domain`.
5. Create `secrets.json` in R2 (generates the cluster SSH key, asks for your Hetzner token and Cloudflare API token).
   ```bash
   ENV_DIR=cluster/dev cluster/_scripts/r2-bootstrap.sh
   ```
6. Apply.
   ```bash
   cd cluster/dev
   terragrunt run --all apply
   ```

First apply is ~10–20 min (kube-hetzner builds a MicroOS snapshot).

Share with teammates: the AWS profile keys (via password manager).

---

## Joining as a teammate

1. Install tools.
   ```bash
   brew install terraform terragrunt awscli jq hcl2json
   ```
2. Get the R2 keys from the cluster owner. Add them to `~/.aws/credentials` under the profile name from [cluster/root.hcl](cluster/root.hcl) (`r2_aws_profile_default`):
   ```ini
   [r2-hetzner-k8s-playground]
   aws_access_key_id     = <from-owner>
   aws_secret_access_key = <from-owner>
   ```
3. (Optional) Restore the cluster SSH key locally if you need `ssh`/`scp` to nodes.
   ```bash
   ENV_DIR=cluster/dev cluster/_scripts/fetch-ssh-key.sh
   ```
4. You're done. Run terragrunt as needed.
   ```bash
   cd cluster/dev
   terragrunt run --all plan
   ```

---

## Daily use

From `cluster/dev/`:

| Command | What |
|---|---|
| `terragrunt run --all plan` | Plan all units |
| `terragrunt run --all apply` | Apply all units |
| `terragrunt run --all destroy` | Tear down |
| `terragrunt dag graph` | Show unit dependency graph |
| `ENV_DIR=cluster/dev cluster/_scripts/secrets-edit.sh` | Edit `secrets.json` in `$EDITOR` (downloads, validates JSON, re-uploads) |
| `ENV_DIR=cluster/dev cluster/_scripts/fetch-ssh-key.sh` | Restore SSH key locally |

Per unit: `cd cluster/dev/<unit> && terragrunt apply`.

### Get the kubeconfig

```bash
cd cluster/dev/cluster
terragrunt output -raw kubeconfig > ../kubeconfig.yaml
chmod 600 ../kubeconfig.yaml
export KUBECONFIG="$PWD/../kubeconfig.yaml"
```

### Argo CD admin password

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

### Open Argo CD UI without DNS

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:80
```

---

## Credentials: alternatives to the AWS profile

The default uses `~/.aws/credentials`. Override with one of these when you need to:

- **`.env` file + direnv** — recommended for IDE/per-folder workflows.
  ```bash
  cp .env.example cluster/dev/.env && $EDITOR cluster/dev/.env
  echo 'dotenv .env' > cluster/dev/.envrc
  direnv allow cluster/dev
  ```
- **`.env` file + dotenvx** — `dotenvx run -f .env -- terragrunt run --all plan`
- **One-shot export** — `set -a; source .env; set +a`
- **Plain shell** — `export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... AWS_REGION=auto`

Helper scripts in `cluster/_scripts/` auto-load `<repo>/.env` and `<env>/.env` (no direnv needed).

Credentials precedence: `AWS_ACCESS_KEY_ID/SECRET_ACCESS_KEY` > `AWS_PROFILE` > `r2_aws_profile` from `env.hcl` > `r2_aws_profile_default` from `root.hcl`.

R2 target precedence (account id and bucket): `r2_account_id` / `r2_bucket` from `env.hcl` > `r2_account_id_default` / `r2_bucket_default` from `root.hcl`.

`.env`, `.env.*`, `.envrc`, `*.tfstate*`, `.cluster_ssh/`, `**/.terragrunt-cache/` are gitignored.

---

## Trade-offs (read before going to prod)

- Secrets land in tfstate (`data.aws_s3_object.secrets.body`). State is encrypted-at-rest in R2 and gated by the R2 token. Fine for a playground.
- Single bucket, single token. Harden by splitting state and secrets into separate buckets/tokens.
- `secrets.json` itself isn't file-encrypted. Rotate by reissuing the R2 token.
- `secrets.json` keys: `hcloud_token`, `cloudflare_api_token`, `ssh_public_key`, `ssh_private_key`. Rotate the Cloudflare token in the Cloudflare dashboard, then `secrets-edit.sh` + re-apply `cloudflare-dns`.
- `cloudflare-dns` records are created with `proxied = false` so cert-manager's HTTP-01 challenge reaches Traefik directly. Don't flip it to `true` without switching the issuer to DNS-01.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `no R2 credentials found` | Set up `~/.aws/credentials` (step 2) or use a `.env`. |
| `403 AccessDenied` on init | R2 token lacks read+write on the bucket. |
| `404` on `secrets.json` during plan | Owner hasn't run `r2-bootstrap.sh` for this env. |
| First `apply` seems stuck | Normal — MicroOS snapshot build, ~10 min. |
| Warnings on acme/argocd about undeclared vars | Expected — only the cluster unit reads R2 secrets. |
