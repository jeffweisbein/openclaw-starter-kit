# SQUAD.md - Multi-Agent Setup Guide

Your AI doesn't have to work alone. Set up a squad of specialized agents that your main AI coordinates.

## The Pattern

```
YOU (human)
  ↕
COORDINATOR (main AI — your direct line)
  ↕                ↕               ↕
CONTENT AGENT    DEV AGENT    RESEARCH AGENT
(tweets, blogs)  (code, ops)  (analytics, intel)
```

You talk to the coordinator. The coordinator delegates to the squad.

## Agent Workspaces

Each agent gets their own folder:

```
~/clawd/
├── AGENTS.md          ← coordinator's operating manual
├── SOUL.md            ← coordinator's personality
├── agents/
│   ├── content-agent/
│   │   ├── SOUL.md    ← content agent's personality + rules
│   │   └── WORKING.md ← drafts awaiting approval
│   ├── dev-agent/
│   │   ├── SOUL.md    ← dev agent's personality + rules
│   │   └── TICK.md    ← activity log (keep trimmed!)
│   └── research-agent/
│       ├── SOUL.md    ← research agent's personality + rules
│       └── FINDINGS.md ← research reports
└── ops/
    ├── policies.json      ← what can auto-approve vs needs human approval
    └── reaction-matrix.json ← how agents react to each other's events
```

## Setting Up Agents in OpenClaw

Each agent runs as a separate OpenClaw agent with its own heartbeat:

```yaml
# In your OpenClaw config, add agents:
agents:
  content-agent:
    model: anthropic/claude-sonnet-4-20250514
    workspace: ./agents/content-agent
    heartbeat:
      interval: 30m
  dev-agent:
    model: anthropic/claude-sonnet-4-20250514
    workspace: ./agents/dev-agent
    heartbeat:
      interval: 15m
  research-agent:
    model: anthropic/claude-sonnet-4-20250514
    workspace: ./agents/research-agent
    heartbeat:
      interval: 2h
```

## Policies (ops/policies.json)

Control what agents can do without asking:

- **auto_approve_rules** — low-risk stuff that doesn't need human approval
- **require_approval** — always ask before doing these (tweets, emails, deploys)
- **never_auto_approve** — hard stops (deleting things, pushing to prod)
- **caps** — daily limits (max 5 tweets, max 10 DMs, etc.)
- **work_hours** — agents only work during these hours

## Reaction Matrix (ops/reaction-matrix.json)

Make agents react to each other — this is where emergent behavior happens:

- Content agent posts a tweet → Research agent analyzes engagement after 1 hour
- Dev agent finds a bug → Coordinator alerts the human immediately
- Research agent spots high engagement → Content agent drafts a followup
- Any mission fails → Dev agent diagnoses what went wrong

Each reaction has:
- **probability** — doesn't always fire (feels more natural)
- **cooldown** — prevents spam
- **delay** — some reactions should wait before acting

## Tips

- **Start with one agent.** Add more as you need them.
- **Trim activity logs weekly.** Dev agent's TICK.md will bloat if you don't.
- **Content agent NEVER posts without approval.** This is critical.
- **Use cheaper models for agents.** Sonnet for agents, Opus for coordinator.
- **Agents communicate through files.** WORKING.md, FINDINGS.md, TICK.md — these are their shared memory.

## Delegation Examples

**"Write a tweet about our new feature"**
→ Coordinator sends task to content agent
→ Content agent drafts in WORKING.md
→ Coordinator reviews and sends to human for approval

**"Check if production is healthy"**
→ Coordinator sends task to dev agent
→ Dev agent checks CI, error rates, uptime
→ Reports back through coordinator

**"What are competitors doing?"**
→ Coordinator sends task to research agent
→ Research agent crawls competitor sites, checks social, analyzes trends
→ Reports findings in FINDINGS.md
