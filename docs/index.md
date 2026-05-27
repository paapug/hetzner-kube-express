# Welcome

**hetzner-kube-express** is a batteries-included, startup-ready Kubernetes platform on [Hetzner Cloud](https://www.hetzner.com/cloud), driven by [Terragrunt](https://terragrunt.gruntwork.io/).

## What's bundled

| Tech                                                                                 | Purpose                                                                                                    |
| ------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------- |
| [Traefik](https://traefik.io/)                                                       | Ingress controller.                                                                                        |
| [cert-manager](https://cert-manager.io/)                                             | Automatic Let's Encrypt certificates via HTTP-01 through Traefik.                                          |
| [Argo CD](https://argo-cd.readthedocs.io/)                                           | GitOps controller, exposed via a Traefik Ingress.                                                          |
| [CloudNativePG](https://cloudnative-pg.io/)                                          | PostgreSQL operator, ready for declarative DB clusters.                                                    |
| [SigNoz](https://signoz.io/)                                                         | Observability stack with auto-instrumented Kubernetes infrastructure metrics and auto-imported dashboards. |

## Built on top of

| Tech                                                                                                       | Purpose                                                                                            |
| ---------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| [k3s](https://k3s.io/) (via [kube-hetzner](https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner)) | Lightweight Kubernetes distribution provisioned on Hetzner `cx23` nodes in `fsn1`.                 |
| [Cilium](https://cilium.io/) + [Hubble](https://docs.cilium.io/en/stable/observability/hubble/)            | CNI with kube-proxy replacement; Hubble adds in-cluster network observability.                     |
| [Klipper](https://klipper.sh/)                                                                             | k3s ServiceLB; exposes Traefik on every node's public IP so no paid Hetzner LB is needed.          |
| [Cloudflare R2](https://developers.cloudflare.com/r2/)                                                     | S3-compatible storage for Terraform state and per-env `secrets.json` (one bucket, both jobs).      |
| [Cloudflare DNS](https://developers.cloudflare.com/dns/)                                                   | A records wired automatically to the cluster's worker node pool                                    |
| [Terragrunt](https://terragrunt.gruntwork.io/)                                                             | Orchestrates the Terraform units as a dependency graph, with one apply across the whole stack.     |

## Cost shape

The default dev environment runs on a handful of cx23 nodes for less than $20/month. Most managed Kubernetes services charge ~$70/month just to keep the control plane running - before a single workload.

## Where to next

[:material-arrow-right: Get started](getting-started.md){ .md-button .md-button--primary }
[:material-account-multiple: Join as a teammate](joining.md){ .md-button }

- New cluster? Head to [Getting started](getting-started.md) for the one-time setup as cluster owner.
- Onboarding onto an existing cluster? See [Joining as a teammate](joining.md).
- Looking for daily commands, trade-offs, and troubleshooting? See the project [README](https://github.com/paapug/hetzner-kube-express#readme).
