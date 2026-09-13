#!/bin/bash
# Opt-in replacement: configure ops/backup.json first. No blanket git add.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec python3 "$SCRIPT_DIR/backup-workspace.py" "$@"
