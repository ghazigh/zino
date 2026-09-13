#!/usr/bin/env bash
#
# Install Terraform into ~/bin.
#
# Cloud Shell does not ship Terraform — what sits on PATH is a placeholder that
# prints install instructions and exits successfully, which is worse than it
# being absent. And Cloud Shell wipes system packages between sessions, so
# `apt install` would not survive. Your home directory does, so that is where
# this puts it.
#
# Usage:
#   ./scripts/install-terraform.sh

# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

VERSION="${TERRAFORM_VERSION:-1.9.8}"
BIN_DIR="$HOME/bin"

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

need curl "Install curl first."
need unzip "Install unzip first."

if [[ -x "$BIN_DIR/terraform" ]] && "$BIN_DIR/terraform" version 2>/dev/null | head -1 | grep -q "v$VERSION"; then
  ok "Terraform $VERSION already installed at $BIN_DIR/terraform"
else
  case "$(uname -m)" in
    x86_64)          ARCH="amd64" ;;
    aarch64|arm64)   ARCH="arm64" ;;
    *)               die "unsupported architecture: $(uname -m)" ;;
  esac

  URL="https://releases.hashicorp.com/terraform/${VERSION}/terraform_${VERSION}_linux_${ARCH}.zip"
  TMP="$(mktemp -d)"
  # Clean up the download directory however this script exits.
  trap 'rm -rf "$TMP"' EXIT

  info "Downloading Terraform $VERSION ($ARCH)"
  curl -fsSL -o "$TMP/terraform.zip" "$URL" || die "download failed: $URL"

  # A proxy or captive portal can answer 200 with an HTML error page, which
  # curl reports as success. Check we actually got a zip before trusting it.
  [[ -s "$TMP/terraform.zip" ]] || die "download produced an empty file: $URL"
  unzip -tq "$TMP/terraform.zip" >/dev/null 2>&1 \
    || die "download is not a valid zip (a proxy may have intercepted it): $URL"

  mkdir -p "$BIN_DIR"
  unzip -oq "$TMP/terraform.zip" -d "$TMP"
  mv "$TMP/terraform" "$BIN_DIR/terraform"
  chmod +x "$BIN_DIR/terraform"
  ok "installed to $BIN_DIR/terraform"
fi

# ~/bin is not on PATH by default, and ordering matters: it has to come before
# the Cloud Shell placeholder, not after it.
if ! grep -qs 'HOME/bin' "$HOME/.bashrc"; then
  # $HOME must stay unexpanded here — it is written literally into .bashrc.
  # shellcheck disable=SC2016
  printf '\n# Added by ZINO scripts/install-terraform.sh\nexport PATH="$HOME/bin:$PATH"\n' >> "$HOME/.bashrc"
  ok "added ~/bin to PATH in ~/.bashrc (applies to new shells)"
else
  ok "PATH already includes ~/bin via .bashrc"
fi

echo
if [[ "$(command -v terraform)" == "$BIN_DIR/terraform" ]]; then
  ok "ready: $(terraform version | head -1)"
else
  warn "Your CURRENT shell still points at $(command -v terraform || echo 'nothing')."
  warn "Run this line, then carry on:"
  echo
  echo "    export PATH=\"\$HOME/bin:\$PATH\""
  echo
  warn "New Cloud Shell sessions will pick it up automatically."
fi
