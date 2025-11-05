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

USE_PROXY=$(jq -r 'if .use_proxy == null then true else .use_proxy end' "$CONFIG_FILE")
PROXY_URL=$(jq -r 'if .proxy_url == null then "http://squid.internal:3128" else .proxy_url end' "$CONFIG_FILE")
APP_DIR=$(jq -r 'if .app_dir == null then "/app" else .app_dir end' "$CONFIG_FILE")
USER_NAME="${SUDO_USER:-$USER}"

# ────────────────────────────────────────────────────────────────
# Proxy setup
if [ "$USE_PROXY" = true ]; then
  export HTTP_PROXY="$PROXY_URL"
  export HTTPS_PROXY="$PROXY_URL"
  export http_proxy="$PROXY_URL"
  export https_proxy="$PROXY_URL"
  export ALL_PROXY="$PROXY_URL"
  export all_proxy="$PROXY_URL"
  export NO_PROXY="localhost,127.0.0.1"
  # npm-specific proxy config for Node.js scripts
  export npm_config_proxy="$PROXY_URL"
  export npm_config_https_proxy="$PROXY_URL"
else
  unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy npm_config_proxy npm_config_https_proxy
fi

# ────────────────────────────────────────────────────────────────
# Verify installation directory exists
if [ ! -d "$APP_DIR" ]; then
  echo "❌ App directory not found: $APP_DIR"
  echo "💡 Run install script first or ensure app_dir is correct in config.json"
  exit 1
fi

# ────────────────────────────────────────────────────────────────
# Update proxy in /etc/environment and ~/.bashrc
if [ "$USE_PROXY" = true ]; then
  echo "Updating proxy in /etc/environment and ~/.bashrc..."
  
  # Update /etc/environment (remove existing proxy entries, then add new ones)
  sudo sed -i '/^HTTP_PROXY=/d; /^HTTPS_PROXY=/d; /^http_proxy=/d; /^https_proxy=/d; /^ALL_PROXY=/d; /^all_proxy=/d; /^NO_PROXY=/d' /etc/environment
  echo "HTTP_PROXY=\"$PROXY_URL\"" | sudo tee -a /etc/environment > /dev/null
  echo "HTTPS_PROXY=\"$PROXY_URL\"" | sudo tee -a /etc/environment > /dev/null
  echo "http_proxy=\"$PROXY_URL\"" | sudo tee -a /etc/environment > /dev/null
  echo "https_proxy=\"$PROXY_URL\"" | sudo tee -a /etc/environment > /dev/null
  echo "ALL_PROXY=\"$PROXY_URL\"" | sudo tee -a /etc/environment > /dev/null
  echo "all_proxy=\"$PROXY_URL\"" | sudo tee -a /etc/environment > /dev/null
  echo "NO_PROXY=\"localhost,127.0.0.1\"" | sudo tee -a /etc/environment > /dev/null
  
  # Update ~/.bashrc (remove existing proxy section, then add new one)
  USER_HOME=$(eval echo ~$USER_NAME)
  BASHRC="$USER_HOME/.bashrc"
  
  # Remove existing proxy section (between markers)
  if [ -f "$BASHRC" ]; then
    sudo -u "$USER_NAME" sed -i '/# ONTIME_INSTALLER_PROXY_START/,/# ONTIME_INSTALLER_PROXY_END/d' "$BASHRC"
  fi
  
  # Add new proxy section
  sudo -u "$USER_NAME" cat >> "$BASHRC" <<EOF

# ONTIME_INSTALLER_PROXY_START
# Proxy settings configured by ontime-installer
export HTTP_PROXY="$PROXY_URL"
export HTTPS_PROXY="$PROXY_URL"
export http_proxy="$PROXY_URL"
export https_proxy="$PROXY_URL"
export ALL_PROXY="$PROXY_URL"
export all_proxy="$PROXY_URL"
export NO_PROXY="localhost,127.0.0.1"
# ONTIME_INSTALLER_PROXY_END
EOF
else
  echo "Removing proxy from /etc/environment and ~/.bashrc..."
  
  # Remove from /etc/environment
  sudo sed -i '/^HTTP_PROXY=/d; /^HTTPS_PROXY=/d; /^http_proxy=/d; /^https_proxy=/d; /^ALL_PROXY=/d; /^all_proxy=/d; /^NO_PROXY=/d' /etc/environment
  
  # Remove from ~/.bashrc
  USER_HOME=$(eval echo ~$USER_NAME)
  BASHRC="$USER_HOME/.bashrc"
  if [ -f "$BASHRC" ]; then
    sudo -u "$USER_NAME" sed -i '/# ONTIME_INSTALLER_PROXY_START/,/# ONTIME_INSTALLER_PROXY_END/d' "$BASHRC"
  fi
fi

# ────────────────────────────────────────────────────────────────
# Update using @getontime/cli
# Use electron mirror for more reliable downloads
export ELECTRON_MIRROR="https://npmmirror.com/mirrors/electron/"

if [ "$USE_PROXY" = true ]; then
  HTTP_PROXY="$PROXY_URL" \
  HTTPS_PROXY="$PROXY_URL" \
  http_proxy="$PROXY_URL" \
  https_proxy="$PROXY_URL" \
  ALL_PROXY="$PROXY_URL" \
  all_proxy="$PROXY_URL" \
  npm_config_proxy="$PROXY_URL" \
  npm_config_https_proxy="$PROXY_URL" \
  ELECTRON_MIRROR="https://npmmirror.com/mirrors/electron/" \
  npx @getontime/cli install --app-dir "$APP_DIR"
else
  ELECTRON_MIRROR="https://npmmirror.com/mirrors/electron/" \
  npx @getontime/cli install --app-dir "$APP_DIR"
fi

# ────────────────────────────────────────────────────────────────
# Update .npmrc file in app directory for npm/pnpm
if [ "$USE_PROXY" = true ]; then
  cat > "$APP_DIR/.npmrc" <<EOF
proxy=$PROXY_URL
https-proxy=$PROXY_URL
EOF
  echo "Updated .npmrc with proxy settings"
else
  rm -f "$APP_DIR/.npmrc"
fi

# ────────────────────────────────────────────────────────────────
# Update systemd service with proxy settings
if [ "$USE_PROXY" = true ]; then
  sudo tee /etc/systemd/system/ontime.service > /dev/null <<EOL
[Unit]
Description=Ontime Node.js Application
After=network.target

[Service]
ExecStart=/snap/bin/node /app/server/esbuild.js
WorkingDirectory=/app/server
Restart=always
User=$USER_NAME
Group=$USER_NAME
Environment=NODE_ENV=docker
Environment=ONTIME_DATA=/data/
Environment=TZ=Europe/Amsterdam
Environment=HTTP_PROXY=$PROXY_URL
Environment=HTTPS_PROXY=$PROXY_URL
Environment=http_proxy=$PROXY_URL
Environment=https_proxy=$PROXY_URL
Environment=ALL_PROXY=$PROXY_URL
Environment=all_proxy=$PROXY_URL
Environment=NO_PROXY=localhost,127.0.0.1
After=network.target

[Install]
WantedBy=multi-user.target
EOL
else
  sudo tee /etc/systemd/system/ontime.service > /dev/null <<EOL
[Unit]
Description=Ontime Node.js Application
After=network.target

[Service]
ExecStart=/snap/bin/node /app/server/esbuild.js
WorkingDirectory=/app/server
Restart=always
User=$USER_NAME
Group=$USER_NAME
Environment=NODE_ENV=docker
Environment=ONTIME_DATA=/data/
Environment=TZ=Europe/Amsterdam
After=network.target

[Install]
WantedBy=multi-user.target
EOL
fi

# ────────────────────────────────────────────────────────────────
# Restart service
sudo systemctl daemon-reload
sudo systemctl restart ontime.service

echo "✅ Ontime updated successfully"
