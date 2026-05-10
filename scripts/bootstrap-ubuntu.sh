#!/usr/bin/env bash

set -euo pipefail

# Bootstrap a fresh Ubuntu 24.04 Hetzner server for the LiteLLM setup.
# This script is intended for a small single-purpose host and makes a few
# deliberate security/convenience tradeoffs documented inline below.

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this script with sudo or as root." >&2
  exit 1
fi

APP_USER="${APP_USER:-litellm}"
APP_HOME="/home/${APP_USER}"
APP_DIR="${APP_HOME}/litellm"

if ! id "${APP_USER}" >/dev/null 2>&1; then
  echo "User ${APP_USER} does not exist. Create it first." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

apt update
apt install -y ca-certificates curl gnupg lsb-release ufw

# Keep SSH reachable before enabling the firewall.
# `ufw allow OpenSSH` opens the standard SSH service port so remote admin
# access continues to work after UFW is enabled. Without this, enabling UFW on
# a remote box can lock you out.
ufw allow OpenSSH
ufw --force enable

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Adding the app user to the `docker` group allows running Docker without
# `sudo`, which is convenient for day-to-day operations on this single-purpose
# server. Be aware that Docker group access is effectively root-equivalent.
usermod -aG docker "${APP_USER}"

install -d -o "${APP_USER}" -g "${APP_USER}" "${APP_DIR}"
install -d -o "${APP_USER}" -g "${APP_USER}" "${APP_DIR}/config"

echo "Bootstrap complete."
echo "Log out and back in before using docker without sudo."
