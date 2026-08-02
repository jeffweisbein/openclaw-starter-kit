#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
# kit-layer.sh: create and compose an org layer
#
# A layer is where everything client-specific lives, so that managed/
# can stay byte-identical to the kit. See layers/README.md for the
# contract.
#
# Commands:
#   ./kit-layer.sh init <org-slug> [--name "Org Name"] [--domain acme.com]
#   ./kit-layer.sh apply <org-slug> [--dry-run] [--force]
#   ./kit-layer.sh check <org-slug>
#   ./kit-layer.sh list
#
# Common flags: --workspace DIR
#
# apply copies the layer's files to their composed positions at the
# workspace root. It never writes inside managed/ and it never
# overwrites an existing user/ file without --force.
#
# Exit: 0 = fine, 1 = usage, 2 = refused
# ═══════════════════════════════════════════════════════════════════

set -uo pipefail

WORKSPACE="${OPENCLAW_WORKSPACE:-$HOME/clawd}"
CMD="${1:-}"; shift 2>/dev/null || true
ORG=""
ORG_NAME=""
ORG_DOMAIN=""
DRY_RUN=false
FORCE=false

case "$CMD" in
  init|apply|check) ORG="${1:-}"; shift 2>/dev/null || true ;;
  list) ;;
  -h|--help|"") sed -n '2,20p' "$0"; exit 0 ;;
  *) echo "unknown command: $CMD" >&2; exit 1 ;;
esac

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace) WORKSPACE="$2"; shift 2 ;;
    --name)      ORG_NAME="$2"; shift 2 ;;
    --domain)    ORG_DOMAIN="$2"; shift 2 ;;
    --dry-run)   DRY_RUN=true; shift ;;
    --force)     FORCE=true; shift ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -t 1 ]]; then
  RED="\033[0;31m"; GREEN="\033[0;32m"; YELLOW="\033[0;33m"
  DIM="\033[2m"; BOLD="\033[1m"; NC="\033[0m"
else
  RED=""; GREEN=""; YELLOW=""; DIM=""; BOLD=""; NC=""
fi

# The five composed directories. Source under the layer, destination at
# the workspace root. Nothing here may point inside managed/ or user/.
COMPOSE="agents:agents
skills:skills
scripts:scripts
playbooks:playbooks
ops:ops"

LAYER="$WORKSPACE/layers/$ORG"

# ─── list ────────────────────────────────────────────────────────
if [[ "$CMD" == "list" ]]; then
  if [[ ! -d "$WORKSPACE/layers" ]]; then
    echo "No layers in $WORKSPACE."
    exit 0
  fi
  found=false
  for d in "$WORKSPACE"/layers/*/; do
    [[ -d "$d" ]] || continue
    found=true
    slug="$(basename "$d")"
    name="$(awk -F= '/^org_name=/{print $2; exit}' "$d/layer.conf" 2>/dev/null)"
    files="$(find "$d" -type f ! -name '.applied' ! -name '.DS_Store' 2>/dev/null | wc -l | tr -d ' ')"
    echo -e "  ${BOLD}$slug${NC} ${DIM}${name:+$name }($files files)${NC}"
  done
  $found || echo "No layers in $WORKSPACE."
  exit 0
fi

[[ -n "$ORG" ]] || { echo "usage: kit-layer.sh $CMD <org-slug>" >&2; exit 1; }
case "$ORG" in
  *[!a-z0-9-]*) echo "org slug must be lowercase letters, digits and hyphens: $ORG" >&2; exit 1 ;;
esac

# ─── init ────────────────────────────────────────────────────────
if [[ "$CMD" == "init" ]]; then
  [[ -d "$LAYER" ]] && { echo -e "${YELLOW}$LAYER already exists.${NC}"; exit 1; }
  KIT_VERSION="$(cat "$WORKSPACE/managed/VERSION" 2>/dev/null || echo unknown)"
  [[ -n "$ORG_NAME" ]] || ORG_NAME="$ORG"

  mkdir -p "$LAYER"
  while IFS=: read -r src _; do
    [[ -z "$src" ]] && continue
    mkdir -p "$LAYER/$src"
    cat > "$LAYER/$src/.gitkeep" <<'EOF'
EOF
  done <<EOF
$COMPOSE
EOF

  cat > "$LAYER/layer.conf" <<EOF
# Layer manifest for $ORG_NAME.
# Plain key=value so no JSON parser is needed. Committed to the private
# downstream repo. Never put secret values in here.
#
# Every value below is also fed to the scrub check in kit-promote.sh,
# so anything you name here can never leak into the public kit.
org_slug=$ORG
org_name=$ORG_NAME
org_domains=${ORG_DOMAIN}
org_aliases=
client_repos=
kit_version=$KIT_VERSION
created=$(date -u +%Y-%m-%d)
EOF

  cat > "$LAYER/scrub-terms.txt" <<'EOF'
# One term per line. Anything listed here blocks a promotion to the
# public kit if it appears in the outgoing files, the commit message,
# or the branch name.
#
# Add: people's names, product names, internal hostnames, project
# codenames, Slack channels, S3 buckets, anything that identifies the
# client. Terms are matched case-insensitively as substrings, so keep
# them at least three characters and specific enough not to match
# ordinary English.
EOF

  cat > "$LAYER/.env.example" <<'EOF'
# Secret NAMES only, never values. Copy to .env and fill in locally.
# .env is gitignored by the file next to this one and must stay that way.
#
# EXAMPLE_API_KEY=
EOF

  cat > "$LAYER/.gitignore" <<'EOF'
.env
.env.*
!.env.example
.applied
*.tfstate
*.tfstate.*
EOF

  cat > "$LAYER/README.md" <<EOF
# $ORG_NAME layer

Everything specific to $ORG_NAME lives here. \`managed/\` stays identical to
the public starter kit so that updates stay small and boring.

## What is in here

| Path | Composes to | For |
|------|-------------|-----|
| \`agents/\` | \`<workspace>/agents/\` | agent definitions built for this client |
| \`skills/\` | \`<workspace>/skills/\` | skills built for this client |
| \`scripts/\` | \`<workspace>/scripts/\` | automation for this client's stack |
| \`playbooks/\` | \`<workspace>/playbooks/\` | per-repo playbooks and runbooks |
| \`ops/\` | \`<workspace>/ops/\` | policy and reaction overrides |

\`layer.conf\` is the manifest. \`scrub-terms.txt\` is the list of words that
must never reach the public kit. \`.env\` holds local secret values and is
gitignored.

## Composing

\`\`\`bash
managed/scripts/kit-layer.sh apply $ORG --dry-run
managed/scripts/kit-layer.sh apply $ORG
\`\`\`

Run it again after every change here, and after every \`kit-sync.sh\`.

## The rule

Nothing in this directory ever travels to the public kit. If a change here
turns out to be useful to everyone, rewrite it generically, put it in
\`managed/\`, and promote that with \`kit-promote.sh\`.
EOF

  echo ""
  echo -e "${GREEN}${BOLD}Created layers/$ORG${NC}"
  echo -e "${DIM}$LAYER${NC}"
  echo ""
  echo -e "${BOLD}Next${NC}"
  echo "  1. Fill in layers/$ORG/layer.conf (domains, aliases, repos)."
  echo "  2. Add the client's names and codenames to layers/$ORG/scrub-terms.txt."
  echo "  3. Put client-specific agents, skills, scripts, playbooks and ops overrides"
  echo "     in the matching subdirectory."
  echo "  4. managed/scripts/kit-layer.sh apply $ORG"
  echo ""
  exit 0
fi

[[ -d "$LAYER" ]] || { echo -e "${RED}No layer at layers/$ORG. Run: kit-layer.sh init $ORG${NC}" >&2; exit 1; }

# ─── shared: enumerate what the layer would place ────────────────
plan_file="$(mktemp)"
trap 'rm -f "$plan_file"' EXIT
: > "$plan_file"

while IFS=: read -r src dst; do
  [[ -z "$src" ]] && continue
  [[ -d "$LAYER/$src" ]] || continue
  ( cd "$LAYER/$src" && find . -type f ! -name '.gitkeep' ! -name '.DS_Store' 2>/dev/null | sed 's|^\./||' ) \
    | while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        printf '%s\t%s\n' "$src/$f" "$dst/$f" >> "$plan_file"
      done
done <<EOF
$COMPOSE
EOF

# ─── check ───────────────────────────────────────────────────────
if [[ "$CMD" == "check" ]]; then
  echo ""
  echo -e "${BOLD}Layer $ORG${NC}"
  echo -e "${DIM}$LAYER${NC}"
  n_ok=0; n_missing=0; n_stale=0
  while IFS=$'\t' read -r src dst; do
    [[ -z "$src" ]] && continue
    if [[ ! -f "$WORKSPACE/$dst" ]]; then
      echo -e "  ${YELLOW}not composed${NC}  $dst"; n_missing=$((n_missing+1))
    elif ! diff -q "$LAYER/$src" "$WORKSPACE/$dst" >/dev/null 2>&1; then
      echo -e "  ${YELLOW}out of date${NC}   $dst"; n_stale=$((n_stale+1))
    else
      n_ok=$((n_ok+1))
    fi
  done < "$plan_file"
  echo ""
  if [[ $((n_missing + n_stale)) == 0 ]]; then
    echo -e "${GREEN}All $n_ok layer files are composed and current.${NC}"
    echo ""; exit 0
  fi
  echo -e "${YELLOW}$n_missing not composed, $n_stale out of date, $n_ok current.${NC}"
  echo "Run: managed/scripts/kit-layer.sh apply $ORG"
  echo ""
  exit 1
fi

# ─── apply ───────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Composing layer $ORG${NC}"
echo -e "${DIM}Workspace: $WORKSPACE${NC}"
echo ""

if [[ ! -s "$plan_file" ]]; then
  echo -e "${YELLOW}The layer is empty. Nothing to compose.${NC}"
  echo ""; exit 0
fi

# Refuse anything that would land inside managed/ or clobber user/.
refused=false
while IFS=$'\t' read -r src dst; do
  [[ -z "$dst" ]] && continue
  case "$dst" in
    managed/*|../*|/*)
      echo -e "${RED}REFUSED: $src would write to $dst${NC}"
      echo -e "${RED}managed/ belongs to the kit. A layer may never write into it.${NC}"
      refused=true ;;
    user/*)
      if [[ -f "$WORKSPACE/$dst" && "$FORCE" != true ]]; then
        echo -e "${RED}REFUSED: $src would overwrite $dst${NC}"
        echo -e "${RED}user/ files belong to the client. Pass --force if you really mean it.${NC}"
        refused=true
      fi ;;
  esac
done < "$plan_file"
if [[ "$refused" == true ]]; then echo ""; exit 2; fi

n_new=0; n_upd=0; n_same=0
while IFS=$'\t' read -r src dst; do
  [[ -z "$src" ]] && continue
  if [[ ! -f "$WORKSPACE/$dst" ]]; then
    echo -e "  ${GREEN}add${NC}     $dst"; n_new=$((n_new+1))
  elif diff -q "$LAYER/$src" "$WORKSPACE/$dst" >/dev/null 2>&1; then
    n_same=$((n_same+1))
  else
    echo -e "  ${YELLOW}update${NC}  $dst"; n_upd=$((n_upd+1))
  fi
done < "$plan_file"
[[ "$n_same" != "0" ]] && echo -e "  ${DIM}$n_same already current${NC}"

if [[ "$DRY_RUN" == true ]]; then
  echo ""
  echo -e "${DIM}Dry run. Nothing written.${NC}"
  echo ""; exit 0
fi

: > "$LAYER/.applied"
while IFS=$'\t' read -r src dst; do
  [[ -z "$src" ]] && continue
  mkdir -p "$WORKSPACE/$(dirname "$dst")"
  cp -p "$LAYER/$src" "$WORKSPACE/$dst"
  echo "$dst" >> "$LAYER/.applied"
done < "$plan_file"

echo ""
echo -e "${GREEN}${BOLD}Composed.${NC} $n_new added, $n_upd updated, $n_same unchanged."
echo -e "${DIM}Placed files listed in layers/$ORG/.applied${NC}"
echo -e "${GREEN}managed/ and user/ were not written to.${NC}"
echo ""
