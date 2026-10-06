#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Robert Hernandez (robert-hernandez-cenk)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/anomalyco/opencode

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

if [[ -z "${var_opencode_web:-}" ]]; then
  if prompt_confirm "Enable the OpenCode web UI? (No runs the headless API server only)" "y"; then
    var_opencode_web="yes"
  else
    var_opencode_web="no"
  fi
fi

fetch_and_deploy_gh_release "opencode" "anomalyco/opencode" "prebuild" "latest" "/opt/opencode" "opencode-linux-$(arch_resolve "x64" "arm64").tar.gz"
ln -sf /opt/opencode/opencode /usr/local/bin/opencode

msg_info "Configuring OpenCode"
cat <<EOF2 >/opt/opencode/.env
OPENCODE_SERVER_USERNAME=opencode
OPENCODE_SERVER_PASSWORD=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-16)
EOF2
msg_ok "Configured OpenCode"

msg_info "Creating Service"
if [[ "${var_opencode_web}" == "yes" ]]; then
  OPENCODE_CMD="web"
else
  OPENCODE_CMD="serve"
fi
cat <<EOF >/etc/systemd/system/opencode.service
[Unit]
Description=OpenCode Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root
EnvironmentFile=/opt/opencode/.env
ExecStart=/opt/opencode/opencode ${OPENCODE_CMD} --hostname 0.0.0.0 --port 4096
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now opencode
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
