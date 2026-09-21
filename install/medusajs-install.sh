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

msg_info "Installing Dependencies"
$STD apt install -y redis-server
msg_ok "Installed Dependencies"

PG_VERSION="17" setup_postgresql
PG_DB_NAME="medusa" PG_DB_USER="medusa" PG_DB_SCHEMA_PERMS="true" PG_DB_CREDS_FILE="/root/medusajs.creds" setup_postgresql_db
NODE_VERSION="22" NODE_MODULE="pnpm@10.11.1" setup_nodejs

# Medusa is a framework, not a released artifact: upstream ships no deployable
# tarball, and create-medusa-app prompts for a storefront even with --skip-db,
# emits telemetry and hands back an invite token instead of a usable admin. The
# starter it clones is deployed directly instead, the way the official Docker
# guide does it. dtc-starter tracks the current release, so its pins are the
# installed version; medusa-starter-default is the legacy layout and lags.
fetch_and_deploy_gh_branch "medusajs" "medusajs/dtc-starter" "main"

msg_info "Setting up Medusa"
cd /opt/medusajs
# Headless: the Next.js storefront is a second app with its own build and is
# not what this container serves.
rm -rf apps/storefront
# jq is present: setup_nodejs installs it.
MEDUSA_VERSION="$(jq -r '.dependencies["@medusajs/medusa"]' apps/backend/package.json)"
# fetch_and_deploy_gh_branch leaves a commit sha here, but updates track the
# Medusa release the packages are pinned to, not the starter's git history.
echo "$MEDUSA_VERSION" >~/.medusajs
# The lockfile still lists the storefront workspace that was just removed.
$STD pnpm install --no-frozen-lockfile
msg_ok "Set up Medusa"

msg_info "Configuring Medusa"
cd /opt/medusajs/apps/backend
ADMIN_EMAIL="admin@medusa.local"
ADMIN_PASSWORD="$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c 16)"
cat <<EOF >/opt/medusajs/apps/backend/.env
DATABASE_URL=postgres://${PG_DB_USER}:${PG_DB_PASS}@127.0.0.1:5432/${PG_DB_NAME}
REDIS_URL=redis://127.0.0.1:6379
JWT_SECRET=$(openssl rand -hex 32)
COOKIE_SECRET=$(openssl rand -hex 32)
AUTH_MFA_ENCRYPTION_KEY=$(openssl rand -hex 32)
STORE_CORS=http://${LOCAL_IP}:9000
ADMIN_CORS=http://${LOCAL_IP}:9000
AUTH_CORS=http://${LOCAL_IP}:9000
HOST=0.0.0.0
PORT=9000
MEDUSA_DISABLE_TELEMETRY=1
EOF
chmod 600 /opt/medusajs/apps/backend/.env
# The starter's config carries only the database and CORS settings. Everything
# added here is what a production start on a LAN address needs.
cat <<'EOF' >/opt/medusajs/apps/backend/medusa-config.ts
import { loadEnv, defineConfig } from '@medusajs/framework/utils'

loadEnv(process.env.NODE_ENV || 'development', process.cwd())

module.exports = defineConfig({
  projectConfig: {
    databaseUrl: process.env.DATABASE_URL,
    // Sessions are kept in Redis; without this they are in-memory and every
    // restart logs everyone out.
    redisUrl: process.env.REDIS_URL,
    // One container runs the API and the job workers together.
    workerMode: 'shared',
    // The built application starts with NODE_ENV=production, where Medusa's
    // cookies default to Secure and a same-site domain. Over plain HTTP on an
    // IP that blocks the admin login outright. Tighten these once a TLS
    // reverse proxy fronts the container.
    cookieOptions: {
      sameSite: 'lax',
      secure: false,
    },
    http: {
      storeCors: process.env.STORE_CORS!,
      adminCors: process.env.ADMIN_CORS!,
      authCors: process.env.AUTH_CORS!,
      jwtSecret: process.env.JWT_SECRET,
      cookieSecret: process.env.COOKIE_SECRET,
    },
  },
  // The defaults are the local event bus and the in-memory workflow engine,
  // both of which upstream marks as unsuitable for production: queued events
  // and in-flight workflow state are lost on restart. The other infrastructure
  // modules keep their single-node defaults. Both resolve through
  // @medusajs/medusa itself, so they need no extra dependency.
  modules: [
    {
      resolve: '@medusajs/medusa/event-bus-redis',
      options: {
        redisUrl: process.env.REDIS_URL,
      },
    },
    {
      resolve: '@medusajs/medusa/workflow-engine-redis',
      options: {
        redis: {
          redisUrl: process.env.REDIS_URL,
        },
      },
    },
  ],
})
EOF
msg_ok "Configured Medusa"

msg_info "Preparing Database"
set -a
source /opt/medusajs/apps/backend/.env
set +a
# --execute-all-links answers the prompts this would otherwise raise for link
# changes. The starter's src/migration-scripts run here too, seeding the
# default sales channel, publishable key, regions and demo catalog; without
# them the Store API has nothing to serve.
$STD pnpm exec medusa db:migrate --execute-all-links
msg_ok "Prepared Database"

msg_info "Creating Admin User"
$STD pnpm exec medusa user --email "$ADMIN_EMAIL" --password "$ADMIN_PASSWORD"
{
  echo "Medusa Admin Credentials"
  echo "Email: $ADMIN_EMAIL"
  echo "Password: $ADMIN_PASSWORD"
} >>/root/medusajs.creds
chmod 600 /root/medusajs.creds
msg_ok "Created Admin User"

msg_info "Building Medusa"
# NODE_ENV stays unset: build reads .env, and the admin bundle inlines what it
# finds. Linting is the starter's dev-time check, not a deployment step.
export NODE_OPTIONS="--max-old-space-size=3072"
$STD pnpm exec medusa build --no-lint
unset NODE_OPTIONS
# .medusa/server carries its own copy of package.json and installs standalone,
# outside the pnpm workspace; upstream's build guide uses npm for it.
cd /opt/medusajs/apps/backend/.medusa/server
$STD npm install --legacy-peer-deps --no-audit --no-fund
msg_ok "Built Medusa"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/medusajs.service
[Unit]
Description=Medusa
Wants=network-online.target
After=network-online.target postgresql.service redis-server.service
Requires=postgresql.service redis-server.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/medusajs/apps/backend/.medusa/server
EnvironmentFile=/opt/medusajs/apps/backend/.env
Environment=NODE_ENV=production
# In production Medusa reads .env.production from the build output, which each
# build recreates. Copying on every start keeps the .env above the one file
# worth editing, and keeps it surviving rebuilds.
ExecStartPre=/bin/cp /opt/medusajs/apps/backend/.env /opt/medusajs/apps/backend/.medusa/server/.env.production
ExecStart=/opt/medusajs/apps/backend/.medusa/server/node_modules/.bin/medusa start
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now medusajs
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
