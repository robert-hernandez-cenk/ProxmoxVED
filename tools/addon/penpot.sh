#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Robert Hernandez
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/penpot/penpot

if command -v curl >/dev/null 2>&1; then
  source <(curl -fsSL ${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/core.func)
  load_functions
elif command -v wget >/dev/null 2>&1; then
  source <(wget -qO- ${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/core.func)
  load_functions
fi
source <(curl -fsSL ${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/lib/tools.func)

color
catch_errors

APP="Penpot"
APP_TYPE="tools"
APP_DIR="/opt/penpot"
REPO="penpot/penpot"
DEFAULT_PORT=9001

header_info "$APP"

if ! grep -q -Ei 'debian|ubuntu' /etc/os-release; then
  msg_error "Unsupported OS. This addon supports only Debian or Ubuntu."
  exit 1
fi

IP=$(hostname -I | awk '{print $1}')

function is_installed() {
  [[ -f "$APP_DIR/docker-compose.yml" ]]
}

# The upstream compose file is kept untouched. Port, public URI and secret key
# live in docker-compose.override.yml and .env, so an update just replaces it.
function fetch_compose() {
  curl -fsSL "https://raw.githubusercontent.com/${REPO}/${1}/docker/images/docker-compose.yaml" -o "$APP_DIR/docker-compose.yml"
}

function install_penpot() {
  local port="${1:-$DEFAULT_PORT}"
  local version secret

  ensure_docker

  version=$(get_latest_github_release "$REPO")
  secret=$(openssl rand -base64 48 | tr -d '\n')

  msg_info "Installing ${APP} ${version}"
  mkdir -p "$APP_DIR"
  fetch_compose "$version"

  cat <<EOF >"$APP_DIR/.env"
PENPOT_VERSION=${version}
PENPOT_PORT=${port}
PENPOT_PUBLIC_URI=http://${IP}:${port}
PENPOT_SECRET_KEY=${secret}
EOF
  chmod 600 "$APP_DIR/.env"

  cat <<'EOF' >"$APP_DIR/docker-compose.override.yml"
services:
  penpot-frontend:
    ports: !override
      - ${PENPOT_PORT}:8080
    environment:
      PENPOT_PUBLIC_URI: ${PENPOT_PUBLIC_URI}
  penpot-backend:
    environment:
      PENPOT_PUBLIC_URI: ${PENPOT_PUBLIC_URI}
      PENPOT_SECRET_KEY: ${PENPOT_SECRET_KEY}
  penpot-admin-console:
    environment:
      PENPOT_PUBLIC_URI: ${PENPOT_PUBLIC_URI}
      PENPOT_SECRET_KEY: ${PENPOT_SECRET_KEY}
  penpot-exporter:
    environment:
      PENPOT_PUBLIC_URI: ${PENPOT_PUBLIC_URI}
      PENPOT_SECRET_KEY: ${PENPOT_SECRET_KEY}
EOF
  echo "$version" >~/.penpot
  msg_ok "Installed ${APP} ${version}"

  msg_info "Starting ${APP} (pulling images, this can take a few minutes)"
  cd "$APP_DIR"
  $STD docker compose up -d
  msg_ok "Started ${APP}"

  msg_ok "${APP} installed at http://${IP}:${port}"
  msg_ok "Outgoing mail (registration, invites) is caught by Mailpit at http://${IP}:8025"
}

function update_penpot() {
  if check_for_gh_release "penpot" "$REPO"; then
    local version="$CHECK_UPDATE_RELEASE"

    msg_info "Updating ${APP} to ${version}"
    cd "$APP_DIR"
    fetch_compose "$version"
    sed -i "s|^PENPOT_VERSION=.*|PENPOT_VERSION=${version}|" .env
    $STD docker compose pull
    $STD docker compose up -d
    echo "$version" >~/.penpot
    msg_ok "Updated ${APP} to ${version}"
  fi
}

function uninstall_penpot() {
  local remove_data=""

  read -r -p "Also delete all projects and files (Docker volumes)? (y/N): " remove_data
  remove_data="${remove_data//[[:space:]]/}"

  msg_info "Removing ${APP}"
  cd "$APP_DIR"
  if [[ "${remove_data,,}" =~ ^(y|yes)$ ]]; then
    $STD docker compose down -v
  else
    $STD docker compose down
  fi
  cd /
  rm -rf "$APP_DIR" ~/.penpot
  msg_ok "${APP} uninstalled"
}

if is_installed; then
  read -r -p "Update (1), Uninstall (2), Cancel (3)? [1/2/3]: " action
  action="${action//[[:space:]]/}"
  case "$action" in
  1) update_penpot ;;
  2) uninstall_penpot ;;
  3) msg_info "Cancelled" ;;
  *) msg_error "Invalid input" ;;
  esac
else
  read -r -p "Enter port number (default: ${DEFAULT_PORT}): " PORT_INPUT
  PORT="${PORT_INPUT:-$DEFAULT_PORT}"
  read -r -p "Install ${APP}? (y/n): " answer
  answer="${answer//[[:space:]]/}"
  [[ "${answer,,}" =~ ^(y|yes)$ ]] && install_penpot "$PORT" || msg_info "Installation skipped"
fi
