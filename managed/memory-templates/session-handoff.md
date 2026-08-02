# Session Handoff (carryover from a context reset)

<!--
WHAT THIS IS

A long session eventually hits its token ceiling and gets archived. The next
session starts clean, which reads to the user as the agent forgetting a
conversation it was in the middle of. It greets them fresh, re-asks what they
were working on, and sometimes redoes work that was already finished.

This file is the fix. Whatever performs the reset writes the tail of the
conversation here BEFORE the new session starts. The new session reads it first
and picks the thread up.

HOW TO WIRE IT

1. `managed/AGENTS-base.md` already tells the agent to read
   `memory/session-handoff.md` first if it exists. That half is done.
2. The write half belongs to whatever resets your context. If you reset by
   hand, write this file by hand before you do. If a script does it, have the
   script dump the tail of the transcript into this shape. If your harness
   compacts on its own, check whether it actually does on your backend before
   you rely on it. See "The context meter is not a promise" in
   `managed/guides/GOTCHAS.md`.
3. The file is consumed, not kept. Once the thread is carried forward, the
   agent moves it to `memory/archives/` or deletes it. A stale handoff is worse
   than none: it makes a fresh session resume a conversation that already
   ended, which is why the timestamp below is load-bearing.

Copy this to `memory/session-handoff.md` and fill it in. Delete this comment.
-->

*Written <TIMESTAMP>. The previous session hit its token ceiling and was archived.*

**This is where the conversation was when it got cut off.** Pick it up from
here. Do not re-ask what the user was doing, and do not redo finished work.

## What the user asked for, most recent last

1. <request>
2. <request>
3. <request>

Anything above that was not finished is still owed.

## Where the work stood

- <what is done and verified>
- <what is half-done, and what the next step is>
- <what is blocked, and on what>

## Last exchanges

**User:** <verbatim>

**Me:** <verbatim>

## Open threads

- <background job or agent that was still running, and where its output lands>
- <anything promised but not yet delivered>
