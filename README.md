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

- **`example-heartbeat-check.sh`** — template for efficient heartbeat checks (scripts are free, model time is expensive)

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

## Philosophy

> Scripts are free. Model time is expensive.

Heartbeat checks should be shell scripts that output NOTHING when there's nothing to do. The AI only wakes up when there's actual output to act on.

> Never auto-approve the dangerous stuff.

Tweets, emails, deploys, deletes — always require human approval. Research, analysis, health checks — auto-approve freely.

> Your AI is only as good as the context you give it.

Fill in USER.md. Name your AI. Tell it your preferences. The more it knows, the better it gets.

## Want Someone to Set This Up For You?

If you'd rather have experts handle the install, configuration, and ongoing management — check out **[OpenClaw Agency](https://hypelab.digital/oca)**.

OCA is a managed retainer where we set up and run OpenClaw agents for your engineering team. Dedicated agents for your codebase, custom playbooks, CI/CD integration, monitoring, and weekly optimization. Plans start at $2k/mo.

**[Learn more →](https://hypelab.digital/oca)**

---

Built with [OpenClaw](https://openclaw.ai) • [Docs](https://docs.openclaw.ai) • [Community](https://discord.com/invite/clawd) • [More Skills](https://clawhub.com)
