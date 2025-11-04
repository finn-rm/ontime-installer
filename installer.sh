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

USE_PROXY=$(jq -r 'if .use_proxy == null then true else .use_proxy end' "$CONFIG_FILE")
PROXY_URL=$(jq -r 'if .proxy_url == null then "http://squid.internal:3128" else .proxy_url end' "$CONFIG_FILE")
REPO_URL=$(jq -r 'if .repo_url == null then "https://github.com/cpvalente/ontime.git" else .repo_url end' "$CONFIG_FILE")
APP_DIR=$(jq -r 'if .app_dir == null then "/app" else .app_dir end' "$CONFIG_FILE")
DATA_DIR=$(jq -r 'if .data_dir == null then "/data" else .data_dir end' "$CONFIG_FILE")
USER_NAME="${SUDO_USER:-$USER}"

# ────────────────────────────────────────────────────────────────
# Proxy setup
if [ "$USE_PROXY" = true ]; then
  echo "Proxy enabled ($PROXY_URL)"
  export HTTP_PROXY="$PROXY_URL"
  export HTTPS_PROXY="$PROXY_URL"
  export http_proxy="$PROXY_URL"
  export https_proxy="$PROXY_URL"
  export NO_PROXY="localhost,127.0.0.1"
  # npm-specific proxy config for Node.js scripts
  export npm_config_proxy="$PROXY_URL"
  export npm_config_https_proxy="$PROXY_URL"
else
  unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy npm_config_proxy npm_config_https_proxy
fi

# ────────────────────────────────────────────────────────────────
# Ensure dependencies
# Install node first (needed for npm/pnpm)
if ! command -v node &>/dev/null; then
  echo "Installing missing tool: node"
  sudo snap install node --classic
  # Ensure snap bin is in PATH for subsequent commands
  export PATH="/snap/bin:$PATH"
fi

# Install other dependencies
for cmd in jq git curl; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Installing missing tool: $cmd"
    if [ "$cmd" = "jq" ]; then
      sudo apt update && sudo apt install -y jq
    else
      sudo apt update && sudo apt install -y "$cmd"
    fi
  fi
done

# Install pnpm (requires node/npm to be available)
if ! command -v pnpm &>/dev/null; then
  echo "Installing missing tool: pnpm"
  # Find npm and get its full path (handles nvm, snap, and regular installations)
  NPM_CMD=""
  if command -v npm &>/dev/null; then
    NPM_CMD=$(command -v npm)
  elif [ -f "/snap/bin/npm" ]; then
    NPM_CMD="/snap/bin/npm"
  elif [ -n "$NVM_DIR" ] && [ -f "$NVM_DIR/versions/node/$(node -v)/bin/npm" ]; then
    NPM_CMD="$NVM_DIR/versions/node/$(node -v)/bin/npm"
  else
    echo "❌ npm not found. Cannot install pnpm."
    exit 1
  fi
  
  # Use full path and preserve PATH for sudo to ensure npm can find node
  if [ "$USE_PROXY" = true ]; then
    sudo env "PATH=$PATH" "$NPM_CMD" --proxy "$PROXY_URL" install -g pnpm
  else
    sudo env "PATH=$PATH" "$NPM_CMD" install -g pnpm
  fi
fi

git config --global advice.detachedHead false
if [ "$USE_PROXY" = true ]; then
  git config --global http.proxy "$PROXY_URL"
  git config --global https.proxy "$PROXY_URL"
fi

# ────────────────────────────────────────────────────────────────
# Latest version
GITHUB_RESPONSE=$(curl -s https://api.github.com/repos/cpvalente/ontime/tags)
if [ $? -ne 0 ] || [ -z "$GITHUB_RESPONSE" ]; then
  echo "❌ Failed to fetch tags from GitHub API"
  exit 1
fi

# Check if response is valid JSON
if ! echo "$GITHUB_RESPONSE" | jq empty 2>/dev/null; then
  echo "❌ GitHub API returned invalid JSON response:"
  echo "$GITHUB_RESPONSE" | head -5
  exit 1
fi

LATEST_VERSION=$(echo "$GITHUB_RESPONSE" | jq -r 'first(.[].name | select(test("^v[0-9]")))')
LATEST_VERSION=${LATEST_VERSION#v}
if [ -z "$LATEST_VERSION" ] || [ "$LATEST_VERSION" = "null" ]; then
  echo "❌ Failed to parse latest version from GitHub API response"
  exit 1
fi
echo "Installing Ontime v$LATEST_VERSION"

# ────────────────────────────────────────────────────────────────
# Prepare directories
sudo mkdir -p "$APP_DIR" "$DATA_DIR"
sudo chown "$USER_NAME":"$USER_NAME" "$APP_DIR" "$DATA_DIR"
mkdir -p "$APP_DIR/client" "$APP_DIR/server" "$APP_DIR/external"

# ────────────────────────────────────────────────────────────────
# Clone repository
cd /tmp
rm -rf ontime
git clone "$REPO_URL"
cd ontime
git checkout "v$LATEST_VERSION"
cp -a . "$APP_DIR/"

# ────────────────────────────────────────────────────────────────
# Install dependencies
cd "$APP_DIR"

# Configure pnpm proxy if needed
if [ "$USE_PROXY" = true ]; then
  pnpm config set proxy "$PROXY_URL"
  pnpm config set https-proxy "$PROXY_URL"
  # Also set npm config for Node.js scripts (like electron postinstall)
  npm config set proxy "$PROXY_URL" || true
  npm config set https-proxy "$PROXY_URL" || true
  # Set environment variables that Node.js HTTP clients check
  export npm_config_proxy="$PROXY_URL"
  export npm_config_https_proxy="$PROXY_URL"
else
  pnpm config delete proxy || true
  pnpm config delete https-proxy || true
  npm config delete proxy || true
  npm config delete https-proxy || true
  unset npm_config_proxy npm_config_https_proxy
fi

pnpm install

# ────────────────────────────────────────────────────────────────
# Set version files
echo "export const ONTIME_VERSION = \"$LATEST_VERSION\";" > "$APP_DIR/apps/server/src/ONTIME_VERSION.js"
echo "export const ONTIME_VERSION = \"$LATEST_VERSION\";" > "$APP_DIR/apps/client/src/ONTIME_VERSION.js"

# ────────────────────────────────────────────────────────────────
# Build
if pnpm --filter=ontime-ui run build; then
  echo "UI build completed"
fi
if pnpm --filter=ontime-server run build; then
  echo "Server build completed"
fi

# ────────────────────────────────────────────────────────────────
# Deploy
cp -r "$APP_DIR/apps/client/build/"* "$APP_DIR/client/"
cp -r "$APP_DIR/apps/server/dist/"* "$APP_DIR/server/"
cp -r "$APP_DIR/apps/server/src/external/"* "$APP_DIR/external/"

# ────────────────────────────────────────────────────────────────
# Systemd service
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

sudo systemctl daemon-reload
sudo systemctl enable ontime.service
sudo systemctl start ontime.service

echo "✅ Ontime v$LATEST_VERSION installed successfully"
