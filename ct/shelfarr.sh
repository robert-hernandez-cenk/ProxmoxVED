#!/usr/bin/env bash
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: robert-hernandez-cenk
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://shelfarr.org/

APP="Shelfarr"
var_tags="${var_tags:-books;audiobooks;arr}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
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

  if [[ ! -f /opt/shelfarr/.env ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "shelfarr" "Pedro-Revez-Silva/shelfarr"; then
    msg_info "Stopping Shelfarr"
    systemctl stop shelfarr
    msg_ok "Stopped Shelfarr"

    create_backup /opt/shelfarr/.env /opt/shelfarr/storage

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "shelfarr" "Pedro-Revez-Silva/shelfarr" "tarball"

    RUBY_VERSION=$(tr -d ' \n' </opt/shelfarr/.ruby-version)
    RUBY_VERSION="${RUBY_VERSION}" RUBY_INSTALL_RAILS="false" setup_ruby
    export PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH"

    restore_backup

    msg_info "Updating Shelfarr"
    cd /opt/shelfarr
    $STD bundle config set --local without 'development test'
    $STD bundle config set --local deployment 'true'
    $STD bundle install
    RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 $STD bundle exec rails assets:precompile
    set -a
    source /opt/shelfarr/.env
    set +a
    $STD bundle exec rails db:prepare
    $STD bundle exec rails runner 'SettingsService.seed_defaults!'
    msg_ok "Updated Shelfarr"

    msg_info "Starting Shelfarr"
    systemctl start shelfarr
    msg_ok "Started Shelfarr"
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
echo -e "${GATEWAY}${BGN}http://${IP}:5056${CL}"
