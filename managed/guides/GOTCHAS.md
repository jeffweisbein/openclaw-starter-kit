# Agent Gotchas

Failure modes that will bite an autonomous agent workspace, and how to avoid them.
These aren't hypotheticals — each one is a real incident that cost a debugging session.
Add your own as you hit them.

## Background work spawned from a turn gets reaped

**Symptom:** you fire off a background sub-agent (or a detached job) from inside a chat
reply or a heartbeat/cron turn, the turn ends, and the work dies half-done — often
reported as "stopped by user" with zero output, even though nobody stopped anything.

**Why:** a sub-agent spawned mid-turn is a *child of that turn*. When the turn ends
(the reply is sent, the cron fires its follow-up, a new inbound message arrives), the
runtime reaps the turn's children. Fire-and-forget from a turn that's about to end is a
race you lose.

**Fix:** do the work **inline** (await it before the turn ends), or hand it to something
**turn-independent** — a standalone cron job, a detached process on a build box, a
durable task queue. Never `spawn && return` from a turn and assume it keeps running.

## Remote/long-running builds die mid-run

**Symptom:** a build or migration dispatched to a remote box (over SSH) dies partway
through with no clear error, especially on longer jobs.

**Why:** three compounding causes — (1) no SSH keepalive, so an idle control channel
gets dropped; (2) the command runs in the foreground of the SSH session, so if the
session drops, the job dies with it; (3) memory pressure on a swapless box triggers the
OS to kill the process.

**Fix:**
- Set `ServerAliveInterval` on the SSH connection so the channel doesn't idle out.
- Run the build **detached** (`nohup … &` writing to a log) and **poll** the log for a
  done/fail marker, instead of holding the job in the foreground.
- Cap the toolchain's heap (e.g. `NODE_OPTIONS=--max-old-space-size=4096`) so a runaway
  build fails loudly instead of getting OOM-killed silently.

## "It compiled / returned 200" is not "it works"

**Symptom:** an agent reports a deploy done because the build succeeded or `curl`
returned 200 — and the live page is actually blank, throwing in the console, or
bouncing auth.

**Why:** a status code and a successful build say nothing about whether the rendered
page functions. Render failures, broken redirects, dead buttons, and client-side
exceptions all return 200.

**Fix:** verify **user-visible behavior**, not just the exit code. Drive the real page
in a browser and assert on content + a screenshot before claiming done — see
`managed/tools/web-verify`. Make the smoke step *block* the "done" claim on failure.

## Verify before you merge, not after

**Symptom:** unverified changes land on the main branch and break the next build for
everyone, or a plausible-but-wrong fix ships because it "looked right."

**Why:** the agent that wrote a change is the worst judge of whether it works — it's
primed to believe its own output.

**Fix:** gate merges/ships behind an **independent** check. Run the build + tests +
smoke, and for non-trivial changes have a *separate*, adversarial pass try to break it
(see `managed/agents-base/verify-agent`). Reading the diff is not verification; running
it is.

## Heartbeat spam

**Symptom:** the agent burns tokens (and your attention) every heartbeat deciding that
nothing is happening.

**Why:** the model was asked to *evaluate* state on every tick instead of only waking
when there's something to act on.

**Fix:** let **scripts** decide whether anything is actionable; only wake the model on
output. Keep `HEARTBEAT.md` tiny. Scripts are free; model time is expensive. (See the
philosophy note in `managed/HEARTBEAT.md`.)
