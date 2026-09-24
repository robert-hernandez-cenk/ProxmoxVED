#!/usr/bin/env bash
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: robert-hernandez-cenk
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://medusajs.com/

APP="MedusaJS-Storefront"
var_tags="${var_tags:-ecommerce;storefront}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-12}"
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

  if [[ ! -f /opt/medusajs-storefront/apps/storefront/.env ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # The storefront exists to be customized, so an update must never re-fetch
  # the starter and overwrite apps/storefront/src. As on the backend, an
  # update is a version bump of the Medusa packages around the user's code.
  if check_for_gh_release "medusajs-storefront" "medusajs/medusa"; then
    # A container that installed through the skipped build gate has a .env
    # that makes next.config.js exit at module load, so pnpm build would fail
    # here too. Check before stopping anything, so a declined update changes
    # nothing at all.
    set -a
    source /opt/medusajs-storefront/apps/storefront/.env
    set +a
    if [[ -z "$NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY" ]] || ! curl -fsS --max-time 10 "${NEXT_PUBLIC_MEDUSA_BACKEND_URL}/health" >/dev/null 2>&1; then
      msg_warn "Storefront cannot be updated until it is configured: set NEXT_PUBLIC_MEDUSA_BACKEND_URL and NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY in /opt/medusajs-storefront/apps/storefront/.env, then run medusajs-storefront-rebuild"
      exit
    fi

    msg_info "Stopping Storefront"
    systemctl stop medusajs-storefront
    msg_ok "Stopped Storefront"

    NEW_VERSION="${CHECK_UPDATE_RELEASE#v}"
    OLD_VERSION="$(<~/.medusajs-storefront)"

    msg_info "Updating Storefront to ${NEW_VERSION}"
    cd /opt/medusajs-storefront
    # Only pins that match the installed version are rewritten, which leaves
    # independently versioned packages such as @medusajs/ui alone.
    sed -i -E "/\"@medusajs\//s/\"${OLD_VERSION}\"/\"${NEW_VERSION}\"/" \
      package.json apps/storefront/package.json
    $STD pnpm install --no-frozen-lockfile
    msg_ok "Updated Storefront to ${NEW_VERSION}"

    msg_info "Rebuilding Storefront"
    # Every NEXT_PUBLIC_* value is inlined into the bundle at build time, so a
    # rebuild is what makes any change take effect.
    cd /opt/medusajs-storefront/apps/storefront
    export NODE_OPTIONS="--max-old-space-size=3072"
    $STD pnpm build
    unset NODE_OPTIONS
    # Written only after the build succeeds, matching the backend script: a
    # failed build aborts via catch_errors, and marking this version current
    # anyway would make the update never retry, leaving the storefront
    # stopped and unbuilt but silently reported as up to date.
    echo "$NEW_VERSION" >~/.medusajs-storefront
    msg_ok "Rebuilt Storefront"

    msg_info "Starting Storefront"
    # enable, not just start: the install script only enables the unit once a
    # build succeeds, so a container that installed unbuilt reaches its first
    # successful update with the unit still disabled.
    systemctl enable -q --now medusajs-storefront
    msg_ok "Started Storefront"
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
echo -e "${GATEWAY}${BGN}http://${IP}:8000${CL}"
