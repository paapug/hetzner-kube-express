# Changelog

All notable changes to this project will be documented here.

This project is still early, so the changelog is intentionally human-sized: what changed, why it matters, and what to watch out for.

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

