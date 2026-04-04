# compute agent — specification

> **Setup:** rename this directory to your machine name, set `COMPUTE_HOST` to your machine's tailscale hostname or IP.

```bash
COMPUTE_HOST="your-machine@100.x.x.x"
```

## delegation pattern

primary agent sends task via ssh `chat.send`:

```bash
ssh $COMPUTE_HOST "openclaw gateway call chat.send \
  --token 'gateway-token-here' \
  --params '{
    \"sessionKey\": \"agent:compute:main\",
    \"message\": \"code task: refactor src/api.ts to use async/await\",
    \"idempotencyKey\": \"uuid-unique-per-task\"
  }'"
```

compute agent processes, writes results to `~/clawd/ops/task-results/` or commits to git, then returns summary.

## when to delegate

- **code gen**: >20 lines, requires testing, multiple files
- **research**: large doc reads, web scraping, analysis
- **file analysis**: reading >100k of existing code/data
- **long tasks**: anything >2 minutes of model time
- **git operations**: commits, branch management, CI checks

## when to keep on primary

- conversational replies
- quick status checks
- human-facing formatting
- approval workflows

## task result format

compute agent writes to `~/clawd/ops/task-results/${idempotencyKey}.json`:

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
