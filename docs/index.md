# Welcome

**hetzner-kube-express** is the shortcut from zero to a solid Kubernetes platform on [Hetzner Cloud](https://www.hetzner.com/cloud): one `terragrunt run --all apply` gets you a batteries-included cluster with ingress, observability, storage, cert-manager, gitops, postgres operator, and container registry.

## What's bundled

| Tech                                                                                 | Purpose                                                                                                    |
| ------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------- |
| [Traefik](https://traefik.io/)                                                       | Ingress controller.                                                                                        |
| [cert-manager](https://cert-manager.io/)                                             | Automatic Let's Encrypt certificates via HTTP-01 through Traefik.                                          |
| [Argo CD](https://argo-cd.readthedocs.io/)                                           | GitOps controller, exposed via a Traefik Ingress.                                                          |
| [CloudNativePG](https://cloudnative-pg.io/)                                          | PostgreSQL operator, ready for declarative DB clusters.                                                    |
| [Harbor](https://goharbor.io/)                                                       | Container registry with bundled Trivy image scanning, exposed via a Traefik Ingress.                       |
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

## Special thanks

Huge thanks to the [kube-hetzner](https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner) maintainers. Their Terraform module does the heavy lifting - k3s on Hetzner, Cilium, Traefik, Klipper, cert-manager - and this project is largely a thin opinionated wrapper around it. If you find this useful, consider starring or sponsoring their repo.

## Where to next

[:material-arrow-right: Get started](getting-started.md){ .md-button .md-button--primary }
[:material-book-open-page-variant: User guide](how-it-fits-together.md){ .md-button }
[:material-account-multiple: Join as a teammate](joining.md){ .md-button }

- Want the high-level map first? Read [How it fits together](how-it-fits-together.md) for the Terragrunt graph, module wiring, and R2 mental model.
- New cluster? Head to [Getting started](getting-started.md) for the one-time setup as cluster owner.
- Onboarding onto an existing cluster? See [Joining as a teammate](joining.md).
- Sending a PR? See [Contributing](contributing.md) for the repo layout, conventions, and Cursor skills setup.
