#!/usr/bin/env bash
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: robert-hernandez-cenk
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://projectzomboid.com/

APP="Project-Zomboid"
var_tags="${var_tags:-gaming;server}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"
export var_pz_build="${var_pz_build:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -x /opt/steamcmd/steamcmd.sh || ! -f /opt/project-zomboid/.branch ]]; then
    msg_error "No Project Zomboid Installation Found!"
    exit
  fi
  PZ_BRANCH=$(cat /opt/project-zomboid/.branch)

  msg_info "Stopping Project Zomboid"
  systemctl stop project-zomboid
  msg_ok "Stopped Project Zomboid"

  create_backup /home/steam/Zomboid

  msg_info "Updating Project Zomboid (${PZ_BRANCH})"
  $STD runuser -u steam -- /opt/steamcmd/steamcmd.sh +login anonymous +quit || true
  if $STD runuser -u steam -- /opt/steamcmd/steamcmd.sh \
    +force_install_dir /opt/project-zomboid/server \
    +login anonymous \
    +app_update 380870 -beta "${PZ_BRANCH}" validate \
    +quit; then
    msg_ok "Updated Project Zomboid (${PZ_BRANCH})"
  else
    restore_backup
    systemctl start project-zomboid
    msg_error "Failed to update Project Zomboid"
    exit 1
  fi

  restore_backup

  PZ_HEAP=$(($(awk '/MemTotal/ {print int($2 / 1024)}' /proc/meminfo) - 1536))
  if [[ -f /opt/project-zomboid/server/ProjectZomboid64.json ]]; then
    sed -i -E "s/-Xmx[0-9]+[mMgG]/-Xmx${PZ_HEAP}m/" /opt/project-zomboid/server/ProjectZomboid64.json
  fi

  msg_info "Starting Project Zomboid"
  systemctl start project-zomboid
  msg_ok "Started Project Zomboid"
  msg_ok "Updated Successfully!"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Connect from the game's Join menu:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}${IP}:16261${CL}"
echo -e "${INFO}${YW} Required ports:${CL} ${BGN}16261-16262 UDP${CL}"
echo -e "${INFO}${YW} Admin credentials:${CL} ${BGN}cat ~/project-zomboid.creds${CL}"
