#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
# kit-drift.sh: report how far a workspace has drifted from the kit
#
# Compares every file in <workspace>/managed/ against the same file in
# a starter kit checkout, and classifies each one:
#
#   clean     identical to the kit
#   local     changed here since the last sync, kit unchanged
#   stale     kit moved since the last sync, this copy did not
#   conflict  both changed since the last sync
#   new       exists in the kit, missing here
#   extra     exists here, not in the kit (belongs in a layer)
#
# The last-sync baseline lives at <workspace>/.kit-baseline and is
# written by kit-sync.sh. Without it the checker still runs, but it can
# only say "same" or "different". It cannot tell local edits apart
# from upstream moves. It says so in the output.
#
# Usage:
#   ./kit-drift.sh                          # clone the public kit, compare
#   ./kit-drift.sh --kit ~/src/starter-kit  # compare against a checkout
#   ./kit-drift.sh --workspace ~/clawd
#   ./kit-drift.sh --details                # add a per-file line summary
#   ./kit-drift.sh --quiet                  # exit code only, for cron
#
# Exit: 0 = no drift, 1 = drift found, 2 = could not run
# ═══════════════════════════════════════════════════════════════════

set -uo pipefail

WORKSPACE="${OPENCLAW_WORKSPACE:-$HOME/clawd}"
KIT_DIR=""
KIT_REPO="${STARTER_KIT_REPO:-https://github.com/jeffweisbein/openclaw-starter-kit.git}"
DETAILS=false
QUIET=false
TMP_CLONE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace) WORKSPACE="$2"; shift 2 ;;
    --kit)       KIT_DIR="$2"; shift 2 ;;
    --repo)      KIT_REPO="$2"; shift 2 ;;
    --details)   DETAILS=true; shift ;;
    --quiet)     QUIET=true; shift ;;
    -h|--help)   sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -t 1 ]]; then
  RED="\033[0;31m"; GREEN="\033[0;32m"; YELLOW="\033[0;33m"
  BLUE="\033[0;34m"; DIM="\033[2m"; BOLD="\033[1m"; NC="\033[0m"
else
  RED=""; GREEN=""; YELLOW=""; BLUE=""; DIM=""; BOLD=""; NC=""
fi

say() { $QUIET || echo -e "$@"; }

if command -v shasum >/dev/null 2>&1; then
  sha_of() { shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'; }
elif command -v sha256sum >/dev/null 2>&1; then
  sha_of() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }
else
  echo "kit-drift: needs shasum or sha256sum" >&2; exit 2
fi

cleanup() { [[ -n "$TMP_CLONE" && -d "$TMP_CLONE" ]] && rm -rf "$TMP_CLONE"; }
trap cleanup EXIT

# ─── Resolve the two trees ───────────────────────────────────────
if [[ ! -d "$WORKSPACE/managed" ]]; then
  echo "kit-drift: no managed/ directory in $WORKSPACE" >&2
  echo "           this workspace predates the managed/ + user/ split (v2.2)." >&2
  exit 2
fi

if [[ -z "$KIT_DIR" ]]; then
  # Maybe we are running from inside a kit checkout already.
  SELF_KIT="$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)"
  if [[ -f "$SELF_KIT/managed/VERSION" && "$SELF_KIT" != "$WORKSPACE" ]]; then
    KIT_DIR="$SELF_KIT"
  else
    TMP_CLONE="$(mktemp -d)"
    say "${DIM}Fetching the latest kit...${NC}"
    if ! git clone --quiet "$KIT_REPO" "$TMP_CLONE/kit" 2>/dev/null; then
      echo "kit-drift: could not clone $KIT_REPO (offline? pass --kit)" >&2
      exit 2
    fi
    KIT_DIR="$TMP_CLONE/kit"
  fi
fi

if [[ ! -d "$KIT_DIR/managed" ]]; then
  echo "kit-drift: $KIT_DIR is not a starter kit checkout (no managed/)" >&2
  exit 2
fi

BASELINE="$WORKSPACE/.kit-baseline"
HAVE_BASELINE=false
RECONSTRUCTED=false
[[ -f "$BASELINE" ]] && HAVE_BASELINE=true

INSTALLED_VERSION="$(cat "$WORKSPACE/managed/VERSION" 2>/dev/null || echo unknown)"
KIT_VERSION="$(cat "$KIT_DIR/managed/VERSION" 2>/dev/null || echo unknown)"

if command -v shasum >/dev/null 2>&1; then SHA="shasum -a 256"; else SHA="sha256sum"; fi

# An install that has never been synced has no baseline file. If the kit
# checkout has history, the commit that shipped the installed version is
# just as good, and it is what keeps a pristine old install from looking
# locally modified everywhere.
WORK="$(mktemp -d)"
trap 'cleanup; rm -rf "$WORK"' EXIT

reconstruct_baseline() {
  local ver="$1" commit="" h rel
  git -C "$KIT_DIR" rev-parse --git-dir >/dev/null 2>&1 || return 1
  for h in $(git -C "$KIT_DIR" log --format=%H -- managed/VERSION 2>/dev/null); do
    if [[ "$(git -C "$KIT_DIR" show "$h:managed/VERSION" 2>/dev/null | tr -d '[:space:]')" == "$ver" ]]; then
      commit="$h"; break
    fi
  done
  [[ -n "$commit" ]] || return 1
  {
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

if [[ "$HAVE_BASELINE" != true && "$INSTALLED_VERSION" != unknown ]]; then
  if reconstruct_baseline "$INSTALLED_VERSION"; then
    BASELINE="$WORK/reconstructed"
    HAVE_BASELINE=true
    RECONSTRUCTED=true
  fi
fi

# ─── File lists (skip build output and editor noise) ─────────────
list_files() {
  ( cd "$1/managed" 2>/dev/null && find . -type f \
      ! -path '*/node_modules/*' \
      ! -path '*/.git/*' \
      ! -name '.DS_Store' \
      ! -name '*.log' \
      | sed 's|^\./||' | sort )
}

list_files "$WORKSPACE" > "$WORK/have"
list_files "$KIT_DIR"   > "$WORK/kit"
sort -u "$WORK/have" "$WORK/kit" > "$WORK/all"

baseline_sha() {
  [[ "$HAVE_BASELINE" == true ]] || return 1
  awk -v p="$1" '
    /^#/ { next }
    { i = index($0, "  "); if (i && substr($0, i+2) == p) { print substr($0, 1, i-1); exit } }
  ' "$BASELINE"
}

for bucket in clean local stale conflict new extra differs; do : > "$WORK/$bucket"; done

while IFS= read -r rel; do
  [[ -z "$rel" ]] && continue
  # VERSION is the kit's own marker. Version skew is in the header already.
  [[ "$rel" == "VERSION" ]] && continue
  h="$WORKSPACE/managed/$rel"
  k="$KIT_DIR/managed/$rel"

  if [[ ! -e "$h" ]]; then echo "$rel" >> "$WORK/new"; continue; fi
  if [[ ! -e "$k" ]]; then echo "$rel" >> "$WORK/extra"; continue; fi

  hs="$(sha_of "$h")"; ks="$(sha_of "$k")"
  if [[ "$hs" == "$ks" ]]; then echo "$rel" >> "$WORK/clean"; continue; fi

  if [[ "$HAVE_BASELINE" != true ]]; then
    echo "$rel" >> "$WORK/differs"; continue
  fi

  bs="$(baseline_sha "$rel")"
  if   [[ -z "$bs"          ]]; then echo "$rel" >> "$WORK/differs"
  elif [[ "$bs" == "$hs"    ]]; then echo "$rel" >> "$WORK/stale"
  elif [[ "$bs" == "$ks"    ]]; then echo "$rel" >> "$WORK/local"
  else                               echo "$rel" >> "$WORK/conflict"
  fi
done < "$WORK/all"

n() { wc -l < "$WORK/$1" | tr -d ' '; }
N_CLEAN=$(n clean); N_LOCAL=$(n local); N_STALE=$(n stale)
N_CONFLICT=$(n conflict); N_NEW=$(n new); N_EXTRA=$(n extra); N_DIFFERS=$(n differs)
N_TOTAL=$(( $(wc -l < "$WORK/all" | tr -d ' ') - 1 ))   # VERSION is not classified
N_DRIFT=$(( N_LOCAL + N_STALE + N_CONFLICT + N_NEW + N_EXTRA + N_DIFFERS ))

# ─── Report ──────────────────────────────────────────────────────
lines_changed() {
  local rel="$1"
  diff -u "$KIT_DIR/managed/$rel" "$WORKSPACE/managed/$rel" 2>/dev/null \
    | grep -c -E '^[+-][^+-]' | tr -d ' '
}

section() {
  local bucket="$1" color="$2" label="$3" note="$4"
  [[ "$(n "$bucket")" == "0" ]] && return 0
  say ""
  say "${color}${BOLD}${label} ($(n "$bucket"))${NC}"
  say "${DIM}  ${note}${NC}"
  while IFS= read -r rel; do
    [[ -z "$rel" ]] && continue
    if [[ "$DETAILS" == true && -e "$WORKSPACE/managed/$rel" && -e "$KIT_DIR/managed/$rel" ]]; then
      say "  managed/$rel ${DIM}($(lines_changed "$rel") lines differ)${NC}"
    else
      say "  managed/$rel"
    fi
  done < "$WORK/$bucket"
}

say ""
say "${BOLD}Starter kit drift report${NC}"
say "${DIM}Workspace: $WORKSPACE${NC}"
say "${DIM}Kit:       $KIT_DIR${NC}"
if [[ "$INSTALLED_VERSION" == "$KIT_VERSION" ]]; then
  say "${DIM}Version:   $INSTALLED_VERSION (current)${NC}"
else
  say "${DIM}Version:   $INSTALLED_VERSION installed, $KIT_VERSION available${NC}"
fi
if [[ "$RECONSTRUCTED" == true ]]; then
  say "${DIM}Baseline:  rebuilt from the kit's history at $INSTALLED_VERSION${NC}"
  say "${DIM}           This workspace has never been synced with kit-sync.sh.${NC}"
elif [[ "$HAVE_BASELINE" == true ]]; then
  SYNCED_AT="$(awk '/^#synced /{print $2; exit}' "$BASELINE")"
  say "${DIM}Baseline:  last synced ${SYNCED_AT:-unknown}${NC}"
else
  say "${YELLOW}Baseline:  none, and the kit's history does not reach $INSTALLED_VERSION.${NC}"
  say "${DIM}           Until then, changed files are reported as 'differs'${NC}"
  say "${DIM}           because there is no way to tell a local edit from an${NC}"
  say "${DIM}           upstream change.${NC}"
fi

say ""
if [[ "$N_DRIFT" == "0" ]]; then
  say "${GREEN}${BOLD}No drift. All $N_CLEAN managed files match the kit.${NC}"
else
  say "${BOLD}$N_CLEAN of $N_TOTAL files clean, $N_DRIFT need attention.${NC}"
fi

section conflict "$RED"    "Conflict"          "Changed here AND upstream. Merge by hand, or move the local change into a layer."
section local    "$YELLOW" "Locally modified"  "Edited on this machine. kit-sync.sh will not overwrite these. Promote the good ones with kit-promote.sh, move the client-specific ones into a layer."
section differs  "$YELLOW" "Differs"           "Does not match the kit. No baseline, so the cause is unknown."
section stale    "$BLUE"   "Behind the kit"    "Untouched here, updated upstream. kit-sync.sh will bring these forward."
section new      "$BLUE"   "New in the kit"    "Added upstream since this install. kit-sync.sh will add them."
section extra    "$YELLOW" "Not in the kit"    "Added to managed/ locally. managed/ is upstream's. Move these into layers/<org>/ so the next sync does not fight them."

say ""
if [[ "$N_DRIFT" == "0" ]]; then
  say "${GREEN}Nothing to do.${NC}"
else
  say "${BOLD}What to do${NC}"
  [[ "$N_STALE$N_NEW" != "00" ]] && \
    say "  Pull upstream changes:  managed/scripts/kit-sync.sh --workspace $WORKSPACE"
  [[ "$N_LOCAL" != "0" || "$N_CONFLICT" != "0" || "$N_DIFFERS" != "0" ]] && \
    say "  Send a fix upstream:    managed/scripts/kit-promote.sh --workspace $WORKSPACE managed/<file>"
  [[ "$N_EXTRA" != "0" || "$N_LOCAL" != "0" ]] && \
    say "  Keep it client-only:    managed/scripts/kit-layer.sh init <org>   (see layers/README.md)"
fi
say ""

[[ "$N_DRIFT" == "0" ]] && exit 0
exit 1
