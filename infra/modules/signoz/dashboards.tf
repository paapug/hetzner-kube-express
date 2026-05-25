locals {
  dashboards_dir          = var.dashboards_dir != "" ? var.dashboards_dir : "${path.module}/dashboards"
  dashboard_files         = fileset(local.dashboards_dir, "*.json")
  dashboard_files_content = { for f in local.dashboard_files : f => file("${local.dashboards_dir}/${f}") }
  dashboards_hash         = substr(sha1(jsonencode(local.dashboard_files_content)), 0, 8)
}

resource "kubernetes_config_map_v1" "signoz_dashboards" {
  metadata {
    name      = "signoz-dashboards"
    namespace = kubernetes_namespace.signoz.metadata[0].name

    labels = {
      "signoz.io/dashboard" = "true"
    }
  }

  # Always create — even when empty — so the Job's volume mount is always valid.
  data = local.dashboard_files_content
}

# Idempotent post-install Job:
#   1) reuse the SA api_key from /sa/api_key if present;
#   2) otherwise register the first admin (or fall back to login) using
#      /admin/{email,password,org_name}, mint a long-lived Service Account +
#      API key, then PATCH the api_key into signoz-service-account-secret via
#      the in-cluster API (no kubectl);
#   3) POST every /dashboards/*.json with header SigNoz-Api-Key.
# Re-runs after a UI password change still succeed because the SA key is the
# only credential needed once it's been minted.
resource "kubernetes_job_v1" "dashboards_import" {
  metadata {
    name      = "signoz-dashboards-import-${local.dashboards_hash}"
    namespace = kubernetes_namespace.signoz.metadata[0].name
  }

  spec {
    backoff_limit              = 5
    ttl_seconds_after_finished = 600

    template {
      metadata {
        labels = {
          app = "signoz-dashboards-import"
        }
      }

      spec {
        restart_policy       = "OnFailure"
        service_account_name = kubernetes_service_account_v1.signoz_bootstrap.metadata[0].name

        container {
          name              = "import"
          image             = "alpine:3.19"
          image_pull_policy = "IfNotPresent"

          command = ["/bin/sh", "-c"]
          args = [<<-EOT
            set -eu
            apk add --no-cache curl jq >/dev/null

            log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }
            err() { printf '[%s] ERROR: %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }

            # http <method> <url> <out_body_file> [extra curl args...] -> echoes status code
            # On non-2xx, dumps the response body to stderr so the failure is visible in `kubectl logs`.
            http() {
              method=$1; url=$2; out=$3; shift 3
              code=$(curl -sS -o "$out" -w "%%{http_code}" -X "$method" "$url" "$@" || echo "000")
              if [ "$code" = "000" ] || [ "$code" -ge 400 ] 2>/dev/null; then
                err "$method $url -> $code"
                if [ -s "$out" ]; then
                  err "response body (truncated to 2KB):"
                  head -c 2048 "$out" >&2
                  printf '\n' >&2
                fi
              else
                log "$method $url -> $code"
              fi
              echo "$code"
            }

            BASE=http://signoz:8080
            K8S=https://kubernetes.default.svc
            K8S_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
            K8S_CA=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
            NS=${kubernetes_namespace.signoz.metadata[0].name}
            SA_SECRET=signoz-service-account-secret

            log "config: BASE=$BASE NS=$NS"
            log "dashboards available:"; ls -la /dashboards/ || true
            log "admin secret keys present: $(ls /admin/ | tr '\n' ' ')"
            log "sa secret keys present: $(ls /sa/ 2>/dev/null | tr '\n' ' ')"

            # Wait for the SigNoz frontend to accept connections before doing anything else.
            # helm_release.signoz waiting on Deployments doesn't mean ClickHouse migrations
            # have finished, so /api/v1/version may 5xx for a while after the chart is "ready".
            log "waiting for $BASE/api/v1/version to return 2xx (max 5 min)..."
            i=0
            until code=$(curl -sS -o /tmp/probe.json -w "%%{http_code}" "$BASE/api/v1/version" 2>/dev/null) \
                  && [ "$code" -ge 200 ] 2>/dev/null && [ "$code" -lt 300 ] 2>/dev/null; do
              i=$((i+1))
              if [ $i -gt 60 ]; then
                err "signoz frontend never became ready (last code=$${code:-none})"
                [ -s /tmp/probe.json ] && head -c 1024 /tmp/probe.json >&2
                exit 1
              fi
              log "  attempt $i: code=$${code:-none}; retrying in 5s"
              sleep 5
            done
            log "signoz frontend ready (version probe returned $code)"

            if [ -s /sa/api_key ]; then
              API_KEY=$(cat /sa/api_key)
              log "reusing existing service account key from $SA_SECRET"
            else
              log "no service account key yet; bootstrapping via admin"
              EMAIL=$(cat /admin/email); PASSWORD=$(cat /admin/password); ORG=$(cat /admin/org_name)
              log "admin email=$EMAIL org=$ORG password_len=$${#PASSWORD}"

              REG_BODY=$(jq -n --arg n admin --arg e "$EMAIL" --arg p "$PASSWORD" --arg o "$ORG" \
                          '{name:$n,email:$e,password:$p,orgName:$o}')
              REG=$(http POST "$BASE/api/v1/register" /tmp/reg.json \
                -H "Content-Type: application/json" -d "$REG_BODY")
              if [ "$REG" = "200" ] || [ "$REG" = "201" ]; then
                JWT=$(jq -r '.data.accessJwt // .accessJwt // empty' /tmp/reg.json)
                log "register succeeded; JWT present: $([ -n "$JWT" ] && echo yes || echo no)"
              else
                log "register returned $REG; trying /api/v2/sessions/email_password"

                # /api/v2/sessions/email_password requires orgId. Resolve it via
                # the unauthenticated /api/v2/sessions/context endpoint, which
                # lists all orgs known to the instance.
                CTX=$(http GET "$BASE/api/v2/sessions/context" /tmp/ctx.json)
                if [ "$CTX" != "200" ]; then
                  err "GET /api/v2/sessions/context failed ($CTX); cannot resolve orgId"
                  exit 1
                fi
                ORG_ID=$(jq -r '(.data.orgs // [])[0].id // empty' /tmp/ctx.json)
                if [ -z "$ORG_ID" ]; then
                  err "no orgs returned by /api/v2/sessions/context; response:"
                  head -c 2048 /tmp/ctx.json >&2; printf '\n' >&2
                  exit 1
                fi
                log "resolved orgId=$ORG_ID for login"

                LOGIN_BODY=$(jq -n --arg e "$EMAIL" --arg p "$PASSWORD" --arg o "$ORG_ID" \
                              '{email:$e,password:$p,orgId:$o}')
                LOGIN=$(http POST "$BASE/api/v2/sessions/email_password" /tmp/login.json \
                  -H "Content-Type: application/json" -d "$LOGIN_BODY")
                if [ "$LOGIN" != "200" ] && [ "$LOGIN" != "201" ]; then
                  err "login failed ($LOGIN); cannot continue"
                  exit 1
                fi
                JWT=$(jq -r '.data.accessJwt // .accessJwt // empty' /tmp/login.json)
              fi
              if [ -z "$JWT" ] || [ "$JWT" = "null" ]; then
                err "no JWT obtained — has the admin password been changed in the UI without updating signoz-initial-admin-secret?"
                err "register response (truncated):"
                [ -s /tmp/reg.json ] && head -c 1024 /tmp/reg.json >&2 && printf '\n' >&2
                err "login response (if attempted, truncated):"
                [ -s /tmp/login.json ] && head -c 1024 /tmp/login.json >&2 && printf '\n' >&2
                exit 1
              fi
              log "obtained admin JWT (len=$${#JWT})"

              ROLES=$(http GET "$BASE/api/v1/roles" /tmp/roles.json -H "Authorization: Bearer $JWT")
              if [ "$ROLES" != "200" ]; then
                err "GET /api/v1/roles failed ($ROLES); body above"
                exit 1
              fi
              ADMIN_ROLE_ID=$(jq -r '(.data // .)[]? | select((.name // "")|ascii_downcase=="admin") | .id' /tmp/roles.json | head -1)
              if [ -z "$ADMIN_ROLE_ID" ]; then
                err "could not resolve admin role id; /api/v1/roles returned:"
                head -c 2048 /tmp/roles.json >&2; printf '\n' >&2
                exit 1
              fi
              log "admin role id=$ADMIN_ROLE_ID"

              SA_BODY='{"name":"terraform-bootstrap"}'
              SA=$(http POST "$BASE/api/v1/service_accounts" /tmp/sa.json \
                -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" -d "$SA_BODY")
              if [ "$SA" != "200" ] && [ "$SA" != "201" ]; then
                err "create service_account failed ($SA); body above"
                exit 1
              fi
              SA_ID=$(jq -r '.data.id // .id // empty' /tmp/sa.json)
              if [ -z "$SA_ID" ]; then
                err "service account create returned no id; response:"
                head -c 2048 /tmp/sa.json >&2; printf '\n' >&2
                exit 1
              fi
              log "service account id=$SA_ID"

              ROLE_BODY=$(jq -n --arg id "$ADMIN_ROLE_ID" '{id:$id}')
              ASSIGN=$(http POST "$BASE/api/v1/service_accounts/$SA_ID/roles" /tmp/assign.json \
                -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" -d "$ROLE_BODY")
              if [ "$ASSIGN" != "200" ] && [ "$ASSIGN" != "201" ] && [ "$ASSIGN" != "204" ]; then
                err "assign role failed ($ASSIGN); body above"
                exit 1
              fi

              # expiresAt: 0 == no expiry per chart convention
              KEY_BODY='{"name":"terraform-bootstrap","expiresAt":0}'
              KEY=$(http POST "$BASE/api/v1/service_accounts/$SA_ID/keys" /tmp/key.json \
                -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" -d "$KEY_BODY")
              if [ "$KEY" != "200" ] && [ "$KEY" != "201" ]; then
                err "mint api key failed ($KEY); body above"
                exit 1
              fi
              API_KEY=$(jq -r '.data.key // .data.token // .key // empty' /tmp/key.json)
              if [ -z "$API_KEY" ] || [ "$API_KEY" = "null" ]; then
                err "API key mint returned no key; response:"
                head -c 2048 /tmp/key.json >&2; printf '\n' >&2
                exit 1
              fi
              log "minted api key (len=$${#API_KEY})"

              B64=$(printf %s "$API_KEY" | base64 | tr -d '\n')
              PATCH_BODY=$(jq -n --arg k "$B64" '{data:{api_key:$k}}')
              PATCH=$(curl -sS -o /tmp/patch.json -w "%%{http_code}" --cacert "$K8S_CA" \
                -H "Authorization: Bearer $K8S_TOKEN" \
                -H "Content-Type: application/strategic-merge-patch+json" \
                -X PATCH "$K8S/api/v1/namespaces/$NS/secrets/$SA_SECRET" \
                -d "$PATCH_BODY" || echo "000")
              if [ "$PATCH" -lt 200 ] 2>/dev/null || [ "$PATCH" -ge 300 ] 2>/dev/null; then
                err "patch $SA_SECRET failed ($PATCH); response:"
                head -c 2048 /tmp/patch.json >&2; printf '\n' >&2
                exit 1
              fi
              log "stored api_key in $SA_SECRET (PATCH -> $PATCH)"
            fi

            log "importing dashboards from /dashboards/"
            count=0; failed=0
            for f in /dashboards/*.json; do
              [ -e "$f" ] || break
              count=$((count+1))
              log "importing $f ($(stat -c %s "$f" 2>/dev/null || wc -c < "$f") bytes)"
              IMP=$(http POST "$BASE/api/v1/dashboards" /tmp/imp.json \
                -H "SigNoz-Api-Key: $API_KEY" -H "Content-Type: application/json" -d @"$f")
              if [ "$IMP" != "200" ] && [ "$IMP" != "201" ]; then
                err "import $f returned $IMP (continuing)"
                failed=$((failed+1))
              fi
            done
            log "dashboards: imported=$((count-failed)) failed=$failed total=$count"
            EOT
          ]

          volume_mount {
            name       = "dashboards"
            mount_path = "/dashboards"
            read_only  = true
          }
          volume_mount {
            name       = "admin"
            mount_path = "/admin"
            read_only  = true
          }
          volume_mount {
            name       = "sa"
            mount_path = "/sa"
            read_only  = true
          }
        }

        volume {
          name = "dashboards"
          config_map {
            name = kubernetes_config_map_v1.signoz_dashboards.metadata[0].name
          }
        }
        volume {
          name = "admin"
          secret {
            secret_name = kubernetes_secret_v1.signoz_initial_admin.metadata[0].name
          }
        }
        volume {
          name = "sa"
          secret {
            secret_name = kubernetes_secret_v1.signoz_service_account.metadata[0].name
            optional    = false
          }
        }
      }
    }
  }

  wait_for_completion = false

  depends_on = [
    helm_release.signoz,
    kubernetes_config_map_v1.signoz_dashboards,
    kubernetes_secret_v1.signoz_initial_admin,
    kubernetes_secret_v1.signoz_service_account,
    kubernetes_role_binding_v1.signoz_bootstrap,
  ]
}
