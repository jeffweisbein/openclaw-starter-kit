#!/bin/bash
# Install the OpenClaw watchdog as a launchd agent
# Usage: ./watchdog-install.sh [alert-phone-number]
#
# The watchdog runs every 2 minutes and monitors:
# - Gateway health (HTTP check)
# - Session file bloat
# - Config validation errors
# - Disk space

set -euo pipefail

ALERT_NUMBER="${1:-}"
LABEL="com.openclaw.watchdog"
PLIST_PATH="$HOME/Library/LaunchAgents/${LABEL}.plist"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WATCHDOG_SCRIPT="${SCRIPT_DIR}/watchdog.sh"
LOG_DIR="$HOME/.openclaw/logs"

mkdir -p "$LOG_DIR"
chmod +x "$WATCHDOG_SCRIPT"

# Unload existing if present
launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true

cat > "$PLIST_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>${LABEL}</string>

    <key>Comment</key>
    <string>OpenClaw Self-Healing Watchdog - Health checks every 2 minutes</string>

    <key>ProgramArguments</key>
    <array>
      <string>/bin/bash</string>
      <string>${WATCHDOG_SCRIPT}</string>
    </array>

    <key>StartInterval</key>
    <integer>120</integer>

    <key>RunAtLoad</key>
    <true/>

    <key>StandardOutPath</key>
    <string>${LOG_DIR}/watchdog-launchd.log</string>
    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/watchdog-launchd.err.log</string>

    <key>EnvironmentVariables</key>
    <dict>
      <key>HOME</key>
      <string>${HOME}</string>
      <key>PATH</key>
      <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
EOF

if [[ -n "$ALERT_NUMBER" ]]; then
  cat >> "$PLIST_PATH" << EOF
      <key>WATCHDOG_ALERT_NUMBER</key>
      <string>${ALERT_NUMBER}</string>
EOF
fi

cat >> "$PLIST_PATH" << EOF
    </dict>
  </dict>
</plist>
EOF

launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"

echo "✅ watchdog installed and running"
echo "   plist: $PLIST_PATH"
echo "   interval: every 2 minutes"
echo "   logs: ${LOG_DIR}/watchdog.log"
[[ -n "$ALERT_NUMBER" ]] && echo "   alerts: $ALERT_NUMBER"
echo ""
echo "to check status: launchctl list | grep watchdog"
echo "to uninstall: launchctl bootout gui/\$(id -u)/${LABEL}"
