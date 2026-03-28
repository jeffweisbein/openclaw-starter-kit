#!/bin/bash
# Agent task monitor — deterministic, zero-token cost
# Checks all running agent tasks and reports status.
# Run via cron every 5-10 minutes.
#
# Philosophy: this script is FREE (no AI tokens).
# Only output when something needs attention.
# Silence = everything is fine.
#
# Checks per task:
# 1. Is the agent process still alive?
# 2. Is there a PR on the branch?
# 3. Are CI checks passing?
# 4. Has it been running too long? (stale detection)
#
# Output format (only if action needed):
#   READY:<task-id> — PR passed all checks, ready for review
#   FAILED:<task-id> — CI failed or agent died
#   STALE:<task-id> — running >4 hours with no commits

set -euo pipefail

TASKS_FILE="${OPENCLAW_WORKSPACE:-$HOME/clawd}/data/active-tasks.json"
STALE_THRESHOLD_HOURS="${STALE_THRESHOLD:-4}"

if [ ! -f "$TASKS_FILE" ]; then
  exit 0
fi

NOW=$(date +%s)
STALE_SECONDS=$((STALE_THRESHOLD_HOURS * 3600))

# Read tasks
python3 -c "
import json, subprocess, os, time

tasks_file = '$TASKS_FILE'
now = $NOW
stale_seconds = $STALE_SECONDS

try:
    tasks = json.load(open(tasks_file))
except:
    exit()

updated = False
for task in tasks:
    if task.get('status') not in ('running', 'pr_open'):
        continue

    task_id = task['id']
    repo = task.get('repo', '')
    branch = task.get('branch', '')
    worktree = task.get('worktree', '')
    started = task.get('startedAt', 0) / 1000

    # Check if worktree still exists
    if worktree and not os.path.isdir(worktree):
        task['status'] = 'cleaned'
        updated = True
        continue

    # Check for recent commits (stale detection)
    if worktree and os.path.isdir(worktree):
        try:
            result = subprocess.run(
                ['git', 'log', '-1', '--format=%ct'],
                capture_output=True, text=True, cwd=worktree, timeout=5
            )
            last_commit = int(result.stdout.strip()) if result.stdout.strip() else 0
            if last_commit > 0 and (now - last_commit) > stale_seconds:
                print(f'STALE:{task_id} — no commits in {stale_seconds // 3600}h (last: {time.strftime(\"%H:%M\", time.localtime(last_commit))})')
        except:
            pass

    # Check for open PR
    if branch and repo:
        try:
            result = subprocess.run(
                ['gh', 'pr', 'list', '--head', branch, '--repo', f'jeffweisbein/{repo}',
                 '--json', 'number,state,statusCheckRollup', '--limit', '1'],
                capture_output=True, text=True, timeout=15
            )
            prs = json.loads(result.stdout) if result.stdout.strip() else []
            if prs:
                pr = prs[0]
                pr_num = pr['number']
                checks = pr.get('statusCheckRollup', [])

                all_passed = all(c.get('conclusion') == 'SUCCESS' for c in checks) if checks else False
                any_failed = any(c.get('conclusion') == 'FAILURE' for c in checks)
                any_pending = any(c.get('status') == 'IN_PROGRESS' for c in checks)

                if any_failed:
                    attempts = task.get('attempts', 1)
                    max_attempts = task.get('maxAttempts', 3)
                    print(f'FAILED:{task_id} — PR #{pr_num} CI failed (attempt {attempts}/{max_attempts})')
                    task['status'] = 'failed'
                    updated = True
                elif all_passed and not any_pending:
                    print(f'READY:{task_id} — PR #{pr_num} all checks passed')
                    task['status'] = 'ready'
                    updated = True
                else:
                    task['status'] = 'pr_open'
                    updated = True
        except:
            pass

if updated:
    json.dump(tasks, open(tasks_file, 'w'), indent=2)
" 2>/dev/null
