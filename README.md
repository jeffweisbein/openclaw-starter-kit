# OpenClaw Starter Kit 🐾

A battle-tested workspace template for giving your AI agent personality, memory, autonomy, and a whole squad.

Compatible with **OpenClaw 2026.4.18+** (Claude Opus 4.7 supported).

Built by [@jeffweisbein](https://x.com/jeffweisbein) — shared on [This Week in Startups](https://thisweekinstartups.com).

## What's New (v2.3 — April 22, 2026)

- **Claude subscription path restored** — `openclaw onboard --auth-choice anthropic-cli` is the recommended path again, routing Anthropic model calls through the Claude Code CLI so your Max/Pro subscription keeps covering usage. Compatible with OpenClaw 2026.4.18+ and Claude Opus 4.7.
- **Per-repo AI playbooks** — `managed/templates/AI_PLAYBOOK-template.md` gives your agent ground truth about each repo's shape, risk areas, gotchas, and verification steps. Cuts down on "agent touched the wrong thing" incidents.
- **Public smoke script template** — `managed/templates/smoke-web.sh.template` pairs with the playbook: parameterized (`BASE_URL` + `PAGES`) check that hits your top pages, fails loud on non-200s or runtime-error bodies, and optionally verifies the Vercel production alias.
- **Memory docs pulled out of hot context** — `user/MEMORY.md` is loaded into every conversation, so the ~55 lines of how-it-works prose now lives in `managed/guides/MEMORY.md` instead. Fresh installs get a lean 20-line index; existing installs are untouched.
- **README tree synced** — listing now matches what's actually on disk (`compute-agent/` rename, `verify-agent/`, `memory-templates/`).

### Upgrading from v2.2

If you already have the starter kit installed:
1. `rsync` or copy the latest `managed/` into your workspace — safe, no `user/` file is touched.
2. Existing `user/MEMORY.md` stays as-is. If you want the slim index, diff against this repo's `user/MEMORY.md` and trim manually.
3. In each of your product repos, copy `managed/templates/AI_PLAYBOOK-template.md` to `AI_PLAYBOOK.md` and `managed/templates/smoke-web.sh.template` to `scripts/smoke-web.sh`, then fill them in.
4. Re-run onboard if your auth currently points at `openai-codex` or `apiKey` and you'd prefer subscription routing: `openclaw onboard --auth-choice anthropic-cli`.

### Previously (v2.2 — April 2, 2026)

- **`managed/` + `user/` split** — files you customize (`user/`) are now cleanly separated from infrastructure files we maintain (`managed/`). Updates to the starter kit only touch `managed/` — your personality, memory, and custom rules are never overwritten.
- **AGENTS.md split** — operating rules live in `managed/AGENTS-base.md` (updatable). Your custom rules live in `user/AGENTS.md` (yours forever).
- **Improved operating rules** — better group chat etiquette, platform formatting, memory pruning guidance, one-reaction-max rule.
- **Mistake tracking** — `user/MISTAKES.md` pattern: log what happened, why, what you fixed, and a rule to prevent it.
- **Leaner core files** — continued trimming from v2.1. faster session startup, more context window for actual work.

## What is this?

This is the exact workspace structure that powers a personal AI assistant with:

- 🧠 **Persistent memory** across sessions — typed, file-based memory with a lean index loaded every conversation ([how it works](managed/guides/MEMORY.md))
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

Earlier this month the direct Claude Max/Pro path into OpenClaw broke. On the current release it works again when routed through the **Claude Code CLI**, which is the path OpenClaw now uses by default. Three options, in recommended order:

**Recommended: Claude subscription via Claude Code CLI**
```bash
openclaw onboard --auth-choice anthropic-cli
```
Uses your existing Claude Max/Pro subscription. OpenClaw routes Anthropic model calls through the Claude Code CLI, keeping your subscription-included usage intact. Supports Claude Opus 4.7 and the rest of the Claude 4 family.

**Alternative: OpenAI Codex OAuth**
```bash
openclaw onboard --auth-choice openai-codex
```
Uses your ChatGPT Plus/Pro subscription. Good if you prefer ChatGPT, or want to avoid the Claude Code CLI dependency.

**Alternative: Anthropic API key (pay-as-you-go)**
```bash
export ANTHROPIC_API_KEY="sk-ant-..."
openclaw onboard
```
Direct API billing. Good if you already use the Claude API for other work.

See `openclaw onboard --help` for the full list of supported auth paths (OpenRouter, local LM Studio / Ollama, DeepSeek, Kimi, Gemini, etc.).

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
│   ├── compute-agent/      — Remote second-machine pattern (heavy compute)
│   └── verify-agent/       — Quality-gate / verification agent
├── guides/
│   ├── AI_PLAYBOOK.md      — Shipping per-repo AI playbooks and smoke scripts
│   ├── MEMORY.md           — Memory system shape: types, what not to store, consolidation
│   ├── MESH.md             — Multi-machine setup
│   ├── SQUAD.md            — Multi-agent team guide
│   └── TOKEN-OPTIMIZATION.md — Stretch your subscription 3-5x
├── memory-templates/       — Typed memory scaffolds (user/feedback/project/reference)
├── ops/
│   ├── policies.json       — Safety policies & auto-approve rules
│   └── reaction-matrix.json — Agent reaction triggers
├── scripts/                — Health checks, backups, utilities
└── templates/
    ├── AI_PLAYBOOK-template.md — Per-repo playbook starter
    └── smoke-web.sh.template   — Public smoke script starter

user/                       ← You own these (never overwritten)
├── AGENTS.md               — Your custom rules & conventions
├── SOUL.md                 — Your agent's personality
├── USER.md                 — About you
├── IDENTITY.md             — Your agent's name & vibe
├── MEMORY.md               — Long-term memory index (see managed/guides/MEMORY.md)
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
