# OpenClaw Starter Kit 🐾

A battle-tested workspace template for giving your AI agent personality, memory, autonomy, and a whole squad.

Compatible with **OpenClaw 2026.3.22+**.

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
| `MISTAKES.md` | Mistake log — tracks agent errors so they don't repeat |
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
├── research-agent/   — analytics, competitors, market intel
└── verify-agent/     — adversarial code reviewer (read-only, tries to break changes)
    └── AGENT.md      — verification specification
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

- **`auto-backup.sh`** — hourly git backup of your workspace. set it as a cron and never lose context again
- **`health-check.sh`** — monitors agent processes + disk usage, alerts via iMessage if something goes down. supports local + remote machines
- **`example-heartbeat-check.sh`** — template for efficient heartbeat checks (scripts are free, model time is expensive)
- **`watchdog.sh`** — self-healing process monitor that restarts crashed agents
- **`oca-provision.sh`** — OCA client provisioning (OpenClaw + starter kit install, used by HypeLab)

## How Memory Works

Memory uses an **index pattern**: MEMORY.md is a lightweight index (~30 lines) that points to typed topic files in `memory/`.

```
MEMORY.md              ← Index only (one-line pointers, max 200 lines)
memory/
├── user-profile.md    ← Who you are, preferences, expertise
├── feedback-rules.md  ← Corrections and confirmed approaches
├── project-active.md  ← Current work, goals, deadlines
├── reference-gotchas.md ← Technical gotchas that cause bugs
└── reference-infra.md ← Server configs, deploy setup
```

Each topic file uses frontmatter with a type (user, feedback, project, reference).

**Why this pattern?** A monolithic MEMORY.md grows until it eats your context window. The index stays small (always loaded) while topic files are read on-demand when relevant. Types help the AI decide what to save where.

**What NOT to store:** Code patterns (read the code), git history (use git log), debugging solutions (the fix is in the code), anything in CLAUDE.md. If the user asks you to save a PR list, ask what was surprising about it — that part is worth keeping.

### Memory Consolidation

Your agent gets smarter overnight. A nightly consolidation cron (2am) automatically:

1. Reviews conversations for unsaved decisions, preferences, and corrections
2. Stores them as typed memory files (not raw session dumps)
3. Cleans stale memories and updates the index
4. Cross-references MISTAKES.md to ensure every mistake has a prevention rule

See MEMORY.md for setup instructions.

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

## Philosophy

> Scripts are free. Model time is expensive.

Heartbeat checks should be shell scripts that output NOTHING when there's nothing to do. The AI only wakes up when there's actual output to act on.

> Never auto-approve the dangerous stuff.

Tweets, emails, deploys, deletes — always require human approval. Research, analysis, health checks — auto-approve freely.

> Your AI is only as good as the context you give it.

Fill in USER.md. Name your AI. Tell it your preferences. The more it knows, the better it gets.

---

Built with [OpenClaw](https://openclaw.ai) • [Docs](https://docs.openclaw.ai) • [Community](https://discord.com/invite/clawd) • [More Skills](https://clawhub.com)

## Verification Agent

The starter kit includes a verification agent (`agents/verify-agent/`) that acts as an adversarial code reviewer. After non-trivial implementations, spawn it to try to break your changes before reporting them done.

```bash
openclaw spawn verify-agent --task "Verify changes in ~/code/myapp. Files changed: src/api.ts, src/db.ts. Run builds, tests, linters. Try to break it."
```

The verifier is read-only (cannot modify your code) and produces a PASS/FAIL/PARTIAL verdict with actual command output as evidence. It fights the common LLM pattern of "reading code and saying it looks correct" instead of actually running it.

See `agents/verify-agent/AGENT.md` for the full specification.

## Code Style Rules

Add these rules to your project CLAUDE.md files to prevent the most common LLM coding mistakes:

**Minimal Changes** — Do not add features, refactor code, or make improvements beyond what was asked. Do not add docstrings or comments to code you did not change. Only add comments where the logic is not self-evident.

**No Speculative Code** — Do not add error handling for scenarios that cannot happen. Do not create helpers or abstractions for one-time operations. Three similar lines of code is better than a premature abstraction.

**Honest Reporting** — If tests fail, say so with the output. If you did not run a verification step, say that rather than implying it succeeded. Never claim "all tests pass" when output shows failures.

These rules target three LLM failure patterns: gold-plating (adding unrequested improvements), speculative engineering (building for hypothetical futures), and success theater (claiming things work without running them).
