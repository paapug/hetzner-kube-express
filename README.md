# hetzner-k8s-playground — Teammate guide

A dev Kubernetes cluster on Hetzner Cloud, provisioned with Terraform
([kube-hetzner](https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner)).
Secrets live in `secrets.vault.json`, encrypted with **Ansible Vault** — you
only need the shared passphrase.

---

## 1. Get the vault passphrase

Ask the cluster owner for it. They will send it via a password manager
(1Password, Bitwarden, etc.) — **not** in chat or email.

## 2. Install prerequisites

```bash
brew install terraform ansible jq
```

(`ssh-keygen` is built-in on macOS/Linux.)

## 3. Clone and unlock

```bash
git clone <repo-url>
cd hetzner-k8s-playground

# Save the passphrase locally (gitignored, mode 600)
umask 077
printf '%s' 'PASTE-THE-PASSPHRASE-HERE' > .vault_pass

# Restore the cluster SSH key for ssh(1)/scp
make ssh-export
```

## 4. Run Terraform

```bash
make init
make plan
make apply
```

The first `apply` takes ~10–20 minutes (kube-hetzner builds a MicroOS snapshot).

## 5. Use the cluster

```bash
# kubectl
terraform output -raw kubeconfig > kubeconfig.yaml
export KUBECONFIG="$PWD/kubeconfig.yaml"
kubectl get nodes

# SSH to a node
ssh -i .cluster_ssh/cluster_ed25519 root@$(terraform output -json control_planes_public_ipv4 | jq -r '.[0]')

# Hubble UI (Cilium observability)
kubectl -n kube-system port-forward svc/hubble-ui 12000:80
# open http://localhost:12000
```

---

## Daily commands

| Command | What it does |
|---------|--------------|
| `make plan`         | Show pending changes |
| `make apply`        | Apply changes |
| `make destroy`      | Tear the cluster down |
| `make output`       | Show Terraform outputs |
| `make secrets-edit` | Edit `secrets.vault.json` in `$EDITOR` |
| `make secrets-view` | Print decrypted JSON |
| `make ssh-export`   | Re-create `.cluster_ssh/cluster_ed25519` |

All `make` targets decrypt secrets into a short-lived tempfile (mode 700,
wiped on exit). Nothing unencrypted ends up on disk in this repo.

## What not to commit

`.gitignore` already covers these, but FYI:

- `.vault_pass` — the passphrase
- `.cluster_ssh/` — the cluster SSH key restored from the vault
- `*.tfstate*` — Terraform state (contains decrypted secrets)
- `kubeconfig.yaml`

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `error: .vault_pass missing` | You skipped step 3. Create the file with the shared passphrase. |
| `Decryption failed` | Wrong passphrase. Ask the owner. |
| `make plan` complains about a missing tool | Re-run step 2 (`brew install ...`). |
| First `apply` seems stuck | Normal — MicroOS snapshot build, ~10 min. |
| `Warning: Unused Attribute … nat_router_primary_ipv4` | Harmless, comes from the vendored module. |

Owner-only tasks (initial vault setup, rotating the passphrase, changing
node count / region) live in the project notes — ask if you need them.
