# Changelog and upgrades

This project is still early, so release notes focus on what changed, why it matters, and what to watch during upgrades.

## Upgrade rule

Upgrade minor versions one by one. For example, go from `0.1.x` to `0.2.x` before moving to a later minor release.

Some releases keep decommissioning units around for one minor version so Terraform can delete resources created by the previous version. If you skip the intermediate release, Terragrunt may no longer discover the old unit folder, and the old resources can be left orphaned.

For each minor upgrade:

```bash
cd infra/<env>
terragrunt run --all apply
```

Review the release notes for that version before applying, especially when the release changes ownership of cloud resources.

## v0.2.0 - ExternalDNS takes over Cloudflare records

Released: 2026-05-30

This release replaces the Terraform-managed `cloudflare-dns` records from v0.1.0 with a preconfigured [ExternalDNS](external-dns.md) controller. DNS is now driven by Kubernetes `Ingress` objects, which makes hostnames follow the same source of truth as Traefik routing and cert-manager certificates.

### Added

- Added the `external-dns` unit, installed by Helm and preconfigured with the Cloudflare API token from R2.
- ExternalDNS watches `Ingress` objects and publishes Cloudflare `A` records from their status IPs.
- ExternalDNS uses a TXT registry owner ID based on the cluster name, so it only manages records owned by this cluster.
- Agent node pools now carry the Klipper `svccontroller.k3s.cattle.io/enablelb=true` label. As a result, Ingress records get only agent pool IPs, not the control-plane IP.

### Changed

- `argocd`, `signoz`, and `harbor` now wait for `external-dns` instead of `cloudflare-dns` before creating their Ingresses.
- Custom DNS entries are no longer configured through `cloudflare.additional_ingress_subdomains`. Additional domains must be configured with Kubernetes `Ingress` objects.
- `cloudflare.additional_ingress_subdomains` should be set to an empty array if it still exists in your environment file:

    ```hcl
    cloudflare = {
      zone_id = "<cloudflare-zone-id>"
      domain  = "<example.com>"

      additional_ingress_subdomains = []
    }
    ```

### Deprecated

- `cloudflare-dns` is deprecated. It applied to v0.1.0, where Terraform created Cloudflare records directly.
- In v0.2.0, the retained `cloudflare-dns` unit is only a decommissioning unit. It lets `terragrunt run --all apply` destroy the records created by v0.1.0 instead of orphaning them.

### Upgrade from v0.1.0

Before applying, set `cloudflare.additional_ingress_subdomains = []` if that value exists locally. This avoids carrying forward old app-hostname configuration and helps prevent git conflicts around a setting that no longer controls DNS.

Then apply the environment normally:

```bash
cd infra/<env>
terragrunt run --all apply
```

During the upgrade, a short DNS interruption of less than one minute is expected. The old records created by `cloudflare-dns` are deleted, and ExternalDNS recreates the records it owns on its reconcile loop, which runs about once per minute.

After the apply, extra application hostnames should exist on their Kubernetes `Ingress` resources. See [ExternalDNS](external-dns.md) and [Bundled ingress](ingress.md) for the v0.2.0 model.

## v0.1.0 - the cheap Kubernetes launchpad

Released: 2026-05-29

First proper release of `hetzner-kube-express`: a batteries-included k3s platform on Hetzner Cloud, wired with Terragrunt, Cloudflare R2, Cloudflare DNS, Traefik, cert-manager, Argo CD, SigNoz, Harbor, and CloudNativePG.

### Added

- k3s cluster provisioning on Hetzner Cloud via `kube-hetzner`.
- Terragrunt environment layout with a dependency graph for applying the full platform.
- Cloudflare R2 backend for Terraform state, per-environment `secrets.json`, and rendered kubeconfigs.
- Cloudflare DNS records pointing ingress hostnames at worker node public IPs.
- Traefik ingress with Let's Encrypt certificates via cert-manager HTTP-01.
- Argo CD as the bundled GitOps controller.
- CloudNativePG as the bundled PostgreSQL operator.
- SigNoz as the bundled observability stack, including Kubernetes infrastructure collection and dashboard import support.
- Harbor as the bundled container registry, including Trivy image scanning.
- Helper scripts for bootstrapping environments, editing R2 secrets, fetching kubeconfig, fetching SSH keys, and trusting Let's Encrypt staging roots on macOS.
- MkDocs Material documentation site with setup, teammate onboarding, architecture, service guides, ingress, persistent volumes, troubleshooting, and contributing notes.
