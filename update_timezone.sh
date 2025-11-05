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
CURRENT_TZ=$(jq -r 'if .timezone == null or .timezone == "" then "GMT" else .timezone end' "$CONFIG_FILE")
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
  fi
  
  if [ -z "$TIMEZONES" ] && [ -z "$NEW_TZ" ]; then
    echo "❌ No timezones found"
    exit 1
  fi
  
  if [ -z "$NEW_TZ" ]; then
    echo ""
    read -p "Enter timezone (or press Enter to search): " search_term
    
    if [ -n "$search_term" ]; then
      # Filter timezones by search term
      FILTERED=$(echo "$TIMEZONES" | grep -i "$search_term" | head -20)
      
      if [ -z "$FILTERED" ]; then
        echo "❌ No timezones found matching: $search_term"
        exit 1
      fi
      
      echo ""
      echo "Matching timezones:"
      echo "$FILTERED" | nl -w2 -s'. '
      echo ""
      read -p "Enter number or timezone name: " choice
      
      # Check if it's a number
      if [[ "$choice" =~ ^[0-9]+$ ]]; then
        NEW_TZ=$(echo "$FILTERED" | sed -n "${choice}p")
      else
        NEW_TZ="$choice"
      fi
    else
      # Show popular/categorized timezones
      echo ""
      echo "Popular timezones:"
      echo "  GMT (Greenwich Mean Time)"
      echo "  UTC (Coordinated Universal Time)"
      echo ""
      echo "You can search by region (e.g., 'Asia', 'Europe', 'America'):"
      read -p "Enter search term or timezone name: " search_term
      
      if [ -n "$search_term" ]; then
        FILTERED=$(echo "$TIMEZONES" | grep -i "$search_term" | head -30)
        if [ -z "$FILTERED" ]; then
          # If no matches, assume user entered full timezone
          NEW_TZ="$search_term"
        else
          echo ""
          echo "Matching timezones:"
          echo "$FILTERED" | nl -w2 -s'. '
          echo ""
          read -p "Enter number or timezone name: " choice
          
          if [[ "$choice" =~ ^[0-9]+$ ]]; then
            NEW_TZ=$(echo "$FILTERED" | sed -n "${choice}p")
          else
            NEW_TZ="$choice"
          fi
        fi
      else
        echo "❌ No timezone specified"
        exit 1
      fi
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

