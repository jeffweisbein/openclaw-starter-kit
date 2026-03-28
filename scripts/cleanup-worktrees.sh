#!/bin/bash
# Clean up merged worktrees and stale task entries
# Run daily via cron to prevent worktree/disk bloat.
#
# What it does:
# 1. Finds worktrees whose branches have been merged to main
# 2. Removes the worktree directory
# 3. Prunes git's worktree list
# 4. Marks tasks as 'done' in active-tasks.json
#
# Usage: ./cleanup-worktrees.sh [repo-path]
# Default: scans all repos under ~/code/

set -euo pipefail

SEARCH_DIR="${1:-$HOME/code}"
TASKS_FILE="${OPENCLAW_WORKSPACE:-$HOME/clawd}/data/active-tasks.json"
CLEANED=0

# Find repos with worktrees
for repo in "$SEARCH_DIR"/*/; do
  [ -d "$repo/.git" ] || continue
  
  cd "$repo"
  
  # List worktrees (skip main working directory)
  git worktree list --porcelain 2>/dev/null | grep "^worktree " | awk '{print $2}' | while read -r wt; do
    # Skip the main repo dir
    [ "$wt" = "$repo" ] && continue
    [ "$wt" = "${repo%/}" ] && continue
    
    # Get the branch for this worktree
    WT_BRANCH=$(git worktree list 2>/dev/null | grep "$wt" | awk '{print $3}' | tr -d '[]')
    [ -z "$WT_BRANCH" ] && continue
    
    # Check if branch is merged to main
    if git branch --merged main 2>/dev/null | grep -q "$WT_BRANCH"; then
      echo "→ cleaning merged worktree: $wt (branch: $WT_BRANCH)"
      git worktree remove "$wt" --force 2>/dev/null || rm -rf "$wt"
      git branch -d "$WT_BRANCH" 2>/dev/null || true
      CLEANED=$((CLEANED + 1))
    fi
  done
  
  # Prune stale worktree entries
  git worktree prune 2>/dev/null
done

# Update tasks file
if [ -f "$TASKS_FILE" ] && [ $CLEANED -gt 0 ]; then
  python3 -c "
import json, os
path = '$TASKS_FILE'
try:
    tasks = json.load(open(path))
    for t in tasks:
        wt = t.get('worktree', '')
        if wt and not os.path.isdir(wt):
            t['status'] = 'done'
    json.dump(tasks, open(path, 'w'), indent=2)
except: pass
" 2>/dev/null
fi

if [ $CLEANED -gt 0 ]; then
  echo "cleaned ${CLEANED} worktree(s)"
fi
