#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
#  Starfall Exodus — onbeheerde Docker-installatie (bootstrap)
#  Model: rorymeijer/regiedeck-install (docker-unattended-install.sh)
# ----------------------------------------------------------------------------
#  Draai op een VERSE server (Debian/Ubuntu) met één commando:
#
#    bash -c "$(curl -fsSL https://raw.githubusercontent.com/rorymeijer/starfall-install/main/docker-unattended-install.sh)"
#
#  De bron-repository (rorymeijer/starfall) is PRIVÉ. Dit bootstrapscript
#  staat daarom in de publieke repo rorymeijer/starfall-install en vraagt —
#  net als bij Regiedeck — om een GitHub-gebruikersnaam en een Personal
#  Access Token (PAT) met leesrechten om de bron te downloaden.
#
#  Dit script:
#    1. installeert Docker + hulpprogramma's (indien nodig);
#    2. kloont (of werkt bij) de repository naar /srv/docker/starfall;
#    3. kiest automatisch een vrije host-poort (vanaf 8080);
#    4. draagt de eigenlijke installatie over aan backend/install.sh, dat een
#       .env met sterke geheimen genereert, de volledige stack start (MariaDB,
#       Redis, web, websocket, scheduler), migreert en een adminaccount maakt;
#    5. zet een nachtelijke back-up-cronjob op de host;
#    6. toont de URL's en het admin-wachtwoord.
#
#  Anders dan bij Regiedeck is GEEN externe database nodig: de stack levert
#  MariaDB en Redis zelf mee.
#
#  Volledig onbeheerd draaien kan via omgevingsvariabelen (geen prompts):
#    STARFALL_REPO           GitHub owner/repo        (standaard rorymeijer/starfall)
#    STARFALL_BRANCH         branch                   (standaard main)
#    STARFALL_DIR            installatiemap           (standaard /srv/docker/starfall)
#    STARFALL_PORT           begin-host-poort         (standaard 8080)
#    STARFALL_DOMAIN         publieke hostnaam        (bv. starfall.example.nl)
#    GITHUB_USER             GitHub-gebruiker         (voor de privérepo)
#    GITHUB_TOKEN            GitHub-token (PAT)       (voor de privérepo)
#    STARFALL_ADMIN_USER     adminnaam                (standaard admin)
#    STARFALL_ADMIN_EMAIL    admin-e-mail             (standaard admin@<domein>)
#    STARFALL_ADMIN_PASS     adminwachtwoord          (standaard: willekeurig)
#    STARFALL_NO_CRON=1      sla de back-up-cron over
# ============================================================================

INSTALL_DIR="${STARFALL_DIR:-/srv/docker/starfall}"
REPO="${STARFALL_REPO:-rorymeijer/starfall}"
BRANCH="${STARFALL_BRANCH:-main}"
START_PORT="${STARFALL_PORT:-8080}"
DOMAIN="${STARFALL_DOMAIN:-}"

info()  { printf '\033[1;36m[starfall]\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m[starfall]\033[0m %s\n' "$*"; }
error() { printf '\033[1;31m[starfall]\033[0m %s\n' "$*" >&2; }
rand_pw() { LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "${1:-20}"; }

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
      warn "Herstart met sudo ..."
      exec sudo -E bash "$0" "$@"
    fi
    error "Dit script vereist root (of sudo)."
    exit 1
  fi
}

# Vraag om GitHub-gegevens voor de privé-bronrepository (net als Regiedeck).
# Env-variabelen hebben voorrang, zodat onbeheerd draaien mogelijk blijft.
prompt_github_credentials() {
  if [ -n "${GITHUB_USER:-}" ] && [ -n "${GITHUB_TOKEN:-}" ]; then
    return 0
  fi
  if [ ! -t 0 ]; then
    error "De bron-repository ${REPO} is privé. Zet GITHUB_USER en GITHUB_TOKEN"
    error "als omgevingsvariabelen om onbeheerd te installeren."
    exit 1
  fi
  echo "GitHub authenticatie voor privé-repo (${REPO}):"
  [ -z "${GITHUB_USER:-}" ]  && read -r    -p "GitHub username: " GITHUB_USER
  [ -z "${GITHUB_TOKEN:-}" ] && { read -r -s -p "GitHub token: " GITHUB_TOKEN; echo; }
  if [ -z "${GITHUB_USER:-}" ] || [ -z "${GITHUB_TOKEN:-}" ]; then
    error "GitHub-gebruiker en -token zijn beide vereist voor de privé-repo."
    exit 1
  fi
}

install_prerequisites() {
  info "Systeemafhankelijkheden controleren ..."
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y git curl ca-certificates iproute2 >/dev/null 2>&1 || true
  else
    warn "Geen apt-get gevonden; zorg zelf dat git, curl en Docker aanwezig zijn."
  fi

  if ! command -v docker >/dev/null 2>&1; then
    info "Docker installeren ..."
    curl -fsSL https://get.docker.com | sh
  fi
  if ! docker compose version >/dev/null 2>&1; then
    error "Docker Compose (v2) ontbreekt. Installeer een recente Docker Engine."
    exit 1
  fi
  systemctl enable --now docker >/dev/null 2>&1 || true
}

find_free_port() {
  local port="$1"
  while :; do
    if ss -ltn 2>/dev/null | grep -q ":${port}[[:space:]]" \
       || docker ps --format '{{.Ports}}' 2>/dev/null | grep -q ":${port}->"; then
      port=$((port + 1))
    else
      echo "$port"; return
    fi
  done
}

clone_or_update() {
  local auth_url="https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/${REPO}.git"
  local clean_url="https://github.com/${REPO}.git"

  if [ -d "${INSTALL_DIR}/.git" ]; then
    info "Bestaande installatie gevonden; code bijwerken ..."
    # Tijdelijk de getokende URL gebruiken zodat fetch op de privé-repo werkt.
    git -C "$INSTALL_DIR" remote set-url origin "$auth_url"
    git -C "$INSTALL_DIR" fetch --all --tags
    git -C "$INSTALL_DIR" checkout "$BRANCH"
    git -C "$INSTALL_DIR" reset --hard "origin/${BRANCH}"
  else
    info "Repository klonen naar ${INSTALL_DIR} ..."
    mkdir -p "$(dirname "$INSTALL_DIR")"
    git clone -b "$BRANCH" "$auth_url" "$INSTALL_DIR"
  fi

  # Bewaar geen token in de git-config.
  git -C "$INSTALL_DIR" remote set-url origin "$clean_url"
  git -C "$INSTALL_DIR" config --system --add safe.directory "$INSTALL_DIR" 2>/dev/null || true
}

setup_backup_cron() {
  [ "${STARFALL_NO_CRON:-0}" = "1" ] && { info "Back-up-cron overgeslagen."; return; }
  info "Nachtelijke back-up-cron instellen (03:30) ..."
  cat > /etc/cron.d/starfall <<EOF
# Starfall Exodus — nachtelijke database-back-up (bewaart de laatste 14).
30 3 * * * root cd ${INSTALL_DIR}/backend && ./backup.sh >> ${INSTALL_DIR}/backend/storage/logs/backup-cron.log 2>&1
EOF
  chmod 0644 /etc/cron.d/starfall
}

main() {
  require_root "$@"

  # Privérepo: vraag de GitHub-gegevens vóór alles (of neem ze uit env).
  prompt_github_credentials

  install_prerequisites
  clone_or_update

  # Token niet langer in het geheugen laten rondslingeren.
  unset GITHUB_TOKEN

  local port; port="$(find_free_port "$START_PORT")"
  info "Vrije host-poort gekozen: ${port}"

  # Publieke URL's afleiden.
  local app_url ws_url cors
  if [ -n "$DOMAIN" ]; then
    app_url="https://${DOMAIN}"; ws_url="wss://${DOMAIN}/ws"; cors="https://${DOMAIN}"
  else
    app_url="http://localhost:${port}"; ws_url="ws://localhost:${port}/ws"; cors="*"
  fi

  # Admin-gegevens.
  local admin_user admin_email admin_pass
  admin_user="${STARFALL_ADMIN_USER:-admin}"
  admin_email="${STARFALL_ADMIN_EMAIL:-admin@${DOMAIN:-starfall.local}}"
  admin_pass="${STARFALL_ADMIN_PASS:-$(rand_pw 20)}"

  info "Installatie uitvoeren via backend/install.sh ..."
  (
    cd "${INSTALL_DIR}/backend"
    HTTP_PORT="$port" \
    APP_URL="$app_url" \
    WS_PUBLIC_URL="$ws_url" \
    CORS_ALLOWED_ORIGINS="$cors" \
    STARFALL_ADMIN_USER="$admin_user" \
    STARFALL_ADMIN_EMAIL="$admin_email" \
    STARFALL_ADMIN_PASS="$admin_pass" \
    ./install.sh
  )

  setup_backup_cron

  echo
  info "Starfall Exodus draait."
  echo "  Installatiemap : ${INSTALL_DIR}"
  echo "  API/health     : ${app_url}/health"
  echo "  Admin-UI       : ${app_url}/admin/"
  echo "  WebSocket      : ${ws_url}"
  echo "  Adminlogin     : ${admin_user} / ${admin_pass}"
  echo
  info "Beheer:  cd ${INSTALL_DIR}/backend && docker compose ps"
  info "Updaten: cd ${INSTALL_DIR}/backend && ./update.sh"
  [ -z "$DOMAIN" ] && warn "Productie? Zet STARFALL_DOMAIN en plaats een TLS-reverse-proxy vóór poort ${port} (zie backend/docs/DEPLOYMENT.md)."
}

main "$@"
