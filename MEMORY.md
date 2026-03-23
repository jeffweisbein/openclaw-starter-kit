# MEMORY.md - Long-Term Memory

*Last updated: (auto-updated by your AI)*

<!-- 
This is your AI's curated long-term memory.
It will fill this in over time as it learns about you, your projects, and your preferences.
Think of it as the AI's journal - distilled wisdom, not raw logs.
-->

## Memory Categories & Token Impact

**critical:** the `instruction` category auto-injects into EVERY message. keep it minimal.

| category | auto-injected? | use for |
|---|---|---|
| `instruction` | **yes, every message** | universal rules only (style, tone, core behavior) |
| `context` | no, searched on-demand | project patterns, api syntax, guardrails |
| `fact` | no, searched on-demand | personal info, dates, preferences |
| `decision` | no, searched on-demand | architectural choices, why things were built a certain way |
| `entity` | no, searched on-demand | people, services, accounts |
| `relationship` | no, searched on-demand | connections between people/things |

**target:** 4-5 instruction memories max (~200 tokens total). everything else as context/fact/decision.

## Sections (filled in by your AI over time)

### About You
<!-- preferences, work style, communication preferences -->

### Projects
<!-- architectures, key decisions, gotchas -->

### Bugs Fixed
<!-- important bugs so they don't repeat -->

### Rules & Lessons
<!-- things learned the hard way -->

## Nightly Memory Consolidation

Your agent's memory improves overnight. A nightly consolidation job runs at 2am and does four things:

1. **Extract unsaved context** — reviews the day's conversations for decisions, preferences, corrections, and facts that weren't saved to memory during the session
2. **Clean stale memories** — removes or updates memories that are no longer accurate (old project states, resolved bugs, outdated preferences)
3. **Review MISTAKES.md** — checks the mistake log and ensures each entry has a corresponding standing rule in memory
4. **Write a summary** — saves a consolidation report to `memory/consolidation-YYYY-MM-DD.md`

### Setting up consolidation

```bash
# Add the nightly consolidation cron (runs at 2am daily)
openclaw cron add "nightly-consolidation" \
  --schedule "0 2 * * *" \
  --prompt "Review today's conversations. Extract any unsaved decisions, preferences, or corrections into memory. Clean up stale memories. Check MISTAKES.md for entries missing standing rules. Write a summary to memory/consolidation-$(date +%Y-%m-%d).md."

# Optional: weekly deep cleanup (Sundays at 3am)
openclaw cron add "weekly-memory-cleanup" \
  --schedule "0 3 * * 0" \
  --prompt "Deep review of all memories. Deduplicate, merge related entries, archive anything older than 90 days that hasn't been accessed. Update MEMORY.md sections."
```

The consolidation job makes your agent smarter over time without you doing anything. Decisions you make in conversation on Monday are searchable context by Tuesday morning.

## MISTAKES.md — Learning from Errors

Your agent maintains `MISTAKES.md` at the workspace root. When something goes wrong — a bad command, a missed preference, a wrong assumption — the agent logs it with a root cause and a standing rule.

The nightly consolidation job cross-references MISTAKES.md entries with stored memories to make sure every mistake has a prevention rule. This closes the loop: mistake happens → gets logged → consolidation creates a rule → agent never repeats it.
