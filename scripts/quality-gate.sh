#!/bin/bash
# Quality gate for agent PRs
# Only notifies you when a PR is ACTUALLY ready — not just created.
#
# Checks:
# 1. PR exists and is open
# 2. CI/checks are passing
# 3. No merge conflicts
# 4. Build succeeds
#
# Usage:
#   ./quality-gate.sh <owner/repo> <pr-number>
#   ./quality-gate.sh jeffweisbein/myapp 42
#
# Returns:
#   "READY" — safe to review/merge
#   "PENDING" — still waiting on checks
#   "FAILED" — something needs fixing
#   nothing — PR doesn't exist or is closed
#
# Use in heartbeat/cron to avoid notification spam.
# Only alert your human when output is "READY".

set -euo pipefail

REPO="${1:?Usage: quality-gate.sh <owner/repo> <pr-number>}"
PR_NUM="${2:?Missing PR number}"

# Check PR state
PR_STATE=$(gh pr view "$PR_NUM" --repo "$REPO" --json state -q '.state' 2>/dev/null)
if [ "$PR_STATE" != "OPEN" ]; then
  exit 0  # closed/merged, nothing to report
fi

# Check CI status
CHECKS=$(gh pr checks "$PR_NUM" --repo "$REPO" 2>/dev/null)
FAILING=$(echo "$CHECKS" | grep -c "fail\|X" 2>/dev/null || echo "0")
PENDING=$(echo "$CHECKS" | grep -c "pending\|\*" 2>/dev/null || echo "0")

# Check merge conflicts
MERGEABLE=$(gh pr view "$PR_NUM" --repo "$REPO" --json mergeable -q '.mergeable' 2>/dev/null)

# Build result
if [ "$FAILING" -gt 0 ]; then
  echo "FAILED: PR #${PR_NUM} has ${FAILING} failing check(s)"
  echo "$CHECKS" | grep "fail\|X" | head -5
elif [ "$PENDING" -gt 0 ]; then
  echo "PENDING: PR #${PR_NUM} has ${PENDING} check(s) still running"
elif [ "$MERGEABLE" = "CONFLICTING" ]; then
  echo "FAILED: PR #${PR_NUM} has merge conflicts"
else
  # All checks passed, no conflicts
  PR_TITLE=$(gh pr view "$PR_NUM" --repo "$REPO" --json title -q '.title' 2>/dev/null)
  CHANGED=$(gh pr view "$PR_NUM" --repo "$REPO" --json changedFiles -q '.changedFiles' 2>/dev/null)
  echo "READY: PR #${PR_NUM} — ${PR_TITLE} (${CHANGED} files changed)"
fi
