#!/usr/bin/env bash
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: robert-hernandez-cenk
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/DaKheera47/job-ops

APP="Job Ops"
var_tags="${var_tags:-jobs;career;ai}"
var_cpu="${var_cpu:-4}"
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

  if [[ ! -d /opt/job-ops ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # The database, PDFs and Codex login live in /var/lib/job-ops, outside /opt/job-ops,
  # so only the .env needs backing up around the clean install.
  if check_for_gh_release "job-ops" "DaKheera47/job-ops"; then
    msg_info "Stopping Job Ops"
    systemctl stop job-ops
    msg_ok "Stopped Job Ops"

    create_backup /opt/job-ops/.env

    NODE_VERSION="22" setup_nodejs
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "job-ops" "DaKheera47/job-ops" "tarball"

    restore_backup

    msg_info "Building Job Ops"
    cd /opt/job-ops
    $STD npm install --workspaces --include-workspace-root --include=dev --no-audit --no-fund --progress=false
    cd /opt/job-ops/orchestrator
    $STD npm run build:client
    cd /opt/job-ops/docs-site
    $STD npm run build
    cp -r /opt/job-ops/docs-site/build /opt/job-ops/orchestrator/dist/docs
    msg_ok "Built Job Ops"

    msg_info "Updating JobSpy and Browsers"
    $STD uv venv /opt/job-ops/.venv
    $STD uv pip install -p /opt/job-ops/.venv/bin/python -r /opt/job-ops/extractors/jobspy/requirements.txt playwright
    PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright $STD /opt/job-ops/.venv/bin/playwright install firefox
    cd /opt/job-ops
    $STD node ./scripts/camoufox-fetch.mjs
    msg_ok "Updated JobSpy and Browsers"

    fetch_and_deploy_gh_release "typst" "typst/typst" "prebuild" "latest" "/opt/typst" "typst-$(arch_resolve "x86_64" "aarch64")-unknown-linux-musl.tar.xz"

    msg_info "Updating Codex and Claude Code CLIs"
    $STD npm install -g @openai/codex @anthropic-ai/claude-code
    msg_ok "Updated Codex and Claude Code CLIs"

    msg_info "Starting Job Ops"
    systemctl start job-ops
    msg_ok "Started Job Ops"
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3005${CL}"
echo -e "${INFO}${YW} Job Ops has no sign-in until you set BASIC_AUTH_USER and BASIC_AUTH_PASSWORD in /opt/job-ops/.env${CL}"
