#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
# kit-sync.sh: pull the latest managed/ into a workspace
#
# Writes only inside <workspace>/managed/. Never reads from, writes to,
# or deletes anything in user/ or layers/. It checksums both of those
# trees before and after and aborts if a single byte moved.
#
# Files you changed locally are left alone unless you pass
# --allow-overwrite, and even then the old copy is backed up first.
#
# On success it records <workspace>/.kit-baseline, which is what lets
# kit-drift.sh tell a local edit apart from an upstream change.
#
# Usage:
#   ./kit-sync.sh                            # show the plan, ask, then write
#   ./kit-sync.sh --dry-run                  # show the plan and stop
#   ./kit-sync.sh --yes                      # no prompt (for provisioning)
#   ./kit-sync.sh --kit ~/src/starter-kit    # sync from a checkout
#   ./kit-sync.sh --allow-overwrite          # also replace locally modified files
#
# Exit: 0 = synced or nothing to do, 1 = declined, 2 = could not run
# ═══════════════════════════════════════════════════════════════════

set -uo pipefail

WORKSPACE="${OPENCLAW_WORKSPACE:-$HOME/clawd}"
KIT_DIR=""
KIT_REPO="${STARTER_KIT_REPO:-https://github.com/jeffweisbein/openclaw-starter-kit.git}"
DRY_RUN=false
ASSUME_YES=false
ALLOW_OVERWRITE=false
TMP_CLONE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace)       WORKSPACE="$2"; shift 2 ;;
    --kit)             KIT_DIR="$2"; shift 2 ;;
    --repo)            KIT_REPO="$2"; shift 2 ;;
    --dry-run)         DRY_RUN=true; shift ;;
    --yes|-y)          ASSUME_YES=true; shift ;;
    --allow-overwrite) ALLOW_OVERWRITE=true; shift ;;
    -h|--help)         sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -t 1 ]]; then
  RED="\033[0;31m"; GREEN="\033[0;32m"; YELLOW="\033[0;33m"
  BLUE="\033[0;34m"; DIM="\033[2m"; BOLD="\033[1m"; NC="\033[0m"
else
  RED=""; GREEN=""; YELLOW=""; BLUE=""; DIM=""; BOLD=""; NC=""
fi

if command -v shasum >/dev/null 2>&1; then
  SHA="shasum -a 256"
elif command -v sha256sum >/dev/null 2>&1; then
  SHA="sha256sum"
else
  echo "kit-sync: needs shasum or sha256sum" >&2; exit 2
fi
sha_of() { $SHA "$1" 2>/dev/null | awk '{print $1}'; }

WORK="$(mktemp -d)"
cleanup() {
  [[ -n "$TMP_CLONE" && -d "$TMP_CLONE" ]] && rm -rf "$TMP_CLONE"
  [[ -d "$WORK" ]] && rm -rf "$WORK"
  return 0
}
trap cleanup EXIT

[[ -d "$WORKSPACE/managed" ]] || { echo "kit-sync: no managed/ in $WORKSPACE" >&2; exit 2; }

if [[ -z "$KIT_DIR" ]]; then
  SELF_KIT="$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)"
  if [[ -f "$SELF_KIT/managed/VERSION" && "$SELF_KIT" != "$WORKSPACE" ]]; then
    KIT_DIR="$SELF_KIT"
  else
    TMP_CLONE="$(mktemp -d)"
    echo -e "${DIM}Fetching the latest kit...${NC}"
    # Full history, not --depth 1: the first sync on an older install
    # rebuilds its baseline from the commit that shipped that version.
    git clone --quiet "$KIT_REPO" "$TMP_CLONE/kit" 2>/dev/null \
      || { echo "kit-sync: could not clone $KIT_REPO (offline? pass --kit)" >&2; exit 2; }
    KIT_DIR="$TMP_CLONE/kit"
  fi
fi
[[ -d "$KIT_DIR/managed" ]] || { echo "kit-sync: $KIT_DIR is not a kit checkout" >&2; exit 2; }

BASELINE="$WORKSPACE/.kit-baseline"
READ_BASELINE="$BASELINE"
HAVE_BASELINE=false; [[ -f "$BASELINE" ]] && HAVE_BASELINE=true
RECONSTRUCTED=false
FROM_VERSION="$(cat "$WORKSPACE/managed/VERSION" 2>/dev/null || echo unknown)"
TO_VERSION="$(cat "$KIT_DIR/managed/VERSION" 2>/dev/null || echo unknown)"

# ─── First sync on an old install: rebuild the baseline from history ──
# Without this, every file the kit changed since the installed version
# looks locally modified, so a pristine install would carry a permanent
# false "you edited this" flag and never take the update. If the kit
# checkout has the history, the installed version's tree is the real
# baseline.
reconstruct_baseline() {
  local ver="$1" commit="" h
  git -C "$KIT_DIR" rev-parse --git-dir >/dev/null 2>&1 || return 1
  for h in $(git -C "$KIT_DIR" log --format=%H -- managed/VERSION 2>/dev/null); do
    if [[ "$(git -C "$KIT_DIR" show "$h:managed/VERSION" 2>/dev/null | tr -d '[:space:]')" == "$ver" ]]; then
      commit="$h"; break
    fi
  done
  [[ -n "$commit" ]] || return 1
  {
    echo "#kit-baseline v1"
    echo "#version $ver"
    echo "#commit $(git -C "$KIT_DIR" rev-parse --short "$commit")"
    echo "#synced reconstructed-from-history"
    git -C "$KIT_DIR" ls-tree -r --name-only "$commit" -- managed/ 2>/dev/null \
      | while IFS= read -r p; do
          rel="${p#managed/}"
          case "$rel" in *node_modules/*|*.DS_Store) continue ;; esac
          echo "$(git -C "$KIT_DIR" show "$commit:$p" 2>/dev/null | $SHA | awk '{print $1}')  $rel"
        done
  } > "$WORK/reconstructed"
  [[ -s "$WORK/reconstructed" ]] || return 1
  return 0
}

if [[ "$HAVE_BASELINE" != true && "$FROM_VERSION" != unknown ]]; then
  if reconstruct_baseline "$FROM_VERSION"; then
    READ_BASELINE="$WORK/reconstructed"
    HAVE_BASELINE=true
    RECONSTRUCTED=true
  fi
fi

list_files() {
  ( cd "$1/managed" 2>/dev/null && find . -type f \
      ! -path '*/node_modules/*' ! -path '*/.git/*' \
      ! -name '.DS_Store' ! -name '*.log' \
      | sed 's|^\./||' | sort )
}

# ─── Fingerprint the untouchable trees ───────────────────────────
fingerprint_sacred() {
  ( cd "$WORKSPACE" 2>/dev/null || return 0
    find user layers -type f ! -path '*/.git/*' ! -name '.DS_Store' 2>/dev/null \
      | sort | while IFS= read -r f; do echo "$(sha_of "$f")  $f"; done )
}
fingerprint_sacred > "$WORK/sacred.before"

list_files "$WORKSPACE" > "$WORK/have"
list_files "$KIT_DIR"   > "$WORK/kit"
sort -u "$WORK/have" "$WORK/kit" > "$WORK/all"

baseline_sha() {
  [[ "$HAVE_BASELINE" == true ]] || return 1
  awk -v p="$1" '
    /^#/ { next }
    { i = index($0, "  "); if (i && substr($0, i+2) == p) { print substr($0, 1, i-1); exit } }
  ' "$READ_BASELINE"
}

for b in add update keep_local keep_extra removed unchanged; do : > "$WORK/$b"; done

while IFS= read -r rel; do
  [[ -z "$rel" ]] && continue
  h="$WORKSPACE/managed/$rel"; k="$KIT_DIR/managed/$rel"

  if [[ ! -e "$k" ]]; then
    # Gone upstream. Only reclaim it if it is untouched since last sync.
    if [[ "$HAVE_BASELINE" == true ]]; then
      bs="$(baseline_sha "$rel")"
      if [[ -n "$bs" && "$bs" == "$(sha_of "$h")" ]]; then echo "$rel" >> "$WORK/removed"; continue; fi
    fi
    echo "$rel" >> "$WORK/keep_extra"; continue
  fi
  if [[ ! -e "$h" ]]; then echo "$rel" >> "$WORK/add"; continue; fi

  hs="$(sha_of "$h")"; ks="$(sha_of "$k")"
  if [[ "$hs" == "$ks" ]]; then echo "$rel" >> "$WORK/unchanged"; continue; fi

  # VERSION is the kit's own marker, not a file a client edits.
  if [[ "$rel" == "VERSION" ]]; then echo "$rel" >> "$WORK/update"; continue; fi

  locally_touched=true
  if [[ "$HAVE_BASELINE" == true ]]; then
    bs="$(baseline_sha "$rel")"
    [[ -n "$bs" && "$bs" == "$hs" ]] && locally_touched=false
  fi

  if [[ "$locally_touched" == true && "$ALLOW_OVERWRITE" != true ]]; then
    echo "$rel" >> "$WORK/keep_local"
  else
    echo "$rel" >> "$WORK/update"
  fi
done < "$WORK/all"

n() { wc -l < "$WORK/$1" | tr -d ' '; }
N_ADD=$(n add); N_UPDATE=$(n update); N_KEEP=$(n keep_local)
N_EXTRA=$(n keep_extra); N_REMOVED=$(n removed); N_UNCHANGED=$(n unchanged)

# ─── The plan ────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Sync plan${NC}"
echo -e "${DIM}Workspace: $WORKSPACE${NC}"
echo -e "${DIM}Kit:       $KIT_DIR${NC}"
echo -e "${DIM}Version:   $FROM_VERSION  ->  $TO_VERSION${NC}"
if [[ "$RECONSTRUCTED" == true ]]; then
  echo -e "${DIM}Baseline:  rebuilt from the kit's history at $FROM_VERSION${NC}"
elif [[ "$HAVE_BASELINE" != true ]]; then
  echo -e "${YELLOW}No baseline, and the kit's history does not reach $FROM_VERSION.${NC}"
  echo -e "${YELLOW}Every changed file counts as locally modified and is kept.${NC}"
fi

show() {
  local bucket="$1" color="$2" verb="$3"
  [[ "$(n "$bucket")" == "0" ]] && return 0
  echo ""
  echo -e "${color}${verb} ($(n "$bucket"))${NC}"
  sed 's|^|  managed/|' "$WORK/$bucket"
}
show add        "$GREEN"  "Add"
show update     "$BLUE"   "Update"
show removed    "$DIM"    "Delete (dropped upstream, untouched here)"
show keep_local "$YELLOW" "Keep as-is (modified here)"
show keep_extra "$YELLOW" "Keep as-is (added here, not in the kit)"

echo ""
echo -e "${DIM}$N_UNCHANGED files already match.${NC}"
[[ "$N_EXTRA" != "0" ]] && \
  echo -e "${DIM}Files added to managed/ locally belong in layers/<org>/. See layers/README.md.${NC}"
echo -e "${GREEN}user/ and layers/ are not read, written, or deleted by this script.${NC}"
if [[ "$N_KEEP" != "0" && "$ALLOW_OVERWRITE" != true ]]; then
  echo -e "${DIM}Pass --allow-overwrite to replace the kept files (old copies are backed up).${NC}"
fi

if [[ $(( N_ADD + N_UPDATE + N_REMOVED )) == 0 ]]; then
  echo ""
  echo -e "${GREEN}Nothing to sync.${NC}"
  # Still record a baseline so drift classification works from here on.
  if [[ ! -f "$BASELINE" && "$DRY_RUN" != true ]]; then
    echo -e "${DIM}Recording a baseline so future drift reports can classify changes.${NC}"
  else
    echo ""; exit 0
  fi
fi

if [[ "$DRY_RUN" == true ]]; then
  echo ""
  echo -e "${DIM}Dry run. Nothing written.${NC}"
  echo ""
  exit 0
fi

if [[ "$ASSUME_YES" != true ]]; then
  echo ""
  printf "Apply this plan? [y/N] "
  read -r reply
  case "$reply" in
    y|Y|yes|YES) ;;
    *) echo -e "${YELLOW}Cancelled. Nothing written.${NC}"; exit 1 ;;
  esac
fi

# ─── Apply ───────────────────────────────────────────────────────
STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="$WORKSPACE/.kit-backups/$STAMP"

copy_in() {
  local rel="$1"
  mkdir -p "$WORKSPACE/managed/$(dirname "$rel")"
  # -p so executable bits on scripts survive the copy
  cp -p "$KIT_DIR/managed/$rel" "$WORKSPACE/managed/$rel"
}
back_up() {
  local rel="$1"
  mkdir -p "$BACKUP/$(dirname "$rel")"
  cp "$WORKSPACE/managed/$rel" "$BACKUP/$rel"
}

while IFS= read -r rel; do [[ -n "$rel" ]] && copy_in "$rel"; done < "$WORK/add"
while IFS= read -r rel; do
  [[ -z "$rel" ]] && continue
  back_up "$rel"; copy_in "$rel"
done < "$WORK/update"
while IFS= read -r rel; do
  [[ -z "$rel" ]] && continue
  back_up "$rel"; rm -f "$WORKSPACE/managed/$rel"
done < "$WORK/removed"

# Prune directories that emptied out. managed/ only.
find "$WORKSPACE/managed" -type d -empty -delete 2>/dev/null
[[ -d "$WORKSPACE/managed" ]] || mkdir -p "$WORKSPACE/managed"

# ─── Prove user/ and layers/ are untouched ───────────────────────
fingerprint_sacred > "$WORK/sacred.after"
if ! diff -q "$WORK/sacred.before" "$WORK/sacred.after" >/dev/null 2>&1; then
  echo ""
  echo -e "${RED}${BOLD}ABORT: user/ or layers/ changed during the sync.${NC}"
  echo -e "${RED}This should be impossible. Report it. Diff:${NC}"
  diff "$WORK/sacred.before" "$WORK/sacred.after"
  [[ -d "$BACKUP" ]] && echo -e "${DIM}Backups of replaced managed/ files: $BACKUP${NC}"
  exit 2
fi

# ─── Record the baseline ─────────────────────────────────────────
# The baseline is the KIT's state at sync time, not the workspace's.
# That is what lets kit-drift.sh answer "who moved, us or upstream?".
# A file kept because it was modified here records the kit's sha, so it
# reads as locally modified next time instead of as behind the kit.
KIT_COMMIT="$(git -C "$KIT_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
{
  echo "#kit-baseline v1"
  echo "#version $TO_VERSION"
  echo "#commit $KIT_COMMIT"
  echo "#synced $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "#note lines below are: <sha256>  <path relative to managed/>"
  echo "#note the shas are the kit's, which is the last upstream state this workspace saw"
  ( cd "$KIT_DIR/managed" && find . -type f \
      ! -path '*/node_modules/*' ! -path '*/.git/*' \
      ! -name '.DS_Store' ! -name '*.log' \
      | sed 's|^\./||' | sort | while IFS= read -r f; do
      echo "$(sha_of "$f")  $f"
    done )
} > "$BASELINE"

echo ""
echo -e "${GREEN}${BOLD}Synced.${NC} managed/ is now at $TO_VERSION."
[[ -d "$BACKUP" ]] && echo -e "${DIM}Replaced files backed up to $BACKUP${NC}"
echo -e "${DIM}Baseline recorded at $BASELINE${NC}"
if [[ "$N_KEEP" != "0" && "$ALLOW_OVERWRITE" != true ]]; then
  echo -e "${YELLOW}$N_KEEP locally modified file(s) were left alone. Run kit-drift.sh to see them.${NC}"
fi
echo ""
exit 0
