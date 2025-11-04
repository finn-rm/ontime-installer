#!/bin/bash
set -e

echo "=== Ontime Uninstall ==="

# ────────────────────────────────────────────────────────────────
# Load configuration from config.json
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.json"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ Config file not found: $CONFIG_FILE"
  exit 1
fi

APP_DIR=$(jq -r '.app_dir // "/app"' "$CONFIG_FILE")
DATA_DIR=$(jq -r '.data_dir // "/data"' "$CONFIG_FILE")
SYSTEMD_SERVICE_FILE="/etc/systemd/system/ontime.service"
USER_NAME="${SUDO_USER:-$USER}"

# Stop service
sudo systemctl stop ontime.service || true
sudo systemctl disable ontime.service || true
sudo rm -f "$SYSTEMD_SERVICE_FILE"
sudo systemctl daemon-reload

# Remove proxy settings
echo "Removing proxy settings..."
# Remove git global proxy settings
git config --global --unset http.proxy || true
git config --global --unset https.proxy || true

# Remove npm global proxy settings
npm config delete proxy || true
npm config delete https-proxy || true

# Remove pnpm global proxy settings
pnpm config delete proxy || true
pnpm config delete https-proxy || true

# Remove proxy from /etc/environment
sudo sed -i '/^HTTP_PROXY=/d; /^HTTPS_PROXY=/d; /^http_proxy=/d; /^https_proxy=/d; /^ALL_PROXY=/d; /^all_proxy=/d; /^NO_PROXY=/d' /etc/environment || true

# Remove proxy from ~/.bashrc
USER_HOME=$(eval echo ~$USER_NAME)
BASHRC="$USER_HOME/.bashrc"
if [ -f "$BASHRC" ]; then
  sudo -u "$USER_NAME" sed -i '/# ONTIME_INSTALLER_PROXY_START/,/# ONTIME_INSTALLER_PROXY_END/d' "$BASHRC" || true
fi

# Remove application files
sudo rm -rf "$APP_DIR"

# Optionally remove data
# sudo rm -rf "$DATA_DIR"

echo "✅ Ontime uninstalled successfully"
