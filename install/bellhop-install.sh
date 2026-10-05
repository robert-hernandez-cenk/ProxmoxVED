#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: robert-hernandez-cenk
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/robert-hernandez-cenk/Bellhop

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# npm ci runs node-gyp on better-sqlite3's binding.gyp and fails without a compiler.
msg_info "Installing Dependencies"
$STD apt install -y \
  build-essential \
  python3
msg_ok "Installed Dependencies"

NODE_VERSION="24" setup_nodejs
fetch_and_deploy_gh_release "bellhop" "robert-hernandez-cenk/Bellhop" "tarball"

msg_info "Building Bellhop"
cd /opt/bellhop
$STD npm ci
$STD npm run web:build
msg_ok "Built Bellhop"

msg_info "Configuring Bellhop"
# The inventory database and the data directory live outside /opt/bellhop,
# so an update that replaces the application directory never touches them.
mkdir -p /var/lib/bellhop/inventory /var/lib/bellhop/data
cat <<EOF >/etc/default/bellhop
PORT=3000
INVENTORY_FILE=/var/lib/bellhop/inventory/bellhop.db
WEB_DATA_DIR=/var/lib/bellhop/data
EOF
cat <<'EOF' >/usr/local/bin/bellhop
#!/bin/sh
set -a
. /etc/default/bellhop
set +a
exec node /opt/bellhop/bin/bellhop.js "$@"
EOF
chmod +x /usr/local/bin/bellhop
# Bellhop reaches every Proxmox host over SSH with this key (its default
# ~/.ssh/id_ed25519 lookup); the operator adds the public half to the hosts.
mkdir -p /root/.ssh
chmod 700 /root/.ssh
if [[ ! -f /root/.ssh/id_ed25519 ]]; then
  ssh-keygen -q -t ed25519 -N "" -C "bellhop@$(hostname)" -f /root/.ssh/id_ed25519
fi
msg_ok "Configured Bellhop"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/bellhop.service
[Unit]
Description=Bellhop web UI
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/bellhop
EnvironmentFile=/etc/default/bellhop
ExecStart=/usr/bin/node --import tsx src/web/server.ts
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now bellhop
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
