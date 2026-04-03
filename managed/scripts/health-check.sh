#!/bin/bash
# Health check for OpenClaw agents
# Checks if agent processes are running, monitors disk usage.
# Alerts via iMessage (macOS) if something is down.
# Writes status to data/health.json for dashboard use.
#
# Configuration via environment variables:
#   ALERT_PHONE     - phone number for iMessage alerts (e.g. +15551234567)
#   REMOTE_HOST     - optional SSH host for a second machine (e.g. agent2@100.x.x.x)
#   REMOTE_NAME     - display name for remote machine (default: "remote")
#   DISK_WARN_PCT   - disk usage % to trigger alert (default: 90)
#
# Cron example (openclaw gateway cron):
#   schedule: { kind: "every", everyMs: 600000 }
#   payload: { kind: "agentTurn", message: "run bash ~/clawd/scripts/health-check.sh" }

WORKSPACE="${OPENCLAW_WORKSPACE:-$HOME/clawd}"
HEALTH_FILE="$WORKSPACE/data/health.json"
ALERT_PHONE="${ALERT_PHONE:-}"
REMOTE_HOST="${REMOTE_HOST:-}"
REMOTE_NAME="${REMOTE_NAME:-remote}"
DISK_WARN_PCT="${DISK_WARN_PCT:-90}"

mkdir -p "$WORKSPACE/data"

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
LOCAL_OK=false
REMOTE_OK=false

# Check local — is openclaw or claude running?
if ps aux | grep -E 'openclaw|claude' | grep -v grep | grep -q .; then
    LOCAL_OK=true
fi

# Check remote (if configured)
REMOTE_DISK=""
if [ -n "$REMOTE_HOST" ]; then
    REMOTE_CHECK=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$REMOTE_HOST" \
        "ps aux | grep -E 'openclaw|claude' | grep -v grep | grep -q . && echo 'up' || echo 'down'" 2>/dev/null)
    if [ "$REMOTE_CHECK" = "up" ]; then
        REMOTE_OK=true
    fi
    REMOTE_DISK=$(ssh -o ConnectTimeout=5 "$REMOTE_HOST" "df -h / | tail -1 | awk '{print \$5}'" 2>/dev/null | tr -d '%')
fi

# Write status JSON
if [ -n "$REMOTE_HOST" ]; then
    cat > "$HEALTH_FILE" <<EOF
{
  "checked_at": "$NOW",
  "local": {
    "status": $([ "$LOCAL_OK" = true ] && echo '"up"' || echo '"down"')
  },
  "$REMOTE_NAME": {
    "status": $([ "$REMOTE_OK" = true ] && echo '"up"' || echo '"down"'),
    "disk_usage_pct": ${REMOTE_DISK:-null}
  }
}
EOF
else
    cat > "$HEALTH_FILE" <<EOF
{
  "checked_at": "$NOW",
  "local": {
    "status": $([ "$LOCAL_OK" = true ] && echo '"up"' || echo '"down"')
  }
}
EOF
fi

# Build alert message
ALERT_MSG=""
if [ "$LOCAL_OK" = false ]; then
    ALERT_MSG="⚠️ local agent is DOWN"
fi
if [ -n "$REMOTE_HOST" ] && [ "$REMOTE_OK" = false ]; then
    [ -n "$ALERT_MSG" ] && ALERT_MSG="$ALERT_MSG\n"
    ALERT_MSG="${ALERT_MSG}⚠️ $REMOTE_NAME agent is DOWN"
fi
if [ -n "$REMOTE_DISK" ] && [ "$REMOTE_DISK" -gt "$DISK_WARN_PCT" ] 2>/dev/null; then
    [ -n "$ALERT_MSG" ] && ALERT_MSG="$ALERT_MSG\n"
    ALERT_MSG="${ALERT_MSG}⚠️ $REMOTE_NAME disk at ${REMOTE_DISK}%"
fi

# Send alert (macOS iMessage) with cooldown to avoid spam
COOLDOWN_FILE="/tmp/openclaw-health-alert-cooldown"
if [ -n "$ALERT_MSG" ] && [ -n "$ALERT_PHONE" ]; then
    if [ ! -f "$COOLDOWN_FILE" ] || [ $(( $(date +%s) - $(stat -f %m "$COOLDOWN_FILE" 2>/dev/null || echo 0) )) -gt 1800 ]; then
        osascript -e "tell application \"Messages\" to send \"$ALERT_MSG\" to participant \"$ALERT_PHONE\" of account 1" 2>/dev/null
        touch "$COOLDOWN_FILE"
        echo "[$(date)] ALERT sent: $ALERT_MSG"
    fi
else
    rm -f "$COOLDOWN_FILE"
    echo "[$(date)] all healthy"
fi
