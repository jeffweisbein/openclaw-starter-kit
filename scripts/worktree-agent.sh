#!/bin/bash
# Spawn a coding agent in an isolated git worktree
# Prevents agents from stepping on each other's work
#
# Usage:
#   ./worktree-agent.sh <repo-path> <branch-name> <task-description> [agent-type]
#
# Example:
#   ./worktree-agent.sh ~/code/myapp feat/new-dashboard "Build the admin dashboard" codex
#
# What it does:
# 1. Creates a git worktree on a fresh branch
# 2. Runs npm/pnpm install
# 3. Spawns the coding agent (codex or claude)
# 4. Tracks the task in active-tasks.json
#
# Why worktrees:
# - Each agent gets its own copy of the codebase
# - No merge conflicts during parallel work
# - Easy cleanup when done
# - Prevents the "another agent removed my code" problem

set -euo pipefail

REPO_PATH="${1:?Usage: worktree-agent.sh <repo-path> <branch-name> <task>}"
BRANCH_NAME="${2:?Missing branch name}"
TASK_DESC="${3:?Missing task description}"
AGENT_TYPE="${4:-codex}"  # codex or claude

# Resolve paths
REPO_PATH=$(cd "$REPO_PATH" && pwd)
REPO_NAME=$(basename "$REPO_PATH")
WORKTREE_BASE="${REPO_PATH}/../worktrees"
WORKTREE_PATH="${WORKTREE_BASE}/${REPO_NAME}-${BRANCH_NAME}"
TASKS_FILE="${OPENCLAW_WORKSPACE:-$HOME/clawd}/data/active-tasks.json"

mkdir -p "$WORKTREE_BASE" "$(dirname "$TASKS_FILE")"

# Create worktree
echo "→ creating worktree: ${WORKTREE_PATH}"
cd "$REPO_PATH"
git fetch origin
git worktree add "$WORKTREE_PATH" -b "$BRANCH_NAME" origin/main 2>/dev/null || \
  git worktree add "$WORKTREE_PATH" "$BRANCH_NAME"

# Install dependencies
cd "$WORKTREE_PATH"
if [ -f "pnpm-lock.yaml" ]; then
  pnpm install --frozen-lockfile 2>/dev/null || pnpm install
elif [ -f "package-lock.json" ]; then
  npm ci 2>/dev/null || npm install
elif [ -f "yarn.lock" ]; then
  yarn install --frozen-lockfile
fi

# Register task
TASK_ID="${REPO_NAME}-${BRANCH_NAME}"
STARTED_AT=$(date +%s)000

python3 -c "
import json, os
path = '$TASKS_FILE'
try:
    tasks = json.load(open(path)) if os.path.exists(path) else []
except: tasks = []

tasks.append({
    'id': '$TASK_ID',
    'repo': '$REPO_NAME',
    'branch': '$BRANCH_NAME',
    'worktree': '$WORKTREE_PATH',
    'agent': '$AGENT_TYPE',
    'description': '''$TASK_DESC''',
    'startedAt': $STARTED_AT,
    'status': 'running',
    'attempts': 1,
    'maxAttempts': 3,
    'notifyOnComplete': True
})

json.dump(tasks, open(path, 'w'), indent=2)
" 2>/dev/null

echo "→ task registered: ${TASK_ID}"
echo "→ worktree ready at: ${WORKTREE_PATH}"
echo ""
echo "next: spawn your agent in this directory"
echo "  cd ${WORKTREE_PATH}"
echo ""

if [ "$AGENT_TYPE" = "codex" ]; then
  echo "  codex --model gpt-5.4-codex -c model_reasoning_effort=high \\"
  echo "    --dangerously-bypass-approvals-and-sandbox \\"
  echo "    \"${TASK_DESC}\""
elif [ "$AGENT_TYPE" = "claude" ]; then
  echo "  claude --model claude-opus-4-6 \\"
  echo "    --dangerously-skip-permissions \\"
  echo "    -p \"${TASK_DESC}\""
fi
