# Troubleshooting

A short list of the failures most users hit. Each entry points at the underlying mechanic so the fix sticks the next time.

## R2 / Terragrunt

### `no R2 credentials found`

Terragrunt cannot resolve R2 credentials.

- The named profile in `infra/root.hcl` (`r2_aws_profile_default`) does not exist in `~/.aws/credentials`, **or**
- `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` are not exported in the current shell.

Set up the profile per [Joining as a teammate](joining.md) step 2, or export the env vars before running Terragrunt.

### `403 AccessDenied` on init

The R2 token in `~/.aws/credentials` lacks the required permissions.

Rotate to an R2 token with read+write on the bucket from the Cloudflare dashboard and update `~/.aws/credentials`.

### `Object (.../secrets.json): couldn't find resource`

The environment has not been bootstrapped yet. The cluster owner runs:

```bash
ENV_DIR=infra/<env> infra/_scripts/env-bootstrap.sh
```

once per environment. See [Secrets and helper scripts](secrets-and-scripts.md) for the full bootstrap flow.

### `terragrunt plan` fails on a fresh clone

Every unit has `mock_outputs` for `plan`, `validate`, `init`, and `destroy`. If a `plan` still fails before any unit has been applied, it is almost always because a unit was added without `mock_outputs`. See the [Contributing guide](contributing.md) for the required `dependency` block shape.

## Certificates

### Certificate stuck in `Pending` for many minutes

cert-manager cannot complete the HTTP-01 challenge. Common causes, in order of likelihood:

1. **ExternalDNS has not reconciled yet.** Wait a minute, then `dig @1.1.1.1 <host>`.
2. **Cloudflare proxy is enabled** on the hostname. HTTP-01 needs requests to reach Traefik directly. Set `proxied = false` for ingress records. See [ACME (Let's Encrypt)](acme.md).
3. **Stale Cloudflare records** from a previous cluster point at the wrong IPs. Check the Ingress address and ExternalDNS logs to confirm the controller is reconciling the current agent IPs.

Inspect the certificate status:

```bash
kubectl describe certificate -n <namespace> <name>
kubectl -n cert-manager logs deploy/cert-manager
```

### Browser shows "Not secure" on a freshly applied environment

The environment is set to `cert_manager.acme_use_staging = true`. Staging certificates are not trusted by browsers or `curl` by default.

On macOS, trust the staging roots locally:

```bash
infra/_scripts/trust-le-staging.sh enable
```

Or switch the environment to production certificates by setting `cert_manager.acme_use_staging = false` in `env.hcl`. See [ACME (Let's Encrypt)](acme.md) for the full flow.

### Production rate-limit error from Let's Encrypt

Each registered domain is limited to a fixed number of new certificates per week. Repeated full apply / destroy cycles on production burn through the budget fast. Stay on `acme_use_staging = true` while iterating.

## DNS

### Traffic still goes to old agent IPs after scaling nodes

ExternalDNS reconciles Cloudflare records from Kubernetes `Ingress` status. If Cloudflare still returns old IPs, first check what Kubernetes is publishing:

```bash
kubectl get ingress -A
```

If the Ingress still shows old addresses, the cluster has not updated the ingress status yet. If the Ingress shows the right agent IPs but Cloudflare does not, check ExternalDNS:

```bash
kubectl -n external-dns logs deploy/external-dns
```

Cloudflare and downstream DNS caches can also keep returning old answers briefly after ExternalDNS has updated the records.

### Wrong zone or wrong domain

`cloudflare.zone_id` and `cloudflare.domain` in `env.hcl` must match the same zone. The token in R2 needs `DNS:Read` and `DNS:Write` scoped to that zone. The most common form of this bug is using the Cloudflare account ID (often visible in the dashboard URL) as the zone ID.

## Cluster

### `kubectl` cannot reach the cluster

The local kubeconfig is stale or missing. Fetch the latest from R2:

```bash
ENV_DIR=infra/<env> infra/_scripts/fetch-kubeconfig.sh
```

The script either merges the new context into `~/.kube/config` or writes a per-env file at `infra/<env>/.kube/config` (mode 600). See [Secrets and helper scripts](secrets-and-scripts.md) for `AUTO_MERGE` behaviour.

### Pods stuck `Pending` after a `Cluster` (CNPG) apply

CloudNativePG spreads instances across distinct nodes. If you ask for three instances on a single-worker cluster, two stay pending forever.

Either reduce `spec.instances` on the `Cluster` resource, or scale `agent_nodepools[].count` in `env.hcl` and apply. See [CloudNativePG](cnpg.md) for the minimum cluster shape.

### Pod stuck `Pending` waiting for a volume

Hetzner block storage volumes are `ReadWriteOnce` and can attach to at most one node at a time. If a pod is rescheduled to a different node while the volume is still attached, it waits.

Usually self-resolves once Kubernetes detaches the volume. If it does not, check `kubectl describe pvc <name>` for the actual event. Volume attachment limits (16 per server) also surface here — see [Persistent Volumes](persistent-volumes.md).

## Bundled services

### SigNoz or Harbor pods getting OOMKilled

Both are heavy on small Hetzner nodes. Before tuning Helm resource values, add worker capacity:

```hcl
hetzner = {
  agent_nodepools = [
    {
      name        = "worker-fsn1"
      server_type = "cx23"
      location    = "fsn1"
      count       = 4   # was 3
    },
  ]
}
```

ClickHouse (SigNoz) and the Harbor core + bundled Postgres are the usual culprits. See [SigNoz](signoz.md) and [Harbor](harbor.md).

### Lost admin password after rotation

- **Argo CD:** the `argocd-initial-admin-secret` is deleted by Argo CD once you rotate through the UI. Re-set the admin password by editing the password hash in the `argocd-secret` Secret directly. See the [upstream user management docs](https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/).
- **SigNoz:** rotate from the UI; the dashboard importer keeps using its own service-account key, not the admin password.
- **Harbor:** rotate from the UI; the chart keeps reading the existing `harbor-admin-secret`.

## Operations

### `FORCE=1 env-bootstrap.sh` ran on a live cluster

`FORCE=1 infra/_scripts/env-bootstrap.sh` generates a new cluster SSH key pair and overwrites `secrets.json` in R2. The new key never reaches existing nodes: Hetzner injects SSH keys via cloud-init at server creation time, so already-running servers keep authorizing only the **previous** public key.

Symptoms after running `FORCE=1` on a live cluster:

- The next `terragrunt apply` on the `cluster` unit fails when kube-hetzner tries to SSH to existing nodes with the new private key (the nodes' `authorized_keys` still has the old public key).
- `fetch-ssh-key.sh` downloads the new key, but it cannot authenticate to existing nodes either.
- k3s, ingress, and workloads keep running. Only Terraform-driven node management is broken.

Recovery, in order of preference:

1. **Restore the previous key material** if you still have it. Use `secrets-edit.sh` to write the old `ssh_public_key` / `ssh_private_key` back into `secrets.json`, then re-apply.

    ```bash
    ENV_DIR=infra/<env> infra/_scripts/secrets-edit.sh
    ```

2. **Manually add the new public key** to `~/.ssh/authorized_keys` on every node (via the Hetzner Cloud Console's web terminal or a previously-trusted SSH session). Then `fetch-ssh-key.sh` works.

3. **Destroy and rebuild the environment.** Last resort; only acceptable if there is no stateful data to preserve, or if you have CNPG / SigNoz / Harbor backups stored elsewhere.

The right way to think about `FORCE=1` is "wipe the environment record in R2 before applying to a fresh Hetzner project". It is not a key-rotation tool for live clusters. See [Secrets and helper scripts](secrets-and-scripts.md).

### Partial destroy left R2 objects behind

`terragrunt run --all destroy` should clean up state objects, but R2 secrets (`secrets/<env>/secrets.json`, `secrets/<env>/kubeconfig.yaml`) are intentionally not deleted: they belong to the environment, not to any single unit. Delete them manually from R2 if you are truly tearing the environment down.

## Still stuck?

- The Terragrunt dependency graph: `cd infra/<env> && terragrunt dag graph`.
- The cluster's own events: `kubectl get events -A --sort-by=.lastTimestamp`.
- The cert-manager controller logs: `kubectl -n cert-manager logs deploy/cert-manager`.
- The Traefik logs (from the `kube-system` namespace in k3s): `kubectl -n kube-system logs -l app.kubernetes.io/name=traefik`.
