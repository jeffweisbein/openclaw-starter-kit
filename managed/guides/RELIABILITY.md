# Reliability: delivered work, not reassuring summaries

These tools are opt-in and standard-library only (Python 3.9+, Git; macOS/Linux).
They do not install runtime patches, edit schedules, send messages or grant permissions.

## 1. One delivery owner

For an automation configured to announce its final reply, the scheduler owns delivery.
The agent returns the deliverable once and does not call a send tool or inject a second
chat copy. Use `managed/templates/scheduled-job.md` as the payload starting point.
Keep the existing schedule, recipient and timezone when repairing a job.

On a timeout, inspect the run ID and delivery acknowledgment before retrying. Never use
fuzzy text matching to deduplicate different user messages. Prefer runtime-owned event
IDs and idempotency keys. Workspace prompts cannot implement exactly-once transport.
A restart test should prove one child result reaches its parent and one final appears
in the client. General reply dedupe and automation double-sending are separate paths.

## 2. Monitor output and scheduler state

The old `outcome-reaper.py` remains available for compatible, stateless artifact checks.
The new monitor adds explicit acknowledgment, recovery transitions and normalized
scheduler state. It does not assume that an artifact proves delivery.

```bash
python3 managed/scripts/reliability.py monitor \
  --workspace /path/to/workspace \
  --manifest /path/to/workspace/ops/job-outcomes.json \
  --scheduler /path/to/workspace/state/scheduler-export.json \
  --state /path/to/workspace/state/monitor-ack.json \
  --report /path/to/workspace/state/monitor-pending.json
```

Map your installed scheduler's API result to this local schema (not an OpenClaw API
schema). `observedAt` is Unix seconds and must be no more than one hour old:

```json
{"observedAt": 0, "jobs": [{"job": "daily-briefing", "enabled": true, "status": "ok"}]}
```

Replace the timestamp with the actual observation time. Include every monitored job;
missing, disabled or failed jobs are not healthy. Omit `--scheduler` only if you accept
an explicit `scheduler_unknown` result. To inspect a JSON receipt's outcome, add
`"receiptStatusField": "status"` to its manifest entry; the value must be `ok`.
Otherwise the artifact check proves freshness only. A fresh producer receipt does not
prove delivery: track the transport's acknowledged-delivery receipt separately.

Changed states produce JSON; unchanged acknowledged states are silent. Ages are not
part of the fingerprint, so each passing minute does not create another alert. Recovery
is a change too. The command returns 0 for a valid report, including detected incidents;
malformed input returns 2 and must raise a monitor-failure incident.

**A report is not an acknowledgment.** Only after confirmed delivery, or an explicit
initial-baseline acceptance, run:

```bash
python3 managed/scripts/reliability.py ack \
  --state /path/to/workspace/state/monitor-ack.json \
  --report /path/to/workspace/state/monitor-pending.json
```

A failed send must not advance state. Keep reports immutable per run and serialize
check/deliver/ack runs; stale acknowledgments are rejected. If your scheduler only
confirms delivery after the agent exits, acknowledgment belongs in a subsequent
reconciler using that run's delivery receipt, not in the generating agent. A crash
between delivery and acknowledgment can replay an alert: pass the fingerprint as the
transport idempotency key where supported. These files do not provide exactly-once
external delivery. Do not install a second monitor if the runtime already owns the
same incident state; use its durable scratch/versioned state instead.

## 3. Completion requires evidence

Use `managed/ops/completion-evidence.example.json`. Bind evidence to task and revision,
require only the relevant stages, and reference actual test/deploy/runtime receipts:

```bash
python3 managed/scripts/reliability.py evidence-check --receipt /path/to/evidence.json
```

Missing, failed, stale or wrong-revision proof blocks completion (exit 1); malformed
receipts exit 2. The latest observation wins, so an older passing test cannot hide a
newer failure. User confirmation must come from the user, not an agent's prediction.

This helper validates caller-supplied receipts. It is not an authorization boundary,
cryptographic attestation or substitute for independent testing. For consequential
releases, configure proof requirements in the runtime's supported Workboard/release
owner, with builder write access excluded. Verify a missing proof is refused there.
Do not assume enabling a plugin automatically enables proof enforcement.

## 4. Runtime update and rollback

Before changing a running gateway:

1. Record the actual core revision, model harness/provider, plugin versions, provenance
   and current health using supported status/inspection commands. Save private backups
   of config/service definitions without printing secrets. Inspect existing state and
   merge changes. Obtain any operator approval required for live interruption.
2. Create a native runtime backup plus database snapshots; test disposable restoration.
   Save a matching rollback package and procedure. Do not expose private backups in Git.
3. Validate candidates in an isolated gateway. A locally installed package loading in
   inspection does not prove the live loader grants the same trusted capabilities.
4. Use the supported updater and plugin installer. Never disable trust checks to make a
   local harness work. Verify official provenance when the runtime requires it. Local
   patches can disappear during updates; keep a versioned inventory and stop on mismatch.
5. Drain/restart through the service manager, then verify core identity, plugin activation,
   actual selected provider (no silent fallback), health and functional behavior.
6. Exercise a disposable conversation: seed a unique fact, compact through its current
   writer, verify later recall; test child completion and one final reply; test proof
   refusal and isolated task routing. Preserve receipts. Roll back on failure.

Health 200 alone is not success. Copying this kit does not install our runtime repairs;
use a release that supports the needed capabilities and run the checks on your build.
See `COMPATIBILITY.md` for limits and `BACKUPS.md` for recovery scope.
