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
  export NO_PROXY="localhost,127.0.0.1"
  CURL_PROXY="--proxy $PROXY_URL"
else
  unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy
  CURL_PROXY=""
fi

# ────────────────────────────────────────────────────────────────
# Verify installation
if [ ! -d "$APP_DIR/.git" ]; then
  echo "❌ Ontime not installed. Run install script first."
  exit 1
fi

cd "$APP_DIR"

# ────────────────────────────────────────────────────────────────
# Latest version
LATEST_VERSION=$(curl $CURL_PROXY https://api.github.com/repos/cpvalente/ontime/tags \
  | jq -r 'first(.[].name | select(test("^v[0-9]")))')
LATEST_VERSION=${LATEST_VERSION#v}
if [ -z "$LATEST_VERSION" ]; then
  echo "❌ Failed to fetch latest version"
  exit 1
fi
echo "Updating Ontime to v$LATEST_VERSION"

# ────────────────────────────────────────────────────────────────
# Fetch latest code
git fetch --tags origin
git checkout "v$LATEST_VERSION"

# ────────────────────────────────────────────────────────────────
# Update dependencies
if [ "$USE_PROXY" = true ]; then
  pnpm config set proxy "$PROXY_URL"
  pnpm config set https-proxy "$PROXY_URL"
else
  pnpm config delete proxy || true
  pnpm config delete https-proxy || true
fi

pnpm install

# ────────────────────────────────────────────────────────────────
# Update version files
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
# Restart service
sudo systemctl daemon-reload
sudo systemctl restart ontime.service

echo "✅ Ontime updated successfully to v$LATEST_VERSION"
