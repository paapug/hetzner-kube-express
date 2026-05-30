provider:
  name: cloudflare

# Reactive: watch Ingress objects and publish records from status.loadBalancer.ingress[].
sources:
  - ingress

policy: sync

domainFilters:
  - ${cloudflare_domain}

# TXT registry: only touch records this cluster owns, so multiple clusters can
# share a zone without fighting over each other's records.
txtOwnerId: ${txt_owner_id}

# Zone-id-filter keeps API calls scoped to the one zone the token is allowed to
# manage; cloudflare-proxied stays off so HTTP-01 reaches Traefik directly.
extraArgs:
  - --zone-id-filter=${cloudflare_zone_id}
%{ if proxied ~}
  - --cloudflare-proxied
%{ endif ~}

env:
  - name: CF_API_TOKEN
    valueFrom:
      secretKeyRef:
        name: ${api_token_secret_name}
        key: cloudflare_api_token
