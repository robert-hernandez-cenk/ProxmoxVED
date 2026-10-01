#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: robert-hernandez-cenk
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://projectzomboid.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

if [[ -z "${var_pz_build:-}" ]]; then
  var_pz_build=$(prompt_select "Project Zomboid build (42 = current, 41 = legacy):" 1 60 "42" "41")
fi
case "${var_pz_build}" in
  42) PZ_BRANCH="public" ;;
  41) PZ_BRANCH="legacy41" ;;
  *)
    msg_error "Unknown Project Zomboid build '${var_pz_build}' (expected 42 or 41)"
    exit 1
    ;;
esac

msg_info "Installing Dependencies"
$STD apt install -y \
  lib32gcc-s1 \
  lib32stdc++6
msg_ok "Installed Dependencies"

msg_info "Creating Steam User and Application Directories"
useradd --system \
  --create-home \
  --home-dir /home/steam \
  --shell /usr/sbin/nologin \
  steam
mkdir -p /opt/project-zomboid/server /opt/steamcmd
echo "${PZ_BRANCH}" >/opt/project-zomboid/.branch
chown -R steam:steam /opt/project-zomboid /opt/steamcmd /home/steam
msg_ok "Created Steam User and Application Directories"

fetch_and_deploy_from_url \
  "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" \
  "/opt/steamcmd"
chown -R steam:steam /opt/steamcmd

msg_info "Installing Project Zomboid Dedicated Server (${PZ_BRANCH})"
$STD runuser -u steam -- /opt/steamcmd/steamcmd.sh +login anonymous +quit || true
$STD runuser -u steam -- /opt/steamcmd/steamcmd.sh \
  +force_install_dir /opt/project-zomboid/server \
  +login anonymous \
  +app_update 380870 -beta "${PZ_BRANCH}" validate \
  +quit
msg_ok "Installed Project Zomboid Dedicated Server (${PZ_BRANCH})"

msg_info "Configuring Project Zomboid"
PZ_HEAP=$(($(awk '/MemTotal/ {print int($2 / 1024)}' /proc/meminfo) - 1536))
if [[ -f /opt/project-zomboid/server/ProjectZomboid64.json ]]; then
  sed -i -E "s/-Xmx[0-9]+[mMgG]/-Xmx${PZ_HEAP}m/" /opt/project-zomboid/server/ProjectZomboid64.json
fi
ADMIN_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c16)
cat <<EOF >/opt/project-zomboid/.env
PZ_ADMIN_PASSWORD=${ADMIN_PASS}
EOF
chmod 600 /opt/project-zomboid/.env
{
  echo "Project Zomboid Credentials"
  echo "Admin Username: admin"
  echo "Admin Password: ${ADMIN_PASS}"
} >~/project-zomboid.creds
msg_ok "Configured Project Zomboid"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/project-zomboid.socket
[Unit]
Description=Project Zomboid Server Console
BindsTo=project-zomboid.service

[Socket]
ListenFIFO=/run/project-zomboid.stdin
SocketUser=steam
SocketMode=0660
RemoveOnStop=true
EOF
cat <<'EOF' >/etc/systemd/system/project-zomboid.service
[Unit]
Description=Project Zomboid Dedicated Server
Wants=network-online.target
After=network-online.target
Requires=project-zomboid.socket
After=project-zomboid.socket

[Service]
Type=simple
User=steam
Group=steam
WorkingDirectory=/opt/project-zomboid/server
Environment=HOME=/home/steam
EnvironmentFile=/opt/project-zomboid/.env
ExecStart=/opt/project-zomboid/server/start-server.sh -servername servertest -adminusername admin -adminpassword ${PZ_ADMIN_PASSWORD}
ExecStop=/bin/sh -c 'echo quit >/run/project-zomboid.stdin; while kill -0 $MAINPID 2>/dev/null; do sleep 1; done'
StandardInput=socket
StandardOutput=journal
StandardError=journal
Restart=on-failure
RestartSec=10
TimeoutStopSec=180

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now project-zomboid
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
