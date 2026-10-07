#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: robert-hernandez-cenk
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/DaKheera47/job-ops

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# python3 and build-essential: npm runs node-gyp on native workspace dependencies.
# The GTK/dbus/asound/xt libraries are what the Playwright and Camoufox Firefox builds link against.
# xvfb, x11vnc, novnc and websockify serve the Cloudflare challenge viewer, which the app starts on demand.
msg_info "Installing Dependencies"
$STD apt install -y \
  build-essential \
  pkg-config \
  python3 \
  xz-utils \
  libgtk-3-0t64 \
  libdbus-glib-1-2 \
  libxt6t64 \
  libx11-xcb1 \
  libasound2t64 \
  xvfb \
  x11vnc \
  novnc \
  websockify
msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs
PYTHON_VERSION="3.12" setup_uv

# Upstream pins Tectonic 0.15.0 in its Dockerfile. Tectonic's "latest" release is a rolling
# "continuous" build with date-versioned assets, so the tag is named explicitly.
fetch_and_deploy_gh_release "tectonic" "tectonic-typesetting/tectonic" "prebuild" "tectonic@0.15.0" "/opt/tectonic" "tectonic-0.15.0-$(arch_resolve "x86_64-unknown-linux-gnu" "aarch64-unknown-linux-musl").tar.gz"
ln -sf /opt/tectonic/tectonic /usr/local/bin/tectonic
fetch_and_deploy_gh_release "typst" "typst/typst" "prebuild" "latest" "/opt/typst" "typst-$(arch_resolve "x86_64" "aarch64")-unknown-linux-musl.tar.xz"
ln -sf /opt/typst/typst /usr/local/bin/typst

msg_info "Installing Codex and Claude Code CLIs"
$STD npm install -g @openai/codex @anthropic-ai/claude-code
msg_ok "Installed Codex and Claude Code CLIs"

fetch_and_deploy_gh_release "job-ops" "DaKheera47/job-ops" "tarball"

msg_info "Building Job Ops"
cd /opt/job-ops
$STD npm install --workspaces --include-workspace-root --include=dev --no-audit --no-fund --progress=false
cd /opt/job-ops/orchestrator
$STD npm run build:client
cd /opt/job-ops/docs-site
$STD npm run build
cp -r /opt/job-ops/docs-site/build /opt/job-ops/orchestrator/dist/docs
msg_ok "Built Job Ops"

msg_info "Installing JobSpy and Browsers"
$STD uv venv /opt/job-ops/.venv
$STD uv pip install -p /opt/job-ops/.venv/bin/python -r /opt/job-ops/extractors/jobspy/requirements.txt playwright
PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright $STD /opt/job-ops/.venv/bin/playwright install firefox
cd /opt/job-ops
$STD node ./scripts/camoufox-fetch.mjs
msg_ok "Installed JobSpy and Browsers"

msg_info "Configuring Job Ops"
mkdir -p /var/lib/job-ops/{pdfs,cloudflare-cookies,codex-home}
cp /opt/job-ops/.env.example /opt/job-ops/.env
msg_ok "Configured Job Ops"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/job-ops.service
[Unit]
Description=Job Ops
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/job-ops/orchestrator
Environment=NODE_ENV=production
Environment=PORT=3005
Environment=PYTHON_PATH=/opt/job-ops/.venv/bin/python
Environment=DATA_DIR=/var/lib/job-ops
Environment=CODEX_HOME=/var/lib/job-ops/codex-home
Environment=PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright
Environment=DISPLAY=:99
Environment=NOVNC_PORT=6080
Environment=NOVNC_HOST=127.0.0.1
Environment=VNC_HOST=127.0.0.1
EnvironmentFile=/opt/job-ops/.env
ExecStartPre=/usr/bin/npx tsx src/server/db/migrate.ts
ExecStart=/usr/bin/npm run start
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now job-ops
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
