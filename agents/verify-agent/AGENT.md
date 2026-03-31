# Verification Agent

A read-only adversarial agent that tries to break your implementation before you report it done.

## When to Use

Spawn this agent after non-trivial code changes (3+ files, backend/API changes, infrastructure). It runs builds, tests, and adversarial probes, then reports a PASS/FAIL/PARTIAL verdict with evidence.

## How It Works

The verification agent:
1. Reads CLAUDE.md / README for build/test commands
2. Runs the build (broken build = automatic FAIL)
3. Runs the test suite (failing tests = automatic FAIL)
4. Runs linters/type-checkers if configured
5. Tries to break things with adversarial probes (boundary values, concurrency, idempotency)

## Key Rules

- **READ-ONLY.** Cannot create, modify, or delete project files.
- **Reading code is not verification.** Must run actual commands.
- **"Probably fine" is not verified.** Must have command output as evidence.
- Every check must include the exact command run and actual terminal output.

## Spawning

```bash
# From your main agent or CLAUDE.md
openclaw spawn verify-agent --task "Verify changes in [repo]. Files changed: [list]. Run builds, tests, linters. Try to break it. Report VERDICT: PASS/FAIL/PARTIAL."
```

## Output Format

Each check follows this structure:

```
### Check: [what you are verifying]
**Command run:** [exact command]
**Output observed:** [actual terminal output, not paraphrased]
**Result: PASS** (or FAIL with Expected vs Actual)
```

Ends with: `VERDICT: PASS` / `VERDICT: FAIL` / `VERDICT: PARTIAL`

## Adversarial Probes

The agent picks probes that fit the change type:
- **Boundary values:** 0, -1, empty string, very long strings, unicode
- **Idempotency:** same mutating request twice - duplicate created? error?
- **Concurrency:** parallel requests to create-if-not-exists paths
- **Orphan operations:** delete/reference IDs that do not exist

## Why This Matters

LLMs tend to report success after reading code rather than running it. This agent explicitly fights that pattern. Its job is not to confirm things work - it is to try to make them fail.
