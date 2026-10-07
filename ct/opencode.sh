#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Robert Hernandez (robert-hernandez-cenk)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/anomalyco/opencode

APP="OpenCode"
var_tags="${var_tags:-ai;dev-tools}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified

export var_opencode_web="${var_opencode_web:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/opencode ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "opencode" "anomalyco/opencode"; then
    msg_info "Stopping OpenCode"
    systemctl stop opencode
    msg_ok "Stopped OpenCode"

    create_backup /opt/opencode/.env

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "opencode" "anomalyco/opencode" "prebuild" "latest" "/opt/opencode" "opencode-linux-$(arch_resolve "x64" "arm64").tar.gz"

    restore_backup

    msg_info "Starting OpenCode"
    systemctl start opencode
    msg_ok "Started OpenCode"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:4096${CL}"
echo -e "${INFO}${YW}Username and password are in /opt/opencode/.env${CL}"
