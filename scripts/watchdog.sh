#!/bin/bash
# OpenClaw Self-Healing Watchdog
# Runs every 2-3 minutes via launchd. Detects and recovers from:
# 1. Gateway process died (launchd KeepAlive should catch this, but belt+suspenders)
# 2. Gateway running but unresponsive (hung process)
# 3. Session file bloat (approaching crash threshold)
# 4. Config validation errors (alerts instead of crash-looping)
#
# Philosophy: fix what you can, alert on what you can't.

set -euo pipefail

# --- Config ---
GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
GATEWAY_URL="http://127.0.0.1:${GATEWAY_PORT}"
OPENCLAW_DIR="${HOME}/.openclaw"
LOG_DIR="${OPENCLAW_DIR}/logs"
WATCHDOG_LOG="${LOG_DIR}/watchdog.log"
STATE_FILE="${LOG_DIR}/watchdog-state.json"
SESSIONS_DIR="${OPENCLAW_DIR}/agents/main/sessions"
SESSION_LINE_WARN=1500
SESSION_LINE_CRIT=1900
MAX_CONSECUTIVE_FAILURES=3
HEALTH_TIMEOUT=5  # seconds

# Alert method: imessage, log, or both
# Set WATCHDOG_ALERT_NUMBER to enable iMessage alerts
ALERT_NUMBER="${WATCHDOG_ALERT_NUMBER:-}"
IMSG_CLI="${IMSG_CLI:-/opt/homebrew/opt/imsg/bin/imsg}"

# --- Functions ---

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$WATCHDOG_LOG"
}

alert() {
  local msg="🩺 openclaw watchdog: $*"
  log "ALERT: $msg"
  
  if [[ -n "$ALERT_NUMBER" && -x "$IMSG_CLI" ]]; then
    "$IMSG_CLI" send "$ALERT_NUMBER" "$msg" 2>/dev/null || true
  fi
}

get_state() {
  local key="$1"
  local default="${2:-0}"
  if [[ -f "$STATE_FILE" ]]; then
    python3 -c "
import json, sys
try:
    d = json.load(open('$STATE_FILE'))
    print(d.get('$key', '$default'))
except: print('$default')
" 2>/dev/null
  else
    echo "$default"
  fi
}

set_state() {
  local key="$1"
  local value="$2"
  python3 -c "
import json, os
path = '$STATE_FILE'
try:
    d = json.load(open(path)) if os.path.exists(path) else {}
except: d = {}
d['$key'] = '$value'
json.dump(d, open(path, 'w'), indent=2)
" 2>/dev/null
}

# --- Health Check ---

check_health() {
  # Try to hit the gateway
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time "$HEALTH_TIMEOUT" \
    "${GATEWAY_URL}/health" 2>/dev/null) || http_code="000"
  
  echo "$http_code"
}

# --- Session Bloat Check ---

check_sessions() {
  if [[ ! -d "$SESSIONS_DIR" ]]; then
    return 0
  fi
  
  local total_lines=0
  local largest_file=""
  local largest_lines=0
  
  for f in "$SESSIONS_DIR"/*.jsonl; do
    [[ -f "$f" ]] || continue
    local lines
    lines=$(wc -l < "$f" 2>/dev/null | tr -d ' ')
    total_lines=$((total_lines + lines))
    if [[ $lines -gt $largest_lines ]]; then
      largest_lines=$lines
      largest_file="$f"
    fi
  done
  
  if [[ $largest_lines -gt $SESSION_LINE_CRIT ]]; then
    log "CRITICAL: session file $(basename "$largest_file") at ${largest_lines} lines (threshold: ${SESSION_LINE_CRIT})"
    alert "session bloat critical — $(basename "$largest_file") at ${largest_lines} lines. truncating to prevent crash."
    
    # Truncate: keep first 200 lines (early context) + last 300 lines (recent)
    local tmp="${largest_file}.tmp"
    head -200 "$largest_file" > "$tmp"
    echo '{"type":"system","message":{"role":"system","content":"[watchdog: session truncated to prevent bloat crash]"}}' >> "$tmp"
    tail -300 "$largest_file" >> "$tmp"
    mv "$tmp" "$largest_file"
    log "Truncated $(basename "$largest_file") from ${largest_lines} to ~501 lines"
    return 1
    
  elif [[ $largest_lines -gt $SESSION_LINE_WARN ]]; then
    log "WARNING: session file $(basename "$largest_file") at ${largest_lines} lines"
    return 0
  fi
  
  return 0
}

# --- Config Validation ---

check_config() {
  # Look for recent config errors in gateway logs
  local err_log="${LOG_DIR}/gateway.err.log"
  [[ -f "$err_log" ]] || return 0
  
  # Check last 20 lines for config validation failures
  if tail -20 "$err_log" 2>/dev/null | grep -q "invalid config\|Missing env var\|must have required property"; then
    local last_alert
    last_alert=$(get_state "last_config_alert" "0")
    local now
    now=$(date +%s)
    local cooldown=3600  # only alert once per hour
    
    if [[ $((now - last_alert)) -gt $cooldown ]]; then
      local errors
      errors=$(tail -20 "$err_log" | grep "invalid config\|Missing env var\|must have required property" | tail -3)
      alert "config errors detected:\n${errors}"
      set_state "last_config_alert" "$now"
    fi
    return 1
  fi
  
  return 0
}

# --- Main ---

mkdir -p "$LOG_DIR"

# 1. Health check
http_code=$(check_health)

if [[ "$http_code" == "200" || "$http_code" == "204" ]]; then
  # Healthy — reset failure counter
  set_state "consecutive_failures" "0"
  set_state "last_healthy" "$(date +%s)"
  
elif [[ "$http_code" == "000" ]]; then
  # No response — gateway might be down or hung
  failures=$(get_state "consecutive_failures" "0")
  failures=$((failures + 1))
  set_state "consecutive_failures" "$failures"
  
  log "Health check failed (attempt ${failures}/${MAX_CONSECUTIVE_FAILURES})"
  
  if [[ $failures -ge $MAX_CONSECUTIVE_FAILURES ]]; then
    log "Gateway unresponsive after ${failures} checks. Attempting recovery..."
    alert "gateway unresponsive after ${failures} health checks. killing and letting launchd restart."
    
    # Find and kill the gateway process
    local gw_pid
    gw_pid=$(lsof -ti ":${GATEWAY_PORT}" 2>/dev/null | head -1) || true
    
    if [[ -n "$gw_pid" ]]; then
      log "Killing hung gateway process ${gw_pid}"
      kill -9 "$gw_pid" 2>/dev/null || true
      sleep 2
    fi
    
    # If launchd doesn't restart it within 10s, try manually
    sleep 10
    local new_code
    new_code=$(check_health)
    if [[ "$new_code" != "200" && "$new_code" != "204" ]]; then
      log "launchd didn't restart gateway. attempting manual start..."
      launchctl kickstart -k "gui/$(id -u)/ai.openclaw.gateway" 2>/dev/null || true
    fi
    
    set_state "consecutive_failures" "0"
    set_state "last_recovery" "$(date +%s)"
  fi
  
else
  # Got a response but not healthy
  log "Health check returned HTTP ${http_code}"
fi

# 2. Session bloat check
check_sessions || true

# 3. Config validation check  
check_config || true

# 4. Disk space check
disk_usage=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
if [[ $disk_usage -gt 90 ]]; then
  alert "disk usage at ${disk_usage}%"
fi
