# Shared helpers. Sourced, not executed.
# shellcheck shell=bash

set -euo pipefail

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BOLD=$'\033[1m'; OFF=$'\033[0m'

info()  { printf '%s==>%s %s\n' "$BOLD" "$OFF" "$*"; }
ok()    { printf '%s  ok%s %s\n' "$GREEN" "$OFF" "$*"; }
warn()  { printf '%s  !!%s %s\n' "$YELLOW" "$OFF" "$*" >&2; }
die()   { printf '%serror%s %s\n' "$RED" "$OFF" "$*" >&2; exit 1; }

# Require a command to be on PATH, with an install hint.
need() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is not installed. $2"
}

confirm() {
  local prompt="$1"
  if [[ "${ZINO_YES:-}" == "1" ]]; then
    info "$prompt — auto-confirmed (ZINO_YES=1)"
    return 0
  fi
  read -r -p "$prompt [y/N] " reply
  [[ "$reply" == "y" || "$reply" == "Y" ]]
}

# Terraform specifically: Cloud Shell ships a placeholder on PATH that prints
# install instructions and exits 0. `command -v` sees it and `terraform init`
# appears to succeed while doing nothing, so existence is not enough — the
# binary has to actually identify itself.
require_terraform() {
  command -v terraform >/dev/null 2>&1 || {
    die "terraform is not installed. Run: ./scripts/install-terraform.sh"
  }
  if ! terraform version 2>&1 | head -1 | grep -q '^Terraform v'; then
    die "terraform on PATH is a placeholder, not the real thing (Cloud Shell does this). Run: ./scripts/install-terraform.sh"
  fi
}

# Point Terraform at the Application Default Credentials file.
#
# Terraform's Google library does not honour CLOUDSDK_CONFIG. Its chain is
# GOOGLE_APPLICATION_CREDENTIALS, then ~/.config/gcloud/..., then the GCE
# metadata server. Cloud Shell relocates gcloud's config dir into /tmp, so the
# file `gcloud auth application-default login` writes is NOT where Terraform
# looks — it falls through to the metadata server instead, and fails there with
# an opaque "invalid token JSON from metadata" that re-running the login can
# never fix, because gcloud keeps writing to the path Terraform ignores.
#
# So find the file and name it explicitly.
require_adc() {
  if [[ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" && -r "${GOOGLE_APPLICATION_CREDENTIALS}" ]]; then
    ok "using credentials at $GOOGLE_APPLICATION_CREDENTIALS"
    return
  fi

  local candidates=() config_dir adc
  # Where Cloud Shell puts it.
  [[ -n "${CLOUDSDK_CONFIG:-}" ]] && candidates+=("$CLOUDSDK_CONFIG/application_default_credentials.json")
  # Ask gcloud itself, in case neither guess is right.
  config_dir="$(gcloud info --format='value(config.paths.global_config_dir)' 2>/dev/null || true)"
  [[ -n "$config_dir" ]] && candidates+=("$config_dir/application_default_credentials.json")
  # The standard location, used everywhere that is not Cloud Shell.
  candidates+=("$HOME/.config/gcloud/application_default_credentials.json")

  for adc in "${candidates[@]}"; do
    if [[ -r "$adc" ]]; then
      export GOOGLE_APPLICATION_CREDENTIALS="$adc"
      ok "credentials found at $adc"
      return
    fi
  done

  printf '%serror%s %s\n' "$RED" "$OFF" "Could not find Application Default Credentials." >&2
  printf '\n    gcloud auth application-default login\n\n' >&2
  printf '%s\n' "Run that (answer y), then re-run this script." >&2
  exit 1
}

# Repository root, regardless of where the script was invoked from.
repo_root() {
  git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel
}
