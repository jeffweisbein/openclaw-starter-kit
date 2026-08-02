#!/usr/bin/env bash
# agent-sandbox.sh — durable per-agent sandboxes, built on Apple `container`.
#
# One shared filesystem for every agent means one bad delete, or one leaked
# token, is everybody's problem. This gives each agent its own durable computer:
# an isolated Linux VM with a persistent home volume. Tools installed in one
# turn are still there the next turn, and agents cannot read each other's files
# or the host's.
#
# Long-lived, not throwaway. One sandbox per agent, `exec` into it, never --rm.
#
#   agent-sandbox.sh provision <agent> [--mem 1024M] [--cpus 2] [--disk 8G]
#                                      [--image IMG] [--no-net]
#   agent-sandbox.sh exec <agent> <command...>   # auto-starts a stopped sandbox
#   agent-sandbox.sh shell <agent>               # interactive
#   agent-sandbox.sh start|stop|status <agent>
#   agent-sandbox.sh list
#   agent-sandbox.sh stop-all                    # free host RAM; state is kept
#   agent-sandbox.sh reset <agent> --yes         # destroy + reprovision empty
#
# Exit code of `exec` is the command's real exit code.
#
# LOCAL OR REMOTE, SAME SCRIPT
#   Unset SANDBOX_HOST and it runs here. Set it and every subcommand is
#   forwarded over SSH to the same script on that machine, so you install one
#   file in one place and call it from anywhere:
#
#     scp managed/scripts/agent-sandbox.sh you@buildbox:~/clawd/managed/scripts/
#     export SANDBOX_HOST=you@buildbox
#     ./agent-sandbox.sh provision researcher
#     ./agent-sandbox.sh exec researcher "npm install -g some-tool"
#
# REQUIREMENTS
#   Apple `container` (macOS 26+). No sudo, no daemon install, nothing global.
#   Set CONTAINER_BIN if it is not on PATH.
#
# CONFIGURATION (all environment variables)
#   SANDBOX_HOST         user@host to run on. Unset means this machine.
#   SANDBOX_REMOTE_PATH  path to this script on SANDBOX_HOST.
#   CONTAINER_BIN        path to the `container` binary.
#   OPENCLAW_WORKSPACE   workspace root; specs go in <workspace>/state/.
#   SANDBOX_SPEC_DIR     override the spec directory outright.
#   SANDBOX_PREFIX       name prefix for containers/volumes/networks (default sbx).
#   SANDBOX_SUBNET_BASE  first two octets for per-agent networks (default 192.168).
#   SANDBOX_IMAGE / SANDBOX_MEM / SANDBOX_CPUS / SANDBOX_DISK   provision defaults.
#
# See managed/guides/SANDBOXES.md.
set -uo pipefail

WORKSPACE="${OPENCLAW_WORKSPACE:-$HOME/clawd}"
PREFIX="${SANDBOX_PREFIX:-sbx}"
SPEC_DIR="${SANDBOX_SPEC_DIR:-$WORKSPACE/state/agent-sandboxes}"
SUBNET_BASE="${SANDBOX_SUBNET_BASE:-192.168}"

DEF_MEM="${SANDBOX_MEM:-1024M}"
DEF_CPUS="${SANDBOX_CPUS:-2}"
DEF_DISK="${SANDBOX_DISK:-8G}"
DEF_IMAGE="${SANDBOX_IMAGE:-docker.io/library/node:22-alpine}"
MOUNT="/agent"

die(){ echo "agent-sandbox: $*" >&2; exit 2; }
usage(){ sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; }

# ── Remote dispatch ──────────────────────────────────────────────
# SANDBOX_REMOTE is set on the far side so the forwarded call runs locally
# there instead of bouncing back out over SSH.
if [ -n "${SANDBOX_HOST:-}" ] && [ -z "${SANDBOX_REMOTE:-}" ]; then
  REMOTE_PATH="${SANDBOX_REMOTE_PATH:-\$HOME/clawd/managed/scripts/agent-sandbox.sh}"
  rq(){ local out="" a; for a in "$@"; do out="$out '$(printf '%s' "$a" | sed "s/'/'\\\\''/g")'"; done; printf '%s' "$out"; }
  SSH_OPTS=(-o ConnectTimeout=10)
  case "${1:-}" in
    shell) exec ssh -t "${SSH_OPTS[@]}" "$SANDBOX_HOST" "SANDBOX_REMOTE=1 bash $REMOTE_PATH$(rq "$@")" ;;
    ""|-h|--help|help) usage; exit 0 ;;
    *) exec ssh "${SSH_OPTS[@]}" "$SANDBOX_HOST" "SANDBOX_REMOTE=1 bash $REMOTE_PATH$(rq "$@")" ;;
  esac
fi

# ── Local execution ──────────────────────────────────────────────
C="${CONTAINER_BIN:-}"
if [ -z "$C" ]; then
  C="$(command -v container 2>/dev/null || true)"
fi
[ -n "$C" ] || C="$HOME/tools/apple-container/prefix/bin/container"

need_container(){
  [ -x "$C" ] || die "the \`container\` binary was not found at '$C'.
Apple \`container\` (macOS 26+) is required. Install it, or set CONTAINER_BIN.
To run the sandboxes on another machine instead, set SANDBOX_HOST=user@host."
}

ensure_system(){
  need_container
  "$C" system status >/dev/null 2>&1 || "$C" system start >/dev/null 2>&1 \
    || die "could not start the container apiserver"
}

valid_id(){ case "$1" in ''|*[!a-z0-9-]*) return 1 ;; *) return 0 ;; esac; }

cname(){ echo "$PREFIX-$1"; }
vname(){ echo "$PREFIX-$1-home"; }
nname(){ echo "$PREFIX-$1-net"; }

state_of(){
  "$C" ls -a 2>/dev/null | awk -v n="$1" 'NR>1 && $1==n {print $5}'
}

next_subnet(){
  # pick an unused $SUBNET_BASE.<n>.0/24 for a new per-agent network
  local used n
  used="$("$C" network ls 2>/dev/null | awk 'NR>1{print $2}')"
  for n in $(seq 70 99); do
    echo "$used" | grep -q "$SUBNET_BASE.$n.0/24" || { echo "$SUBNET_BASE.$n.0/24"; return 0; }
  done
  return 1
}

cmd_provision(){
  local agent="$1"; shift
  local mem="$DEF_MEM" cpus="$DEF_CPUS" disk="$DEF_DISK" image="$DEF_IMAGE" nonet=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --mem) mem="$2"; shift 2 ;;
      --cpus) cpus="$2"; shift 2 ;;
      --disk) disk="$2"; shift 2 ;;
      --image) image="$2"; shift 2 ;;
      --no-net) nonet=1; shift ;;
      *) die "unknown provision flag: $1" ;;
    esac
  done
  ensure_system
  local cn vn nn st
  cn="$(cname "$agent")"; vn="$(vname "$agent")"; nn="$(nname "$agent")"

  st="$(state_of "$cn")"
  if [ -n "$st" ]; then
    echo "agent-sandbox: $cn already exists (state=$st) — nothing to do. Use 'reset' to rebuild."
    return 0
  fi

  # volume: ALWAYS create explicitly with a size cap. An auto-created volume
  # defaults to a 512 GiB sparse image, which is not something you want lying
  # around per agent.
  if ! "$C" volume ls 2>/dev/null | awk 'NR>1{print $1}' | grep -qx "$vn"; then
    echo "==> creating volume $vn ($disk)"
    "$C" volume create -s "$disk" "$vn" >/dev/null || die "volume create failed"
  fi

  # per-agent network so two agents cannot reach each other over IP
  local netargs=()
  if [ "$nonet" -eq 1 ]; then
    netargs=(--network none)
  else
    if ! "$C" network ls 2>/dev/null | awk 'NR>1{print $1}' | grep -qx "$nn"; then
      local sn; sn="$(next_subnet)" || die "no free subnet for $nn"
      echo "==> creating network $nn ($sn)"
      "$C" network create --subnet "$sn" "$nn" >/dev/null || die "network create failed"
    fi
    netargs=(--network "$nn")
  fi

  echo "==> creating container $cn (mem=$mem cpus=$cpus image=$image)"
  "$C" run -d --name "$cn" \
    -m "$mem" -c "$cpus" \
    "${netargs[@]}" \
    -v "$vn:$MOUNT" \
    -w "$MOUNT" \
    -e "HOME=$MOUNT" \
    -e "AGENT_ID=$agent" \
    --label "agent=$agent" \
    "$image" sleep infinity >/dev/null || die "container run failed"

  # wait for it to come up
  local i; for i in 1 2 3 4 5 6 7 8 9 10; do
    [ "$(state_of "$cn")" = "running" ] && break; sleep 1
  done

  echo "==> bootstrapping $MOUNT"
  "$C" exec "$cn" sh -c "
    set -e
    mkdir -p $MOUNT/work $MOUNT/.npm-global $MOUNT/.local/bin $MOUNT/.cache $MOUNT/bin
    mkdir -p /etc/profile.d
    cat > /etc/profile.d/00-agent-sandbox.sh <<'EOF'
export AGENT_ID='$agent'
export HOME=$MOUNT
export NPM_CONFIG_PREFIX=$MOUNT/.npm-global
export NPM_CONFIG_CACHE=$MOUNT/.cache/npm
export PIP_CACHE_DIR=$MOUNT/.cache/pip
export PYTHONUSERBASE=$MOUNT/.local
export PATH=$MOUNT/.npm-global/bin:$MOUNT/.local/bin:$MOUNT/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
cd $MOUNT/work 2>/dev/null || true
EOF
    chmod 0644 /etc/profile.d/00-agent-sandbox.sh
    printf '%s\n' '# agent sandbox' > $MOUNT/.profile
    echo '. /etc/profile.d/00-agent-sandbox.sh' >> $MOUNT/.profile
  " || die "bootstrap failed"

  # Remember the spec so `reset` rebuilds with the SAME caps instead of
  # silently reverting to the defaults.
  mkdir -p "$SPEC_DIR"
  printf 'MEM=%s\nCPUS=%s\nDISK=%s\nIMAGE=%s\nNONET=%s\n' "$mem" "$cpus" "$disk" "$image" "$nonet" > "$SPEC_DIR/$agent.spec"

  local netdesc="$nn"; [ "$nonet" -eq 1 ] && netdesc="none"
  echo "==> provisioned $cn  (home volume $vn at $MOUNT, network $netdesc)"
  cmd_status "$agent"
}

ensure_running(){
  local cn="$1" st
  st="$(state_of "$cn")"
  [ -n "$st" ] || die "sandbox $cn does not exist — run: agent-sandbox.sh provision ${cn#$PREFIX-}"
  if [ "$st" != "running" ]; then
    "$C" start "$cn" >/dev/null 2>&1 || die "could not start $cn"
    local i; for i in 1 2 3 4 5 6 7 8 9 10; do
      [ "$(state_of "$cn")" = "running" ] && break; sleep 1
    done
  fi
}

cmd_exec(){
  local agent="$1"; shift
  [ $# -gt 0 ] || die "no command given"
  ensure_system
  local cn; cn="$(cname "$agent")"
  ensure_running "$cn"
  # login shell so /etc/profile.d/00-agent-sandbox.sh (PATH, HOME, npm prefix) applies
  "$C" exec "$cn" /bin/sh -lc "$*"
}

cmd_shell(){
  local agent="$1"
  ensure_system
  local cn; cn="$(cname "$agent")"
  ensure_running "$cn"
  "$C" exec -it "$cn" /bin/sh -l
}

cmd_start(){ ensure_system; local cn; cn="$(cname "$1")"; ensure_running "$cn"; echo "started $cn"; }
cmd_stop(){  ensure_system; local cn; cn="$(cname "$1")"; "$C" stop "$cn" 2>&1; }

# Stop every RUNNING sandbox. Only $PREFIX-* is touched, never anything else on
# the box. Each running sandbox costs a few hundred MB of host RAM even idle.
cmd_stop_all(){
  ensure_system
  local names n
  names="$("$C" ls 2>/dev/null | awk -v p="^$PREFIX-" 'NR>1 && $1 ~ p {print $1}')"
  [ -n "$names" ] || { echo "no running sandboxes"; return 0; }
  for n in $names; do echo "stopping $n"; "$C" stop "$n" >/dev/null 2>&1; done
}

cmd_status(){
  ensure_system
  local agent="$1" cn vn
  cn="$(cname "$agent")"; vn="$(vname "$agent")"
  echo "--- $agent ---"
  "$C" ls -a 2>/dev/null | awk -v n="$cn" 'NR==1 || $1==n'
  "$C" volume ls 2>/dev/null | awk -v v="$vn" 'NR==1 || $1==v'
  local img
  img="$("$C" volume inspect "$vn" 2>/dev/null | awk -F'"' '/"source"/{print $4}' | sed 's#\\/#/#g')"
  [ -n "$img" ] && echo "volume image: $img ($(du -h "$img" 2>/dev/null | awk '{print $1}') on disk)"
}

cmd_list(){
  ensure_system
  echo "=== sandboxes ==="
  "$C" ls -a 2>/dev/null | awk -v p="^$PREFIX-" 'NR==1 || $1 ~ p'
  echo
  echo "=== volumes ==="
  "$C" volume ls 2>/dev/null | awk -v p="^$PREFIX-" 'NR==1 || $1 ~ p'
  echo
  echo "=== networks ==="
  "$C" network ls 2>/dev/null | awk -v p="^$PREFIX-" 'NR==1 || $1 ~ p'
}

cmd_reset(){
  local agent="$1"; shift
  local yes=0
  [ "${1:-}" = "--yes" ] && yes=1
  [ "$yes" -eq 1 ] || die "reset destroys $(cname "$agent") AND its volume $(vname "$agent"). Re-run with --yes."
  ensure_system
  local cn vn; cn="$(cname "$agent")"; vn="$(vname "$agent")"
  echo "==> stopping + deleting $cn"
  "$C" stop "$cn" >/dev/null 2>&1
  "$C" rm "$cn" >/dev/null 2>&1
  echo "==> deleting volume $vn"
  "$C" volume rm "$vn" >/dev/null 2>&1
  echo "==> reprovisioning"
  # rebuild with the recorded spec, not the defaults
  local flags=()
  if [ -f "$SPEC_DIR/$agent.spec" ]; then
    # shellcheck disable=SC1090
    MEM=""; CPUS=""; DISK=""; IMAGE=""; NONET=0
    . "$SPEC_DIR/$agent.spec"
    [ -n "$MEM" ]   && flags+=(--mem "$MEM")
    [ -n "$CPUS" ]  && flags+=(--cpus "$CPUS")
    [ -n "$DISK" ]  && flags+=(--disk "$DISK")
    [ -n "$IMAGE" ] && flags+=(--image "$IMAGE")
    [ "${NONET:-0}" = "1" ] && flags+=(--no-net)
    echo "    (using recorded spec: ${flags[*]})"
  fi
  cmd_provision "$agent" "${flags[@]}"
}

SUB="${1:-}"; shift || true
case "$SUB" in
  provision) [ $# -ge 1 ] || die "provision needs an agent id"; valid_id "$1" || die "bad agent id"; cmd_provision "$@" ;;
  exec)      [ $# -ge 2 ] || die "exec needs <agent> <command>"; valid_id "$1" || die "bad agent id"; cmd_exec "$@" ;;
  shell)     [ $# -ge 1 ] || die "shell needs an agent id"; cmd_shell "$1" ;;
  start)     [ $# -ge 1 ] || die "start needs an agent id"; cmd_start "$1" ;;
  stop)      [ $# -ge 1 ] || die "stop needs an agent id"; cmd_stop "$1" ;;
  status)    [ $# -ge 1 ] || die "status needs an agent id"; cmd_status "$1" ;;
  list|ls)   cmd_list ;;
  stop-all)  cmd_stop_all ;;
  reset)     [ $# -ge 1 ] || die "reset needs an agent id"; cmd_reset "$@" ;;
  ""|-h|--help|help) usage ;;
  *) die "unknown subcommand: $SUB" ;;
esac
