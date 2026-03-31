# MEMORY.md - Index

*This is an index file. Each entry points to a topic file in the memory/ directory.*
*Do not write content directly here. Write to topic files and add a one-line pointer.*

*Last updated: (auto-updated by your AI)*

## How This Works

MEMORY.md is loaded into every conversation. Keep it under 200 lines. Each entry should be one line, under ~150 characters, linking to a topic file with the actual content.

Topic files use frontmatter with a type taxonomy:

```markdown
---
name: Short title
description: One-line description used for relevance matching
type: user | feedback | project | reference
---

Content here.
```

### Memory Types

| Type | What to store | Examples |
|---|---|---|
| `user` | Who the user is, their role, preferences, expertise | "senior Go dev, new to React", "prefers terse responses" |
| `feedback` | Corrections and confirmed approaches from the user | "don't mock the database in tests", "single bundled PR was the right call" |
| `project` | Ongoing work, goals, decisions not derivable from code | "merge freeze after Thursday for mobile release" |
| `reference` | Pointers to external resources and systems | "pipeline bugs tracked in Linear project INGEST" |

### What NOT to Store

- Code patterns, architecture, file paths (derivable by reading the project)
- Git history, recent changes (use `git log` / `git blame`)
- Debugging solutions (the fix is in the code, context in the commit message)
- Anything already in CLAUDE.md files
- Ephemeral task details or current conversation context

These exclusions apply even when the user asks. If they ask you to save a PR list, ask what was surprising or non-obvious about it - that part is worth keeping.

### Before Recommending from Memory

A memory that names a file, function, or flag is a claim about what existed when the memory was written. Before recommending it:
- If it names a file path: check the file exists
- If it names a function or flag: grep for it
- If the user is about to act on it: verify first

"The memory says X exists" is not the same as "X exists now."

## Index

### User
- [Your Name](memory/user-profile.md) - role, preferences, work style

### Feedback
- [Standing Rules](memory/feedback-rules.md) - corrections and confirmed approaches

### Project
- [Active Work](memory/project-active.md) - current tasks and status

### Reference
- [Technical Gotchas](memory/reference-gotchas.md) - things that cause bugs if forgotten
- [Infrastructure](memory/reference-infra.md) - server configs, deploy setup

## Nightly Consolidation

A nightly job reviews conversations and extracts unsaved decisions, preferences, and corrections into typed memory files. Set it up:

```bash
openclaw cron add "nightly-consolidation" \
  --schedule "0 2 * * *" \
  --prompt "Review today's conversations. Extract unsaved decisions, preferences, or corrections into typed memory files (user/feedback/project/reference). Update the MEMORY.md index. Clean stale memories. Check MISTAKES.md for entries missing standing rules. Write summary to memory/consolidation-$(date +%Y-%m-%d).md."
```
