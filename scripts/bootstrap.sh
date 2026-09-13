#!/usr/bin/env bash
#
# One-time GCP bootstrap for ZINO, entirely from the CLI.
#
# Creates the things Terraform cannot create for itself: the project, the
# billing link, the enabled APIs, and the bucket that holds Terraform's own
# state. Then writes the Terraform backend and tfvars files.
#
# Safe to re-run — every step checks before it acts.
#
# Usage:
#   ./scripts/bootstrap.sh --project zino-prod --billing 0X0X0X-0X0X0X-0X0X0X
#   ./scripts/bootstrap.sh --project zino-prod --billing ... --region europe-west1
#
# Set ZINO_YES=1 to skip confirmation prompts.

# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PROJECT=""
BILLING=""
REGION="europe-west1"

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)  PROJECT="${2:-}"; shift 2 ;;
    --billing)  BILLING="${2:-}"; shift 2 ;;
    --region)   REGION="${2:-}";  shift 2 ;;
    -h|--help)  usage 0 ;;
    *)          die "unknown argument: $1 (try --help)" ;;
  esac
done

[[ -n "$PROJECT" ]] || { warn "--project is required"; usage 1; }

ROOT="$(repo_root)"
TFDIR="$ROOT/infra/terraform"
STATE_BUCKET="${PROJECT}-zino-tfstate"

# --- Preflight --------------------------------------------------------------

info "Checking prerequisites"
need gcloud   "Install: https://cloud.google.com/sdk/docs/install"
need terraform "Install: https://developer.hashicorp.com/terraform/install"
need npx      "Install Node.js 18+: https://nodejs.org"

if ! gcloud auth list --filter=status:ACTIVE --format='value(account)' | grep -q .; then
  die "Not logged in. Run: gcloud auth login && gcloud auth application-default login"
fi
ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' | head -1)"
ok "authenticated as $ACCOUNT"

# Terraform authenticates separately from gcloud, via Application Default
# Credentials. Being logged into gcloud does not imply ADC exists.
if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
  die "Application Default Credentials missing. Run: gcloud auth application-default login"
fi
ok "application default credentials present"

# --- Project ----------------------------------------------------------------

info "Project: $PROJECT"
if gcloud projects describe "$PROJECT" >/dev/null 2>&1; then
  ok "project already exists"
else
  confirm "Create GCP project '$PROJECT'?" || die "aborted"
  gcloud projects create "$PROJECT"
  ok "created"
fi

gcloud config set project "$PROJECT" >/dev/null
ok "gcloud default project set"

# Installing into a project that already runs something: say so plainly, and
# check for the specific names ZINO is about to claim.
#
# Only ask about a service whose API is already on. Querying a disabled API
# makes gcloud stop and ask whether to enable it — and with stderr hidden that
# prompt is invisible, so the script looks frozen. --quiet belts-and-braces it.
# A project with the API off cannot hold any of these resources anyway.
ENABLED_APIS="$(gcloud services list --enabled --project="$PROJECT" \
  --format='value(config.name)' --quiet 2>/dev/null || true)"

EXISTING_RUN=""
EXISTING_SQL=""
if grep -qx 'run.googleapis.com' <<<"$ENABLED_APIS"; then
  EXISTING_RUN="$(gcloud run services list --project="$PROJECT" \
    --format='value(metadata.name)' --quiet 2>/dev/null || true)"
fi
if grep -qx 'sqladmin.googleapis.com' <<<"$ENABLED_APIS"; then
  EXISTING_SQL="$(gcloud sql instances list --project="$PROJECT" \
    --format='value(name)' --quiet 2>/dev/null || true)"
fi
if [[ -n "$EXISTING_RUN$EXISTING_SQL" ]]; then
  warn "This project already contains resources:"
  [[ -n "$EXISTING_RUN" ]] && warn "  Cloud Run: $(echo "$EXISTING_RUN" | tr '\n' ' ')"
  [[ -n "$EXISTING_SQL" ]] && warn "  Cloud SQL: $(echo "$EXISTING_SQL" | tr '\n' ' ')"
  warn "ZINO will ADD to it, not replace anything. Terraform only ever manages"
  warn "what it created, so a later destroy cannot touch the above."

  # A name clash is the one thing that would actually break, so fail early.
  echo "$EXISTING_RUN" | grep -qx "zino-webui" \
    && die "a Cloud Run service named 'zino-webui' already exists here. Use a different project."
  echo "$EXISTING_SQL" | grep -qx "zino-pg" \
    && die "a Cloud SQL instance named 'zino-pg' already exists here. Use a different project."
  ok "no name conflicts"

  confirm "Install ZINO into this existing project?" || die "aborted"
fi

# --- Billing ----------------------------------------------------------------
# Nothing below works without billing: Cloud Run, Cloud SQL and Secret Manager
# all refuse to enable on an unbilled project.

if gcloud beta billing projects describe "$PROJECT" \
     --format='value(billingEnabled)' 2>/dev/null | grep -qi true; then
  ok "billing already enabled"
elif [[ -n "$BILLING" ]]; then
  info "Linking billing account $BILLING"
  gcloud beta billing projects link "$PROJECT" --billing-account="$BILLING"
  ok "billing linked"
else
  warn "Billing is not enabled and --billing was not given."
  warn "List your accounts with:  gcloud beta billing accounts list"
  die  "Re-run with --billing <ACCOUNT_ID>"
fi

# --- APIs -------------------------------------------------------------------
# Terraform also enables these, but it cannot: enabling them is itself an API
# call that needs serviceusage enabled first. So we do it here.

info "Enabling APIs (this takes a minute)"
gcloud services enable \
  run.googleapis.com \
  sqladmin.googleapis.com \
  secretmanager.googleapis.com \
  storage.googleapis.com \
  iamcredentials.googleapis.com \
  servicenetworking.googleapis.com \
  compute.googleapis.com \
  firebase.googleapis.com \
  firebasehosting.googleapis.com \
  identitytoolkit.googleapis.com \
  --project="$PROJECT"
ok "APIs enabled"

# --- Terraform state bucket -------------------------------------------------
# Terraform state contains the generated database password in plaintext. It must
# not live on a laptop, and it must be versioned so a bad apply is recoverable.

info "Terraform state bucket: gs://$STATE_BUCKET"
if gcloud storage buckets describe "gs://$STATE_BUCKET" >/dev/null 2>&1; then
  ok "bucket already exists"
else
  gcloud storage buckets create "gs://$STATE_BUCKET" \
    --project="$PROJECT" \
    --location="$REGION" \
    --uniform-bucket-level-access \
    --public-access-prevention
  ok "bucket created"
fi

gcloud storage buckets update "gs://$STATE_BUCKET" --versioning >/dev/null
ok "versioning on"

# --- Firebase ---------------------------------------------------------------

info "Adding Firebase to the project"
if npx --yes firebase-tools@13 projects:list 2>/dev/null | grep -q "$PROJECT"; then
  ok "Firebase already enabled"
else
  # Idempotent in practice, but it errors if already added, hence the guard.
  npx --yes firebase-tools@13 projects:addfirebase "$PROJECT" \
    || warn "could not add Firebase automatically — run: npx firebase-tools projects:addfirebase $PROJECT"
fi

# --- Generate Terraform config ---------------------------------------------

info "Writing Terraform configuration"

cat > "$TFDIR/backend.tf" <<EOF
# Generated by scripts/bootstrap.sh — do not edit by hand.
terraform {
  backend "gcs" {
    bucket = "$STATE_BUCKET"
    prefix = "zino/prod"
  }
}
EOF
ok "wrote infra/terraform/backend.tf"

if [[ -f "$TFDIR/terraform.tfvars" ]]; then
  warn "infra/terraform/terraform.tfvars already exists — leaving it alone"
  # A tfvars written by an older version of this script silently keeps its old
  # settings forever. Name what is missing rather than let that go unnoticed.
  MISSING=""
  for key in project_id region domain enable_oidc min_instances cpu memory; do
    grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$TFDIR/terraform.tfvars" || MISSING="$MISSING $key"
  done
  if [[ -n "$MISSING" ]]; then
    warn "  it does not set:$MISSING"
    warn "  Terraform will use the defaults for those, which are the cheap ones."
    warn "  To regenerate it with every setting spelled out and explained:"
    warn "    rm $TFDIR/terraform.tfvars && $0 --project $PROJECT"
  else
    ok "it sets every current option"
  fi
else
  cat > "$TFDIR/terraform.tfvars" <<EOF
project_id = "$PROJECT"
region     = "$REGION"

# Firebase Hosting serves https://$PROJECT.web.app until you set a domain.
domain = ""

# Login: Open WebUI's own accounts. Switch to Firebase Auth with
# ./scripts/enable-oidc.sh once you want Google sign-in.
enable_oidc = false

# Sizing. Defaults are the cheapest useful setup: the server shuts down when
# nobody is using it, so you pay only for the database while idle.
# The cost of that is a ~30-60s wait on the first message after a quiet spell.
# Set min_instances = 1 to make it always instant — see docs/cost.md for what
# that costs before you do.
min_instances = 0
cpu           = "1"
memory        = "2Gi"
EOF
  ok "wrote infra/terraform/terraform.tfvars"
fi

# Firebase Hosting's region must match Terraform's, and firebase.json is not
# templated — so check rather than silently diverge.
if ! grep -q "\"region\": \"$REGION\"" "$ROOT/firebase.json"; then
  warn "firebase.json names a different region than --region $REGION."
  warn "Update the 'region' field in firebase.json to '$REGION' before deploying."
fi

echo
info "Bootstrap complete."
cat <<EOF

  Next:  ./scripts/deploy.sh

  That runs terraform apply and publishes Firebase Hosting. Review the plan it
  shows you before confirming — it creates a Cloud SQL instance, which is the
  part that costs money.
EOF
