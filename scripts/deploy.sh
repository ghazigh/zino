#!/usr/bin/env bash
#
# Deploy ZINO: apply the infrastructure, then publish Firebase Hosting.
#
# Run ./scripts/bootstrap.sh first. Safe to re-run — Terraform converges, and
# Hosting deploys are versioned and instantly rollback-able.
#
# Usage:
#   ./scripts/deploy.sh              # shows a plan, asks before applying
#   ./scripts/deploy.sh --plan-only  # shows the plan and stops
#
# Set ZINO_YES=1 to skip confirmation prompts.

# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PLAN_ONLY=0
[[ "${1:-}" == "--plan-only" ]] && PLAN_ONLY=1
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

ROOT="$(repo_root)"
TFDIR="$ROOT/infra/terraform"

need gcloud    "Install: https://cloud.google.com/sdk/docs/install"
need terraform "Install: https://developer.hashicorp.com/terraform/install"
need npx       "Install Node.js 18+: https://nodejs.org"

[[ -f "$TFDIR/backend.tf" ]] \
  || die "infra/terraform/backend.tf missing. Run ./scripts/bootstrap.sh first."
[[ -f "$TFDIR/terraform.tfvars" ]] \
  || die "infra/terraform/terraform.tfvars missing. Run ./scripts/bootstrap.sh first."

PROJECT="$(grep -E '^project_id' "$TFDIR/terraform.tfvars" | cut -d'"' -f2)"
[[ -n "$PROJECT" ]] || die "could not read project_id from terraform.tfvars"
info "Project: $PROJECT"

# --- Infrastructure ---------------------------------------------------------

info "terraform init"
terraform -chdir="$TFDIR" init -input=false

info "terraform plan"
# Plan to a file so what you approve is exactly what gets applied — with a bare
# `apply`, Terraform re-plans and could act on state that changed in between.
terraform -chdir="$TFDIR" plan -input=false -out=tfplan

if [[ "$PLAN_ONLY" == "1" ]]; then
  info "Plan only — stopping here."
  exit 0
fi

echo
warn "Applying creates billable resources: a Cloud SQL instance and an"
warn "always-warm Cloud Run instance. Review the plan above."
confirm "Apply this plan?" || { rm -f "$TFDIR/tfplan"; die "aborted"; }

info "terraform apply"
terraform -chdir="$TFDIR" apply -input=false tfplan
rm -f "$TFDIR/tfplan"
ok "infrastructure applied"

WEBUI_URL="$(terraform -chdir="$TFDIR" output -raw webui_url)"
PUBLIC_URL="$(terraform -chdir="$TFDIR" output -raw public_url)"

# --- Wait for the app -------------------------------------------------------
# The first boot runs database migrations, so the service can accept traffic a
# while after Terraform reports success.

info "Waiting for Open WebUI to answer on $WEBUI_URL"
for i in $(seq 1 30); do
  CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$WEBUI_URL" || true)"
  # Any non-5xx means it is serving; a redirect to the login page is success.
  if [[ -n "$CODE" && "$CODE" != "000" && "$CODE" -lt 500 ]]; then
    ok "responding (HTTP $CODE)"
    break
  fi
  [[ "$i" == "30" ]] && die "did not become healthy. Check: gcloud run services logs read zino-webui --region=<region> --project=$PROJECT"
  printf '  ... attempt %s/30 (HTTP %s)\n' "$i" "${CODE:-none}"
  sleep 10
done

# --- Hosting ----------------------------------------------------------------

info "Deploying Firebase Hosting"
npx --yes firebase-tools@13 deploy --only hosting \
  --project "$PROJECT" --non-interactive
ok "hosting deployed"

echo
info "ZINO is live."
cat <<EOF

  $PUBLIC_URL

  First run:
    1. Open the URL and register. The FIRST account becomes the administrator.
    2. Admin Panel -> Settings -> Connections: add your LLM provider + API key.
    3. Workspace -> Models: build your agents.

  Nothing else needs deploying — agents and connections live in the database.
EOF
