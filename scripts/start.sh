#!/usr/bin/env bash
#
# Start ZINO on this machine. One command, no cloud, no cost.
#
# Creates .env with a generated secret on first run, starts Open WebUI and its
# database, waits for it to answer, and prints the address.
#
# Usage:
#   ./scripts/start.sh          # start (and set up on first run)
#   ./scripts/start.sh --stop   # stop, keeping all your data
#   ./scripts/start.sh --logs   # follow the logs

# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ROOT="$(repo_root)"
cd "$ROOT"

case "${1:-}" in
  -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  --stop)    docker compose down && ok "stopped — your data is kept"; exit 0 ;;
  --logs)    exec docker compose logs -f ;;
  "")        ;;
  *)         die "unknown argument: $1 (try --help)" ;;
esac

need docker "Install Docker Desktop: https://docs.docker.com/get-started/get-docker/"

docker info >/dev/null 2>&1 || die "Docker is installed but not running. Start Docker Desktop, then re-run."

# --- First-run setup --------------------------------------------------------

if [[ -f .env ]]; then
  ok ".env already exists — leaving it alone"
else
  info "Creating .env"
  cp .env.example .env

  # WEBUI_SECRET_KEY encrypts the provider API keys you enter in the admin UI.
  # Generating it here means there is no manual step, and no chance of the
  # placeholder being left in place.
  if command -v openssl >/dev/null 2>&1; then
    SECRET="$(openssl rand -hex 32)"
  else
    SECRET="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  fi
  # Portable in-place edit: GNU and BSD sed disagree about -i.
  sed "s/^WEBUI_SECRET_KEY=$/WEBUI_SECRET_KEY=$SECRET/" .env > .env.tmp && mv .env.tmp .env
  ok "generated WEBUI_SECRET_KEY"

  warn "Keep .env safe. That key encrypts the provider API keys you will add"
  warn "in the admin UI — losing it means entering them all again."
fi

# --- Start ------------------------------------------------------------------

info "Starting ZINO (first run pulls ~2GB, so give it a few minutes)"
docker compose up -d

info "Waiting for ZINO to answer"
for i in $(seq 1 60); do
  CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:3000 || true)"
  # Any non-5xx means it is serving; a redirect to the login page is success.
  if [[ -n "$CODE" && "$CODE" != "000" && "$CODE" -lt 500 ]]; then
    ok "ZINO is up"
    break
  fi
  if [[ "$i" == "60" ]]; then
    warn "It did not answer within 5 minutes. Check what it is doing with:"
    warn "    ./scripts/start.sh --logs"
    exit 1
  fi
  sleep 5
done

cat <<EOF

  ${BOLD}http://localhost:3000${OFF}

  1. Register. The FIRST account becomes the administrator.
  2. Admin Panel -> Settings -> Connections: add your LLM provider + API key.
  3. Workspace -> Models: build your agents.

  Stop with:  ./scripts/start.sh --stop     (your data is kept)
  Logs with:  ./scripts/start.sh --logs

EOF
