#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Robert Hernandez
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/penpot/penpot

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

setup_docker

msg_info "Setting up Penpot"
RELEASE=$(get_latest_github_release "penpot/penpot")
IP=$(hostname -I | awk '{print $1}')
PORT="${var_penpot_port:-9001}"
PUBLIC_URI="${var_penpot_public_uri:-http://${IP}:${PORT}}"
case "${var_penpot_telemetry:-yes}" in
no | false | 0) TELEMETRY="false" ;;
*) TELEMETRY="true" ;;
esac
mkdir -p /opt/penpot
curl -fsSL "https://raw.githubusercontent.com/penpot/penpot/${RELEASE}/docker/images/docker-compose.yaml" -o /opt/penpot/docker-compose.yml
cat <<EOF >/opt/penpot/.env
PENPOT_VERSION=${RELEASE}
PENPOT_PORT=${PORT}
PENPOT_PUBLIC_URI=${PUBLIC_URI}
PENPOT_TELEMETRY_ENABLED=${TELEMETRY}
PENPOT_SECRET_KEY=$(openssl rand -base64 48 | tr -d '\n')
EOF
chmod 600 /opt/penpot/.env
# The upstream compose file stays untouched so an update can replace it;
# port, public URI and secret key are overridden here from .env
cat <<'EOF' >/opt/penpot/docker-compose.override.yml
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
      PENPOT_TELEMETRY_ENABLED: ${PENPOT_TELEMETRY_ENABLED}
  penpot-admin-console:
    environment:
      PENPOT_PUBLIC_URI: ${PENPOT_PUBLIC_URI}
      PENPOT_SECRET_KEY: ${PENPOT_SECRET_KEY}
  penpot-exporter:
    environment:
      PENPOT_PUBLIC_URI: ${PENPOT_PUBLIC_URI}
      PENPOT_SECRET_KEY: ${PENPOT_SECRET_KEY}
EOF
echo "${RELEASE}" >~/.penpot
msg_ok "Set up Penpot ${RELEASE}"

msg_info "Starting Penpot (pulling images)"
cd /opt/penpot
$STD docker compose up -d
msg_ok "Started Penpot"

motd_ssh
customize
cleanup_lxc
