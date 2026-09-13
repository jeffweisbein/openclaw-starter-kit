# Scheduled job payload template

- Job ID: <stable scheduler ID>
- Task: <bounded operation>
- Inputs: <explicit sources and audience>
- Workspace/memory root: <configured paths, not inferred host names>
- Expected output and idle receipt: <path/schema>
- Failure receipt: <path/schema; never refresh success on failure>
- Delivery owner: scheduler announcement of final response
- Cadence/timezone/recipient: preserved in scheduler configuration

Use the current run date, not a date embedded when this template was installed.
Run the operation and verify its output. Return the deliverable once; do not also send,
forward or inject it through another channel. If nothing changed, use the installed
scheduler's documented silent-result convention. Do not append commentary after that
result. Do not mark a message delivered without the transport acknowledgment.

Before retrying side effects, check the previous run ID and outcome. Save a compact
checkpoint for interrupted work. If a monitor or backup failed, report the failure
without claiming the service is down or previous backups were lost.
