#!/bin/bash
set -e

echo "=== Ontime Timezone Update ==="

# ────────────────────────────────────────────────────────────────
# Load configuration from config.json
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.json"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ Config file not found: $CONFIG_FILE"
  exit 1
fi

# ────────────────────────────────────────────────────────────────
# Check if systemd service exists
if [ ! -f "/etc/systemd/system/ontime.service" ]; then
  echo "❌ Ontime systemd service not found"
  echo "💡 Run install script first"
  exit 1
fi

# ────────────────────────────────────────────────────────────────
# Get current timezone from config
CURRENT_TZ=$(jq -r 'if .timezone == null or .timezone == "" then "Europe/Berlin" else .timezone end' "$CONFIG_FILE")
echo "Current timezone: $CURRENT_TZ"

# ────────────────────────────────────────────────────────────────
# Get new timezone
if [ -n "$1" ]; then
  # Timezone provided as argument
  NEW_TZ="$1"
else
  # Interactive mode - get timezones from OS
  echo ""
  echo "Getting available timezones from system..."
  
  # Try to get timezones from timedatectl first (systemd systems)
  if command -v timedatectl &>/dev/null; then
    TIMEZONES=$(timedatectl list-timezones 2>/dev/null)
  # Fallback to reading from /usr/share/zoneinfo
  elif [ -d "/usr/share/zoneinfo" ]; then
    TIMEZONES=$(find /usr/share/zoneinfo -type f ! -name "*.tab" ! -name "*.list" | sed 's|/usr/share/zoneinfo/||' | sort)
  else
    echo "❌ Could not find timezone information on this system"
    read -p "Enter timezone (e.g., Asia/Singapore, GMT, UTC): " NEW_TZ
    if [ -z "$NEW_TZ" ]; then
      exit 1
    fi
  fi
  
  if [ -z "$TIMEZONES" ] && [ -z "$NEW_TZ" ]; then
    echo "❌ No timezones found"
    exit 1
  fi
  
  if [ -z "$NEW_TZ" ]; then
    # Install fzf if needed
    if ! command -v fzf &>/dev/null; then
      echo "Installing fzf for interactive timezone selection..."
      if command -v apt-get &>/dev/null; then
        # Try apt first (Ubuntu/Debian)
        if sudo apt-get update && sudo apt-get install -y fzf 2>/dev/null; then
          echo "✅ fzf installed successfully"
        else
          # Fallback: install via git (official method)
          echo "Installing fzf from GitHub..."
          if command -v git &>/dev/null && command -v bash &>/dev/null; then
            FZF_DIR="/tmp/fzf"
            rm -rf "$FZF_DIR"
            git clone --depth 1 https://github.com/junegunn/fzf.git "$FZF_DIR" 2>/dev/null || {
              echo "❌ Failed to clone fzf repository"
              echo "⚠️  Please install fzf manually or provide timezone as argument: ./update_timezone.sh Asia/Singapore"
              exit 1
            }
            "$FZF_DIR/install" --bin 2>/dev/null || {
              echo "❌ Failed to install fzf"
              echo "⚠️  Please install fzf manually or provide timezone as argument: ./update_timezone.sh Asia/Singapore"
              exit 1
            }
            # Add to PATH temporarily (fzf installs to ~/.fzf/bin or ~/.local/bin)
            export PATH="$HOME/.fzf/bin:$HOME/.local/bin:$PATH"
          else
            echo "❌ git or bash not found. Cannot install fzf."
            echo "⚠️  Please install fzf manually or provide timezone as argument: ./update_timezone.sh Asia/Singapore"
            exit 1
          fi
        fi
      elif command -v yum &>/dev/null; then
        sudo yum install -y fzf || {
          echo "❌ Failed to install fzf via yum"
          echo "⚠️  Please install fzf manually or provide timezone as argument: ./update_timezone.sh Asia/Singapore"
          exit 1
        }
      elif command -v dnf &>/dev/null; then
        sudo dnf install -y fzf || {
          echo "❌ Failed to install fzf via dnf"
          echo "⚠️  Please install fzf manually or provide timezone as argument: ./update_timezone.sh Asia/Singapore"
          exit 1
        }
      elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm fzf || {
          echo "❌ Failed to install fzf via pacman"
          echo "⚠️  Please install fzf manually or provide timezone as argument: ./update_timezone.sh Asia/Singapore"
          exit 1
        }
      else
        echo "⚠️  Could not install fzf automatically. Please install it manually."
        echo "   You can also provide timezone as argument: ./update_timezone.sh Asia/Singapore"
        exit 1
      fi
    fi
    
    # Ensure fzf is in PATH (in case it was just installed)
    if ! command -v fzf &>/dev/null; then
      export PATH="$HOME/.fzf/bin:$HOME/.local/bin:$PATH"
    fi
    
    # Use fzf for interactive selection
    echo ""
    echo "Select timezone (use arrow keys to navigate, type to filter, Enter to select):"
    NEW_TZ=$(echo "$TIMEZONES" | fzf --height 40% --border --prompt="Timezone: " --header="Current: $CURRENT_TZ | Use arrow keys ↑↓, type to search, Enter to select" --preview="echo 'Selected: {}'")
    
    if [ -z "$NEW_TZ" ]; then
      echo "❌ No timezone selected"
      exit 1
    fi
  fi
fi

# ────────────────────────────────────────────────────────────────
# Validate timezone (basic check)
if [ -z "$NEW_TZ" ]; then
  echo "❌ Invalid timezone"
  exit 1
fi

# ────────────────────────────────────────────────────────────────
# Update config.json
echo "Updating config.json with timezone: $NEW_TZ"
TEMP_CONFIG=$(mktemp)
jq ".timezone = \"$NEW_TZ\"" "$CONFIG_FILE" > "$TEMP_CONFIG"
mv "$TEMP_CONFIG" "$CONFIG_FILE"

# ────────────────────────────────────────────────────────────────
# Load other config values needed for systemd service
USE_PROXY=$(jq -r 'if .use_proxy == null then false else .use_proxy end' "$CONFIG_FILE")
PROXY_URL=$(jq -r 'if .proxy_url == null then "http://squid.internal:3128" else .proxy_url end' "$CONFIG_FILE")
USER_NAME="${SUDO_USER:-$USER}"

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
# Update systemd service
echo "Updating systemd service with timezone: $NEW_TZ..."
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
Environment=TZ=$NEW_TZ
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
Environment=TZ=$NEW_TZ

[Install]
WantedBy=multi-user.target
EOL
fi

# ────────────────────────────────────────────────────────────────
# Reload and restart service
sudo systemctl daemon-reload
sudo systemctl restart ontime.service

echo "✅ Timezone updated to $NEW_TZ successfully"
echo "💡 Service has been restarted with the new timezone"

