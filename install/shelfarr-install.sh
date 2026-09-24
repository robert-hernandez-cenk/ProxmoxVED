#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: robert-hernandez-cenk
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://shelfarr.org/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  build-essential \
  ffmpeg \
  git \
  libsqlite3-dev \
  libvips42 \
  libyaml-dev \
  pkg-config \
  sqlite3
msg_ok "Installed Dependencies"

fetch_and_deploy_gh_release "shelfarr" "Pedro-Revez-Silva/shelfarr" "tarball"

RUBY_VERSION=$(tr -d ' \n' </opt/shelfarr/.ruby-version)
RUBY_VERSION="${RUBY_VERSION}" RUBY_INSTALL_RAILS="false" setup_ruby
export PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH"

msg_info "Installing Application Dependencies"
cd /opt/shelfarr
$STD bundle config set --local without 'development test'
$STD bundle config set --local deployment 'true'
$STD bundle install
msg_ok "Installed Application Dependencies"

msg_info "Configuring Shelfarr"
mkdir -p /opt/shelfarr/storage
# The upstream image generates these on first boot in bin/docker-entrypoint and
# keeps them in the storage volume; here they are written once into .env.
cat <<EOF >/opt/shelfarr/.env
RAILS_ENV=production
PORT=5056
SOLID_QUEUE_IN_PUMA=1
SECRET_KEY_BASE=$(openssl rand -hex 64)
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=$(openssl rand -hex 32)
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=$(openssl rand -hex 32)
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=$(openssl rand -hex 32)
EOF
chmod 640 /opt/shelfarr/.env
msg_ok "Configured Shelfarr"

msg_info "Precompiling Assets"
RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 $STD bundle exec rails assets:precompile
msg_ok "Precompiled Assets"

msg_info "Preparing Database"
set -a
source /opt/shelfarr/.env
set +a
$STD bundle exec rails db:prepare
$STD bundle exec rails runner 'SettingsService.seed_defaults!'
msg_ok "Prepared Database"

msg_info "Creating Service"
# Thruster, the image's default front end, is skipped: it only adds asset
# caching and X-Sendfile in front of the same Puma. SOLID_QUEUE_IN_PUMA lets
# Puma supervise the job workers, so one unit covers web and background work.
cat <<EOF >/etc/systemd/system/shelfarr.service
[Unit]
Description=Shelfarr Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/shelfarr
EnvironmentFile=/opt/shelfarr/.env
Environment=PATH=/root/.rbenv/shims:/root/.rbenv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/root/.rbenv/shims/bundle exec puma -C config/puma.rb
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now shelfarr
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
