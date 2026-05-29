# CloudNativePG

[CloudNativePG](https://cloudnative-pg.io/) (CNPG) is the bundled PostgreSQL operator. In the provided environment it is enabled by default, so a normal `terragrunt run --all apply` installs the operator into the `cnpg-system` namespace.

Unlike Argo CD, SigNoz, and Harbor, CNPG has no UI and no Ingress. It is purely a control plane: install the operator, then create `Cluster` custom resources to get Postgres clusters.

## Configure or disable it

CNPG is configured from `infra/<env>/env.hcl`. That is where you control whether it is enabled and which chart version is installed.

To skip CNPG in a new environment, set its `enabled` flag to `false` before the first apply:

```hcl
cnpg = {
  enabled = false
}
```

If CNPG is already installed, destroy any `Cluster` resources you created, then destroy the `cnpg` unit before flipping the flag.

!!! danger "Destroying the operator does not delete databases"
    The CNPG operator is cluster-scoped; the bundled chart installs only the operator workload into `cnpg-system`. `Cluster` resources, their pods, and their backing `PersistentVolumeClaim`s live in whatever namespace you put them. Tear those down explicitly, or they survive an operator destroy and remain unmanaged.

## Your first Cluster

A minimal three-instance Postgres cluster, backed by the Hetzner storage class:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: app-db
  namespace: default
spec:
  instances: 3
  storage:
    size: 10Gi
    storageClass: hcloud-volumes
  bootstrap:
    initdb:
      database: app
      owner: app
```

Apply it:

```bash
kubectl -n default apply -f cluster.yaml
kubectl -n default get cluster app-db -w
```

CNPG creates:

- a primary pod and two replicas;
- one Hetzner volume per instance (one writer plus two read replicas);
- read/write and read-only `Service`s named `app-db-rw` and `app-db-ro`;
- a `Secret` named `app-db-app` with the generated application user credentials.

Workloads in the same cluster connect with `app-db-rw.my-app.svc.cluster.local`. Username and password come from the `app-db-app` secret.

!!! note "Hetzner volume minimum is 10 GiB"
    Sizes below 10 GiB are silently rounded up by Hetzner. See [Persistent Volumes](persistent-volumes.md) for storage class details and grow-only behavior.

!!! warning "Three instances need three nodes"
    CNPG schedules each instance on a distinct node by default. On a single-worker dev cluster, set `spec.instances: 1` or scale `agent_nodepools[].count` before applying.

## Backups

CNPG supports continuous backups to S3-compatible object storage, which means Cloudflare R2 works directly. Point a `Cluster.spec.backup` configuration at a bucket, supply credentials via a Kubernetes `Secret`, and CNPG schedules base backups + WAL archiving.

!!! tip "Use a dedicated R2 bucket for backups"
    Create a separate R2 bucket for CNPG backups instead of reusing the project's state + secrets bucket. A dedicated bucket lets you:

    - issue an R2 API token scoped to just that bucket, so a leaked CNPG credential cannot read or rewrite Terraform state or `secrets.json`;
    - configure backup-specific lifecycle rules (retention, transition to cold tier) without affecting Terraform state objects;
    - track backup storage cost and growth independently of infrastructure state.

    Store the backup R2 credentials in a Kubernetes `Secret` in the same namespace as the `Cluster`. Do not put them in `infra/<env>/env.hcl` or `secrets.json` — they belong to the workload, not to the platform.

The full backup / restore reference lives in the [upstream CNPG documentation](https://cloudnative-pg.io/docs/). That page is the authoritative source for retention, point-in-time recovery, and disaster-recovery workflows; this project does not pre-configure any of it.

!!! danger "Persistent volumes are not backups"
    A working Cluster on Hetzner block storage is not a backup. Configure CNPG backups (or your own pgdump strategy) before you put data in that you cannot lose.

## Resource expectations

CNPG itself is light — one operator pod. The Postgres pods you create with it scale with workload. Treat each Postgres instance as a normal stateful workload when sizing nodes, especially shared_buffers / `resources.requests.memory`.
