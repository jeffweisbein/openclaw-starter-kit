# Active task checkpoint

Copy under the configured memory root at `sessions/<opaque-session-id>/<task-id>.md`.
Use only for the matching audience/session/task. This is a compact checkpoint, not a transcript.

- Updated: <ISO timestamp>
- Audience: <private owner / explicitly authorized group>
- Session ID: <opaque ID>
- Task ID: <stable ID>
- Goal: <current objective>
- Latest user correction: <takes precedence over older plans>
- Completed and evidence: <artifact/run/commit references>
- Next action: <one concrete action>
- Pending work: <run IDs and result locations; check before retrying>
- Existing authorization and limits: <scope; do not infer new authority>
- Unverified or blocked: <what evidence is missing>
- Deferred topics: <pointers, not duplicated history>

On resume verify identity and current state. Record acknowledgment of recovered work;
retain evidence rather than deleting based on timestamp. Private checkpoints are not
inputs to public-room agents or untrusted build tasks.
