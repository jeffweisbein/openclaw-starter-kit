#!/bin/bash
# OpenClaw Mac Bootstrap Script
# Run this on a fresh Mac to set up a full OpenClaw agent environment.
# Automates everything from Homebrew to gateway launch.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/jeffweisbein/openclaw-starter-kit/main/scripts/bootstrap-mac.sh | bash
#   OR
#   ./bootstrap-mac.sh [--identity NAME] [--tailscale-key TSKEY]
#
# What it does:
# 1. Installs Homebrew (if missing)
# 2. Installs Node.js, git, tailscale, imsg
# 3. Installs OpenClaw globally
# 4. Sets up workspace directory structure
# 5. Configures tailscale for mesh networking
# 6. Generates gateway config with secure tokens
# 7. Installs watchdog for self-healing
# 8. Starts the gateway via launchd

set -euo pipefail

# --- Parse Args ---
IDENTITY=""
TAILSCALE_KEY=""
ALERT_NUMBER=""
PEER_GATEWAY=""
WORKSPACE="$HOME/clawd"

while [[ $# -gt 0 ]]; do
  case $1 in
    --identity) IDENTITY="$2"; shift 2 ;;
    --tailscale-key) TAILSCALE_KEY="$2"; shift 2 ;;
    --alert) ALERT_NUMBER="$2"; shift 2 ;;
    --peer) PEER_GATEWAY="$2"; shift 2 ;;
    --workspace) WORKSPACE="$2"; shift 2 ;;
    *) echo "unknown arg: $1"; exit 1 ;;
  esac
done

# --- Interactive prompts for missing values ---
if [[ -z "$IDENTITY" ]]; then
  read -p "agent identity name (e.g. clawd, nova, patches): " IDENTITY
fi

echo ""
echo "🚀 bootstrapping openclaw agent: ${IDENTITY}"
echo "   workspace: ${WORKSPACE}"
echo ""

# --- Helper ---
step() { echo ""; echo "→ $*"; }

# --- 1. Homebrew ---
step "checking homebrew..."
if ! command -v brew &>/dev/null; then
  echo "  installing homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
else
  echo "  homebrew ✓"
fi

# --- 2. Dependencies ---
step "installing dependencies..."
brew install node git 2>/dev/null || true

# Tailscale
if ! command -v tailscale &>/dev/null; then
  echo "  installing tailscale..."
  brew install --cask tailscale 2>/dev/null || true
fi

# imsg (for iMessage integration)
if ! command -v imsg &>/dev/null; then
  echo "  installing imsg..."
  brew install openclaw/tap/imsg 2>/dev/null || echo "  imsg tap not available — skip (can add later)"
fi

echo "  node $(node -v) ✓"

# --- 3. OpenClaw ---
step "installing openclaw..."
npm install -g openclaw 2>/dev/null || npm install -g openclaw
OPENCLAW_VERSION=$(openclaw --version 2>/dev/null || echo "installed")
echo "  openclaw ${OPENCLAW_VERSION} ✓"

# --- 4. Workspace ---
step "setting up workspace..."
mkdir -p "$WORKSPACE"/{agents,tasks,scripts,docs,share}
mkdir -p "$HOME/.openclaw"/{logs,extensions,agents}

# Create task board
if [[ ! -f "$WORKSPACE/tasks/active.md" ]]; then
  cat > "$WORKSPACE/tasks/active.md" << 'TASKEOF'
# Active Tasks

_Updated: $(date '+%Y-%m-%d')_

## 🔥 In Progress

## 🅿️ Parked

## ✅ Done Today
TASKEOF
fi

# --- 5. Generate tokens ---
step "generating secure tokens..."
GATEWAY_TOKEN=$(openssl rand -hex 24)
HOOKS_TOKEN=$(openssl rand -hex 24)

# --- 6. Tailscale ---
step "configuring tailscale..."
if command -v tailscale &>/dev/null; then
  if [[ -n "$TAILSCALE_KEY" ]]; then
    echo "  authenticating with pre-auth key..."
    sudo tailscale up --authkey="$TAILSCALE_KEY" --hostname="openclaw-${IDENTITY}" 2>/dev/null || true
  else
    TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "")
    if [[ -n "$TAILSCALE_IP" ]]; then
      echo "  tailscale connected: ${TAILSCALE_IP} ✓"
    else
      echo "  tailscale not connected."
      echo "  run: tailscale up --hostname=openclaw-${IDENTITY}"
      echo "  or re-run with: --tailscale-key YOUR_PREAUTH_KEY"
    fi
  fi
fi

# --- 7. OpenClaw config ---
step "generating openclaw config..."

TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "")
TAILSCALE_MODE="off"
if [[ -n "$TAILSCALE_IP" ]]; then
  TAILSCALE_MODE="on"
fi

cat > "$HOME/.openclaw/openclaw.json" << CONFIGEOF
{
  "meta": {
    "bootstrapVersion": "1.0.0",
    "identity": "${IDENTITY}",
    "bootstrapDate": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "anthropic/claude-sonnet-4-6-20260217",
        "fallbacks": []
      },
      "workspace": "${WORKSPACE}",
      "memorySearch": {
        "enabled": false,
        "sources": ["memory"]
      },
      "compaction": {
        "memoryFlush": { "enabled": true }
      },
      "maxConcurrent": 4,
      "subagents": { "maxConcurrent": 8 },
      "sandbox": { "mode": "off" }
    },
    "list": [
      { "id": "main" }
    ]
  },
  "tools": {
    "alsoAllow": ["group:plugins"]
  },
  "commands": {
    "native": "auto",
    "nativeSkills": "auto",
    "restart": true
  },
  "hooks": {
    "enabled": true,
    "token": "${HOOKS_TOKEN}"
  },
  "channels": {},
  "gateway": {
    "port": 18789,
    "mode": "local",
    "bind": "loopback",
    "auth": {
      "mode": "token",
      "token": "${GATEWAY_TOKEN}"
    },
    "tailscale": {
      "mode": "${TAILSCALE_MODE}",
      "resetOnExit": false
    },
    "remote": {
      "token": "${GATEWAY_TOKEN}"
    }
  },
  "plugins": {
    "slots": {
      "memory": "memory-tools"
    },
    "entries": {
      "memory-tools": {
        "enabled": true,
        "config": {
          "embedding": {},
          "dbPath": "${HOME}/.openclaw/memory/tools"
        }
      }
    }
  }
}
CONFIGEOF

echo "  config written to ~/.openclaw/openclaw.json ✓"

# --- 8. Peer configuration ---
if [[ -n "$PEER_GATEWAY" ]]; then
  step "configuring peer gateway..."
  echo "  peer: ${PEER_GATEWAY}"
  
  # Save peer info for cross-gateway communication
  cat > "$WORKSPACE/.peer-config.json" << PEEREOF
{
  "peer": "${PEER_GATEWAY}",
  "identity": "${IDENTITY}",
  "configured": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
PEEREOF
  echo "  peer config saved ✓"
fi

# --- 9. Install watchdog ---
step "installing self-healing watchdog..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ -f "${SCRIPT_DIR}/watchdog.sh" ]]; then
  cp "${SCRIPT_DIR}/watchdog.sh" "$WORKSPACE/scripts/watchdog.sh"
  cp "${SCRIPT_DIR}/watchdog-install.sh" "$WORKSPACE/scripts/watchdog-install.sh"
  chmod +x "$WORKSPACE/scripts/watchdog.sh" "$WORKSPACE/scripts/watchdog-install.sh"
  bash "$WORKSPACE/scripts/watchdog-install.sh" "$ALERT_NUMBER"
else
  echo "  watchdog scripts not found in ${SCRIPT_DIR} — skip"
  echo "  install manually later from the starter kit"
fi

# --- 10. Gateway setup via openclaw onboard ---
step "running openclaw onboard..."
openclaw gateway install 2>/dev/null || true

# --- 11. Start gateway ---
step "starting gateway..."
# The onboard/install should have created the launchd plist
# If not, start manually
if launchctl list | grep -q "ai.openclaw.gateway"; then
  echo "  gateway service already loaded ✓"
else
  openclaw gateway start 2>/dev/null || true
fi

# Wait for health
sleep 3
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://127.0.0.1:18789/health" 2>/dev/null || echo "000")

if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "204" ]]; then
  echo "  gateway healthy ✓"
else
  echo "  gateway not responding yet (HTTP ${HTTP_CODE}) — may need manual check"
fi

# --- Summary ---
echo ""
echo "═══════════════════════════════════════════════"
echo "  ✅ openclaw agent '${IDENTITY}' bootstrapped!"
echo "═══════════════════════════════════════════════"
echo ""
echo "  workspace:    ${WORKSPACE}"
echo "  config:       ~/.openclaw/openclaw.json"
echo "  gateway:      http://127.0.0.1:18789"
echo "  gateway token: ${GATEWAY_TOKEN}"
echo "  hooks token:   ${HOOKS_TOKEN}"
[[ -n "$TAILSCALE_IP" ]] && echo "  tailscale ip:  ${TAILSCALE_IP}"
echo ""
echo "  next steps:"
echo "  1. run 'openclaw auth' to connect your anthropic/openai keys"
echo "  2. set up channels (imessage, discord, etc)"
[[ -z "$TAILSCALE_IP" ]] && echo "  3. connect tailscale: tailscale up --hostname=openclaw-${IDENTITY}"
[[ -n "$PEER_GATEWAY" ]] && echo "  3. peer gateway configured: ${PEER_GATEWAY}"
echo ""
echo "  to test: curl http://127.0.0.1:18789/health"
echo ""
