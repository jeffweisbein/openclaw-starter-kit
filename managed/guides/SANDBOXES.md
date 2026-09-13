# Per-agent sandboxes

If every agent shares one filesystem, one bad delete is everybody's problem and
one leaked token is every agent's token. `managed/scripts/agent-sandbox.sh`
gives each agent its own durable computer instead: an isolated Linux VM with a
persistent home volume, built on Apple `container`.

Durable is the important word. This is not a throwaway container per command.
The sandbox is long-lived, you `exec` into it, and a tool installed in one turn
is still installed the next turn. An agent that has to reinstall its toolchain
on every invocation will simply stop using the sandbox.

## What each agent gets

| Thing | Name | Notes |
|---|---|---|
| Container (VM) | `sbx-<agent>` | Long-lived. `stop`/`start`, never `--rm` |
| Home volume | `sbx-<agent>-home` | ext4 image mounted at `/agent`, which is `$HOME` |
| Network | `sbx-<agent>-net` | Its own `/24`, so agents cannot reach each other |
| Provision spec | `<workspace>/state/agent-sandboxes/<agent>.spec` | So `reset` rebuilds with the same caps |

Inside the sandbox, `/etc/profile.d/00-agent-sandbox.sh` sets `HOME=/agent`,
`NPM_CONFIG_PREFIX`, `PYTHONUSERBASE`, the npm and pip caches, and a `PATH` that
picks all of it up. `exec` always runs a **login** shell, so it applies.

Two things survive `stop`/`start`: everything on the volume, and the container's
own rootfs, so system packages installed with the image's package manager stay
too.

## Requirements

Apple `container` 1.0+, which needs macOS 26. No sudo, no daemon to install,
nothing global changed. If the binary is not on `PATH`, set `CONTAINER_BIN`.

## Local or remote, same script

Sandboxes are most useful on a second machine, because that is usually where
the heavy work goes. The script handles both:

```bash
# here
./managed/scripts/agent-sandbox.sh provision researcher

# on a build box: copy the same file there, then point at it
scp managed/scripts/agent-sandbox.sh you@buildbox:~/clawd/managed/scripts/
export SANDBOX_HOST=you@buildbox
./managed/scripts/agent-sandbox.sh provision researcher
```

With `SANDBOX_HOST` set, every subcommand is forwarded over SSH to the same
script on that machine. One file, one place, called from anywhere. Set
`SANDBOX_REMOTE_PATH` if you put it somewhere other than
`~/clawd/managed/scripts/agent-sandbox.sh`.

## Use it

```bash
S=./managed/scripts/agent-sandbox.sh

$S provision researcher                                  # idempotent
$S provision builder --mem 2048M --cpus 3 --disk 16G     # custom caps
$S provision auditor --no-net                            # loopback only

$S exec researcher "npm install -g some-tool"
$S exec researcher "some-tool --version"
$S shell researcher                                      # interactive

$S list
$S status researcher
$S stop researcher                                       # frees its RAM, keeps state
$S stop-all                                              # RAM hygiene
$S reset researcher --yes                                # wipe THIS agent only
```

`exec` auto-starts a stopped sandbox, and its exit code is the command's real
exit code, so it composes into scripts.

`--no-net` is worth knowing about. It gives the sandbox loopback only: nothing
in, nothing out, not even a package install. That is the right shape for
anything that reads untrusted input and does not need the network, because it
removes the exfiltration path entirely rather than trying to detect it.

## Configuration

Everything is an environment variable, because your machine names, workspace
layout and subnet range are not the same as anyone else's.

| Variable | Default | What |
|---|---|---|
| `SANDBOX_HOST` | unset (local) | `user@host` to run on |
| `SANDBOX_REMOTE_PATH` | `$HOME/clawd/managed/scripts/agent-sandbox.sh` | Where the script lives there |
| `CONTAINER_BIN` | `container` on `PATH` | The `container` binary |
| `OPENCLAW_WORKSPACE` | `~/clawd` | Workspace root |
| `SANDBOX_SPEC_DIR` | `<workspace>/state/agent-sandboxes` | Where specs are recorded |
| `SANDBOX_PREFIX` | `sbx` | Name prefix for containers, volumes and networks |
| `SANDBOX_SUBNET_BASE` | `192.168` | First two octets of per-agent networks |
| `SANDBOX_IMAGE` | `docker.io/library/node:22-alpine` | Base image |
| `SANDBOX_MEM` / `SANDBOX_CPUS` / `SANDBOX_DISK` | `1024M` / `2` / `8G` | Provision defaults |

Change `SANDBOX_SUBNET_BASE` if `192.168.70` through `192.168.99` collides with
your LAN. Change `SANDBOX_PREFIX` if you already run containers with names that
would clash: `stop-all` and `list` only ever touch names carrying the prefix,
and that is the only thing keeping them off the rest of the box.

## Failure modes worth knowing

**A volume with no size cap.** An auto-created volume defaults to a 512 GiB
sparse image. The script always creates the volume explicitly with a cap, which
is why `--disk` exists and why you should set it deliberately.

**`reset` quietly reverting to defaults.** Provisioning records the caps to a
spec file so a rebuild uses the same ones. Without that, an agent that needed
3 CPUs comes back with 2 and gets slower for reasons nobody connects to the
reset.

**RAM.** Each running sandbox costs a few hundred megabytes of host memory even
while idle. `stop-all` between batches is not optional on a small box, and state
is kept, so stopping costs nothing but the restart.

## What this is and is not

It is real isolation between agents: separate filesystems, separate networks,
no view of the host's disk. That covers the accident case completely, and it
covers a compromised agent as far as the container boundary goes.

It is not a claim about escaping a VM, and it does not protect anything you
mount into the sandbox or any credential you pass in. Give each agent only the
tokens it needs, scoped as narrowly as the provider allows. The sandbox limits
what a leak reaches, not what a leak is worth.

## v2.6: Docker/Colima and effective-policy verification

Keep the Apple-container option above when it fits. A Docker-compatible runtime such as
Colima is an alternative for an OpenClaw-managed dedicated builder. Use the runtime's
supported sandbox configuration and inspect the effective policy before routing work.
Do not build another container orchestrator on top of the kit.

Recommended bounded builder profile: non-root user, read-only root filesystem, dropped
capabilities, no-new-privileges, no network, one dedicated writable task directory,
explicit read-only skill mounts only, and no host credentials or Docker socket mounted.
Prebuild dependencies into the image; a no-network builder cannot download them.
Container inspection does not expose private file contents, but never publish raw
inspection output: environment fields can contain credentials.

Run against an already-created container with its exact context and mounted task path:

```bash
python3 managed/scripts/check-isolation.py \
  --context builder-context --container builder-container --task-path /workspace
```

If the runtime needs a read-only skills mount, explicitly add `--allow-readonly /skills`
with its actual destination and review the source separately. Unexpected mounts fail.
The helper checks effective policy, UID, socket absence and a temporary task-file
write/read. It does not install Colima, change the default context, or run on the host
when inspection fails. It does not itself test arbitrary egress or runtime routing.

Finally run a real task through the dedicated agent: write/read its scratch file, attempt
an innocuous forbidden-path read and a harmless outbound connection, and verify denials
in actual tool receipts. Keep credentials out of the test. Only that establishes the
agent is routed into the inspected sandbox; creating a container is not sufficient.

A config value can validate without reaching the service environment. If the gateway
needs a nondefault Docker context, use its supported persistent service wrapper/environment
mechanism and verify it after restart. Do not overwrite the operator's default context
or loosen the sandbox to work around a routing error. Preserve config and service backups.
