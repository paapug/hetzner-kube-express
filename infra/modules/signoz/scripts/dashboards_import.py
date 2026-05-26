"""SigNoz post-install bootstrap + dashboard importer.

Idempotent flow, run as a Kubernetes Job (one-shot):

  1. Wait for the SigNoz frontend to return 2xx on /api/v1/version (the Helm
     release is "ready" before ClickHouse migrations finish, so the API can
     5xx for a while after the chart is installed).
  2. Fast path: if /sa/api_key already exists in the mounted SA secret, use
     it and skip straight to step 4.
  3. Bootstrap: register the first admin via /api/v1/register (or, if that
     400s, log in via /api/v2/sessions/email_password using orgId resolved
     from /api/v2/sessions/context). Mint a long-lived Service Account API
     key (POST /api/v1/service_accounts then POST /service_accounts/{id}/keys)
     and PATCH it into signoz-service-account-secret using the in-cluster
     Kubernetes API.
  4. POST every dashboard JSON file under /dashboards/ to /api/v1/dashboards
     with header `SigNoz-Api-Key`.

Stdlib only (urllib, ssl, json, base64). Designed for a python:*-alpine image.
"""

from __future__ import annotations

import base64
import glob
import json
import logging
import os
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

# In-cluster paths populated by the Job's volume mounts and the projected SA token.
ADMIN_DIR = "/admin"
SA_DIR = "/sa"
DASHBOARDS_DIR = "/dashboards"
SA_TOKEN_PATH = "/var/run/secrets/kubernetes.io/serviceaccount/token"  # noqa: S105
SA_CA_PATH = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"

SIGNOZ_BASE = os.environ.get("SIGNOZ_BASE", "http://signoz:8080")
K8S_API = os.environ.get("K8S_API", "https://kubernetes.default.svc")
NAMESPACE = os.environ.get("NAMESPACE", "signoz")
SA_SECRET = "signoz-service-account-secret"
SA_NAME = "terraform-bootstrap"

PROBE_ATTEMPTS = 60
PROBE_INTERVAL_SECONDS = 5
HTTP_TIMEOUT = 30


logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] %(levelname)s %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("signoz-bootstrap")


class HTTPError(Exception):
    """Wraps a non-2xx HTTP response with status + body for logging."""

    def __init__(self, method: str, url: str, status: int, body: bytes):
        self.method = method
        self.url = url
        self.status = status
        self.body = body
        super().__init__(f"{method} {url} -> {status}")


def http(
    method: str,
    url: str,
    *,
    headers: dict[str, str] | None = None,
    json_body: Any = None,
    raw_body: bytes | None = None,
    cafile: str | None = None,
    expected_status: tuple[int, ...] = (200, 201, 204),
) -> tuple[int, bytes]:
    """Single HTTP call. Logs status; raises HTTPError on unexpected status.

    Uses the system trust store by default. `cafile` switches to a
    custom CA bundle (for the in-cluster Kubernetes API).
    """
    headers = dict(headers or {})
    body: bytes | None = None
    if json_body is not None:
        body = json.dumps(json_body).encode()
        headers.setdefault("Content-Type", "application/json")
    elif raw_body is not None:
        body = raw_body

    req = urllib.request.Request(url, data=body, method=method, headers=headers)
    ctx = ssl.create_default_context(cafile=cafile) if url.startswith("https://") else None

    try:
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT, context=ctx) as resp:
            status = resp.status
            data = resp.read()
    except urllib.error.HTTPError as e:
        status = e.code
        data = e.read() if e.fp is not None else b""
    except urllib.error.URLError as e:
        log.error("%s %s -> network error: %s", method, url, e.reason)
        raise HTTPError(method, url, 0, str(e.reason).encode()) from e

    if status in expected_status:
        log.info("%s %s -> %s", method, url, status)
        return status, data

    body_preview = data[:2048].decode("utf-8", errors="replace")
    log.error("%s %s -> %s\nresponse body (truncated):\n%s", method, url, status, body_preview)
    raise HTTPError(method, url, status, data)


def read_file(path: str) -> str:
    with open(path) as f:
        return f.read().rstrip("\n")


def wait_for_signoz_ready() -> None:
    log.info("waiting for %s/api/v1/version to return 2xx (max %d min)...",
             SIGNOZ_BASE, PROBE_ATTEMPTS * PROBE_INTERVAL_SECONDS // 60)
    for attempt in range(1, PROBE_ATTEMPTS + 1):
        try:
            status, _ = http("GET", f"{SIGNOZ_BASE}/api/v1/version", expected_status=(200,))
            log.info("signoz frontend ready (attempt %d, status %d)", attempt, status)
            return
        except HTTPError as e:
            log.info("  attempt %d/%d: status=%s; retrying in %ds",
                     attempt, PROBE_ATTEMPTS, e.status, PROBE_INTERVAL_SECONDS)
        time.sleep(PROBE_INTERVAL_SECONDS)
    raise SystemExit("signoz frontend never became ready")


def bootstrap_service_account() -> str:
    """Register first admin (or fall back to login), mint and persist SA key.

    Returns the minted API key. Patches signoz-service-account-secret in
    Kubernetes so subsequent runs skip this whole branch.
    """
    email = read_file(f"{ADMIN_DIR}/email")
    password = read_file(f"{ADMIN_DIR}/password")
    org_name = read_file(f"{ADMIN_DIR}/org_name")
    log.info("admin email=%s org=%s password_len=%d", email, org_name, len(password))

    jwt = _obtain_admin_jwt(email, password, org_name)
    log.info("obtained admin JWT (len=%d)", len(jwt))

    auth = {"Authorization": f"Bearer {jwt}"}

    # Resolve admin role id; SigNoz returns roles either at top-level or under .data
    _, roles_body = http("GET", f"{SIGNOZ_BASE}/api/v1/roles", headers=auth)
    # Role names: SigNoz >=0.125 uses signoz-admin/editor/viewer/anonymous;
    # older versions used plain admin/editor/viewer. Match either.
    roles_payload = json.loads(roles_body)
    roles = roles_payload.get("data") or roles_payload or []
    admin_role_id = next(
        (
            r["id"]
            for r in roles
            if (r.get("name") or "").lower() in ("signoz-admin", "admin")
        ),
        None,
    )
    if not admin_role_id:
        names = [r.get("name") for r in roles]
        raise SystemExit(f"could not resolve admin role id; available roles={names!r}; full body: {roles_body!r}")
    log.info("admin role id=%s", admin_role_id)

    # Create SA, assign admin role, mint key. expiresAt:0 == no expiry per chart convention.
    _, sa_body = http("POST", f"{SIGNOZ_BASE}/api/v1/service_accounts",
                      headers=auth, json_body={"name": SA_NAME})
    sa_id = (json.loads(sa_body).get("data") or {}).get("id") or json.loads(sa_body).get("id")
    if not sa_id:
        raise SystemExit(f"service account create returned no id; response: {sa_body!r}")
    log.info("service account id=%s", sa_id)

    http("POST", f"{SIGNOZ_BASE}/api/v1/service_accounts/{sa_id}/roles",
         headers=auth, json_body={"id": admin_role_id})

    _, key_body = http("POST", f"{SIGNOZ_BASE}/api/v1/service_accounts/{sa_id}/keys",
                       headers=auth, json_body={"name": SA_NAME, "expiresAt": 0})
    key_payload = json.loads(key_body)
    api_key = (
        (key_payload.get("data") or {}).get("key")
        or (key_payload.get("data") or {}).get("token")
        or key_payload.get("key")
    )
    if not api_key:
        raise SystemExit(f"API key mint returned no key; response: {key_body!r}")
    log.info("minted api key (len=%d)", len(api_key))

    _persist_api_key(api_key)
    log.info("stored api_key in %s", SA_SECRET)
    return api_key


def _extract_token(payload: dict) -> str | None:
    """Pull a bearer token out of either of the SigNoz response shapes.

    /api/v1/register returns { data: { accessJwt, refreshJwt }, status }.
    /api/v2/sessions/email_password returns AuthtypesGettableToken
    ({ data: { accessToken, refreshToken, tokenType, expiresIn }, status }).
    """
    data = payload.get("data") or {}
    for key in ("accessJwt", "accessToken", "token", "jwt"):
        if data.get(key):
            return data[key]
        if payload.get(key):
            return payload[key]
    return None


def _obtain_admin_jwt(email: str, password: str, org_name: str) -> str:
    """Try /api/v1/register first, fall back to /api/v2/sessions/email_password.

    The login fallback needs orgId, which we look up via the unauthenticated
    /api/v2/sessions/context endpoint.
    """
    try:
        _, reg_body = http(
            "POST",
            f"{SIGNOZ_BASE}/api/v1/register",
            json_body={"name": "admin", "email": email, "password": password, "orgName": org_name},
        )
        reg = json.loads(reg_body)
        jwt = _extract_token(reg)
        if jwt:
            log.info("register succeeded")
            return jwt
        log.warning("register 2xx but no token field found; response keys=%s; falling back to login",
                    sorted((reg.get("data") or reg).keys()))
    except HTTPError as e:
        # 400 with "self-registration is disabled" is the normal case on a
        # re-apply where the admin already exists from a previous install
        # but the SA secret was wiped.
        log.info("register returned %s; falling back to /api/v2/sessions/email_password", e.status)

    # /api/v2/sessions/context lists the orgs the given email belongs to.
    # Despite not being in the OpenAPI's `parameters` block, the handler
    # requires `?email=...` and rejects an empty value with `invalid_valuer`.
    ctx_url = f"{SIGNOZ_BASE}/api/v2/sessions/context?{urllib.parse.urlencode({'email': email})}"
    _, ctx_body = http("GET", ctx_url)
    orgs = (json.loads(ctx_body).get("data") or {}).get("orgs") or []
    if not orgs:
        raise SystemExit(
            f"no orgs returned by /api/v2/sessions/context for email={email}; response: {ctx_body!r}"
        )
    org_id = orgs[0]["id"]
    log.info("resolved orgId=%s for login", org_id)

    _, login_body = http(
        "POST",
        f"{SIGNOZ_BASE}/api/v2/sessions/email_password",
        json_body={"email": email, "password": password, "orgId": org_id},
    )
    login = json.loads(login_body)
    jwt = _extract_token(login)
    if not jwt:
        log.error("login response shape unexpected; full body:\n%s", login_body[:2048].decode("utf-8", errors="replace"))
        raise SystemExit(
            "no JWT obtained — has the admin password been changed in the UI without "
            "updating signoz-initial-admin-secret?"
        )
    return jwt


def _persist_api_key(api_key: str) -> None:
    """Strategic-merge-patch signoz-service-account-secret with the new api_key."""
    with open(SA_TOKEN_PATH) as f:
        sa_token = f.read().strip()
    b64 = base64.b64encode(api_key.encode()).decode()
    http(
        "PATCH",
        f"{K8S_API}/api/v1/namespaces/{NAMESPACE}/secrets/{SA_SECRET}",
        headers={
            "Authorization": f"Bearer {sa_token}",
            "Content-Type": "application/strategic-merge-patch+json",
        },
        json_body={"data": {"api_key": b64}},
        cafile=SA_CA_PATH,
    )


def import_dashboards(api_key: str) -> None:
    files = sorted(glob.glob(f"{DASHBOARDS_DIR}/*.json"))
    if not files:
        log.info("no dashboards to import (%s/*.json is empty)", DASHBOARDS_DIR)
        return

    log.info("importing %d dashboards from %s", len(files), DASHBOARDS_DIR)
    failed = 0
    for path in files:
        size = os.path.getsize(path)
        log.info("importing %s (%d bytes)", path, size)
        try:
            with open(path, "rb") as f:
                payload = f.read()
            http(
                "POST",
                f"{SIGNOZ_BASE}/api/v1/dashboards",
                headers={"SigNoz-Api-Key": api_key, "Content-Type": "application/json"},
                raw_body=payload,
            )
        except HTTPError as e:
            log.error("import %s returned %s (continuing)", path, e.status)
            failed += 1

    log.info("dashboards: imported=%d failed=%d total=%d",
             len(files) - failed, failed, len(files))


def main() -> int:
    log.info("config: BASE=%s NS=%s", SIGNOZ_BASE, NAMESPACE)
    log.info("admin secret keys present: %s", sorted(os.listdir(ADMIN_DIR)))
    sa_keys = sorted(os.listdir(SA_DIR)) if os.path.isdir(SA_DIR) else []
    log.info("sa secret keys present: %s", sa_keys)

    wait_for_signoz_ready()

    sa_key_path = f"{SA_DIR}/api_key"
    if os.path.isfile(sa_key_path) and os.path.getsize(sa_key_path) > 0:
        api_key = read_file(sa_key_path)
        log.info("reusing existing service account key from %s", SA_SECRET)
    else:
        log.info("no service account key yet; bootstrapping via admin")
        api_key = bootstrap_service_account()

    import_dashboards(api_key)
    return 0


if __name__ == "__main__":
    sys.exit(main())
