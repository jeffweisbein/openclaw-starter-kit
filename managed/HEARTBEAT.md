# HEARTBEAT.md

<!--
Your AI reads this on every heartbeat poll.
Keep it SMALL — scripts are free, model time is expensive.
Only wake the model when scripts produce output.
-->

## Checks

```bash
python3 /path/to/workspace/managed/scripts/outcome-reaper.py
```

<!-- Add your own check scripts here. Only act on output. -->
<!-- Example:
```bash
/path/to/check-email.sh
/path/to/check-calendar.sh
/path/to/check-mentions.sh
```
-->

## If outcome-reaper.py outputs JOB_OUTCOME_STALE
A job stopped producing its artifact while the scheduler still calls it healthy.
That combination is the most expensive failure mode a workspace has, because
nobody investigates a green board.

1. Read the `breaks:` line. That is the actual user-visible consequence.
2. If the entry carries a CAVEAT (the job doesn't write a receipt when idle),
   confirm it's really dead before raising it, then fix the job to always write.
   The ambiguity between "quiet" and "dead" is itself the bug.
3. Otherwise diagnose it. Tell the user what broke and since when.
4. The incident isn't closed until the fix is captured: either a corrected
   budget in `ops/job-outcomes.json` or a new check that would have caught it
   sooner.

If it outputs OUTCOME_REAPER_BROKEN, the manifest itself is unreadable. Fix that
first, since every check it covers is silently not running.

## Memory Maintenance (once per day, first heartbeat after 6pm)
If today's date differs from "Last updated" in user/MEMORY.md:
1. Read recent `memory/YYYY-MM-DD.md` files (today + yesterday)
2. Update user/MEMORY.md with anything significant
3. Remove outdated info
4. If MEMORY.md > 10k chars, archive completed items to `docs/archive/memory-archive-YYYY-MM-DD.md`
5. Update the "Last updated" date

## If All Scripts Return Nothing
Reply: HEARTBEAT_OK

---

**Philosophy**: Scripts are free. Model time is expensive.
Don't burn tokens deciding "nothing happening" — let scripts decide that.
