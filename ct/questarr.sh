#!/usr/bin/env bash
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: robert-hernandez-cenk
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Doezer/Questarr

APP="Questarr"
var_tags="${var_tags:-arr;games;downloads}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-6}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/questarr ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "questarr" "Doezer/Questarr"; then
    msg_info "Stopping Questarr"
    systemctl stop questarr
    msg_ok "Stopped Questarr"

    create_backup /opt/questarr/.env /opt/questarr/data

    NODE_VERSION="22" setup_nodejs
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "questarr" "Doezer/Questarr" "tarball"

    restore_backup

    msg_info "Building Questarr"
    cd /opt/questarr
    $STD npm ci --no-audit --no-fund --ignore-scripts
    $STD npm rebuild better-sqlite3
    $STD npm run build
    $STD npm prune --omit=dev --ignore-scripts --no-audit --no-fund
    msg_ok "Built Questarr"

    msg_info "Starting Questarr"
    systemctl start questarr
    msg_ok "Started Questarr"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:5000${CL}"
