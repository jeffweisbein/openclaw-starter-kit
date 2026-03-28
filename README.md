# OpenClaw Starter Kit 🐾

A battle-tested workspace template for giving your AI agent personality, memory, autonomy, and a whole squad.

Built by [@jeffweisbein](https://x.com/jeffweisbein) — shared on [This Week in Startups](https://thisweekinstartups.com).

## What is this?

This is the exact workspace structure that powers a personal AI assistant with:

- 🧠 **Persistent memory** across sessions (daily logs + curated long-term memory)
- 🎭 **Real personality** — opinions, tone, boundaries (not a corporate chatbot)
- 👥 **Multi-agent squad** — content writer, dev ops, researcher that coordinate autonomously
- 🔒 **Safety policies** — auto-approve rules, daily caps, hard stops for dangerous actions
- ⚡ **Proactive behavior** — checks email, calendar, mentions without being asked
- 🔄 **Agent reactions** — agents trigger each other (tweet posted → analyze engagement → draft followup)

## Quick Start

1. Install OpenClaw: `npm i -g openclaw` (or see [docs](https://docs.openclaw.ai))
2. Copy these files into your OpenClaw workspace (default: `~/clawd/`)
3. Fill in `USER.md` with your info
4. Fill in `IDENTITY.md` to name your AI
5. Start chatting — your AI will evolve from there

```bash
# Copy the starter kit
cp -r openclaw-starter-kit/* ~/clawd/
mkdir -p ~/clawd/memory

# Start OpenClaw
openclaw gateway start
```

## Want Someone to Set This Up For You?

**[OpenClaw Agency (OCA)](https://hypelab.digital/oca)** is a managed retainer where we install, configure, and run your agents for you. Custom playbooks, CI/CD integration, ongoing optimization. Plans start at $2k/mo.

→ [Learn more at hypelab.digital/oca](https://hypelab.digital/oca)


## What's Inside

### Core Files

| File | Purpose |
|------|---------|
| `AGENTS.md` | Operating manual — behavior, safety, when to speak vs stay quiet |
| `SOUL.md` | Personality — opinions, values, tone |
| `USER.md` | About you — preferences, work style, projects |
| `IDENTITY.md` | The AI's own identity — name, vibe, emoji |
| `MEMORY.md` | Long-term memory — curated by the AI over time |
| `HEARTBEAT.md` | Periodic checks — what to monitor proactively |
| `TOOLS.md` | Local tool notes — device names, SSH hosts, quirks |
| `SQUAD.md` | Multi-agent setup guide - how to run a team of AI agents |
| `TOKEN-OPTIMIZATION.md` | How to stretch your AI subscription 3-5x further |
| `MESH.md` | Multi-machine setup - delegate compute across machines |

### Multi-Agent Squad (`agents/`)

Pre-configured specialized agents:

```
agents/
├── content-agent/    — tweets, blogs, outreach (never posts without approval)
│   ├── SOUL.md
│   └── WORKING.md   — draft queue
├── dev-agent/        — code review, monitoring, bug triage
│   ├── SOUL.md
│   └── TICK.md       — activity log
└── research-agent/   — analytics, competitors, market intel
    ├── SOUL.md
    └── FINDINGS.md   — research reports
```

### Shared Brain (`shared/` + `intel/`)

Cross-agent knowledge and strategic context:

```
shared/                    — every agent reads at startup
├── product-context.md     — what you're building, priorities, positioning
├── voice-and-framing.md   — how to talk about your products
├── decisions.md           — key decisions + WHY (prevents contradictions)
└── user-signals.md        — what users are saying and doing

intel/                     — strategic radar, curated from conversations
├── competitors.md         — what competitors are doing
├── trends.md              — industry trends and implications
├── ideas-backlog.md       — feature ideas with supporting context
└── opportunities.md       — time-sensitive market opportunities
```

**How it works:** When you share an article or insight with your main agent, it files it in `intel/` and cross-references with existing knowledge. When discussing future features, the agent pulls relevant intel automatically. All agents read `shared/` so they never contradict each other on positioning or decisions.

### Operations (`ops/`)

Battle-tested governance:

- **`policies.json`** — auto-approve rules, daily caps, work hours, hard stops
- **`reaction-matrix.json`** — agents react to each other's events (emergent behavior!)

### Scripts (`scripts/`)

- **`worktree-agent.sh`** — spawn coding agents in isolated git worktrees (prevents agents from stepping on each other)
- **`check-agents.sh`** — deterministic task monitor that checks agent status without burning tokens
- **`quality-gate.sh`** — only notifies you when a PR is truly ready (CI passed + no conflicts)
- **`cleanup-worktrees.sh`** — daily cleanup of merged worktrees and stale tasks
- **`auto-backup.sh`** — hourly git backup of your workspace
- **`health-check.sh`** — monitors agent processes + disk usage, alerts via iMessage
- **`example-heartbeat-check.sh`** — template for efficient heartbeat checks (scripts are free, model time is expensive)
- **`watchdog.sh`** — self-healing process monitor that restarts crashed agents

## How Memory Works

```
Session 1: AI learns you prefer short updates
  → writes to memory/2026-02-23.md
  → updates MEMORY.md with the preference

Session 2: AI wakes up fresh, reads MEMORY.md
  → knows your preferences from day one
  → continues where it left off
```

**Daily files** (`memory/YYYY-MM-DD.md`) = raw logs of what happened
**Long-term** (`MEMORY.md`) = curated wisdom, reviewed and distilled periodically

The AI maintains its own memory during heartbeats — reviewing daily logs and updating MEMORY.md like a human reviewing their journal.

## Worktree Isolation (NEW)

The biggest risk when running parallel coding agents: they clobber each other's work. Agent A removes code that Agent B just wrote. We learned this the hard way.

**Solution: git worktrees.** Each agent gets its own isolated copy of the codebase on its own branch.

```bash
# Spawn an agent in an isolated worktree
./scripts/worktree-agent.sh ~/code/myapp feat/new-api "Build the REST API"

# Run multiple agents in parallel — no conflicts
./scripts/worktree-agent.sh ~/code/myapp feat/dashboard "Build admin dashboard"
./scripts/worktree-agent.sh ~/code/myapp fix/auth-bug "Fix the OAuth token refresh"
```

The `check-agents.sh` script monitors all running tasks every 5-10 minutes — zero tokens burned. It only outputs when something needs human attention (PR ready, CI failed, agent stale).

When branches are merged, `cleanup-worktrees.sh` removes the worktree directories automatically.

## Quality Gates (NEW)

Stop getting pinged every time an agent opens a PR. Instead, get notified when a PR is **actually ready**:

```bash
# Only outputs when all checks pass
./scripts/quality-gate.sh myorg/myrepo 42
# → READY: PR #42 — Add user dashboard (8 files changed)
```

Set this up in a cron to monitor all open PRs. Your agent only bothers you when something is genuinely ready to merge or needs your attention.

**Definition of done** (teach this to your agents):
- PR created and pushed
- Branch synced to main (no merge conflicts)
- CI passing (lint, types, tests)
- Build succeeds
- Screenshots included (if UI changes)

## How the Agent Squad Works

```
YOU → text your AI → COORDINATOR delegates → AGENTS work → results flow back
```

- **Content agent** drafts a tweet → queues in WORKING.md → coordinator reviews → you approve → posted
- **Dev agent** spots a failing CI → alerts coordinator → you get a text
- **Research agent** finds competitor launched a feature → reports in FINDINGS.md → content agent drafts a response

Agents react to each other via `reaction-matrix.json`:
- Tweet posted → research agent analyzes engagement (50% chance, after 1 hour)
- Bug detected → alert human immediately (100% chance, no delay)
- High engagement → content agent drafts followup (70% chance)

## Workspace Backup

Your workspace is your agent's brain. Back it up.

```bash
# Make your workspace a git repo (if it isn't already)
cd ~/clawd
git init
git remote add origin git@github.com:yourname/my-agent.git

# Run the backup script once to test
bash scripts/auto-backup.sh

# Set up hourly auto-backup via openclaw cron:
# name: "workspace-backup"
# schedule: "0 * * * *"
# payload: { kind: "agentTurn", message: "run bash ~/clawd/scripts/auto-backup.sh" }
```

Add a `.gitignore` for large/temp files:
```
node_modules/
*.log
.DS_Store
.next/
```

## Health Monitoring

If you're running agents 24/7, you need to know when they go down.

```bash
# Configure alerts (set your phone number)
export ALERT_PHONE="+15551234567"

# Optional: monitor a second machine
export REMOTE_HOST="agent2@100.x.x.x"
export REMOTE_NAME="forge"

# Test it
bash scripts/health-check.sh

# Set up as a cron (every 10 minutes):
# name: "health-check"
# schedule: { kind: "every", everyMs: 600000 }
# payload: { kind: "agentTurn", message: "run bash ~/clawd/scripts/health-check.sh" }
```

Status is written to `data/health.json` for dashboard use.

## Cron Pipeline Pattern (NEW)

Chain cron jobs to build automated pipelines. Each job runs at a set time, writes output to files, and downstream jobs pick it up:

```
7:00am  → news scan → writes to news-scans/industry-YYYY-MM-DD.md
9:00am  → content ideas (reads news scans) → pushes to drafts queue
10:00am → pitch evaluator (reads news scans) → pushes to pitch queue
```

Each step is an isolated agent turn. No mega-sessions. No token bloat. Each agent gets fresh context with just what it needs.

Example cron setup:
```json
{
  "name": "morning-news-scan",
  "schedule": { "kind": "cron", "expr": "0 7 * * 1-5", "tz": "America/New_York" },
  "payload": {
    "kind": "agentTurn",
    "message": "Scan industry news and save findings to news-scans/",
    "timeoutSeconds": 300
  },
  "sessionTarget": "isolated"
}
```

## Philosophy

> Scripts are free. Model time is expensive.

Heartbeat checks should be shell scripts that output NOTHING when there's nothing to do. The AI only wakes up when there's actual output to act on.

> Never auto-approve the dangerous stuff.

Tweets, emails, deploys, deletes — always require human approval. Research, analysis, health checks — auto-approve freely.

> Your AI is only as good as the context you give it.

Fill in USER.md. Name your AI. Tell it your preferences. The more it knows, the better it gets.

---

Built with [OpenClaw](https://openclaw.ai) • [Docs](https://docs.openclaw.ai) • [Community](https://discord.com/invite/clawd) • [More Skills](https://clawhub.com)
