#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
# kit-promote.sh: send a generic improvement from a client install
#              back to the public starter kit
#
# Only files under managed/ can travel. user/ and layers/ never leave
# the client's machine, and the script refuses paths in either one.
#
# Before it writes anything it scrubs the outgoing content, the commit
# message, and the branch name for client identifiers: org names and
# slugs from layers/*/layer.conf, extra terms from
# layers/*/scrub-terms.txt, API keys and tokens, emails, private IPs,
# phone numbers, home directory paths, and any domain that does not
# already appear in the kit. A hit stops the promotion. It does not
# warn and continue.
#
# It commits on a new branch cut from the kit's upstream default
# branch. It never pushes and never opens a PR.
#
# Usage:
#   ./kit-promote.sh --kit ~/src/starter-kit managed/scripts/health-check.sh
#   ./kit-promote.sh --kit ~/src/starter-kit --dry-run managed/guides/GOTCHAS.md
#   ./kit-promote.sh --kit ~/src/starter-kit \
#       --message "fix: handle empty task file" \
#       --branch fix/empty-task-file \
#       managed/scripts/check-agents.sh
#
#   --allow TERM   waive one false positive, by exact string. Repeatable.
#                  Every waiver is printed in the report.
#
# Exit: 0 = committed, 1 = usage or state problem, 2 = scrub failed
# ═══════════════════════════════════════════════════════════════════

set -uo pipefail

WORKSPACE="${OPENCLAW_WORKSPACE:-$HOME/clawd}"
KIT_DIR=""
BRANCH=""
MESSAGE=""
DRY_RUN=false
ALLOW_BINARY=false
PATHS=""
ALLOWED=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace)    WORKSPACE="$2"; shift 2 ;;
    --kit)          KIT_DIR="$2"; shift 2 ;;
    --branch)       BRANCH="$2"; shift 2 ;;
    --message|-m)   MESSAGE="$2"; shift 2 ;;
    --allow)        ALLOWED="$ALLOWED
$2"; shift 2 ;;
    --allow-binary) ALLOW_BINARY=true; shift ;;
    --dry-run)      DRY_RUN=true; shift ;;
    -h|--help)      sed -n '2,35p' "$0"; exit 0 ;;
    -*) echo "unknown argument: $1" >&2; exit 1 ;;
    *)  PATHS="$PATHS
$1"; shift ;;
  esac
done

if [[ -t 1 ]]; then
  RED="\033[0;31m"; GREEN="\033[0;32m"; YELLOW="\033[0;33m"
  DIM="\033[2m"; BOLD="\033[1m"; NC="\033[0m"
else
  RED=""; GREEN=""; YELLOW=""; DIM=""; BOLD=""; NC=""
fi

die() { echo -e "${RED}kit-promote: $*${NC}" >&2; exit 1; }

PATHS="$(echo "$PATHS" | sed '/^$/d')"
ALLOWED="$(echo "$ALLOWED" | sed '/^$/d')"
[[ -n "$PATHS" ]] || die "no paths given. Pass one or more paths under managed/."
[[ -d "$WORKSPACE/managed" ]] || die "no managed/ in $WORKSPACE"

if [[ -z "$KIT_DIR" ]]; then
  SELF_KIT="$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)"
  [[ -f "$SELF_KIT/managed/VERSION" && "$SELF_KIT" != "$WORKSPACE" ]] && KIT_DIR="$SELF_KIT"
fi
[[ -n "$KIT_DIR" && -d "$KIT_DIR/managed" ]] || die "pass --kit <path to a starter kit checkout>"
KIT_DIR="$(cd "$KIT_DIR" && pwd)"
git -C "$KIT_DIR" rev-parse --git-dir >/dev/null 2>&1 || die "$KIT_DIR is not a git repository"
[[ -z "$(git -C "$KIT_DIR" status --porcelain)" ]] || die "$KIT_DIR has uncommitted changes. Commit or stash them first."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ─── 1. Structural gate: nothing outside managed/ travels ────────
echo ""
echo -e "${BOLD}Promoting to the kit${NC}"
echo -e "${DIM}From: $WORKSPACE${NC}"
echo -e "${DIM}To:   $KIT_DIR${NC}"
echo ""

: > "$WORK/files"
while IFS= read -r p; do
  [[ -z "$p" ]] && continue
  rel="${p#./}"
  rel="${rel#$WORKSPACE/}"
  case "$rel" in
    managed/*) ;;
    user/*|layers/*)
      echo -e "${RED}${BOLD}REFUSED: $rel${NC}"
      echo -e "${RED}user/ and layers/ never travel upstream. That is the whole point of the split.${NC}"
      echo ""
      exit 2 ;;
    *)
      die "$rel is not under managed/. Only managed/ files can be promoted." ;;
  esac
  [[ -f "$WORKSPACE/$rel" ]] || die "$rel does not exist in $WORKSPACE"
  echo "$rel" >> "$WORK/files"
done <<EOF
$PATHS
EOF
sort -u "$WORK/files" -o "$WORK/files"

# ─── 2. Binary gate ──────────────────────────────────────────────
while IFS= read -r rel; do
  [[ -z "$rel" ]] && continue
  if ! grep -Iq . "$WORKSPACE/$rel" 2>/dev/null; then
    if [[ "$ALLOW_BINARY" != true ]]; then
      echo -e "${RED}${BOLD}REFUSED: $rel is binary.${NC}"
      echo -e "${RED}Screenshots and other binaries cannot be scrubbed by reading them.${NC}"
      echo -e "${RED}Check it by eye for client UI, names, and URLs, then pass --allow-binary.${NC}"
      echo ""
      exit 2
    fi
    echo -e "${YELLOW}Binary allowed by hand: $rel${NC}"
  fi
done < "$WORK/files"

[[ -n "$MESSAGE" ]] || MESSAGE="chore: promote $(head -1 "$WORK/files") from a client install"
[[ -n "$BRANCH" ]]  || BRANCH="promote/$(echo "$MESSAGE" | tr '[:upper:]' '[:lower:]' \
                        | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-40 \
                        | sed -E 's/-+$//')"

# ─── 3. Build the client identifier list ─────────────────────────
: > "$WORK/terms"
add_term() {
  local t
  t="$(echo "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [[ ${#t} -ge 3 ]] || return 0
  echo "$t" >> "$WORK/terms"
}

if [[ -d "$WORKSPACE/layers" ]]; then
  for layer in "$WORKSPACE"/layers/*/; do
    [[ -d "$layer" ]] || continue
    add_term "$(basename "$layer")"
    if [[ -f "$layer/layer.conf" ]]; then
      while IFS= read -r line; do
        case "$line" in \#*|"") continue ;; esac
        key="${line%%=*}"; val="${line#*=}"
        case "$key" in
          org_slug|org_name|org_aliases|org_domains|client_repos)
            echo "$val" | tr ',' '\n' | while IFS= read -r v; do add_term "$v"; done ;;
        esac
      done < "$layer/layer.conf"
    fi
    if [[ -f "$layer/scrub-terms.txt" ]]; then
      while IFS= read -r line; do
        case "$line" in \#*|"") continue ;; esac
        add_term "$line"
      done < "$layer/scrub-terms.txt"
    fi
  done
fi

# The operator's own machine is a client identifier too.
add_term "$(basename "$HOME")"
if git -C "$WORKSPACE" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$WORKSPACE" remote -v 2>/dev/null \
    | sed -E 's#.*[:/]([^/]+/[^ ]+)\.git.*#\1#' | sort -u \
    | while IFS= read -r r; do add_term "$r"; done
fi

sort -u "$WORK/terms" -o "$WORK/terms" 2>/dev/null || : > "$WORK/terms"
# Drop anything explicitly waived.
if [[ -n "$ALLOWED" ]]; then
  echo "$ALLOWED" | sort -u > "$WORK/allowed"
  grep -v -x -F -f "$WORK/allowed" "$WORK/terms" > "$WORK/terms.f" 2>/dev/null || : > "$WORK/terms.f"
  mv "$WORK/terms.f" "$WORK/terms"
else
  : > "$WORK/allowed"
fi

# ─── 4. Scrub ────────────────────────────────────────────────────
: > "$WORK/hits"

record() { # source, line number, category, evidence
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$WORK/hits"
}

waived() {
  [[ -s "$WORK/allowed" ]] || return 1
  grep -q -x -F "$1" "$WORK/allowed"
}

SECRET_RE='(sk-ant-[A-Za-z0-9_-]{12,}|sk-[A-Za-z0-9]{24,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|xox[abposr]-[A-Za-z0-9-]{10,}|tskey-[A-Za-z0-9-]{10,}|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----)'
EMAIL_RE='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
HOME_RE='/(Users|home)/[A-Za-z0-9._-]+'
IP_RE='\b(100\.(6[4-9]|[7-9][0-9]|1[0-1][0-9]|12[0-7])\.[0-9]{1,3}\.[0-9]{1,3}|10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|192\.168\.[0-9]{1,3}\.[0-9]{1,3})\b'
PHONE_RE='\+1[0-9]{10}\b'
DOMAIN_RE='[a-zA-Z0-9][a-zA-Z0-9.-]*\.(com|net|org|io|ai|co|dev|app|xyz|sh|cloud|so|me)\b'

# Anything that already appears verbatim in the public kit is, by
# definition, not this client's. Without this, promoting a file means
# tripping over the kit's own example phone number and doc links on
# lines the client never touched. Client identifiers from layers/ are
# NOT allowlisted this way. They always fail.
{
  for re in "$SECRET_RE" "$EMAIL_RE" "$HOME_RE" "$IP_RE" "$PHONE_RE" "$DOMAIN_RE"; do
    grep -rhoE "$re" "$KIT_DIR/managed" "$KIT_DIR/README.md" 2>/dev/null
  done
  printf '%s\n' localhost 127.0.0.1
} | tr '[:upper:]' '[:lower:]' | sort -u > "$WORK/known-literals"

known_literal() {
  grep -q -x -F "$(echo "$1" | tr '[:upper:]' '[:lower:]')" "$WORK/known-literals"
}

scan_file() { # $1 = label, $2 = path to scan
  local label="$1" f="$2" spec cat re ln m

  if [[ -s "$WORK/terms" ]]; then
    grep -n -i -o -F -f "$WORK/terms" "$f" 2>/dev/null \
      | while IFS=: read -r ln m; do
          [[ -z "$m" ]] && continue
          waived "$m" && continue
          record "$label" "$ln" "client-identifier" "$m"
        done
  fi

  for spec in "secret:$SECRET_RE" "email:$EMAIL_RE" "home-path:$HOME_RE" \
              "private-ip:$IP_RE" "phone:$PHONE_RE"; do
    cat="${spec%%:*}"; re="${spec#*:}"
    grep -n -oE "$re" "$f" 2>/dev/null | while IFS=: read -r ln m; do
      [[ -z "$m" ]] && continue
      case "$cat" in
        home-path) case "$m" in /Users/you|/home/you|/Users/USER|/home/user) continue ;; esac ;;
        email)     case "$m" in *@example.com|*@example.org) continue ;; esac ;;
      esac
      known_literal "$m" && continue
      waived "$m" && continue
      record "$label" "$ln" "$cat" "$m"
    done
  done

  grep -n -oE "$DOMAIN_RE" "$f" 2>/dev/null | while IFS=: read -r ln m; do
    [[ -z "$m" ]] && continue
    known_literal "$m" && continue
    waived "$m" && continue
    record "$label" "$ln" "unknown-domain" "$(echo "$m" | tr '[:upper:]' '[:lower:]')"
  done
}

while IFS= read -r rel; do
  [[ -z "$rel" ]] && continue
  grep -Iq . "$WORKSPACE/$rel" 2>/dev/null || continue
  scan_file "$rel" "$WORKSPACE/$rel"
done < "$WORK/files"

printf '%s\n' "$MESSAGE" > "$WORK/msg";    scan_file "commit message" "$WORK/msg"
printf '%s\n' "$BRANCH"  > "$WORK/branch"; scan_file "branch name"    "$WORK/branch"

# ─── 5. Report ───────────────────────────────────────────────────
N_TERMS="$(wc -l < "$WORK/terms" | tr -d ' ')"
N_HITS="$(sort -u "$WORK/hits" 2>/dev/null | wc -l | tr -d ' ')"

echo -e "${DIM}Files:  $(wc -l < "$WORK/files" | tr -d ' ')${NC}"
echo -e "${DIM}Branch: $BRANCH${NC}"
echo -e "${DIM}Scrub:  $N_TERMS client term(s) from layers/, plus secret, email, path, IP, phone and domain patterns${NC}"
if [[ -s "$WORK/allowed" ]]; then
  echo -e "${YELLOW}Waived by hand: $(tr '\n' ' ' < "$WORK/allowed")${NC}"
fi
echo ""

if [[ "$N_HITS" != "0" ]]; then
  echo -e "${RED}${BOLD}SCRUB FAILED: $N_HITS client identifier(s) in the outgoing change.${NC}"
  echo -e "${RED}Nothing was written. The kit checkout is untouched.${NC}"
  echo ""
  sort -u "$WORK/hits" | while IFS=$'\t' read -r src ln cat ev; do
    padded="$(printf '%-20s' "[$cat]")"
    printf "  ${RED}%s${NC}%s${DIM}:%s${NC}  %s\n" "$padded" "$src" "$ln" "$ev"
  done
  echo ""
  echo -e "${BOLD}Fix one of these ways${NC}"
  echo "  Rewrite the file so the change is generic, then run this again."
  echo "  Move the client-specific part into layers/<org>/ and promote only what is left."
  echo "  If a hit is genuinely not a client identifier, waive it: --allow '<exact string>'"
  echo ""
  exit 2
fi

echo -e "${GREEN}Scrub passed. No client identifiers found.${NC}"

# ─── 6. Show the diff against upstream ───────────────────────────
DEFAULT_BRANCH=""
if git -C "$KIT_DIR" remote get-url origin >/dev/null 2>&1; then
  git -C "$KIT_DIR" fetch --quiet origin 2>/dev/null
  DEFAULT_BRANCH="$(git -C "$KIT_DIR" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"
  [[ -n "$DEFAULT_BRANCH" ]] || DEFAULT_BRANCH="origin/$(git -C "$KIT_DIR" rev-parse --abbrev-ref HEAD)"
else
  DEFAULT_BRANCH="$(git -C "$KIT_DIR" rev-parse --abbrev-ref HEAD)"
  echo -e "${YELLOW}No origin remote. Cutting the branch from local $DEFAULT_BRANCH.${NC}"
fi

echo ""
echo -e "${BOLD}Change against $DEFAULT_BRANCH${NC}"
while IFS= read -r rel; do
  [[ -z "$rel" ]] && continue
  if [[ -f "$KIT_DIR/$rel" ]]; then
    diff -u "$KIT_DIR/$rel" "$WORKSPACE/$rel" | sed "1,2d; s|^|  |" | head -60
    [[ "$(diff -u "$KIT_DIR/$rel" "$WORKSPACE/$rel" | wc -l | tr -d ' ')" -gt 62 ]] \
      && echo -e "  ${DIM}... truncated${NC}"
  else
    echo -e "  ${GREEN}new file: $rel ($(wc -l < "$WORKSPACE/$rel" | tr -d ' ') lines)${NC}"
  fi
done < "$WORK/files"

if [[ "$DRY_RUN" == true ]]; then
  echo ""
  echo -e "${DIM}Dry run. Nothing written.${NC}"
  echo ""
  exit 0
fi

# ─── 7. Cut the branch and commit. No push. ──────────────────────
ORIG_BRANCH="$(git -C "$KIT_DIR" rev-parse --abbrev-ref HEAD)"
git -C "$KIT_DIR" checkout --quiet -b "$BRANCH" "$DEFAULT_BRANCH" 2>/dev/null \
  || die "could not create branch $BRANCH in $KIT_DIR"

while IFS= read -r rel; do
  [[ -z "$rel" ]] && continue
  mkdir -p "$KIT_DIR/$(dirname "$rel")"
  cp "$WORKSPACE/$rel" "$KIT_DIR/$rel"
  git -C "$KIT_DIR" add "$rel"
done < "$WORK/files"

if [[ -z "$(git -C "$KIT_DIR" status --porcelain)" ]]; then
  echo ""
  echo -e "${YELLOW}Nothing to commit. The kit already has this content.${NC}"
  git -C "$KIT_DIR" checkout --quiet "$ORIG_BRANCH"
  git -C "$KIT_DIR" branch -D "$BRANCH" >/dev/null 2>&1
  echo ""
  exit 0
fi

git -C "$KIT_DIR" commit --quiet -m "$MESSAGE"

echo ""
echo -e "${GREEN}${BOLD}Committed on $BRANCH in $KIT_DIR${NC}"
echo -e "${DIM}Not pushed. Review it, then push and open the PR yourself:${NC}"
echo "  git -C $KIT_DIR log -p -1"
echo "  git -C $KIT_DIR push -u origin $BRANCH"
echo ""
