#!/usr/bin/env bash
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: robert-hernandez-cenk
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/applypack/applypack

APP="ApplyPack"
var_tags="${var_tags:-jobs;career;ai}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
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

  if [[ ! -d /opt/applypack ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # The database lives in PostgreSQL; the worker applies pending migrations when it starts.
  if check_for_gh_release "applypack" "applypack/applypack"; then
    msg_info "Stopping ApplyPack"
    systemctl stop applypack-web applypack
    msg_ok "Stopped ApplyPack"

    create_backup /opt/applypack/.env

    NODE_VERSION="24" setup_nodejs
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "applypack" "applypack/applypack" "tarball"

    restore_backup

    msg_info "Building ApplyPack"
    cd /opt/applypack
    $STD npm ci --no-audit --no-fund --progress=false
    $STD npm run build
    msg_ok "Built ApplyPack"

    msg_info "Updating AI Engine CLIs"
    $STD npm install -g @anthropic-ai/claude-code @google/gemini-cli @openai/codex
    msg_ok "Updated AI Engine CLIs"

    msg_info "Starting ApplyPack"
    systemctl start applypack applypack-web
    msg_ok "Started ApplyPack"
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:4747${CL}"
echo -e "${INFO}${YW} ApplyPack has no sign-in until you set WEB_BASIC_AUTH=user:password in /opt/applypack/.env${CL}"
