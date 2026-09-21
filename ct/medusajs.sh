#!/usr/bin/env bash
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: robert-hernandez-cenk
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://medusajs.com/

APP="Medusa"
var_tags="${var_tags:-ecommerce;commerce}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-15}"
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

  if [[ ! -f /opt/medusajs/apps/backend/.env ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # Every Medusa package ships on the release's version, so the monorepo's tag
  # is the version of the installed packages even though the application was
  # scaffolded from the starter rather than deployed from that repo.
  if check_for_gh_release "medusajs" "medusajs/medusa"; then
    msg_info "Stopping Medusa"
    systemctl stop medusajs
    msg_ok "Stopped Medusa"

    NEW_VERSION="${CHECK_UPDATE_RELEASE#v}"
    OLD_VERSION="$(<~/.medusajs)"

    msg_info "Updating Medusa to ${NEW_VERSION}"
    cd /opt/medusajs
    # Nothing is re-fetched: the application's own code in apps/backend/src is
    # the user's, and an update is a version bump of the packages around it.
    # Only pins that match the installed version are rewritten, which leaves
    # the independently versioned design system (@medusajs/ui) alone.
    sed -i -E "/\"@medusajs\//s/\"${OLD_VERSION}\"/\"${NEW_VERSION}\"/" \
      package.json apps/backend/package.json
    $STD pnpm install --no-frozen-lockfile
    msg_ok "Updated Medusa to ${NEW_VERSION}"

    msg_info "Migrating Database"
    cd /opt/medusajs/apps/backend
    set -a
    source /opt/medusajs/apps/backend/.env
    set +a
    $STD pnpm exec medusa db:migrate --execute-all-links
    msg_ok "Migrated Database"

    msg_info "Rebuilding Medusa"
    # .medusa/server is recreated by every build, so its dependencies have to
    # be installed again each time. The service copies .env.production in on
    # start, so that file needs nothing here.
    export NODE_OPTIONS="--max-old-space-size=3072"
    $STD pnpm exec medusa build --no-lint
    unset NODE_OPTIONS
    cd /opt/medusajs/apps/backend/.medusa/server
    $STD npm install --legacy-peer-deps --no-audit --no-fund
    echo "$NEW_VERSION" >~/.medusajs
    msg_ok "Rebuilt Medusa"

    msg_info "Starting Medusa"
    systemctl start medusajs
    msg_ok "Started Medusa"
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
echo -e "${GATEWAY}${BGN}http://${IP}:9000/app${CL}"
