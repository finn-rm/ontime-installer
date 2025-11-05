#!/bin/bash
set -e

echo "=== Ontime Uninstall ==="

# ────────────────────────────────────────────────────────────────
# Stop and remove systemd service
if [ -f "/etc/systemd/system/ontime.service" ]; then
  echo "Stopping and removing systemd service..."
  sudo systemctl stop ontime.service || true
  sudo systemctl disable ontime.service || true
  sudo rm -f /etc/systemd/system/ontime.service
  sudo systemctl daemon-reload
fi

# ────────────────────────────────────────────────────────────────
# Uninstall @getontime/cli globally
if command -v ontime &>/dev/null; then
  echo "Uninstalling @getontime/cli..."
  sudo npm uninstall -g @getontime/cli
  echo "✅ Ontime uninstalled successfully"
else
  echo "⚠️  @getontime/cli is not installed globally"
fi
