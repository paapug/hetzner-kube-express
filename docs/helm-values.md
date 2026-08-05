# Helm value overrides

The modules configure safe defaults for each bundled Helm chart. You can add
other chart values in `infra/<env>/env.hcl` without changing the module.

Use these maps in a service block:

- `helm_set` for normal values;
- `helm_set_sensitive` for values that must not appear in plan or apply output.

Both maps use Helm dot-path keys. They work like `helm --set`, and they override
the values supplied by the module.

## Set a chart value

Add a flat `map(string)` to the service block:

```hcl
harbor = {
  enabled       = true
  chart_version = "<harbor-chart-version>"
  host          = "harbor.<your-domain>"

  helm_set = {
    "trivy.enabled" = "false"
  }
}
```

All map values are strings. Quote booleans and numbers. Helm converts them when
the chart expects another type.

For SigNoz, `helm_set` targets the `signoz` chart. Use
`k8s_infra_helm_set` for the separate `k8s-infra` chart:

```hcl
signoz = {
  # Other SigNoz settings are omitted.

  helm_set = {
    "signoz.replicaCount" = "2"
  }

  k8s_infra_helm_set = {
    "presets.logsCollection.enabled" = "false"
  }
}
```

SigNoz also supports `k8s_infra_helm_set_sensitive`.

## Find valid keys

Read the values for the chart version configured in `env.hcl`:

```bash
helm show values <chart> \
  --version <chart-version> \
  --repo <chart-repository>
```

Use the path from the YAML output as the map key. For example, this YAML:

```yaml
trivy:
  enabled: true
```

becomes:

```hcl
helm_set = {
  "trivy.enabled" = "false"
}
```

If a key contains a literal dot, escape it for Helm and HCL:

```hcl
helm_set = {
  "ingress.annotations.cert-manager\\.io/cluster-issuer" = "letsencrypt-prod"
}
```

This interface is intended for scalar values. If a chart needs a list or a
structured object, add a typed module variable and render it in the module.

## Modify platform wiring with care

Most chart values are safe to tune. You can change resource requests, replica
counts, feature flags, and storage sizes. For example, changing a 5 GiB volume
to 10 GiB does not break the platform. Prefer the typed `pvc_sizes` setting
because it is easier to find, but `helm_set` still applies last.

Some values connect a chart to Terraform-managed resources. Modify these only
when you understand the related wiring and update it as one change:

- Disabling Argo CD `configs.params.server.insecure` also requires Traefik to
  use HTTPS and trust the Argo CD server certificate.
- Enabling a chart-managed Ingress for Argo CD or SigNoz creates a second
  Ingress. Decide which Ingress owns routing, DNS, and certificates.
- Changing Harbor exposure, chart TLS, or `externalURL` can conflict with the
  module-managed Traefik Ingress. Change the related routing together.
- Replacing Harbor `existingSecretAdminPassword` or its key transfers password
  ownership away from the Secret that Terraform creates.
- Changing the ExternalDNS provider, sources, filters, TXT owner, token source,
  or proxy setting changes its DNS ownership and security boundaries. Proxy
  mode also affects HTTP-01 certificate renewal.
- Changing the SigNoz collector endpoints sends `k8s-infra` telemetry to a
  different collector. Make sure that endpoint and protocol are valid.

Other values are available for normal tuning. Review the Helm plan because some
changes can restart workloads or resize persistent storage.

## Sensitive values

Use `helm_set_sensitive` when a value must not appear in Terraform plan or
apply output:

```hcl
harbor = {
  # Other Harbor settings are omitted.

  helm_set_sensitive = {
    "some.chart.password" = "<local-secret>"
  }
}
```

Install the repository hook before you use this map:

```bash
infra/_scripts/install-git-hooks.sh
```

The hook replaces each staged `helm_set_sensitive` value with
`REPLACE_WITH_HELM_SECRET`. It does not change your worktree. The keys remain
in git, so another operator can see which local values they must provide.

!!! danger "The hook is required"
    If the hook is not installed, git can commit the real values from
    `helm_set_sensitive`. Check `git config core.hooksPath` before you commit.

`helm_set_sensitive` only hides output and protects the staged `env.hcl`.
Terraform still stores the value in the R2 state, and Helm stores it in the
release Secret inside the cluster. Anyone with access to either location can
recover it.

Keep platform credentials in R2 `secrets.json`. This includes Hetzner and
Cloudflare tokens and the cluster SSH key. Do not copy them into either Helm
map.

The hook only redacts values inside `helm_set_sensitive`. Values in `helm_set`,
including hostnames and email addresses, are committed as written.

## Apply the change

Plan and apply the affected unit:

```bash
cd infra/<env>/<unit>
terragrunt plan
terragrunt apply
```

Review the plan carefully. A Helm value change can restart Deployments or
StatefulSets, and a chart can interpret an invalid path as a new unused value.
