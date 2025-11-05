#!/bin/bash
set -e

echo "=== Ontime Installation ==="

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
TIMEZONE=$(jq -r 'if .timezone == null or .timezone == "" then "Europe/Berlin" else .timezone end' "$CONFIG_FILE")
USER_NAME="${SUDO_USER:-$USER}"

# ────────────────────────────────────────────────────────────────
# Ensure dependencies
# Load nvm if it exists (for user's node/npm)
if [ -s "$HOME/.nvm/nvm.sh" ]; then
  source "$HOME/.nvm/nvm.sh"
elif [ -s "/home/$USER_NAME/.nvm/nvm.sh" ]; then
  source "/home/$USER_NAME/.nvm/nvm.sh"
fi

# Install node first (needed for npm)
if ! command -v node &>/dev/null; then
  echo "Installing Node.js..."
  sudo snap install node --classic
  # Ensure snap bin is in PATH for subsequent commands
  export PATH="/snap/bin:$PATH"
fi

# Install jq if needed
if ! command -v jq &>/dev/null; then
  echo "Installing jq..."
  sudo apt update && sudo apt install -y jq
fi

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

if [ -z "$NPM_CMD" ]; then
  echo "❌ npm not found. Cannot install @getontime/cli."
  exit 1
fi

echo "Using npm: $NPM_CMD"

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
  # npm-specific proxy config
  export npm_config_proxy="$PROXY_URL"
  export npm_config_https_proxy="$PROXY_URL"
else
  unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy npm_config_proxy npm_config_https_proxy
fi

# ────────────────────────────────────────────────────────────────
# Install @getontime/cli globally
echo "Installing @getontime/cli globally..."
if [ "$USE_PROXY" = true ]; then
  sudo env "PATH=$PATH" "HTTP_PROXY=$PROXY_URL" "HTTPS_PROXY=$PROXY_URL" "http_proxy=$PROXY_URL" "https_proxy=$PROXY_URL" "npm_config_proxy=$PROXY_URL" "npm_config_https_proxy=$PROXY_URL" "$NPM_CMD" install -g @getontime/cli
else
  sudo env "PATH=$PATH" "$NPM_CMD" install -g @getontime/cli
fi

# ────────────────────────────────────────────────────────────────
# Find ontime command path
ONTIME_CMD=$(command -v ontime || echo "/usr/local/bin/ontime")
if [ ! -f "$ONTIME_CMD" ]; then
  # Try alternative locations
  if [ -f "/snap/bin/ontime" ]; then
    ONTIME_CMD="/snap/bin/ontime"
  elif [ -f "/usr/bin/ontime" ]; then
    ONTIME_CMD="/usr/bin/ontime"
  else
    echo "⚠️  Could not find ontime command. Please verify installation."
    ONTIME_CMD="ontime"
  fi
fi

# ────────────────────────────────────────────────────────────────
# Create systemd service
echo "Creating systemd service with timezone: $TIMEZONE..."
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
Environment=TZ=$TIMEZONE
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
Environment=TZ=$TIMEZONE

[Install]
WantedBy=multi-user.target
EOL
fi

sudo systemctl daemon-reload
sudo systemctl enable ontime.service
sudo systemctl start ontime.service

echo "✅ Ontime installed successfully"
echo "💡 Service 'ontime.service' has been created and started"
echo "💡 You can also run 'ontime' directly to start the application"
