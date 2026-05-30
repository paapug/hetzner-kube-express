# ACME (Let's Encrypt)

The `acme` unit creates a cert-manager `ClusterIssuer` that requests Let's Encrypt certificates via the HTTP-01 challenge through Traefik. cert-manager itself is bundled by the `kube-hetzner` Terraform module, so this unit's job is just to wire a project-wide issuer that the other units annotate on their `Ingress` resources.

## Staging vs production

ACME settings live in `infra/<env>/env.hcl` under `cert_manager`:

```hcl
cert_manager = {
  acme_email       = "you@example.com"
  acme_use_staging = true
}
```

`acme_use_staging` controls which Let's Encrypt directory the issuer points at and, consequently, which `ClusterIssuer` name the unit creates:

| `acme_use_staging` | ACME directory | Issuer name created |
| --- | --- | --- |
| `true` | `acme-staging-v02.api.letsencrypt.org` | `letsencrypt-staging` |
| `false` | `acme-v02.api.letsencrypt.org` | `letsencrypt-prod` |

Downstream units (`argocd`, `signoz`, `harbor`) read the issuer name from `dependency.acme.outputs.issuer_name` and annotate it onto their Ingress. Flipping `acme_use_staging` rewires every downstream Ingress to the new issuer on the next apply.

!!! tip "Flip to staging while iterating"
    Set `acme_use_staging = true` on an environment whenever you expect to apply and destroy it repeatedly. Let's Encrypt production has strict rate limits per registered domain; staging does not. Flip back to `false` once the rest of the wiring is stable.

## Trust the staging roots locally (macOS)

Staging certificates are not trusted by browsers or `curl` by default. On macOS, the helper script adds the staging roots to the login keychain:

```bash
infra/_scripts/trust-le-staging.sh enable
infra/_scripts/trust-le-staging.sh status
infra/_scripts/trust-le-staging.sh disable
```

This only affects your local trust store. The cluster itself does not need to trust the staging roots.

## Switching to production

Once everything works on staging:

1. Edit `infra/<env>/env.hcl` and set `cert_manager.acme_use_staging = false`.
2. Apply the `acme` unit, then the units whose Ingress reference the issuer:

    ```bash
    cd infra/<env>
    terragrunt run --all apply
    ```

cert-manager re-issues each certificate against the production directory on the next reconcile.

!!! warning "Production has rate limits"
    Let's Encrypt production limits new certificates per registered domain per week. If you destroy and re-create environments rapidly on production, you can lock yourself out for several days. Keep `acme_use_staging = true` for short-lived environments.

## How HTTP-01 works in this stack

The HTTP-01 challenge is the reason ExternalDNS-managed Cloudflare records are not proxied. cert-manager creates a challenge `Ingress` for each requested certificate; Let's Encrypt fetches a well-known URL on the hostname; the request needs to reach Traefik directly.

The full traffic path, including the certificate flow, is in [Bundled ingress](ingress.md).

!!! danger "Do not enable Cloudflare proxy"
    If you flip `proxied = true` for an Ingress hostname while HTTP-01 is still the solver, cert-manager stops being able to complete challenges. Existing certificates keep working until renewal, then break. Move the ACME solver to DNS-01 first if you need proxying.

## Inspecting issued certificates

cert-manager stores each issued certificate in a Kubernetes `Secret` next to the `Ingress` that requested it. To see the live status of every certificate in the cluster:

```bash
kubectl get certificates -A
kubectl describe certificate -n <namespace> <name>
```

If a certificate is stuck, the `describe` output and the cert-manager controller logs (`kubectl -n cert-manager logs deploy/cert-manager`) usually point at the problem — most often DNS not resolving yet, or a stale Ingress hostname.
