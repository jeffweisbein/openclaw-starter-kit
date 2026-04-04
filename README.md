# OpenClaw Starter Kit 🐾

A battle-tested workspace template for giving your AI agent personality, memory, autonomy, and a whole squad.

Compatible with **OpenClaw 2026.4.2+**.

Built by [@jeffweisbein](https://x.com/jeffweisbein) — shared on [This Week in Startups](https://thisweekinstartups.com).

## What's New (v2.2 — April 2, 2026)

- **`managed/` + `user/` split** — files you customize (`user/`) are now cleanly separated from infrastructure files we maintain (`managed/`). Updates to the starter kit only touch `managed/` — your personality, memory, and custom rules are never overwritten.
- **AGENTS.md split** — operating rules live in `managed/AGENTS-base.md` (updatable). Your custom rules live in `user/AGENTS.md` (yours forever).
- **Improved operating rules** — better group chat etiquette, platform formatting, memory pruning guidance, one-reaction-max rule.
- **Mistake tracking** — `user/MISTAKES.md` pattern: log what happened, why, what you fixed, and a rule to prevent it.
- **Leaner core files** — continued trimming from v2.1. faster session startup, more context window for actual work.

### Upgrading from v2.1

If you already have the starter kit installed:
1. Copy `managed/` into your workspace (safe — these are all infrastructure files)
2. Your existing `SOUL.md`, `USER.md`, `IDENTITY.md`, `MEMORY.md`, and agent files are untouched
3. Optionally move your old `AGENTS.md` to `user/AGENTS.md` and let `managed/AGENTS-base.md` handle the base rules

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
3. Fill in `user/USER.md` with your info
4. Fill in `user/IDENTITY.md` to name your AI
5. Start chatting — your AI will evolve from there

```bash
# Copy the starter kit
cp -r openclaw-starter-kit/* ~/clawd/
mkdir -p ~/clawd/memory

# Start OpenClaw
openclaw gateway start
```

## Authentication

As of April 4, 2026, Anthropic no longer covers OpenClaw usage under Claude Max/Pro subscriptions. You have three paths forward:

**Recommended: OpenAI-Codex OAuth**
```bash
openclaw onboard --auth-choice openai-codex
```
Uses your ChatGPT Plus/Pro subscription. Works with all OpenClaw features.

**Alternative: Anthropic API Key**
Set your environment variable:
```bash
export ANTHROPIC_API_KEY="sk-ant-..."
```
Pay-as-you-go billing. Good if you use Claude API already.

**Legacy: Claude Subscription**
Still works via separate usage bundles at claude.ai (not covered by your subscription).

For details, see the [Anthropic announcement](https://www.threads.com/@boris_cherny/post/DWsAWeND5nm/).

## Want Someone to Set This Up For You?

**[OpenClaw Agency (OCA)](https://hypelab.digital/oca)** is a managed retainer where we install, configure, and run your agents for you. Custom playbooks, CI/CD integration, ongoing optimization. Plans start at $2k/mo.

→ [Learn more at hypelab.digital/oca](https://hypelab.digital/oca)

## What's Inside

### Structure

```
managed/                    ← We maintain these (safe to update)
├── AGENTS-base.md          — Operating rules, safety, group chat etiquette
├── HEARTBEAT.md            — Periodic check template
├── TOOLS.md                — Tool notes cheat sheet
├── VERSION                 — Current starter kit version
├── agents-base/            — Agent infrastructure templates
│   └── forge/              — Remote coding workhorse setup
├── guides/
│   ├── MESH.md             — Multi-machine setup
│   ├── SQUAD.md            — Multi-agent team guide
│   └── TOKEN-OPTIMIZATION.md — Stretch your subscription 3-5x
├── ops/
│   ├── policies.json       — Safety policies & auto-approve rules
│   └── reaction-matrix.json — Agent reaction triggers
└── scripts/                — Health checks, backups, utilities

user/                       ← You own these (never overwritten)
├── AGENTS.md               — Your custom rules & conventions
├── SOUL.md                 — Your agent's personality
├── USER.md                 — About you
├── IDENTITY.md             — Your agent's name & vibe
├── MEMORY.md               — Long-term curated memory
├── MISTAKES.md             — Learned lessons & prevention rules
├── agents/                 — Your agent squad (customizable)
│   ├── content-agent/
│   ├── dev-agent/
│   └── research-agent/
├── intel/                  — Competitive intel, ideas, opportunities
└── shared/                 — Cross-agent context
```

### The Two Folders

| Folder | Who owns it | Updated by | Purpose |
|--------|-------------|------------|---------|
| `managed/` | OpenClaw Starter Kit | Kit updates | Infrastructure, scripts, operating rules |
| `user/` | You | You (and your AI) | Personality, memory, custom rules |

**Rule: starter kit updates only ever touch `managed/`.** Your `user/` files are sacred.

## Multi-Agent Squad

Pre-configured specialized agents in `user/agents/`:

- **content-agent** — tweets, blogs, outreach (never posts without approval)
- **dev-agent** — code review, monitoring, bug triage
- **research-agent** — analytics, competitors, market intel

See `managed/guides/SQUAD.md` for setup instructions.

## Token Optimization

See `managed/guides/TOKEN-OPTIMIZATION.md` for how to stretch a $200/month Claude Max subscription 3-5x further.

## Multi-Machine Setup

See `managed/guides/MESH.md` for delegating compute across machines (e.g., a Mac Mini "forge" for heavy coding).

## Contributing

PRs welcome. If you've battle-tested a pattern that makes agents better, share it.

## License

MIT — use it, fork it, make it yours.
