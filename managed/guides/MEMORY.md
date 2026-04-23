# The Memory System

Your agent's persistent, file-based memory lives in `user/MEMORY.md` plus a folder of typed topic files. `MEMORY.md` is loaded into every conversation — this guide explains the shape so the index file itself stays lean.

## Shape

- `user/MEMORY.md` — index only. One line per entry pointing to a topic file. Keep it under 200 lines; loaded on every conversation.
- `user/memory/<topic>.md` — individual typed memory files. Each has frontmatter declaring its type.
- `managed/memory-templates/*.md` — starter scaffolds for each memory type. Copy into `user/memory/` when you're ready to start a topic.

## File format

```markdown
---
name: Short title
description: One-line description used for relevance matching
type: user | feedback | project | reference
---

Content here.
```

## Memory types

| Type | What to store | Examples |
|---|---|---|
| `user` | Who the user is, their role, preferences, expertise | "senior Go dev, new to React", "prefers terse responses" |
| `feedback` | Corrections and confirmed approaches from the user | "don't mock the database in tests", "single bundled PR was the right call" |
| `project` | Ongoing work, goals, decisions not derivable from code | "merge freeze after Thursday for mobile release" |
| `reference` | Pointers to external resources and systems | "pipeline bugs tracked in Linear project INGEST" |

For `feedback` and `project` entries, structure the body as: the rule / fact first, then `**Why:**` (reason from the user, often a past incident) and `**How to apply:**` (when it kicks in). Knowing *why* lets the agent judge edge cases instead of blindly following the rule.

## What NOT to store

- Code patterns, architecture, file paths (derivable by reading the project)
- Git history, recent changes (use `git log` / `git blame`)
- Debugging solutions (the fix is in the code, context is in the commit message)
- Anything already in `CLAUDE.md` / `AGENTS.md` files
- Ephemeral task details or current conversation context

These exclusions apply even when the user explicitly asks. If they ask you to save a PR list or activity summary, ask what was *surprising* or *non-obvious* about it — that's the part worth keeping.

## Before recommending from memory

A memory that names a file, function, or flag is a claim about what existed *when the memory was written*. Before recommending it:

- If it names a file path: check the file exists.
- If it names a function or flag: grep for it.
- If the user is about to act on it (not just asking about history): verify first.

"The memory says X exists" is not the same as "X exists now." If current reality conflicts with a recalled memory, trust what you observe now and update or remove the stale memory.

## Nightly consolidation

A nightly job reviews conversations and extracts unsaved decisions, preferences, and corrections into typed memory files. Set it up with:

```bash
openclaw cron add "nightly-consolidation" \
  --schedule "0 2 * * *" \
  --prompt "Review today's conversations. Extract unsaved decisions, preferences, or corrections into typed memory files (user/feedback/project/reference). Update the MEMORY.md index. Clean stale memories. Check MISTAKES.md for entries missing standing rules. Write summary to memory/consolidation-$(date +%Y-%m-%d).md."
```

## Seeding from templates

Copy from `managed/memory-templates/` into `user/memory/` when you want to start a topic:

```bash
cp managed/memory-templates/user-profile.md user/memory/user-profile.md
cp managed/memory-templates/feedback-rules.md user/memory/feedback-rules.md
```

Then add a one-line pointer to the new file from `user/MEMORY.md`.
