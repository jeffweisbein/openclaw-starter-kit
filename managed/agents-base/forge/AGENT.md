# forge agent — specification

## delegation pattern

primary agent sends task via ssh `chat.send`:

```bash
ssh forge@100.71.12.50 "openclaw gateway call chat.send \
  --token 'gateway-token-here' \
  --params '{
    \"sessionKey\": \"agent:forge:main\",
    \"message\": \"code task: refactor src/api.ts to use async/await\",
    \"idempotencyKey\": \"uuid-unique-per-task\"
  }'"
```

forge processes, writes results to `~/clawd/ops/task-results.json` or commits to git, then returns summary.

## when to delegate to forge

- **code gen**: >20 lines, requires testing, multiple files
- **research**: large doc reads, web scraping, analysis
- **file analysis**: reading >100k of existing code/data
- **long tasks**: anything >2 minutes of model time
- **git operations**: commits, branch management, CI checks

## when to keep local (primary agent)

- conversational replies
- quick status checks
- human-facing formatting
- approval workflows

## example flow

```
primary: "read src/api.ts and refactor to async/await"
  ↓
delegates via ssh → forge
  ↓
forge: reads file, rewrites, runs tests, commits
  ↓
forge returns: "refactored 8 functions. all tests pass. commit: a3f2d9c"
  ↓
primary: surfaces to user with summary
```

## task result format

forge writes to `~/clawd/ops/task-results/${idempotencyKey}.json`:

```json
{
  "status": "done|error|partial",
  "output": "human-readable summary",
  "commits": ["sha1", "sha2"],
  "files_modified": ["src/api.ts"],
  "command_output": "full stderr + stdout for verification",
  "duration_ms": 45000
}
```

primary agent reads this file and reports result.
