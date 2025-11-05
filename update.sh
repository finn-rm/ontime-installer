#!/bin/bash
set -e

echo "=== Ontime Update ==="

# ────────────────────────────────────────────────────────────────
# Load configuration from config.json
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.json"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ Config file not found: $CONFIG_FILE"
  exit 1
fi

USE_PROXY=$(jq -r 'if .use_proxy == null then false else .use_proxy end' "$CONFIG_FILE")
PROXY_URL=$(jq -r 'if .proxy_url == null then "http://squid.internal:3128" else .proxy_url end' "$CONFIG_FILE")
USER_NAME="${SUDO_USER:-$USER}"

# ────────────────────────────────────────────────────────────────
# Verify @getontime/cli is installed
if ! command -v ontime &>/dev/null; then
  echo "❌ @getontime/cli is not installed globally"
  echo "💡 Run install script first"
  exit 1
fi

# ────────────────────────────────────────────────────────────────
# Proxy setup
if [ "$USE_PROXY" = true ]; then
  echo "Proxy enabled ($PROXY_URL)"
  export HTTP_PROXY="$PROXY_URL"
  export HTTPS_PROXY="$PROXY_URL"
  export http_proxy="$PROXY_URL"
  export https_proxy="$PROXY_URL"
  export ALL_PROXY="$PROXY_URL"
  export all_proxy="$PROXY_URL"
  export NO_PROXY="localhost,127.0.0.1"
  export npm_config_proxy="$PROXY_URL"
  export npm_config_https_proxy="$PROXY_URL"
else
  unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy npm_config_proxy npm_config_https_proxy
fi

# ────────────────────────────────────────────────────────────────
# Update @getontime/cli globally
echo "Updating @getontime/cli..."
if [ "$USE_PROXY" = true ]; then
  sudo env "PATH=$PATH" "HTTP_PROXY=$PROXY_URL" "HTTPS_PROXY=$PROXY_URL" "http_proxy=$PROXY_URL" "https_proxy=$PROXY_URL" "npm_config_proxy=$PROXY_URL" "npm_config_https_proxy=$PROXY_URL" npm update -g @getontime/cli
else
  sudo npm update -g @getontime/cli
fi

# ────────────────────────────────────────────────────────────────
# Find ontime command path
ONTIME_CMD=$(command -v ontime || echo "/usr/local/bin/ontime")
if [ ! -f "$ONTIME_CMD" ]; then
  if [ -f "/snap/bin/ontime" ]; then
    ONTIME_CMD="/snap/bin/ontime"
  elif [ -f "/usr/bin/ontime" ]; then
    ONTIME_CMD="/usr/bin/ontime"
  else
    ONTIME_CMD="ontime"
  fi
fi

# ────────────────────────────────────────────────────────────────
# Update systemd service with proxy settings if needed
if [ -f "/etc/systemd/system/ontime.service" ]; then
  echo "Updating systemd service..."
  if [ "$USE_PROXY" = true ]; then
    sudo tee /etc/systemd/system/ontime.service > /dev/null <<EOL
[Unit]
Description=Ontime Application
After=network.target

[Service]
ExecStart=$ONTIME_CMD
Restart=always
User=$USER_NAME
Group=$USER_NAME
Environment=HTTP_PROXY=$PROXY_URL
Environment=HTTPS_PROXY=$PROXY_URL
Environment=http_proxy=$PROXY_URL
Environment=https_proxy=$PROXY_URL
Environment=ALL_PROXY=$PROXY_URL
Environment=all_proxy=$PROXY_URL
Environment=NO_PROXY=localhost,127.0.0.1

[Install]
WantedBy=multi-user.target
EOL
  else
    sudo tee /etc/systemd/system/ontime.service > /dev/null <<EOL
[Unit]
Description=Ontime Application
After=network.target

[Service]
ExecStart=$ONTIME_CMD
Restart=always
User=$USER_NAME
Group=$USER_NAME

[Install]
WantedBy=multi-user.target
EOL
  fi
  
  sudo systemctl daemon-reload
  sudo systemctl restart ontime.service
fi

echo "✅ Ontime updated successfully"
