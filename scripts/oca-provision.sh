#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
# OCA Provisioning Script
# Runs AFTER oca-client-mac-setup.sh (which handles OS hardening).
# This script installs OpenClaw, deploys the starter kit, configures
# API keys, starts the gateway, and sets up cron jobs.
#
# Usage:
#   ./oca-provision.sh                    # interactive install
#   ./oca-provision.sh --dry-run          # show what would happen
#   ./oca-provision.sh --check            # verify existing install
#   ./oca-provision.sh --auth oauth        # use OAuth (skip auth prompt)
#   ./oca-provision.sh --auth apikey       # use API keys (skip auth prompt)
#
# ═══════════════════════════════════════════════════════════════════

set -euo pipefail

# ─── OCA Config — HypeLab sets these per-client ─────────────────
OCA_CLIENT_NAME=""          # e.g. "acme-corp"
OCA_AGENT_NAME=""           # e.g. "jarvis"
OCA_TAILSCALE_AUTHKEY=""    # pre-auth key for tailnet join
OCA_HYPELAB_MONITOR_URL=""  # optional: monitoring webhook

# ─── Defaults ────────────────────────────────────────────────────
WORKSPACE="${HOME}/clawd"
OPENCLAW_DIR="${HOME}/.openclaw"
STARTER_KIT_REPO="https://github.com/jeffweisbein/openclaw-starter-kit.git"
GATEWAY_PORT=18789
MIN_NODE_VERSION=20
DRY_RUN=false
CHECK_ONLY=false
AUTH_MODE=""          # oauth or apikey (empty = interactive prompt)
OAUTH_PROVIDER=""     # anthropic or openai (for oauth mode)
REPORT_FILE=""

# ─── Colors ──────────────────────────────────────────────────────
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
CYAN="\033[0;36m"
BOLD="\033[1m"
RESET="\033[0m"

# ─── Logging ─────────────────────────────────────────────────────
pass()  { echo -e "  ${GREEN}[PASS]${RESET} $*"; }
warn()  { echo -e "  ${YELLOW}[WARN]${RESET} $*"; }
fail()  { echo -e "  ${RED}[FAIL]${RESET} $*"; }
info()  { echo -e "  ${BLUE}[INFO]${RESET} $*"; }
step()  { echo -e "\n${CYAN}${BOLD}→ $*${RESET}"; }

# ─── Report tracking ────────────────────────────────────────────
declare -a REPORT_ENTRIES=()
REPORT_STATUS="success"
report_add() {
  local key="$1" value="$2"
  REPORT_ENTRIES+=("\"${key}\": ${value}")
}

# ─── Parse args ──────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)       DRY_RUN=true; shift ;;
    --check)         CHECK_ONLY=true; shift ;;
    --workspace)     WORKSPACE="$2"; shift 2 ;;
    --client)        OCA_CLIENT_NAME="$2"; shift 2 ;;
    --agent)         OCA_AGENT_NAME="$2"; shift 2 ;;
    --tailscale-key) OCA_TAILSCALE_AUTHKEY="$2"; shift 2 ;;
    --monitor-url)   OCA_HYPELAB_MONITOR_URL="$2"; shift 2 ;;
    --auth)          AUTH_MODE="$2"; shift 2 ;;
    --provider)      OAUTH_PROVIDER="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--dry-run] [--check] [--workspace PATH] [--client NAME] [--agent NAME]"
      echo "       [--tailscale-key KEY] [--monitor-url URL]"
      echo "       [--auth oauth|apikey] [--provider anthropic|openai]"
      exit 0 ;;
    *) echo "unknown arg: $1"; exit 1 ;;
  esac
done

REPORT_FILE="${WORKSPACE}/oca-provision-report.json"

# ─── Banner ──────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  OCA Provisioning — OpenClaw Agent Setup${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
if $DRY_RUN; then
  echo -e "  ${YELLOW}DRY RUN — no changes will be made${RESET}"
fi
if $CHECK_ONLY; then
  echo -e "  ${BLUE}CHECK MODE — verifying existing install${RESET}"
fi
echo ""

# ═════════════════════════════════════════════════════════════════
# 1. PRE-FLIGHT CHECKS
# ═════════════════════════════════════════════════════════════════
step "Pre-flight checks"

# macOS check
if [[ "$(uname)" != "Darwin" ]]; then
  fail "This script requires macOS (detected: $(uname))"
  exit 1
fi
pass "macOS detected ($(sw_vers -productVersion))"
report_add "macos_version" "\"$(sw_vers -productVersion)\""

# Node.js check
if ! command -v node &>/dev/null; then
  fail "Node.js not found. Install Node.js ${MIN_NODE_VERSION}+ first."
  fail "  brew install node  OR  https://nodejs.org"
  exit 1
fi

NODE_VERSION=$(node -v | sed 's/v//' | cut -d. -f1)
if [[ "$NODE_VERSION" -lt "$MIN_NODE_VERSION" ]]; then
  fail "Node.js ${MIN_NODE_VERSION}+ required (found: $(node -v))"
  exit 1
fi
pass "Node.js $(node -v)"
report_add "node_version" "\"$(node -v)\""

# Current user
CURRENT_USER=$(whoami)
pass "Running as: ${CURRENT_USER}"
report_add "user" "\"${CURRENT_USER}\""

if $CHECK_ONLY; then
  step "Checking existing installation"

  if command -v openclaw &>/dev/null; then
    pass "OpenClaw installed: $(openclaw --version 2>/dev/null || echo 'unknown version')"
  else
    fail "OpenClaw not installed"
    REPORT_STATUS="fail"
  fi

  if [[ -d "$WORKSPACE" ]]; then
    pass "Workspace exists: ${WORKSPACE}"
  else
    fail "Workspace missing: ${WORKSPACE}"
    REPORT_STATUS="fail"
  fi

  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://127.0.0.1:${GATEWAY_PORT}/health" 2>/dev/null || echo "000")
  if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "204" ]]; then
    pass "Gateway healthy (port ${GATEWAY_PORT})"
  else
    fail "Gateway not responding (HTTP ${HTTP_CODE})"
    REPORT_STATUS="fail"
  fi

  # Check auth — either OAuth or API keys
  OAUTH_LOGGED_IN=false
  if command -v openclaw &>/dev/null; then
    if openclaw auth status 2>/dev/null | grep -qi "logged in\|authenticated"; then
      pass "OAuth authentication active"
      OAUTH_LOGGED_IN=true
    fi
  fi

  if [[ "${OAUTH_LOGGED_IN}" != "true" ]]; then
    if [[ -f "${OPENCLAW_DIR}/.env" ]]; then
      if grep -q "ANTHROPIC_API_KEY=" "${OPENCLAW_DIR}/.env" 2>/dev/null; then
        pass "Anthropic API key configured"
      else
        warn "Anthropic API key not found in .env"
      fi
    else
      fail "No OAuth session and no .env file at ${OPENCLAW_DIR}/.env"
      REPORT_STATUS="fail"
    fi
  fi

  echo ""
  echo -e "${BOLD}Check result: ${REPORT_STATUS}${RESET}"
  exit 0
fi

# ═════════════════════════════════════════════════════════════════
# 2. INSTALL OPENCLAW
# ═════════════════════════════════════════════════════════════════
step "Installing OpenClaw"

if command -v openclaw &>/dev/null; then
  EXISTING_VERSION=$(openclaw --version 2>/dev/null || echo "unknown")
  info "OpenClaw already installed (${EXISTING_VERSION}), updating..."
  if ! $DRY_RUN; then
    npm install -g openclaw 2>/dev/null || npm install -g openclaw
  fi
else
  info "Installing OpenClaw globally..."
  if ! $DRY_RUN; then
    npm install -g openclaw 2>/dev/null || npm install -g openclaw
  fi
fi

OPENCLAW_VERSION=$(openclaw --version 2>/dev/null || echo "installed")
pass "OpenClaw ${OPENCLAW_VERSION}"
report_add "openclaw_version" "\"${OPENCLAW_VERSION}\""

# ═════════════════════════════════════════════════════════════════
# 3. INITIAL SETUP
# ═════════════════════════════════════════════════════════════════
step "Running OpenClaw setup"

if ! $DRY_RUN; then
  mkdir -p "${OPENCLAW_DIR}"
  if [[ ! -f "${OPENCLAW_DIR}/openclaw.json" ]]; then
    info "No existing config found — running interactive setup..."
    openclaw setup 2>/dev/null || openclaw configure 2>/dev/null || {
      warn "Interactive setup failed — will generate config manually"
    }
  else
    info "Existing config found at ${OPENCLAW_DIR}/openclaw.json"
  fi
else
  info "[dry-run] Would run: openclaw setup"
fi
pass "OpenClaw configured"

# ═════════════════════════════════════════════════════════════════
# 4. DEPLOY STARTER KIT
# ═════════════════════════════════════════════════════════════════
step "Deploying starter kit"

if [[ -d "${WORKSPACE}/.git" ]]; then
  info "Workspace already has a git repo — pulling latest..."
  if ! $DRY_RUN; then
    cd "${WORKSPACE}" && git pull --ff-only 2>/dev/null || warn "Could not pull (may have local changes)"
  fi
elif [[ -d "${WORKSPACE}" ]] && [[ "$(ls -A "${WORKSPACE}" 2>/dev/null)" ]]; then
  warn "Workspace exists and is not empty — skipping clone to avoid data loss"
  info "To deploy fresh: rm -rf ${WORKSPACE} && re-run this script"
else
  info "Cloning starter kit into ${WORKSPACE}..."
  if ! $DRY_RUN; then
    git clone "${STARTER_KIT_REPO}" "${WORKSPACE}"
  fi
fi

pass "Starter kit deployed to ${WORKSPACE}"
report_add "workspace" "\"${WORKSPACE}\""

# ═════════════════════════════════════════════════════════════════
# 5. SELECT AUTHENTICATION METHOD
# ═════════════════════════════════════════════════════════════════
step "Configuring authentication"

EXA_CONFIGURED=false

if [[ -z "${AUTH_MODE}" ]] && ! $DRY_RUN; then
  echo ""
  echo -e "  ${BOLD}Select authentication method:${RESET}"
  echo "    1) OAuth (Claude Max / ChatGPT Pro subscription) — recommended for managed clients"
  echo "    2) API Keys (Anthropic / OpenAI direct)"
  echo ""
  read -p "  Choice [1/2]: " AUTH_CHOICE
  case "${AUTH_CHOICE}" in
    1) AUTH_MODE="oauth" ;;
    2) AUTH_MODE="apikey" ;;
    *) info "Invalid choice, defaulting to API keys"; AUTH_MODE="apikey" ;;
  esac
elif [[ -z "${AUTH_MODE}" ]]; then
  AUTH_MODE="apikey"
fi

info "Auth mode: ${AUTH_MODE}"
report_add "auth_mode" "\"${AUTH_MODE}\""

# ═════════════════════════════════════════════════════════════════
# 5a. OAUTH FLOW
# ═════════════════════════════════════════════════════════════════
if [[ "${AUTH_MODE}" == "oauth" ]]; then
  step "Setting up OAuth authentication"

  # Select provider if not already set
  if [[ -z "${OAUTH_PROVIDER}" ]] && ! $DRY_RUN; then
    echo ""
    echo -e "  ${BOLD}Select OAuth provider:${RESET}"
    echo "    1) Claude Max (Anthropic)"
    echo "    2) ChatGPT Pro (OpenAI)"
    echo ""
    read -p "  Provider [1/2]: " PROVIDER_CHOICE
    case "${PROVIDER_CHOICE}" in
      1) OAUTH_PROVIDER="anthropic" ;;
      2) OAUTH_PROVIDER="openai" ;;
      *) info "Invalid choice, defaulting to Anthropic"; OAUTH_PROVIDER="anthropic" ;;
    esac
  elif [[ -z "${OAUTH_PROVIDER}" ]]; then
    OAUTH_PROVIDER="anthropic"
  fi

  info "OAuth provider: ${OAUTH_PROVIDER}"
  report_add "oauth_provider" "\"${OAUTH_PROVIDER}\""

  if ! $DRY_RUN; then
    echo ""
    info "Opening browser for OAuth login..."

    if [[ "${OAUTH_PROVIDER}" == "openai" ]]; then
      openclaw onboard --auth-choice openai-codex || {
        fail "OAuth login failed for OpenAI"
        REPORT_STATUS="partial"
      }
    else
      openclaw onboard --auth-choice oauth || {
        fail "OAuth login failed for Anthropic"
        REPORT_STATUS="partial"
      }
    fi

    # Verify auth succeeded
    sleep 2
    if openclaw auth status 2>/dev/null | grep -qi "logged in\|authenticated"; then
      pass "OAuth authentication successful"
    else
      fail "OAuth authentication could not be verified"
      warn "You may need to run openclaw auth login manually"
      REPORT_STATUS="partial"
    fi
  else
    info "[dry-run] Would run: openclaw auth login ${OAUTH_PROVIDER:+--provider ${OAUTH_PROVIDER}}"
  fi

  # Exa key (still needed separately for web search)
  if ! $DRY_RUN; then
    mkdir -p "${OPENCLAW_DIR}"
    ENV_FILE="${OPENCLAW_DIR}/.env"
    [[ -f "${ENV_FILE}" ]] || touch "${ENV_FILE}"

    if grep -q "EXA_API_KEY=" "${ENV_FILE}" 2>/dev/null; then
      info "Exa API key already set"
      EXA_CONFIGURED=true
    else
      echo ""
      echo -e "  ${BOLD}Exa API key (optional — web search)${RESET}"
      echo "  Get one at: https://exa.ai"
      read -sp "  EXA_API_KEY (enter to skip): " EXA_KEY
      echo ""
      if [[ -n "${EXA_KEY}" ]]; then
        echo "EXA_API_KEY=${EXA_KEY}" >> "${ENV_FILE}"
        pass "Exa API key saved"
        EXA_CONFIGURED=true
      else
        info "Skipped Exa key"
      fi
    fi

    chmod 600 "${ENV_FILE}"
  else
    info "[dry-run] Would prompt for: EXA_API_KEY"
  fi

  report_add "api_keys_configured" "true"

# ═════════════════════════════════════════════════════════════════
# 5b. API KEY FLOW
# ═════════════════════════════════════════════════════════════════
else
  step "Configuring API keys"

  if ! $DRY_RUN; then
    mkdir -p "${OPENCLAW_DIR}"
    ENV_FILE="${OPENCLAW_DIR}/.env"
    [[ -f "${ENV_FILE}" ]] || touch "${ENV_FILE}"

    # Anthropic (required)
    if grep -q "ANTHROPIC_API_KEY=" "${ENV_FILE}" 2>/dev/null; then
      info "Anthropic API key already set"
    else
      echo ""
      echo -e "  ${BOLD}Anthropic API key (required)${RESET}"
      echo "  Get one at: https://console.anthropic.com/settings/keys"
      read -sp "  ANTHROPIC_API_KEY: " ANTHROPIC_KEY
      echo ""
      if [[ -n "${ANTHROPIC_KEY}" ]]; then
        echo "ANTHROPIC_API_KEY=${ANTHROPIC_KEY}" >> "${ENV_FILE}"
        pass "Anthropic API key saved"
      else
        fail "Anthropic API key is required"
        REPORT_STATUS="partial"
      fi
    fi

    # OpenAI (optional)
    if grep -q "OPENAI_API_KEY=" "${ENV_FILE}" 2>/dev/null; then
      info "OpenAI API key already set"
    else
      echo ""
      echo -e "  ${BOLD}OpenAI API key (optional — fallback model)${RESET}"
      read -sp "  OPENAI_API_KEY (enter to skip): " OPENAI_KEY
      echo ""
      if [[ -n "${OPENAI_KEY}" ]]; then
        echo "OPENAI_API_KEY=${OPENAI_KEY}" >> "${ENV_FILE}"
        pass "OpenAI API key saved"
      else
        info "Skipped OpenAI key"
      fi
    fi

    # Exa (optional)
    if grep -q "EXA_API_KEY=" "${ENV_FILE}" 2>/dev/null; then
      info "Exa API key already set"
      EXA_CONFIGURED=true
    else
      echo ""
      echo -e "  ${BOLD}Exa API key (optional — web search)${RESET}"
      echo "  Get one at: https://exa.ai"
      read -sp "  EXA_API_KEY (enter to skip): " EXA_KEY
      echo ""
      if [[ -n "${EXA_KEY}" ]]; then
        echo "EXA_API_KEY=${EXA_KEY}" >> "${ENV_FILE}"
        pass "Exa API key saved"
        EXA_CONFIGURED=true
      else
        info "Skipped Exa key"
      fi
    fi

    chmod 600 "${ENV_FILE}"
    pass "API keys written to ${ENV_FILE}"
  else
    info "[dry-run] Would prompt for: ANTHROPIC_API_KEY, OPENAI_API_KEY, EXA_API_KEY"
  fi

  report_add "api_keys_configured" "true"
fi

# ═════════════════════════════════════════════════════════════════
# 7-8. ENABLE PLUGINS & CONFIGURE EXA
# ═════════════════════════════════════════════════════════════════
step "Configuring plugins"

if [[ "${EXA_CONFIGURED}" == "true" ]]; then
  info "Enabling Exa search plugin..."
  if ! $DRY_RUN; then
    openclaw plugins enable exa 2>/dev/null || warn "Could not enable exa plugin (may need manual setup)"

    CONFIG_FILE="${OPENCLAW_DIR}/openclaw.json"
    if [[ -f "${CONFIG_FILE}" ]] && command -v python3 &>/dev/null; then
      python3 -c "
import json, sys
try:
    with open('${CONFIG_FILE}', 'r') as f:
        config = json.load(f)
    config.setdefault('tools', {}).setdefault('web', {}).setdefault('search', {})['provider'] = 'exa'
    with open('${CONFIG_FILE}', 'w') as f:
        json.dump(config, f, indent=2)
    print('  updated openclaw.json with exa search provider')
except Exception as e:
    print(f'  warning: could not update config: {e}', file=sys.stderr)
"
    fi
  fi
  pass "Exa search enabled as default provider"
  report_add "exa_enabled" "true"
else
  info "Exa not configured — skipping plugin setup"
  report_add "exa_enabled" "false"
fi

# ═════════════════════════════════════════════════════════════════
# 9. CREATE MEMORY DIRECTORY
# ═════════════════════════════════════════════════════════════════
step "Setting up memory directory"

if ! $DRY_RUN; then
  mkdir -p "${WORKSPACE}/memory"
fi
pass "Memory directory ready: ${WORKSPACE}/memory"

# ═════════════════════════════════════════════════════════════════
# 10. START GATEWAY
# ═════════════════════════════════════════════════════════════════
step "Starting OpenClaw gateway"

if ! $DRY_RUN; then
  openclaw gateway install 2>/dev/null || true

  if ! launchctl list 2>/dev/null | grep -q "ai.openclaw.gateway"; then
    openclaw gateway start 2>/dev/null || warn "Could not start gateway (may need manual start)"
  else
    info "Gateway service already loaded"
  fi

  sleep 3
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://127.0.0.1:${GATEWAY_PORT}/health" 2>/dev/null || echo "000")
  if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "204" ]]; then
    pass "Gateway healthy on port ${GATEWAY_PORT}"
    report_add "gateway_healthy" "true"
  else
    warn "Gateway not responding yet (HTTP ${HTTP_CODE}) — may need a moment"
    report_add "gateway_healthy" "false"
  fi
else
  info "[dry-run] Would run: openclaw gateway install && openclaw gateway start"
  report_add "gateway_healthy" "\"dry-run\""
fi

# ═════════════════════════════════════════════════════════════════
# 11. NIGHTLY CONSOLIDATION CRON
# ═════════════════════════════════════════════════════════════════
step "Setting up nightly memory consolidation"

CONSOLIDATION_PROMPT='Review today'\''s conversations. Extract any unsaved decisions, preferences, or corrections into memory. Clean up stale memories. Check MISTAKES.md for entries missing standing rules. Write a summary to memory/consolidation-$(date +%Y-%m-%d).md.'

if ! $DRY_RUN; then
  openclaw cron add "nightly-consolidation" \
    --schedule "0 2 * * *" \
    --prompt "${CONSOLIDATION_PROMPT}" 2>/dev/null || {
    warn "Could not add cron via openclaw — you may need to add it manually"
    info "Schedule: 0 2 * * * (daily at 2am)"
  }
else
  info "[dry-run] Would add cron: nightly-consolidation @ 0 2 * * *"
fi
pass "Nightly consolidation cron configured (2am daily)"
report_add "cron_consolidation" "true"

# ═════════════════════════════════════════════════════════════════
# 12. WEEKLY MEMORY CLEANUP CRON
# ═════════════════════════════════════════════════════════════════
step "Setting up weekly memory cleanup"

CLEANUP_PROMPT='Deep review of all memories. Deduplicate, merge related entries, archive anything older than 90 days that has not been accessed. Update MEMORY.md sections.'

if ! $DRY_RUN; then
  openclaw cron add "weekly-memory-cleanup" \
    --schedule "0 3 * * 0" \
    --prompt "${CLEANUP_PROMPT}" 2>/dev/null || {
    warn "Could not add cron via openclaw — you may need to add it manually"
    info "Schedule: 0 3 * * 0 (Sundays at 3am)"
  }
else
  info "[dry-run] Would add cron: weekly-memory-cleanup @ 0 3 * * 0"
fi
pass "Weekly cleanup cron configured (Sundays 3am)"
report_add "cron_weekly_cleanup" "true"

# ═════════════════════════════════════════════════════════════════
# TAILSCALE (if OCA key provided)
# ═════════════════════════════════════════════════════════════════
if [[ -n "${OCA_TAILSCALE_AUTHKEY}" ]]; then
  step "Configuring Tailscale for OCA remote management"

  HOSTNAME="oca-${OCA_CLIENT_NAME:-client}-${OCA_AGENT_NAME:-agent}"

  if ! command -v tailscale &>/dev/null; then
    info "Installing Tailscale..."
    if ! $DRY_RUN; then
      brew install --cask tailscale 2>/dev/null || {
        fail "Could not install Tailscale"
        REPORT_STATUS="partial"
      }
    fi
  fi

  if command -v tailscale &>/dev/null; then
    if ! $DRY_RUN; then
      info "Joining HypeLab tailnet as ${HOSTNAME}..."
      sudo tailscale up --authkey="${OCA_TAILSCALE_AUTHKEY}" --hostname="${HOSTNAME}" 2>/dev/null || {
        warn "Could not join tailnet — may need manual setup"
      }

      TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "")
      if [[ -n "${TAILSCALE_IP}" ]]; then
        pass "Tailscale connected: ${TAILSCALE_IP}"
        report_add "tailscale_ip" "\"${TAILSCALE_IP}\""
      else
        warn "Tailscale not yet connected"
        report_add "tailscale_ip" "null"
      fi
    else
      info "[dry-run] Would join tailnet as: ${HOSTNAME}"
    fi
  fi

  # Configure SSH access for hypelab-agent user
  step "Configuring SSH access for HypeLab remote management"

  if ! $DRY_RUN; then
    if ! id "hypelab-agent" &>/dev/null; then
      info "Creating hypelab-agent user..."
      sudo sysadminctl -addUser hypelab-agent -shell /bin/bash -password "$(openssl rand -hex 16)" 2>/dev/null || {
        warn "Could not create hypelab-agent user — may need manual setup"
      }
    else
      info "hypelab-agent user already exists"
    fi

    HYPELAB_HOME=$(eval echo ~hypelab-agent 2>/dev/null || echo "/Users/hypelab-agent")
    sudo mkdir -p "${HYPELAB_HOME}/.ssh" 2>/dev/null || true
    sudo chmod 700 "${HYPELAB_HOME}/.ssh" 2>/dev/null || true
    sudo systemsetup -setremotelogin on 2>/dev/null || true

    pass "SSH access configured for hypelab-agent"
    report_add "ssh_configured" "true"
  else
    info "[dry-run] Would create hypelab-agent user and configure SSH"
    report_add "ssh_configured" "\"dry-run\""
  fi
else
  info "No Tailscale auth key provided — skipping remote management setup"
  report_add "tailscale_ip" "null"
  report_add "ssh_configured" "false"
fi

# ═════════════════════════════════════════════════════════════════
# 13. VERIFY INSTALLATION
# ═════════════════════════════════════════════════════════════════
step "Verifying installation"

CHECKS_PASSED=0
CHECKS_TOTAL=0

CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
if command -v openclaw &>/dev/null; then
  pass "OpenClaw binary found"
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
  fail "OpenClaw binary not found"
fi

CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
if [[ -d "${WORKSPACE}" ]]; then
  pass "Workspace exists"
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
  fail "Workspace missing"
fi

CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
if [[ -d "${WORKSPACE}/memory" ]]; then
  pass "Memory directory exists"
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
  fail "Memory directory missing"
fi

CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
if [[ -f "${OPENCLAW_DIR}/openclaw.json" ]]; then
  pass "Config file exists"
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
  fail "Config file missing"
fi

CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
if [[ "${AUTH_MODE}" == "oauth" ]]; then
  if command -v openclaw &>/dev/null && openclaw auth status 2>/dev/null | grep -qi "logged in\|authenticated"; then
    pass "OAuth session active"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
  else
    fail "OAuth session not active"
  fi
else
  if [[ -f "${OPENCLAW_DIR}/.env" ]]; then
    pass "API keys file exists"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
  else
    fail "API keys file missing"
  fi
fi

if ! $DRY_RUN; then
  CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://127.0.0.1:${GATEWAY_PORT}/health" 2>/dev/null || echo "000")
  if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "204" ]]; then
    pass "Gateway responding"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
  else
    warn "Gateway not responding (HTTP ${HTTP_CODE})"
  fi
fi

report_add "checks_passed" "${CHECKS_PASSED}"
report_add "checks_total" "${CHECKS_TOTAL}"

# ═════════════════════════════════════════════════════════════════
# 14. GENERATE REPORT
# ═════════════════════════════════════════════════════════════════
step "Generating provision report"

if ! $DRY_RUN; then
  mkdir -p "$(dirname "${REPORT_FILE}")"

  # Build JSON report
  {
    echo "{"
    echo "  \"provisioned_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
    echo "  \"status\": \"${REPORT_STATUS}\","
    echo "  \"oca_client\": \"${OCA_CLIENT_NAME}\","
    echo "  \"oca_agent\": \"${OCA_AGENT_NAME}\","
    for i in "${!REPORT_ENTRIES[@]}"; do
      if [[ $i -lt $((${#REPORT_ENTRIES[@]} - 1)) ]]; then
        echo "  ${REPORT_ENTRIES[$i]},"
      else
        echo "  ${REPORT_ENTRIES[$i]}"
      fi
    done
    echo "}"
  } > "${REPORT_FILE}"

  pass "Report saved to ${REPORT_FILE}"
else
  info "[dry-run] Would write report to ${REPORT_FILE}"
fi

# Send to monitoring webhook if configured
if [[ -n "${OCA_HYPELAB_MONITOR_URL}" ]] && [[ -f "${REPORT_FILE}" ]] && ! $DRY_RUN; then
  info "Sending report to HypeLab monitoring..."
  curl -s -X POST -H "Content-Type: application/json" -d @"${REPORT_FILE}" "${OCA_HYPELAB_MONITOR_URL}" 2>/dev/null || {
    warn "Could not reach monitoring webhook"
  }
fi

# ═════════════════════════════════════════════════════════════════
# DONE
# ═════════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
echo -e "  ${GREEN}${BOLD}✅ OCA Provisioning Complete${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
echo ""
echo -e "  workspace:     ${WORKSPACE}"
echo -e "  config:        ${OPENCLAW_DIR}/openclaw.json"
if [[ "${AUTH_MODE}" == "oauth" ]]; then
  echo -e "  auth:          OAuth (${OAUTH_PROVIDER:-anthropic})"
else
  echo -e "  auth:          API keys (${OPENCLAW_DIR}/.env)"
fi
echo -e "  gateway:       http://127.0.0.1:${GATEWAY_PORT}"
echo -e "  verification:  ${CHECKS_PASSED}/${CHECKS_TOTAL} checks passed"
echo -e "  report:        ${REPORT_FILE}"
[[ -n "${OCA_CLIENT_NAME}" ]] && echo -e "  client:        ${OCA_CLIENT_NAME}"
[[ -n "${OCA_AGENT_NAME}" ]] && echo -e "  agent:         ${OCA_AGENT_NAME}"
echo ""
echo -e "  ${BOLD}Next steps:${RESET}"
echo "  1. Fill in ${WORKSPACE}/USER.md with client info"
echo "  2. Fill in ${WORKSPACE}/IDENTITY.md to name the agent"
echo "  3. Test: openclaw chat \"hello\""
echo ""
