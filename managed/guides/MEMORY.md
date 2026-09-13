# Memory: one root, explicit audience

`user/MEMORY.md` is a private long-term index, loaded only in the owner's private main session. It is not automatically shared with group chats or worker agents. References reachable from the index inherit that restriction.

## Configure once

Copy `managed/ops/workspace.example.json` to `ops/workspace.json`. `memoryRoot` is workspace-relative (default `memory`). `OPENCLAW_WORKSPACE` identifies the workspace; the helpers otherwise use `~/clawd`.

For a fresh install use:

- `user/MEMORY.md`: curated private index.
- `<memoryRoot>/YYYY-MM-DD.md`: daily notes.
- `<memoryRoot>/topics/`: stable user, feedback, project and reference notes.
- `<memoryRoot>/sessions/<opaque-session-id>/<task-id>.md`: compact task checkpoints.

Use opaque identifiers, not phone numbers or email addresses in paths. Copy the templates from `managed/memory-templates/`; templates do not activate automatic capture.

## Existing installations

Run `python3 managed/scripts/reliability.py memory-check --workspace /path/to/workspace`.
It is read-only. If both `memory/` and `user/memory/` contain files, reconcile them manually before enabling consolidation. Choose the existing authoritative root, compare overlapping files, preserve originals, then point runtime indexing, scripts and scheduler payloads at that same root. The checker cannot inspect external runtime indexing configuration for you.

Kit sync never migrates user data. A missing root is reported, not silently created somewhere else.

## Capture and resume

Save stable preferences as active directives with observed date; supersede contradicted preferences rather than keeping both active. Keep decisions with their rationale. Save temporary work in a task checkpoint or requested report, not the long-term index. User requests to save work are honored.

Use a checkpoint only when its audience, session and task match. Preserve completed work, latest correction, next action, evidence, pending IDs and verification limits. Do not paste whole transcripts into checkpoints. Do not delete a checkpoint simply because its timestamp predates the current session.

Before acting on a recalled path, flag, PR or deployment, verify it still exists and applies. Successful compaction means the runtime completed compaction and a later turn recalls seeded context; a shrinking context meter alone is not proof.

## Consolidation

Schedule through the installed runtime's supported automation interface; inspect its help/schema rather than copying old cron flags. Read existing schedules first and preserve cadence/delivery. Use the configured root, actual current date and explicit private-session scope. Save a receipt even when no changes are needed. If review or validation fails, withhold memory writes and report the failure; never proceed with unreviewed consolidation by default. Run a fixture-only pass before touching personal memory.
