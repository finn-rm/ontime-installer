#!/bin/bash
set -e

echo "=== Ontime Uninstall ==="

USER_NAME="${SUDO_USER:-$USER}"

# ────────────────────────────────────────────────────────────────
# Load nvm if it exists (for user's node/npm)
if [ -s "$HOME/.nvm/nvm.sh" ]; then
  source "$HOME/.nvm/nvm.sh"
elif [ -s "/home/$USER_NAME/.nvm/nvm.sh" ]; then
  source "/home/$USER_NAME/.nvm/nvm.sh"
fi

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
# Find npm command path (handles nvm, snap, and regular installations)
NPM_CMD=""
if command -v npm &>/dev/null; then
  NPM_CMD=$(command -v npm)
elif [ -f "/snap/bin/npm" ]; then
  NPM_CMD="/snap/bin/npm"
elif [ -n "$NVM_DIR" ] && [ -d "$NVM_DIR/versions/node" ]; then
  # Find the active nvm node version
  NODE_VERSION=$(node -v 2>/dev/null | sed 's/v//')
  if [ -n "$NODE_VERSION" ] && [ -f "$NVM_DIR/versions/node/$NODE_VERSION/bin/npm" ]; then
    NPM_CMD="$NVM_DIR/versions/node/$NODE_VERSION/bin/npm"
  fi
fi

# ────────────────────────────────────────────────────────────────
# Uninstall @getontime/cli globally
if command -v ontime &>/dev/null; then
  echo "Uninstalling @getontime/cli..."
  if [ -n "$NPM_CMD" ]; then
    sudo env "PATH=$PATH" "$NPM_CMD" uninstall -g @getontime/cli
  else
    echo "⚠️  npm not found. Cannot uninstall @getontime/cli."
    exit 1
  fi
  echo "✅ Ontime uninstalled successfully"
else
  echo "⚠️  @getontime/cli is not installed globally"
fi
