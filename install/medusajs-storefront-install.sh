#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: robert-hernandez-cenk
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://medusajs.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# No database and no Redis: the storefront is stateless and reads everything
# from the Medusa backend's Store API.
NODE_VERSION="22" NODE_MODULE="pnpm@10.11.1" setup_nodejs

# The storefront is the second app of the same monorepo the MedusaJS script
# deploys. medusajs/nextjs-starter-medusa, the standalone starter, was
# archived in April 2026, so this is the only source tracking current
# releases.
fetch_and_deploy_gh_branch "medusajs-storefront" "medusajs/dtc-starter" "main"

msg_info "Setting up Storefront"
cd /opt/medusajs-storefront
# Mirror of what the MedusaJS script does to apps/storefront: this container
# serves the frontend, and the backend is a separate deployment.
rm -rf apps/backend
# jq is present: setup_nodejs installs it.
MEDUSA_VERSION="$(jq -r '.dependencies["@medusajs/js-sdk"]' apps/storefront/package.json)"
# fetch_and_deploy_gh_branch leaves a commit sha in ~/.medusajs-storefront, but
# updates track the Medusa release the SDK is pinned to, not the starter's git
# history. This must come after that call, which writes the file.
echo "$MEDUSA_VERSION" >~/.medusajs-storefront
# The lockfile still lists the backend workspace that was just removed.
$STD pnpm install --no-frozen-lockfile
msg_ok "Set up Storefront"

msg_info "Configuring Storefront"
# Every value here is baked into the bundle at build time, so these are read
# from the environment at install and changed later only via a rebuild.
BACKEND_URL="${MEDUSA_BACKEND_URL:-http://localhost:9000}"
PUBLISHABLE_KEY="${MEDUSA_PUBLISHABLE_KEY:-}"
DEFAULT_REGION="${MEDUSA_DEFAULT_REGION:-us}"
BASE_URL="${STOREFRONT_BASE_URL:-http://${LOCAL_IP}:8000}"
# NODE_ENV is deliberately absent: Next warns about a non-standard NODE_ENV in
# .env, and the service sets it instead.
cat <<EOF >/opt/medusajs-storefront/apps/storefront/.env
NEXT_PUBLIC_MEDUSA_BACKEND_URL=${BACKEND_URL}
NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY=${PUBLISHABLE_KEY}
NEXT_PUBLIC_DEFAULT_REGION=${DEFAULT_REGION}
NEXT_PUBLIC_BASE_URL=${BASE_URL}
EOF
msg_ok "Configured Storefront"

msg_info "Creating Rebuild Helper"
cat <<'EOF' >/usr/local/bin/medusajs-storefront-rebuild
#!/usr/bin/env bash
# Rebuild the storefront after editing its .env.
# Every NEXT_PUBLIC_* value is inlined into the bundle at build time, so a
# configuration change needs a rebuild; restarting alone keeps serving the old
# values, which looks exactly like the change not taking effect.
set -euo pipefail
cd /opt/medusajs-storefront/apps/storefront
export NODE_OPTIONS="--max-old-space-size=3072"
pnpm build
systemctl enable -q --now medusajs-storefront && systemctl restart medusajs-storefront
echo "Storefront rebuilt and restarted."
EOF
chmod +x /usr/local/bin/medusajs-storefront-rebuild
msg_ok "Created Rebuild Helper"

msg_info "Creating Service"
# The binary is addressed directly rather than through pnpm, because pnpm's
# location depends on how Node was installed while the workspace .bin is not.
cat <<EOF >/etc/systemd/system/medusajs-storefront.service
[Unit]
Description=Medusa Storefront
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/medusajs-storefront/apps/storefront
EnvironmentFile=/opt/medusajs-storefront/apps/storefront/.env
Environment=NODE_ENV=production
ExecStart=/opt/medusajs-storefront/apps/storefront/node_modules/.bin/next start -p 8000
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
msg_ok "Created Service"

# next.config.js runs check-env-variables at module load and exits when the
# publishable key is empty -- and it is loaded by `next build` and `next start`
# alike. The build also statically generates the region and country routes by
# fetching the backend. So a key and a reachable backend are real
# preconditions, not conveniences: without them the install still lays
# everything down, but the build is skipped rather than failing deep inside
# Next with a misleading error.
if [[ -n "$PUBLISHABLE_KEY" ]] && curl -fsS --max-time 10 "${BACKEND_URL}/health" >/dev/null 2>&1; then
  msg_info "Building Storefront"
  cd /opt/medusajs-storefront/apps/storefront
  export NODE_OPTIONS="--max-old-space-size=3072"
  $STD pnpm build
  unset NODE_OPTIONS
  systemctl enable -q --now medusajs-storefront
  msg_ok "Built Storefront"
else
  msg_warn "Storefront not built: set NEXT_PUBLIC_MEDUSA_BACKEND_URL and NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY in /opt/medusajs-storefront/apps/storefront/.env, then run medusajs-storefront-rebuild"
fi

motd_ssh
customize
cleanup_lxc
