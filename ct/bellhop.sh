#!/usr/bin/env bash
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: robert-hernandez-cenk
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/robert-hernandez-cenk/Bellhop

APP="Bellhop"
var_tags="${var_tags:-proxmox;homelab;dashboard}"
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

  if [[ ! -d /opt/bellhop ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # The inventory, data directory and SSH key live in /var/lib/bellhop and
  # /root/.ssh, outside /opt/bellhop, so the clean install leaves them alone.
  if check_for_gh_release "bellhop" "robert-hernandez-cenk/Bellhop"; then
    msg_info "Stopping Bellhop"
    systemctl stop bellhop
    msg_ok "Stopped Bellhop"

    NODE_VERSION="24" setup_nodejs
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "bellhop" "robert-hernandez-cenk/Bellhop" "tarball"

    msg_info "Building Bellhop"
    cd /opt/bellhop
    $STD npm ci
    $STD npm run web:build
    msg_ok "Built Bellhop"

    msg_info "Starting Bellhop"
    systemctl start bellhop
    msg_ok "Started Bellhop"
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
echo -e "${INFO}${YW} Add this SSH public key to /root/.ssh/authorized_keys on a Proxmox node (cluster-wide):${CL}"
echo -e "${TAB}${BGN}$(pct exec "$CTID" -- cat /root/.ssh/id_ed25519.pub)${CL}"
echo -e "${INFO}${YW} After importing the inventory, mark this container as Bellhop's own guest:${CL}"
echo -e "${TAB}${BGN}bellhop set-config bellhopGuest $(pct exec "$CTID" -- hostname) --apply${CL}"
echo -e "${INFO}${YW} First-run guide: https://github.com/robert-hernandez-cenk/Bellhop/blob/main/docs/lxc-container.md${CL}"
