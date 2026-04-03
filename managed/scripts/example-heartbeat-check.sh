#!/bin/bash
# Example heartbeat check script
# Philosophy: scripts are free, model time is expensive.
# Only output something if action is needed — silence = nothing to do.

# Example: Check if any git repos have uncommitted changes
check_dirty_repos() {
  for dir in ~/Projects/*/; do
    if [ -d "$dir/.git" ]; then
      cd "$dir"
      if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
        echo "DIRTY_REPO: $(basename $dir) has uncommitted changes"
      fi
    fi
  done
}

# Example: Check if disk space is low
check_disk_space() {
  local usage=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
  if [ "$usage" -gt 90 ]; then
    echo "DISK_WARNING: Root disk at ${usage}% capacity"
  fi
}

# Run checks
check_dirty_repos
check_disk_space

# If nothing was printed, the heartbeat handler knows nothing needs attention
