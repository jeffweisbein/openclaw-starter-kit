#!/bin/bash
# Auto-backup your OpenClaw workspace to GitHub
# Runs hourly via cron. Commits only if there are changes.
# Setup: your workspace (~~/clawd/) should be a git repo with a remote.
#
# Cron example (openclaw gateway cron):
#   schedule: "0 * * * *"
#   payload: { kind: "agentTurn", message: "run bash ~/clawd/scripts/auto-backup.sh" }

WORKSPACE="${OPENCLAW_WORKSPACE:-$HOME/clawd}"
cd "$WORKSPACE" || exit 1

# Add everything except large/temp files
git add -A

# Check if there are staged changes
if git diff --cached --quiet; then
    exit 0  # nothing to commit
fi

# Count changed files for commit message
CHANGED=$(git diff --cached --name-only | wc -l | tr -d ' ')
TIMESTAMP=$(date '+%Y-%m-%d %H:%M')

git commit -m "auto-backup: ${CHANGED} files changed at ${TIMESTAMP}" --quiet
git push origin main --quiet 2>/dev/null

echo "[$(date)] backed up ${CHANGED} files"
