# Cloudflare DNS

The `cloudflare-dns` unit creates Cloudflare `A` records for the hostnames each environment uses. It reads the Cloudflare API token from R2, the zone ID and domain from `env.hcl`, and the worker node public IPs from the `cluster` unit's outputs.

Each enabled bundled service (Argo CD, SigNoz, Harbor) automatically gets `A` records that point at every worker node IP. Together with Klipper exposing Traefik on every node, that gives simple DNS round-robin without a paid load balancer.

For the full picture of how requests flow from a browser through DNS, Traefik, and into a pod, see [Bundled ingress](ingress.md).

## Configure

The relevant settings in `infra/<env>/env.hcl`:

```hcl
cloudflare = {
  zone_id                       = "<cloudflare-zone-id>"
  domain                        = "<example.com>"
  additional_ingress_subdomains = []
}
```

| Setting | What it controls |
| --- | --- |
| `zone_id` | The Cloudflare zone whose records this environment is allowed to manage. Pick the zone for the domain this environment owns. |
| `domain` | Base domain used to expand `additional_ingress_subdomains` into FQDNs. |
| `additional_ingress_subdomains` | Extra subdomains under `domain` that should resolve to the worker nodes. |

Hostnames for the bundled services (`argocd.host`, `signoz.host`, `harbor.host`) come from the per-service blocks in the same file. Disabled services are skipped automatically.

## Adding an app hostname

To create a Cloudflare record for your own app, add a subdomain to `cloudflare.additional_ingress_subdomains`:

```hcl
cloudflare = {
  zone_id = "<cloudflare-zone-id>"
  domain  = "<example.com>"

  additional_ingress_subdomains = [
    "app",
    "api",
  ]
}
```

Each entry is expanded under `cloudflare.domain` (so `app` becomes `app.example.com`) and gets one `A` record per worker IP. Apply the DNS unit:

```bash
cd infra/<env>/cloudflare-dns
terragrunt apply
```

Your `Service` and `Ingress` still live in Kubernetes (or in whatever Argo CD is syncing). The DNS unit only manages the records.

!!! tip "Subdomain, not FQDN"
    Entries in `additional_ingress_subdomains` must be relative to `cloudflare.domain`. Use `app`, not `app.example.com` or `https://app.example.com/`. The unit validates this and refuses malformed values.

## Round-robin behaviour

For unproxied records, Cloudflare returns every `A` record for the hostname in [rotating order](https://developers.cloudflare.com/dns/manage-dns-records/how-to/round-robin-dns/). Clients that always try the first answer therefore spread roughly evenly across workers over time.

This is simple load sharing, not a managed load balancer:

- DNS and client caches can make traffic uneven.
- Plain round-robin does not health-check workers, so a wedged node can keep getting traffic until Cloudflare TTL expires (default 300 s in this project).
- For real load balancing with health checks, switch to a Hetzner Load Balancer or front the worker IPs with Cloudflare's Load Balancing product. Both cost more than the default setup.

## Proxy mode

Records are managed with Cloudflare proxying disabled (`proxied = false`).

!!! danger "Do not enable Cloudflare proxy"
    cert-manager currently uses HTTP-01, and those challenges need to reach Traefik directly. Flipping `proxied = true` breaks certificate issuance and renewal. Only enable proxy mode if you also switch the ACME solver to something compatible, such as DNS-01.

See [ACME (Let's Encrypt)](acme.md) for the certificate flow and [Bundled ingress](ingress.md) for the full traffic path.

## Partial applies and stale DNS

If you change worker node pools and run a full environment apply, Terragrunt updates the cluster first and then reconciles DNS automatically.

!!! warning "Apply DNS after a cluster-only apply"
    If you apply only the `cluster` unit after changing node pools, Cloudflare keeps pointing at the old worker IPs until you also apply the DNS unit. Until you do, traffic can land on workers that no longer exist:

    ```bash
    cd infra/<env>/cluster
    terragrunt apply

    cd ../cloudflare-dns
    terragrunt apply
    ```

The full-environment apply path does this automatically because of the unit dependency graph.

## Token scope

The Cloudflare API token in R2 needs `DNS:Read` and `DNS:Write` on the zone (`zone_id`) this environment manages. It does not need account-level permissions, and it should not be the global API key.

If the token has the wrong scope, the unit fails on apply with a Cloudflare 4xx. Rotate the token via the Cloudflare UI, update `secrets.json` in R2 with `secrets-edit.sh`, and re-run apply.
