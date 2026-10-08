#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: robert-hernandez-cenk
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Doezer/Questarr

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# npm runs node-gyp configure for better-sqlite3 even when a prebuilt binary exists,
# which needs a toolchain and Python (same reason the Dockerfile adds g++, make, python3).
# 7zip is what the Dockerfile installs for archive extraction.
msg_info "Installing Dependencies"
$STD apt install -y \
  build-essential \
  python3 \
  7zip
msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs

fetch_and_deploy_gh_release "questarr" "Doezer/Questarr" "tarball"

msg_info "Building Questarr"
cd /opt/questarr
$STD npm ci --no-audit --no-fund --ignore-scripts
$STD npm rebuild better-sqlite3
$STD npm run build
$STD npm prune --omit=dev --ignore-scripts --no-audit --no-fund
msg_ok "Built Questarr"

msg_info "Configuring Questarr"
mkdir -p /opt/questarr/data
cat <<EOF >/opt/questarr/.env
NODE_ENV=production
PORT=5000
SQLITE_DB_PATH=/opt/questarr/data/sqlite.db
EOF
msg_ok "Configured Questarr"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/questarr.service
[Unit]
Description=Questarr
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/questarr
EnvironmentFile=/opt/questarr/.env
ExecStart=/usr/bin/node dist/server/index.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now questarr
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
