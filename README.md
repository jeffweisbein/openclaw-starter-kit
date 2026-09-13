# OpenClaw Starter Kit 🐾

A battle-tested workspace template for giving your AI agent personality, memory, autonomy, and a whole squad.

Runtime features vary by OpenClaw version and harness. See the [compatibility and upgrade guide](managed/guides/COMPATIBILITY.md); syncing this kit does not install runtime fixes.

Built by [@jeffweisbein](https://x.com/jeffweisbein) — shared on [This Week in Startups](https://thisweekinstartups.com).

## What's New (v2.6 — September 13, 2026)

**An agent that remembers the task, reports once, shows its evidence and has a recovery plan.**

- **One private memory root:** consistent reader/writer/index guidance, read-only ambiguity checks and session-scoped checkpoints. No automatic user-data migration.
- **Single-owner delivery:** scheduler payload template, acknowledgment-based incident monitoring, recovery notifications and explicit disabled/unknown scheduler states.
- **Evidence-backed completion:** task/revision-bound, fresh, latest-result checks; honest separation of receipt validation from runtime-enforced authorization.
- **Backups that report failure:** opt-in file selection replaces blanket Git staging; push retries, success-only receipts, SQLite snapshots and disposable restoration checks.
- **Effective isolation checks:** inspect an existing Docker/Colima builder and test scratch access; keep Apple-container support and verify actual agent routing separately.
- **Upgrade and rollback guidance:** package/plugin provenance, post-restart model/harness checks, compaction recall, child-result delivery and proof refusal.
- **Corrected safety claims:** hooks are supplemental, harness-specific and currently fail open; they are not a containment boundary.

Start with [COMPATIBILITY.md](managed/guides/COMPATIBILITY.md), then
[RELIABILITY.md](managed/guides/RELIABILITY.md) and [BACKUPS.md](managed/guides/BACKUPS.md).
**Migration note:** the backup helper now requires a reviewed `ops/backup.json`;
prepare it before the next scheduled backup. No runtime restart or schedule changes are automatic.

### Previous release

## What's New (v2.5 — August 2, 2026)

- **Org layers** — `layers/<org>/` is the third place, for everything specific to one client or company: agent definitions, skills, scripts, per-repo playbooks, policy overrides. It exists so `managed/` can stay byte-identical to the kit, which is what keeps updates silent instead of hand-merged. `managed/scripts/kit-layer.sh` creates a layer and composes it over `managed/` at the workspace root. It refuses to write inside `managed/` and will not overwrite a `user/` file. See [`layers/README.md`](layers/README.md).
- **Drift checker** — `managed/scripts/kit-drift.sh` reports which `managed/` files no longer match the kit and why: clean, locally modified, behind the kit, conflict, new upstream, or added here. It answers the first question on every support call in about a second, and exits 1 on drift so it works as a cron check.
- **Two-way sync** — `managed/scripts/kit-sync.sh` pulls the latest `managed/` into an install. It shows the plan, asks before writing, keeps files you changed locally, backs up anything it replaces, and fingerprints `user/` and `layers/` before and after so it can prove it did not touch them. `managed/scripts/kit-promote.sh` sends a generic fix the other way, cutting the branch from the kit's upstream default branch.
- **The scrub check** — `kit-promote.sh` reads the outgoing files, the commit message and the branch name for client identifiers before it writes anything: org names and terms from your layers, API keys and tokens, emails, private IPs, phone numbers, home paths, and any domain not already in the kit. A hit stops the promotion and prints file, line and matched text. It refuses `user/` and `layers/` paths outright.
- **Sync guide** — [`managed/guides/SYNC.md`](managed/guides/SYNC.md) covers the routine, and why a private downstream copy is a plain clone rather than GitHub's Fork button.
- **Destructive-command guard** — `managed/scripts/guard-destructive.py` is a `PreToolUse` hook that denies deletion inside your protected trees and tells the agent to use `trash` instead, and denies schema-destroying SQL against anything not provably local. Permission rules are posture, and in an autonomous workspace posture gets relaxed. It can deny matching Claude Code Bash calls when installed, including under `bypassPermissions`; it is not a sandbox and does not cover other tool paths. Protected and ephemeral directory lists are configuration, not constants, because your layout is not somebody else's: start from `managed/ops/guard-destructive.example.json`.
- **External-content screener** — `managed/scripts/screen-external.py` screens fetched pages, search results and scraped text for prompt injection before the model acts on it, as a `PostToolUse` hook. No LLM call, no network, no dependency, so it is cheap enough to run on every fetch. Scoring is combination-based rather than keyword-based: a lone action verb is nothing, and the score only climbs when an action co-occurs with something addressing or overriding the agent. That is what keeps it off press releases and READMEs, which is what keeps it switched on.
- **Hooks guide** — [`managed/guides/HOOKS.md`](managed/guides/HOOKS.md) wires both of them, and is specific about which settings scope to use and why a project-scoped hook is invisible to your scheduled jobs. Both hooks fail open on a crash and log it at their own level, so "has this been dead for months" is one `grep` away.
- **Outcome tracking** — a scheduler tells you a job ran. It does not tell you the work happened, and a green board is where an expensive failure goes to hide for a month. `managed/scripts/outcome-reaper.py` checks that each job is still producing its artifact, from outside the job, and prints only what is stale. The rule that makes it work is that a no-op must still write a receipt, since otherwise "nothing to report" and "I am broken" are the same silence. Manifest starts at `managed/ops/job-outcomes.example.json`; wiring is already in `managed/HEARTBEAT.md`.
- **Per-agent sandboxes** — `managed/scripts/agent-sandbox.sh` gives each agent a durable computer instead of a shared filesystem: an isolated VM with a persistent home volume, its own network, and tools that are still installed next turn. Set `SANDBOX_HOST` and the same script runs it all on a second machine over SSH. Needs Apple `container` on macOS 26. See [`managed/guides/SANDBOXES.md`](managed/guides/SANDBOXES.md).
- **Session handoff on context reset** — a session that hits its token ceiling gets archived, and the next one greets your user fresh and re-asks what they were working on. v2.5 used a single handoff file; v2.6 supersedes it with identity-checked, session-scoped checkpoints in `managed/memory-templates/session-handoff.md`.
- **Six more gotchas** — [`managed/guides/GOTCHAS.md`](managed/guides/GOTCHAS.md) grows the green-scheduler trap, cron model pins that are not in the models allowlist (and why a working probe does not prove one), a context meter that reads 100% while nothing is compacting, context resets that look like amnesia, treating fetched content as instructions, and deletion that nothing can undo.

### Upgrading from v2.4

1. Use the reviewed sync plan in [COMPATIBILITY.md](managed/guides/COMPATIBILITY.md); do not overwrite customized managed files with a blanket copy.
2. From then on, use the tools instead. `managed/scripts/kit-drift.sh --workspace ~/clawd` shows what your install has accumulated, and `managed/scripts/kit-sync.sh --workspace ~/clawd` takes the update and records `<workspace>/.kit-baseline` for next time. On a v2.4 workspace that has never been synced there is no baseline yet, so both tools rebuild one from the kit's history at your installed version. Nothing to set up.
3. Optional, and only if you have edited `managed/` files or added your own: `managed/scripts/kit-layer.sh init <org-slug>`, then move those files into `layers/<org-slug>/` and run `managed/scripts/kit-layer.sh apply <org-slug>`.
4. Install the hooks. Copy the two example configs and edit them to match your layout, then merge the `hooks` block from [`managed/guides/HOOKS.md`](managed/guides/HOOKS.md) into `~/.claude/settings.json` and restart your sessions. Hooks are read at startup, so an edit does nothing to a session that is already running.
   ```bash
   mkdir -p ~/clawd/ops
   cp managed/ops/guard-destructive.example.json ~/clawd/ops/guard-destructive.json
   cp managed/ops/job-outcomes.example.json      ~/clawd/ops/job-outcomes.json
   python3 managed/scripts/tests/test_guard_destructive.py
   python3 managed/scripts/tests/test_screen_external.py
   ```
   Both test suites build their own throwaway workspace in a temp directory, so they are safe to run against a live install. Set `OPENCLAW_WORKSPACE` if your workspace is not `~/clawd`.
5. Fill in `ops/job-outcomes.json` with your own jobs, then add `python3 <workspace>/managed/scripts/outcome-reaper.py` to your heartbeat checks. With no manifest it exits silently, so wiring it before you have written one is fine.

Nothing here is required. Existing installs keep working untouched, `layers/` is empty until you create one, files you have already modified in `managed/` are left alone by the sync, and the hooks do nothing until you put them in `settings.json` yourself.

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
- **Memory docs pulled out of hot context** — The private main-session `user/MEMORY.md` index stays lean, so the ~55 lines of how-it-works prose now lives in `managed/guides/MEMORY.md` instead. Fresh installs get a lean 20-line index; existing installs are untouched.
- **README tree synced** — listing now matches what's actually on disk (`compute-agent/` rename, `verify-agent/`, `memory-templates/`).

### Upgrading from v2.2

If you already have the starter kit installed:
1. `rsync` or copy the latest `managed/` into your workspace — safe, no `user/` file is touched.
2. Existing `user/MEMORY.md` stays as-is. If you want the slim index, diff against this repo's `user/MEMORY.md` and trim manually.
3. In each of your product repos, copy `managed/templates/AI_PLAYBOOK-template.md` to `AI_PLAYBOOK.md` and `managed/templates/smoke-web.sh.template` to `scripts/smoke-web.sh`, then fill them in.
4. Historical authentication guidance is superseded by the current Authentication section and installed runtime onboarding.

### Previously (v2.2 — April 2, 2026)

- **`managed/` + `user/` split** — files you customize (`user/`) are now cleanly separated from infrastructure files we maintain (`managed/`). Updates to the starter kit only touch `managed/` — your personality, memory, and custom rules are never overwritten.
- **AGENTS.md split** — operating rules live in `managed/AGENTS-base.md` (updatable). Your custom rules live in `user/AGENTS.md` (yours forever).
- **Improved operating rules** — better group chat etiquette, platform formatting, memory pruning guidance, one-reaction-max rule.
- **Mistake tracking** — `user/MISTAKES.md` pattern: log what happened, why, what you fixed, and a rule to prevent it.
- **Leaner core files** — continued trimming from v2.1. faster session startup, more context window for actual work.

## What is this?

This is the exact workspace structure that powers a personal AI assistant with:

- 🧠 **Persistent memory** across sessions — typed, file-based memory with a lean index restricted to the private main session ([how it works](managed/guides/MEMORY.md))
- 🎭 **Real personality** — opinions, tone, boundaries (not a corporate chatbot)
- 👥 **Multi-agent squad** — content writer, dev ops, researcher that coordinate autonomously
- 🔒 **Safety policies** — auto-approve rules, daily caps, hard stops for dangerous actions
- 🛑 **Supplemental command guards** — hooks that deny covered destructive commands when loaded by the configured harness ([how to wire them](managed/guides/HOOKS.md))
- ⚡ **Proactive behavior** — checks email, calendar, mentions without being asked
- 🔄 **Agent reactions** — agents trigger each other (tweet posted → analyze engagement → draft followup)

## Quick Start

1. Install OpenClaw using its [current documentation](https://docs.openclaw.ai).
2. Follow [fresh installation and compatibility](managed/guides/COMPATIBILITY.md).
   Copy the kit only into a **new** workspace; use `kit-sync.sh` for an existing one.
3. Fill in `user/USER.md` and `user/IDENTITY.md` with your own preferences and identity.
4. Select the canonical private memory root and run `memory-check`.
5. Configure one scheduled job, its single delivery owner, and reviewed backup inputs.
6. Run the fixture tests, then verify actual delivery, recovery and any worker isolation.

The files are templates; copying them does not activate hooks, schedules or sandboxing.
The kit does not overwrite your live OpenClaw configuration or restart your gateway.

## Authentication and model choice

Use `openclaw onboard --help` and the current runtime's onboarding interface to discover
supported authentication paths. Availability, provider terms and subscription coverage
can change. Confirm the **actual running provider/harness**, not just the selected model.
Subscription capacity and separately metered API usage are different budgets.

Enter credentials only through the provider's sign-in flow or the host's masked secret
entry. Never put API keys into chat, shell history, example commands or committed files.
No private credentials are shipped with this kit. A cheaper/local model should replace
another model only after task-specific quality checks, not merely because it is cheaper.

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
│   ├── RELIABILITY.md       — Delivery, evidence, monitoring and runtime acceptance
│   ├── BACKUPS.md           — Selected-file backup and disposable SQLite restore
│   ├── COMPATIBILITY.md     — Requirements, onboarding and safe v2.6 upgrade
│   ├── AI_PLAYBOOK.md      — Shipping per-repo AI playbooks and smoke scripts
│   ├── GOTCHAS.md          — Agent failure modes (turn-reaping, green schedulers, verify) and fixes
│   ├── HOOKS.md            — Wiring the safety hooks, and which settings scope they belong in
│   ├── MEMORY.md           — Memory system shape: types, what not to store, consolidation
│   ├── MESH.md             — Multi-machine setup
│   ├── SANDBOXES.md        — A durable isolated VM per agent, local or on a second machine
│   ├── SQUAD.md            — Multi-agent team guide
│   ├── SYNC.md             — Drift, updates, promoting fixes back, private downstream repos
│   └── TOKEN-OPTIMIZATION.md — Task-specific usage and cost guidance
├── memory-templates/       — Typed memory scaffolds (user/feedback/project/reference/handoff)
├── ops/
│   ├── policies.json       — Safety policies & auto-approve rules
│   ├── reaction-matrix.json — Agent reaction triggers
│   ├── guard-destructive.example.json — Protected/ephemeral trees for the guard hook
│   └── job-outcomes.example.json — Job → artifact → freshness budget manifest
├── scripts/                — Health checks, backups, utilities
│   ├── reliability.py       — Memory audit, evidence, monitor/ack and SQLite checks
│   ├── backup-workspace.py  — Explicit-file Git backup and success receipts
│   ├── check-isolation.py   — Existing Docker/Colima policy and task-write check
│   ├── guard-destructive.py — PreToolUse hook: supplemental command-string guard
│   ├── screen-external.py  — PostToolUse hook: prompt-injection screen on fetched content
│   ├── outcome-reaper.py   — Which jobs stopped producing their artifact, scheduler be damned
│   ├── agent-sandbox.sh    — Durable per-agent sandboxes (Apple container), local or remote
│   ├── kit-drift.sh        — What in managed/ no longer matches the kit, and why
│   ├── kit-sync.sh         — Pull the latest managed/ in, never touching user/ or layers/
│   ├── kit-promote.sh      — Send a generic fix back up, scrubbed for client identifiers
│   ├── kit-layer.sh        — Create and compose an org layer
│   ├── lib/                — Shared script internals (the screener's signal engine)
│   └── tests/              — Test suites for the hooks; each builds its own temp workspace
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

## Safety Hooks

Two supplemental Claude Code hooks for the tool paths on which they are installed:

- **`guard-destructive.py`** — denies deletion inside your protected trees and destructive SQL against anything not provably local
- **`screen-external.py`** — screens fetched pages, search results and scraped text for prompt injection

Both fail open on a crash and log it loudly. See `managed/guides/HOOKS.md` for the settings block, which scope to put it in, and how to check it is actually running.

## Token Optimization

See `managed/guides/TOKEN-OPTIMIZATION.md` for historical tuning ideas. Measure quality and metered usage on your current plan; no fixed savings multiplier is guaranteed. Do not silently substitute a cheaper model without task-specific evaluation.

## Multi-Machine Setup

See `managed/guides/MESH.md` for delegating compute across machines (e.g., a Mac Mini for heavy coding). For isolation between agents on that machine, `managed/guides/SANDBOXES.md` gives each one a durable VM of its own.

## Contributing

PRs welcome. If you've battle-tested a pattern that makes agents better, share it.

## License

MIT — use it, fork it, make it yours.
