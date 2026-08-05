#!/usr/bin/env bash
# Strip identifying values from infra/dev/env.hcl and infra/root.hcl. Reads HCL
# from stdin, writes anonymized HCL to stdout. Safe to run on either file:
# substitutions are keyed on field names that don't overlap between the two.
#
# Keep the placeholder strings in sync with env-bootstrap.sh, which prompts the
# user for real values and substitutes back into the worktree.
#
# REPLACE_WITH_HELM_SECRET is the exception: env-bootstrap.sh does not prompt for
# it, because helm_set_sensitive ships commented out and is per-operator. It also
# needs the awk pass below rather than a sed range, because a sed range cannot
# close on the line it opened on, so `helm_set_sensitive = { "a" = "b" }` would
# leak into the following lines.
set -euo pipefail

sed -E \
  -e 's/(operator_email[[:space:]]*=[[:space:]]*")[^"]*(")/\1REPLACE_WITH_OPERATOR_EMAIL\2/' \
  -e 's/(zone_id[[:space:]]*=[[:space:]]*")[^"]*(")/\1REPLACE_WITH_CLOUDFLARE_ZONE_ID\2/' \
  -e 's/(domain[[:space:]]*=[[:space:]]*")[^"]*(")/\1REPLACE_WITH_CLOUDFLARE_DOMAIN\2/' \
  -e 's/(r2_account_id_default[[:space:]]*=[[:space:]]*")[^"]*(")/\1REPLACE_WITH_CF_ACCOUNT_ID\2/' \
  -e 's/(r2_bucket_default[[:space:]]*=[[:space:]]*")[^"]*(")/\1REPLACE_WITH_R2_BUCKET\2/' \
  -e 's/(acme_use_staging[[:space:]]*=[[:space:]]*)(true|false)/\1false/' |
  awk '
    # Redact every value inside a helm_set_sensitive block. Redaction runs before
    # the brace count, so braces inside a value cannot skew the depth.
    !redact && /helm_set_sensitive[[:space:]]*=[[:space:]]*\{/ { redact = 1; depth = 0 }
    redact {
      gsub(/=[[:space:]]*"[^"]*"/, "= \"REPLACE_WITH_HELM_SECRET\"")
      depth += gsub(/\{/, "{")
      depth -= gsub(/\}/, "}")
      if (depth <= 0) { redact = 0 }
    }
    { print }
  '
