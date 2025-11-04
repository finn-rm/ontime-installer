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

# Stop service
sudo systemctl stop ontime.service || true
sudo systemctl disable ontime.service || true
sudo rm -f "$SYSTEMD_SERVICE_FILE"
sudo systemctl daemon-reload

# Remove application files
sudo rm -rf "$APP_DIR"

# Optionally remove data
# sudo rm -rf "$DATA_DIR"

echo "✅ Ontime uninstalled successfully"
