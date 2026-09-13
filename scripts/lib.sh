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

# Repository root, regardless of where the script was invoked from.
repo_root() {
  git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel
}
