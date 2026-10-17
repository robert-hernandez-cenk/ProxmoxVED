#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Robert Hernandez
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/penpot/penpot

APP="Penpot"
var_tags="${var_tags:-design;docker}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-6144}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
# Docker inside the LXC
var_nesting="${var_nesting:-1}"
var_keyctl="${var_keyctl:-1}"

# Settings the install script accepts up front; unset means its default
export var_penpot_port="${var_penpot_port:-}"
export var_penpot_public_uri="${var_penpot_public_uri:-}"
export var_penpot_telemetry="${var_penpot_telemetry:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/penpot/docker-compose.yml ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "penpot" "penpot/penpot"; then
    msg_info "Updating Penpot"
    cd /opt/penpot
    curl -fsSL "https://raw.githubusercontent.com/penpot/penpot/${CHECK_UPDATE_RELEASE}/docker/images/docker-compose.yaml" -o docker-compose.yml
    sed -i "s|^PENPOT_VERSION=.*|PENPOT_VERSION=${CHECK_UPDATE_RELEASE}|" .env
    $STD docker compose pull
    $STD docker compose up -d
    echo "${CHECK_UPDATE_RELEASE}" >~/.penpot
    msg_ok "Updated Penpot to ${CHECK_UPDATE_RELEASE}"
  fi
  exit
}

start

# Asked in Advanced install; Default install and unattended runs skip it
# and fall back to http://<container-ip>:<port> in the install script
if [[ -z "${var_penpot_public_uri}" ]]; then
  var_penpot_public_uri=$(prompt_input "Penpot public URL, e.g. https://design.example.com (blank = http://<container-ip>:${var_penpot_port:-9001}):" "" 120)
fi

build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:9001${CL}"
if [[ -n "${var_penpot_port}" && "${var_penpot_port}" != "9001" ]]; then
  echo -e "${INFO}${YW}Port set to ${var_penpot_port}:${CL} ${GATEWAY}${BGN}http://${IP}:${var_penpot_port}${CL}"
fi
if [[ -n "${var_penpot_public_uri}" ]]; then
  echo -e "${INFO}${YW}Public URL:${CL} ${GATEWAY}${BGN}${var_penpot_public_uri}${CL}"
fi
echo -e "${INFO}${YW}Outgoing mail (registration, invites) is caught by Mailpit:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:8025${CL}"
