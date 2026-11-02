# Operating lessons: continuity, corrections and delivered results

Updated November 2, 2026. These are portable procedures, not bundled runtime features.
Use existing checkpoint, scheduler and release mechanisms; do not install a parallel control plane.

## 1. Correct the current task, not a remembered task

Recover the exact conversation/task checkpoint before replacing it. Keep goal, latest
correction, next action, evidence and limits compact. Link older details instead of
copying entire histories. Latest explicit user direction outranks a saved summary.
Read session history through supported interfaces, not private raw transcript databases.

Before a handoff, record task identity and current decision revision. After a correction,
update the same task record and steer its existing workers. Compare returned work to the
current revision before accepting it. A late result is not automatically current evidence.
A rejected follow-up or empty pending-work list means no continuation is queued; report
that state rather than promising an automatic resume.

A prompt-level revision check is only a workflow convention. Enforced stale-worker
blocking requires supported runtime hooks, durable state, validated caller lineage and
live refusal tests. Experimental decision-contract plugins and patched binaries are not
included or activated by this kit. Do not copy a private binary path into public setup.
Already-running side effects cannot necessarily be recalled after a correction.

## 2. Match verification to the requested outcome

Establish the smallest observable acceptance condition before substantial work. Separate:
source changed → checks passed → artifact built → installed/deployed → live behavior
observed → user confirmed. Do not collapse these into “done.”

For a recurring defect, bind proof to the exact source/artifact and existing issue. Replay
the original failure against the old case, then test the corrected and valid cases. Label
fixtures, synthetic probes and real-user outcomes separately. Reuse passing evidence when
nothing relevant changed; avoid repeated broad suites for reassurance.

For native apps, compare the installed artifact with the verified build and inspect the
actual target machine. A successful build on one host does not prove installation on
another. For websites, verify the intended deployment and signed-in user flow where
possible; a public HTTP 200 does not test authenticated behavior.

## 3. Upgrade without losing the thread

Follow RELIABILITY.md and BACKUPS.md. Inspect current state and retain rollback artifacts.
Exclude old backup trees and regenerable temporary files from a new archive. Use native
consistent database backups and disposable restore checks; copying an actively written
SQLite file is not a validated backup.

Record package build identity, loaded plugin source and selected executable separately.
An updater success receipt proves its reported stage, not every optional plugin's
activation. A plugin directory on disk is not proof it loaded. After restart, test a
fresh conversation and the specific repaired path. A selected model may still have
fallen back; inspect the actual provider/harness.

If restart drains the current turn, checkpoint before releasing it. Confirm whether a
continuation was accepted. Do not launch a second updater because the first call timed
out. Recover the existing update ID and inspect its terminal receipt first.

## 4. Route events and reasoning deliberately

Use scripts for deterministic checks, bounded read retries, deduplication and status
transitions. Use model judgment where interpretation is needed. Keep recurring model
work isolated from the main conversation with explicit model, reasoning and context
settings supported by that runtime. Preserve existing schedules and delivery ownership.

Retry only known transient, safe operations within a hard budget. Do not retry a send,
payment or uncertain write merely because its acknowledgment is missing. Keep unknown,
failed, disabled and healthy states distinct.

## 5. Learn from content feedback without inventing evidence

Read current edits and rejection reasons before drafting. Treat them as voice guidance,
not a source for factual claims. Rejected angles need a new approach, not synonyms.
For source-led replies, read the original and contribute a distinct implication. Avoid
bulk repetitive replies, invented experience and unsupported product claims. Publication
requires authorization; slower posting cannot guarantee freedom from platform flags.

Measure observed outcomes separately from configuration: a scheduled job is not an
observed run; a published post is not an attributed sale. Preserve unknown attribution.
