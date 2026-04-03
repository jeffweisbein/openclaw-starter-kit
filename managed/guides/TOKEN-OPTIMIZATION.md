# Token Optimization Guide

how to stretch your claude max (or any llm subscription) way further.

## the problem

every message you send includes:
- all previous messages in the conversation (context window)
- all auto-injected instructions (memory category: `instruction`)
- system prompts, tool definitions, file contents read during the session

a 50-message conversation might send 100k+ tokens per message. that's why you burn through a $200/month plan in 2-3 days.

## quick wins (free, immediate)

### 1. minimize auto-injected instructions

openclaw's memory-tools plugin auto-injects every memory with `category: instruction` into every single message. each instruction burns tokens on every exchange.

**rules:**
- only store truly universal rules as `instruction` (style, tone, core behavior)
- store everything else as `context` (searched on-demand, not auto-injected)
- aim for 4-5 instruction memories max, ~200 tokens total

**good instruction memories** (needed every message):
- writing style / tone
- core delegation rules
- communication preferences

**bad instruction memories** (move to context):
- api syntax/patterns (only needed when using that api)
- project-specific guardrails (only needed when working on that project)  
- reference templates (only needed when writing that type of content)

### 2. reset conversations often

context grows linearly with conversation length. message 50 carries all 49 previous messages.

| conversation length | approx tokens per message | waste factor |
|---|---|---|
| 5 messages | ~5k | 1x (baseline) |
| 20 messages | ~30k | 6x |
| 50 messages | ~80k | 16x |
| 100 messages | context limit hit | compaction kicks in |

**rule of thumb:** start a new conversation when switching topics. one focused 10-message thread beats a 50-message mega-thread.

### 3. use file reads efficiently

`Read` with `offset` and `limit` instead of reading entire files. a 500-line file read once stays in context forever.

### 4. batch questions

5 separate messages = 5 full context sends. one message with 5 questions = 1 context send.

## multi-machine delegation

if you have two machines (e.g. agent-1 + agent-2), route tasks by complexity:

| task type | where to run | why |
|---|---|---|
| quick answers, conversation | primary (agent-1) | low tokens, fast |
| code generation | secondary (forge) | high tokens, delegated |
| web research | secondary (forge) | fetching burns context |
| file analysis | secondary (forge) | large content in context |
| local file edits | primary (agent-1) | needs filesystem access |

delegation via ssh:
```bash
ssh agent-2@<tailscale-ip> "openclaw gateway call chat.send \
  --token '<gateway-token>' \
  --params '{\"sessionKey\": \"agent:main:main\", \"message\": \"<task>\", \"idempotencyKey\": \"<unique-id>\"}'"
```

**important:** `sessions_spawn` with `gatewayUrl` does NOT delegate compute. it still runs locally. use `chat.send` via ssh for true delegation.

## memory hygiene

periodically audit your memories:

```
# check how many instruction memories exist
# in your memory db:
sqlite3 ~/.openclaw/memory/tools/memory.db \
  "SELECT COUNT(*) FROM memories WHERE category = 'instruction';"
```

target: 4-5 instruction memories, everything else as context/fact/decision.

## session auto-reset

configure your agent to proactively suggest session resets when context exceeds 50%. this prevents the worst token waste from mega-conversations.
