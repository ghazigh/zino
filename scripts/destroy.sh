#!/usr/bin/env bash
#
# Tear ZINO down. Deletes the Cloud Run service, the database and its contents.
#
# Usage:
#   ./scripts/destroy.sh

# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ROOT="$(repo_root)"
TFDIR="$ROOT/infra/terraform"
require_terraform

PROJECT="$(grep -E '^project_id' "$TFDIR/terraform.tfvars" 2>/dev/null | cut -d'"' -f2 || true)"
[[ -n "$PROJECT" ]] || die "no terraform.tfvars — nothing to destroy"

warn "This destroys ZINO in project '$PROJECT':"
warn "  - the Cloud SQL database, and with it every agent, tool and chat"
warn "  - the Cloud Run service"
warn "Uploaded files in the GCS bucket are NOT deleted (force_destroy is off)."
echo
read -r -p "Type the project ID to confirm: " typed
[[ "$typed" == "$PROJECT" ]] || die "did not match — aborted"

# deletion_protection on the SQL instance will block this by design. Clearing it
# is a deliberate, separate act rather than something this script does for you.
warn "If Terraform refuses on the SQL instance, that is deletion_protection"
warn "doing its job. Set deletion_protection = false in sql.tf, apply, re-run."

terraform -chdir="$TFDIR" destroy
