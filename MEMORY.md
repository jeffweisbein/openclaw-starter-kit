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
