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

## A green scheduler is not a working job

**Symptom:** the job list reads all healthy, nothing is overdue, nothing is erroring,
and the work has not actually happened for weeks. Somebody else notices first.

**Why:** a scheduler tracks whether a job ran. `lastRunStatus: ok` means the agent turn
completed. A turn completes fine when the API key it needed expired, when the script it
called started returning an empty list, or when the job has been quietly writing nothing
since a dependency moved. Nobody investigates a green board, so the failure gets weeks
of runway.

**Fix:** stop monitoring jobs and start monitoring the artifact each job is responsible
for keeping fresh, from outside the job. `managed/scripts/outcome-reaper.py` reads a
manifest of job to artifact to freshness budget and prints only what is stale, so it
costs nothing on a healthy workspace. Start from
`managed/ops/job-outcomes.example.json`.

**The rule that makes it work: a no-op must still write a receipt.** "Nothing to
report" and "I am broken" are otherwise the same observable, which is silence. A job
that legitimately found nothing must still touch its artifact on that run, and the error
path must not, so a failed run reads as stale. A job that cannot tell quiet from dead is
not monitored, it is decorated.

Set freshness budgets to cover the longest *legitimate* gap. A weekday-only job needs 72
hours, not 30, or it false-alarms every Saturday, and a check everyone has learned to
ignore is worse than no check.

## A cron's model pin has to be in the allowlist too

**Symptom:** a scheduled job fails on every single fire with a model error, while the
exact same model works fine when you try it by hand.

**Why:** pinning a model on a job and permitting that model are two different settings.
The pin says which model to use. The allowlist (`agents.defaults.models`, or whatever
your harness calls it) says which models an agent may use at all. A pin that is not in
the allowlist is rejected at dispatch, before the job does anything, so the failure is
100% reproducible and looks nothing like a model problem.

**Fix:** when you pin a model on a job, add it to the allowlist in the same change. And
know what a probe proves: running the model once from a shell, or seeing it in a
`models list` output, tests the *provider*, not the *agent path*. Those go through
different config. The only probe that means anything is a real dispatch through the same
path the job uses.

While you are in there: every recurring job should declare its model explicitly. An
unpinned job inherits your default, which is usually the expensive one you picked for
interactive work, and a monitoring check that wakes a frontier model every 15 minutes is
a bill you find at the end of the month.

## The context meter is not a promise

**Symptom:** the context indicator sits at 100%, you wait for the automatic compaction
you have seen before, and nothing happens. The session just gets worse: slower, more
forgetful, eventually stuck.

**Why:** auto-compaction is a property of the backend, not of the UI. Route the same
harness through a different backend (a CLI-subscription path rather than a direct API
path, say) and the meter still renders while nothing is watching it. The display is
reporting a number. It is not evidence that anything acts on the number.

**Fix:** find out empirically whether your backend compacts, by filling a session and
watching. If it does not, own the reset yourself: a script, a scheduled check, or a
habit. Do not wait for a rescue that was never wired up.

## A context reset looks like amnesia

**Symptom:** a long session gets archived at its token ceiling, the next one starts
clean, and the agent greets the user fresh, re-asks what they were working on, and
sometimes redoes work that was already finished.

**Why:** the reset is correct. The handoff is missing. Nothing carried the thread from
the dying session into the new one, so from the user's side a collaborator walked out
mid-sentence and came back with no memory of the conversation.

**Fix:** write the tail of the conversation to `memory/session-handoff.md` *before* the
reset, and have the agent read it first on startup. `managed/AGENTS-base.md` already
does the reading half. Template and the shape of the writing half:
`managed/memory-templates/session-handoff.md`.

Treat the file as consumed, not kept. A stale handoff makes a fresh session resume a
conversation that already ended, which is a worse failure than the one it was fixing, so
timestamp it and archive it once the thread is carried forward.

## Everything an agent fetches is instructions until you screen it

**Symptom:** a page, a scraped profile, or an email tells the agent to ignore its
instructions, email something somewhere, or keep a step quiet, and the agent partly
complies. Or it does not comply, and nobody ever finds out the attempt was made.

**Why:** fetched text lands in the same context window as the user's request. There is
no type system separating data from instructions in there. A wrapper banner that says
"treat the following as untrusted" helps, and it is not a boundary.

**Fix:** screen external content before the model acts on it.
`managed/scripts/screen-external.py` runs as a `PostToolUse` hook on the web tools and
annotates hostile content, with no LLM call and no network, so it is cheap enough for
every fetch. Wiring is in `managed/guides/HOOKS.md`.

Two things to get right or it will be switched off in a week. **Score combinations, not
keywords:** a lone action verb is nothing, and a document only looks like an attack when
an action co-occurs with something addressing or overriding the agent. **Check the false
positives harder than the true ones:** a screener that flags a press release and a
README stops being read, and then it protects nothing.

## Deleting is not reversible, and the agent is the one deleting

**Symptom:** a file that existed in no backup is gone. Usually a scheduled job did it,
usually as a cleanup step nobody reviewed, usually noticed days later.

**Why:** `rm` is the default thing an agent reaches for, permission settings get relaxed
because the whole point is not stopping to ask about every command, and the blast radius
of a wrong path is unbounded.

**Fix:** make deletion recoverable inside the trees that hold anything hand-made or
generated once. `managed/scripts/guard-destructive.py` is a `PreToolUse` hook that
denies `rm` there and tells the agent to use `trash` instead, while leaving `tmp`,
`logs`, build output and dependency directories alone so nothing regresses. It applies
the same treatment to schema-destroying SQL against anything not provably local.

The reason it is a hook and not a rule in `AGENTS.md` is that a hook survives
`bypassPermissions` and a rule in a markdown file survives nothing. Configure the
protected list to match your actual layout: a default list that does not match your
directories protects nothing. See `managed/guides/HOOKS.md`.
