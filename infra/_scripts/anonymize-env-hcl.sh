#!/usr/bin/env bash
# Strip identifying values from infra/dev/env.hcl and infra/root.hcl. Reads HCL
# from stdin, writes anonymized HCL to stdout. Safe to run on either file:
# substitutions are keyed on field names that don't overlap between the two.
#
# Keep the placeholder strings in sync with env-bootstrap.sh, which prompts the
# user for real values and substitutes back into the worktree.
set -euo pipefail

exec sed -E \
  -e 's/(operator_email[[:space:]]*=[[:space:]]*")[^"]*(")/\1REPLACE_WITH_OPERATOR_EMAIL\2/' \
  -e 's/(zone_id[[:space:]]*=[[:space:]]*")[^"]*(")/\1REPLACE_WITH_CLOUDFLARE_ZONE_ID\2/' \
  -e 's/(domain[[:space:]]*=[[:space:]]*")[^"]*(")/\1REPLACE_WITH_CLOUDFLARE_DOMAIN\2/' \
  -e 's/(r2_account_id_default[[:space:]]*=[[:space:]]*")[^"]*(")/\1REPLACE_WITH_CF_ACCOUNT_ID\2/' \
  -e 's/(r2_bucket_default[[:space:]]*=[[:space:]]*")[^"]*(")/\1REPLACE_WITH_R2_BUCKET\2/' \
  -e 's/(acme_use_staging[[:space:]]*=[[:space:]]*)(true|false)/\1false/'
