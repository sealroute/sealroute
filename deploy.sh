#!/usr/bin/env bash
# SealRoute self-host helper.
#
# Usage:
#   ./deploy.sh up        # pull (if needed) and start the stack
#   ./deploy.sh down      # stop the stack
#   ./deploy.sh restart   # down + up
#   ./deploy.sh pull      # refresh the app image from the registry
#   ./deploy.sh logs      # tail app logs
#   ./deploy.sh sh        # shell into the app container
#   ./deploy.sh psql      # open psql in the postgres container
#   ./deploy.sh status    # docker compose ps
#   ./deploy.sh rm        # force-remove the current containers (keeps volumes)
#   ./deploy.sh reset     # destroy containers + data volumes (DANGEROUS)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"
ENV_FILE="${ENV_FILE:-.env}"
ENV_EXAMPLE="${ENV_EXAMPLE:-.env.example}"
PROJECT_NAME="${PROJECT_NAME:-sealroute}"

if [ -t 1 ]; then
  C_BLUE="\033[1;34m"; C_GREEN="\033[1;32m"; C_RED="\033[1;31m"; C_YELLOW="\033[1;33m"; C_RESET="\033[0m"
else
  C_BLUE=""; C_GREEN=""; C_RED=""; C_YELLOW=""; C_RESET=""
fi

info()  { printf "${C_BLUE}==>${C_RESET} %s\n" "$*"; }
ok()    { printf "${C_GREEN}OK${C_RESET}  %s\n" "$*"; }
warn()  { printf "${C_YELLOW}!!${C_RESET}  %s\n" "$*"; }
die()   { printf "${C_RED}xx${C_RESET}  %s\n" "$*" >&2; exit 1; }

require_docker() {
  command -v docker >/dev/null 2>&1 || die "docker is not installed or not on PATH"
  docker info >/dev/null 2>&1 || die "docker daemon is not running"

  if docker compose version >/dev/null 2>&1; then
    DC=(docker compose -p "$PROJECT_NAME" -f "$COMPOSE_FILE")
  elif command -v docker-compose >/dev/null 2>&1; then
    DC=(docker-compose -p "$PROJECT_NAME" -f "$COMPOSE_FILE")
  else
    die "docker compose plugin not found"
  fi
}

ensure_env_file() {
  if [ ! -f "$ENV_FILE" ]; then
    if [ -f "$ENV_EXAMPLE" ]; then
      cp "$ENV_EXAMPLE" "$ENV_FILE"
      warn "Created $ENV_FILE from $ENV_EXAMPLE -- review it before running again"
    else
      die "Neither $ENV_FILE nor $ENV_EXAMPLE exists"
    fi
  fi

  if grep -qE '^SECRET_KEY_BASE=replace-me' "$ENV_FILE"; then
    info "Generating SECRET_KEY_BASE in $ENV_FILE"
    local secret
    secret="$(openssl rand -hex 64 2>/dev/null || ruby -rsecurerandom -e 'print SecureRandom.hex(64)')"
    if [ "$(uname -s)" = "Darwin" ]; then
      sed -i '' "s|^SECRET_KEY_BASE=.*|SECRET_KEY_BASE=$secret|" "$ENV_FILE"
    else
      sed -i "s|^SECRET_KEY_BASE=.*|SECRET_KEY_BASE=$secret|" "$ENV_FILE"
    fi
  fi
}

pull_with_retry() {
  local attempt=1 max=3
  while [ "$attempt" -le "$max" ]; do
    info "Pulling images (attempt $attempt/$max)"
    if "${DC[@]}" pull; then
      return 0
    fi
    warn "Pull failed; sleeping 5s before retry"
    sleep 5
    attempt=$((attempt + 1))
  done
  warn "Image pull kept failing -- continuing; docker compose will retry on up"
  return 0
}

cmd_build() {
  warn "This compose file uses a prebuilt image (\$APP_IMAGE)."
  warn "Set APP_IMAGE in $ENV_FILE to a tag you build/push elsewhere."
  warn "Nothing to build locally. Use './deploy.sh pull' to refresh."
}

cmd_pull() {
  info "Pulling app image: ${APP_IMAGE:-sealroute/sealroute:latest}"
  pull_with_retry
  ok "Pulled"
}

cmd_up() {
  pull_with_retry
  info "Starting stack"
  "${DC[@]}" up -d
  ok "Stack is up"
  if [ -n "${HOST:-}" ]; then
    printf "    Web: https://%s (Caddy will issue a TLS cert automatically)\n" "$HOST"
  else
    printf "    HOST is not set in %s -- Caddy needs it to bind to your domain\n" "$ENV_FILE"
  fi
  printf "\nFollow logs with: %s logs\n" "$0"
}

cmd_down() {
  info "Stopping stack"
  "${DC[@]}" down
  ok "Stopped"
}

cmd_restart() {
  cmd_down
  cmd_up
}

cmd_logs() {
  "${DC[@]}" logs -f --tail=200 "${1:-app}"
}

cmd_sh() {
  "${DC[@]}" exec app /bin/sh
}

cmd_psql() {
  "${DC[@]}" exec postgres psql -U postgres -d sealroute
}

cmd_status() {
  "${DC[@]}" ps
}

cmd_rm() {
  info "Force-removing SealRoute containers (volumes are preserved)"
  "${DC[@]}" down --remove-orphans || true
  for name in sealroute-app sealroute-postgres sealroute-caddy; do
    if docker ps -a --format '{{.Names}}' | grep -qx "$name"; then
      info "Removing container $name"
      docker rm -f "$name" >/dev/null
    fi
  done
  ok "Containers removed (run './deploy.sh up' to recreate)"
}

cmd_reset() {
  warn "This will delete the SealRoute database, uploaded files, and Caddy TLS state."
  printf "Type 'yes' to continue: "
  read -r answer
  [ "$answer" = "yes" ] || die "Aborted"
  "${DC[@]}" down -v || true
  ok "Data wiped"
}

main() {
  require_docker
  ensure_env_file
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a

  case "${1:-up}" in
    up|start)    cmd_up ;;
    down|stop)   cmd_down ;;
    restart)     cmd_restart ;;
    pull)        cmd_pull ;;
    build)       cmd_build ;;
    logs)        shift || true; cmd_logs "$@" ;;
    sh|shell)    cmd_sh ;;
    psql)        cmd_psql ;;
    status|ps)   cmd_status ;;
    rm|remove)   cmd_rm ;;
    reset)       cmd_reset ;;
    -h|--help|help)
      sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
      ;;
    *)
      die "Unknown command: $1 (try: $0 help)"
      ;;
  esac
}

main "$@"
