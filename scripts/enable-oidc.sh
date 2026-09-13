#!/usr/bin/env bash
#
# Switch ZINO from Open WebUI's built-in accounts to Firebase Auth (Google
# sign-in) — the one part of the setup that is not fully scriptable.
#
# Neither gcloud nor the Firebase CLI can create an OAuth client or enable a
# sign-in provider; both are console-only. This script does everything around
# those two clicks and tells you exactly what to click.
#
# Usage:
#   ./scripts/enable-oidc.sh

# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

ROOT="$(repo_root)"
TFDIR="$ROOT/infra/terraform"

need gcloud    "Install: https://cloud.google.com/sdk/docs/install"
need terraform "Install: https://developer.hashicorp.com/terraform/install"

[[ -f "$TFDIR/terraform.tfvars" ]] || die "run ./scripts/bootstrap.sh first"
PROJECT="$(grep -E '^project_id' "$TFDIR/terraform.tfvars" | cut -d'"' -f2)"
PUBLIC_URL="$(terraform -chdir="$TFDIR" output -raw public_url 2>/dev/null || echo "https://$PROJECT.web.app")"

cat <<EOF

${BOLD}Two console steps — no CLI equivalent exists for either.${OFF}

1. Enable Google sign-in:

     https://console.firebase.google.com/project/$PROJECT/authentication/providers

   Enable the Google provider. Under "Authorized domains", confirm your domain
   is listed (the default $PROJECT.web.app already is).

2. Copy the OAuth client credentials:

     https://console.cloud.google.com/apis/credentials?project=$PROJECT

   Enabling Google sign-in creates an OAuth 2.0 Client ID automatically. Open
   it and add this authorized redirect URI:

     ${BOLD}$PUBLIC_URL/oauth/oidc/callback${OFF}

   Then copy the Client ID and Client secret — you will paste them next.

EOF

confirm "Done both steps?" || die "aborted — re-run when ready"

# Terraform creates these secrets, but only once enable_oidc is true; and
# enable_oidc cannot be applied until the secrets have values. Break the cycle
# by creating them here, then let Terraform adopt them.
for name in zino-oauth-client-id zino-oauth-client-secret; do
  if gcloud secrets describe "$name" --project="$PROJECT" >/dev/null 2>&1; then
    ok "secret $name exists"
  else
    gcloud secrets create "$name" --replication-policy=automatic --project="$PROJECT"
    ok "created secret $name"
  fi
done

read -r -p "OAuth Client ID: " CLIENT_ID
[[ -n "$CLIENT_ID" ]] || die "client ID cannot be empty"
# -s so the secret is not echoed to the terminal or captured in scrollback.
read -r -s -p "OAuth Client secret: " CLIENT_SECRET; echo
[[ -n "$CLIENT_SECRET" ]] || die "client secret cannot be empty"

printf '%s' "$CLIENT_ID"     | gcloud secrets versions add zino-oauth-client-id     --data-file=- --project="$PROJECT"
printf '%s' "$CLIENT_SECRET" | gcloud secrets versions add zino-oauth-client-secret --data-file=- --project="$PROJECT"
ok "credentials stored in Secret Manager"

if grep -q '^enable_oidc' "$TFDIR/terraform.tfvars"; then
  sed -i.bak 's/^enable_oidc.*/enable_oidc = true/' "$TFDIR/terraform.tfvars"
  rm -f "$TFDIR/terraform.tfvars.bak"
else
  echo 'enable_oidc = true' >> "$TFDIR/terraform.tfvars"
fi
ok "enable_oidc = true"

echo
info "Now apply it:  ./scripts/deploy.sh"
warn "Existing email/password accounts stay. OAUTH_MERGE_ACCOUNTS_BY_EMAIL is on,"
warn "so signing in with Google on the same address adopts the existing account."
