#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: robert-hernandez-cenk
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/applypack/applypack

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

NODE_VERSION="24" setup_nodejs
PG_VERSION="16" setup_postgresql
PG_DB_NAME="applypack" PG_DB_USER="applypack" setup_postgresql_db

fetch_and_deploy_gh_release "applypack" "applypack/applypack" "tarball"

msg_info "Building ApplyPack"
cd /opt/applypack
$STD npm ci --no-audit --no-fund --progress=false
$STD npm run build
msg_ok "Built ApplyPack"

msg_info "Installing AI Engine CLIs"
$STD npm install -g @anthropic-ai/claude-code @google/gemini-cli @openai/codex
msg_ok "Installed AI Engine CLIs"

# Upstream binds the dashboard to loopback; WEB_HOST=0.0.0.0 makes it reachable from the LAN.
msg_info "Configuring ApplyPack"
cp /opt/applypack/.env.example /opt/applypack/.env
sed -i 's|^WEB_HOST=.*|WEB_HOST=0.0.0.0|' /opt/applypack/.env
cat <<EOF >>/opt/applypack/.env

DATABASE_URL=postgresql://${PG_DB_USER}:${PG_DB_PASS}@127.0.0.1:5432/${PG_DB_NAME}
NODE_ENV=production
EOF
msg_ok "Configured ApplyPack"

# The worker runs prisma migrate deploy on start, so the dashboard starts after it.
msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/applypack.service
[Unit]
Description=ApplyPack Worker
After=network-online.target postgresql.service
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/applypack
EnvironmentFile=/opt/applypack/.env
ExecStart=/usr/bin/node dist/index.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
cat <<EOF >/etc/systemd/system/applypack-web.service
[Unit]
Description=ApplyPack Dashboard
After=applypack.service postgresql.service
Wants=applypack.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/applypack
EnvironmentFile=/opt/applypack/.env
ExecStart=/usr/bin/node dist/web/server.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now applypack applypack-web
msg_ok "Created Services"

motd_ssh
customize
cleanup_lxc
