<div align="center">

<img alt="hetzner-kube-express logo" src="docs/img/logo.svg" width="160">

<h1>hetzner-kube-express</h1>

<p><strong>Cheap, batteries-included Kubernetes on Hetzner Cloud.</strong></p>

<p>
  One <code>terragrunt run --all apply</code> gets you ingress, TLS, GitOps, observability, storage, a Postgres operator, and a container registry for less than a managed control plane at the big three.
</p>

<p>
  <a href="https://paapug.github.io/hetzner-kube-express/"><img alt="Docs" src="https://img.shields.io/badge/docs-live-2e7d32?style=for-the-badge"></a>
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/github/license/paapug/hetzner-kube-express?style=for-the-badge"></a>
</p>

<p>
  <img alt="k3s" src="https://img.shields.io/badge/k3s-ffc61c?style=flat-square&logo=k3s&logoColor=black">
  <img alt="Terraform" src="https://img.shields.io/badge/Terraform-7b42bc?style=flat-square&logo=terraform&logoColor=white">
  <img alt="Terragrunt" src="https://img.shields.io/badge/Terragrunt-5c4ee5?style=flat-square">
  <img alt="Hetzner Cloud" src="https://img.shields.io/badge/Hetzner_Cloud-d50c2d?style=flat-square">
  <img alt="Cloudflare R2" src="https://img.shields.io/badge/Cloudflare_R2-f38020?style=flat-square&logo=cloudflare&logoColor=white">
</p>

<p>
  <a href="https://paapug.github.io/hetzner-kube-express/">Read the docs</a>
  &middot;
  <a href="https://paapug.github.io/hetzner-kube-express/getting-started/">Get started</a>
  &middot;
  <a href="https://paapug.github.io/hetzner-kube-express/how-it-fits-together/">How it fits together</a>
</p>

</div>

---

## The Pitch

Managed Kubernetes is great until the bill shows up. This repo gives you a startup-friendly k3s platform on Hetzner Cloud: low cost, batteries included, and plain Terraform/Terragrunt under the hood.

It is mostly curated wiring around excellent building blocks: [kube-hetzner](https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner), [ExternalDNS](https://kubernetes-sigs.github.io/external-dns/) with [Cloudflare DNS](https://developers.cloudflare.com/dns/), [Cloudflare R2](https://developers.cloudflare.com/r2/), [Traefik](https://traefik.io/), [cert-manager](https://cert-manager.io/), [Argo CD](https://argo-cd.readthedocs.io/), [SigNoz](https://signoz.io/), [Harbor](https://goharbor.io/), and [CloudNativePG](https://cloudnative-pg.io/).

## What's Inside

- **Ingress, TLS, and DNS:** Traefik + cert-manager + ExternalDNS-managed Cloudflare records, exposed on agent nodes by k3s Klipper, with no paid load balancers.
- **GitOps:** [Argo CD](https://paapug.github.io/hetzner-kube-express/argocd/) installed through Helm and exposed through Traefik.
- **Observability:** [SigNoz](https://paapug.github.io/hetzner-kube-express/signoz/) with Kubernetes infrastructure collection and imported dashboards.
- **Container registry:** [Harbor](https://paapug.github.io/hetzner-kube-express/harbor/) with bundled Trivy image scanning.
- **Postgres operator:** [CloudNativePG](https://paapug.github.io/hetzner-kube-express/cnpg/) ready for declarative database clusters.
- **State and secrets:** Terraform state, `secrets.json`, and rendered kubeconfigs stored in [Cloudflare R2](https://paapug.github.io/hetzner-kube-express/secrets-and-scripts/).
- **Cheap default shape:** a small Hetzner `cx23` dev cluster that stays well below most managed Kubernetes control-plane minimums.

## Quick Taste

This is the core flow, not the full setup guide:

```bash
ENV_DIR=infra/dev infra/_scripts/env-bootstrap.sh
cd infra/dev && $EDITOR env.hcl
terragrunt run --all apply
```

The first run builds a MicroOS snapshot if the Hetzner project does not already have one, then applies the Terragrunt dependency graph. Read [Getting started](https://paapug.github.io/hetzner-kube-express/getting-started/) before copy-pasting anything into a real account.

## Docs Map

- New cluster: [Getting started](https://paapug.github.io/hetzner-kube-express/getting-started/)
- Existing cluster teammate: [Joining as a teammate](https://paapug.github.io/hetzner-kube-express/joining/)
- Mental model: [How it fits together](https://paapug.github.io/hetzner-kube-express/how-it-fits-together/)
- Day-to-day secrets and kubeconfig flow: [Secrets and helper scripts](https://paapug.github.io/hetzner-kube-express/secrets-and-scripts/)
- Something broke: [Troubleshooting](https://paapug.github.io/hetzner-kube-express/troubleshooting/)

## Know the Trade-Offs

- R2 access is powerful. Anyone who can read `secrets.json` can retrieve infrastructure credentials and the cluster SSH key.
- Cloudflare ingress records stay unproxied while cert-manager uses HTTP-01. Flip proxy mode only if you also move certificates to DNS-01.
- DNS round-robin is cheap, not magic. It does not health-check agent nodes.
- SigNoz and Harbor are useful but not tiny. On small nodes, add worker capacity before tuning Helm values blind.

## Roadmap

- [x] Argo CD
- [x] CloudNativePG operator
- [x] SigNoz observability stack
- [x] Harbor container registry
- [x] Documentation that does not make you sad
- [x] ExternalDNS
- [ ] Authentik / Zitadel
- [ ] Allow additional Helm values to be passed to modules
- [ ] CI tests
- [ ] Modular cluster provider

## Contributing

See [Contributing](https://paapug.github.io/hetzner-kube-express/contributing/) for the repo layout, conventions, how to wire a new unit, and the Cursor DevOps skills setup.

## License

Apache License 2.0 - see [LICENSE](LICENSE).
