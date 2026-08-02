# OpenClaw Starter Kit 🐾

A battle-tested workspace template for giving your AI agent personality, memory, autonomy, and a whole squad.

Compatible with **OpenClaw 2026.4.18+** (Claude Opus 4.7 supported).

Built by [@jeffweisbein](https://x.com/jeffweisbein) — shared on [This Week in Startups](https://thisweekinstartups.com).

## What's New (v2.5 — August 2, 2026)

- **Org layers** — `layers/<org>/` is the third place, for everything specific to one client or company: agent definitions, skills, scripts, per-repo playbooks, policy overrides. It exists so `managed/` can stay byte-identical to the kit, which is what keeps updates silent instead of hand-merged. `managed/scripts/kit-layer.sh` creates a layer and composes it over `managed/` at the workspace root. It refuses to write inside `managed/` and will not overwrite a `user/` file. See [`layers/README.md`](layers/README.md).
- **Drift checker** — `managed/scripts/kit-drift.sh` reports which `managed/` files no longer match the kit and why: clean, locally modified, behind the kit, conflict, new upstream, or added here. It answers the first question on every support call in about a second, and exits 1 on drift so it works as a cron check.
- **Two-way sync** — `managed/scripts/kit-sync.sh` pulls the latest `managed/` into an install. It shows the plan, asks before writing, keeps files you changed locally, backs up anything it replaces, and fingerprints `user/` and `layers/` before and after so it can prove it did not touch them. `managed/scripts/kit-promote.sh` sends a generic fix the other way, cutting the branch from the kit's upstream default branch.
- **The scrub check** — `kit-promote.sh` reads the outgoing files, the commit message and the branch name for client identifiers before it writes anything: org names and terms from your layers, API keys and tokens, emails, private IPs, phone numbers, home paths, and any domain not already in the kit. A hit stops the promotion and prints file, line and matched text. It refuses `user/` and `layers/` paths outright.
- **Sync guide** — [`managed/guides/SYNC.md`](managed/guides/SYNC.md) covers the routine, and why a private downstream copy is a plain clone rather than GitHub's Fork button.

### Upgrading from v2.4

1. `rsync` or copy the latest `managed/` into your workspace as usual. Safe, no `user/` file is touched.
2. From then on, use the tools instead. `managed/scripts/kit-drift.sh --workspace ~/clawd` shows what your install has accumulated, and `managed/scripts/kit-sync.sh --workspace ~/clawd` takes the update and records `<workspace>/.kit-baseline` for next time. On a v2.4 workspace that has never been synced there is no baseline yet, so both tools rebuild one from the kit's history at your installed version. Nothing to set up.
3. Optional, and only if you have edited `managed/` files or added your own: `managed/scripts/kit-layer.sh init <org-slug>`, then move those files into `layers/<org-slug>/` and run `managed/scripts/kit-layer.sh apply <org-slug>`.

Nothing here is required. Existing installs keep working untouched, `layers/` is empty until you create one, and files you have already modified in `managed/` are left alone by the sync.

## What's New (v2.4 — July 11, 2026)

- **Browser-driven smoke tests** — `managed/tools/web-verify` is the upgrade to the curl smoke template. It drives a real Chromium browser through a JSON **flow spec** against a live or preview URL, captures screenshots + console/page/network errors, and returns a **deterministic pass/fail** (exit 0/1). Catches render failures, broken auth redirects, dead buttons, and client-side JS exceptions that a 200 status hides. Includes public + authed example flows, secret-safe credential refs, and a `--base` flag to smoke-test preview deploys before merge.
- **Gotchas guide** — `managed/guides/GOTCHAS.md` documents the agent failure modes that cost real debugging sessions and how to avoid them: background work spawned from a turn getting reaped, remote/long builds dying mid-run, "it returned 200" ≠ "it works", verify-before-merge, and heartbeat spam.
- **Playbook + verify-agent wired to web-verify** — `AI_PLAYBOOK.md` and the verify agent now point at the browser smoke as the layer on top of the curl check.

### Upgrading from v2.3

1. `rsync` or copy the latest `managed/` into your workspace — safe, no `user/` file is touched.
2. `cd managed/tools/web-verify && npm install` (installs Playwright + Chromium).
3. Copy `flows/example-home.json` to a real flow for each app, set `baseUrl` + a couple of `expectText` assertions, and wire it into your ship-loop's smoke step.

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
│   ├── GOTCHAS.md          — Agent failure modes (turn-reaping, remote builds, verify) and fixes
│   ├── MEMORY.md           — Memory system shape: types, what not to store, consolidation
│   ├── MESH.md             — Multi-machine setup
│   ├── SQUAD.md            — Multi-agent team guide
│   ├── SYNC.md             — Drift, updates, promoting fixes back, private downstream repos
│   └── TOKEN-OPTIMIZATION.md — Stretch your subscription 3-5x
├── memory-templates/       — Typed memory scaffolds (user/feedback/project/reference)
├── ops/
│   ├── policies.json       — Safety policies & auto-approve rules
│   └── reaction-matrix.json — Agent reaction triggers
├── scripts/                — Health checks, backups, utilities
│   ├── kit-drift.sh        — What in managed/ no longer matches the kit, and why
│   ├── kit-sync.sh         — Pull the latest managed/ in, never touching user/ or layers/
│   ├── kit-promote.sh      — Send a generic fix back up, scrubbed for client identifiers
│   └── kit-layer.sh        — Create and compose an org layer
├── tools/
│   └── web-verify/         — Browser-driven smoke test (real Chromium, screenshots, pass/fail)
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

layers/                     ← Your org's own material (never overwritten)
└── <org>/                  — Config, agents, skills, scripts, playbooks, ops overrides
```

### The Three Folders

| Folder | Who owns it | Updated by | Purpose |
|--------|-------------|------------|---------|
| `managed/` | OpenClaw Starter Kit | Kit updates | Infrastructure, scripts, operating rules |
| `user/` | You | You (and your AI) | Personality, memory, custom rules |
| `layers/<org>/` | You | You | Everything specific to your company or client |

**Rule: starter kit updates only ever touch `managed/`.** Your `user/` and `layers/` files are sacred.

The counter-rule matters just as much: **keep `managed/` identical to the kit.** Identical files update silently. Edited ones have to be reconciled by hand on every release, and at three installs that is a permanent tax. If a change is generic, promote it upstream. If it is specific to one client, it belongs in a layer.

```bash
managed/scripts/kit-drift.sh --workspace ~/clawd     # what has drifted, and why
managed/scripts/kit-sync.sh  --workspace ~/clawd     # take the latest managed/
managed/scripts/kit-layer.sh init acme               # start a layer
```

See [`layers/README.md`](layers/README.md) for the layer contract and [`managed/guides/SYNC.md`](managed/guides/SYNC.md) for the update and promotion flow.

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
