# HEARTBEAT.md

<!--
Your AI reads this on every heartbeat poll.
Keep it SMALL — scripts are free, model time is expensive.
Only wake the model when scripts produce output.
-->

## Checks

<!-- Add your check scripts here. Only act on output. -->
<!-- Example:
```bash
/path/to/check-email.sh
/path/to/check-calendar.sh
/path/to/check-mentions.sh
```
-->

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
