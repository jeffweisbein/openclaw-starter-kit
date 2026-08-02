#!/usr/bin/env python3
"""outcome-reaper.py -- check that scheduled jobs are still producing their work.

A scheduler tracks whether a job RAN. That is not the same question as whether
the work happened. `lastRunStatus: ok` means the agent turn completed. A turn
completes fine when the API key it needed expired, when the script it called
started returning an empty list, or when the job has been quietly writing
nothing for two months.

So this does not monitor jobs. It monitors the ARTIFACT each job is responsible
for keeping fresh, and it checks it from OUTSIDE the job. A dashboard reading
all-green while nothing has been delivered for weeks is the most expensive
failure mode an autonomous workspace has, because nobody goes looking.

THE RULE THAT MAKES THIS WORK: a no-op must still write a receipt.
"Nothing to report" and "I am broken" are otherwise the same observable, which
is silence. A job that legitimately has nothing to say must still touch its
artifact. Any job listed with "noOpWritesReceipt": false cannot be
distinguished from dead, and that is a hardening task, not a setting.

Silent on a healthy workspace, so it costs nothing to run on every heartbeat.
Prints only what is stale.

Usage:
  outcome-reaper.py              # heartbeat mode: silent unless something is stale
  outcome-reaper.py --all        # show every tracked job, healthy included
  outcome-reaper.py --coverage   # how much of the workspace is actually monitored
  outcome-reaper.py --manifest <path>

Manifest location, in order:
  1. --manifest <path>
  2. $JOB_OUTCOMES_MANIFEST
  3. <workspace>/ops/job-outcomes.json

<workspace> is $OPENCLAW_WORKSPACE, or ~/clawd. Start from
`managed/ops/job-outcomes.example.json`. With no manifest at all this exits 0
and says nothing, so it is safe to wire into a heartbeat before you have
written one.
"""
import json
import os
import sys
import time

HOME = os.path.expanduser("~")
ROOT = os.path.abspath(os.path.expanduser(
    os.environ.get("OPENCLAW_WORKSPACE") or os.path.join(HOME, "clawd")))


def manifest_path(args):
    if "--manifest" in args:
        i = args.index("--manifest")
        if i + 1 < len(args):
            return os.path.expanduser(args[i + 1])
    if os.environ.get("JOB_OUTCOMES_MANIFEST"):
        return os.path.expanduser(os.environ["JOB_OUTCOMES_MANIFEST"])
    return os.path.join(ROOT, "ops", "job-outcomes.json")


def check(entry, now):
    """Return (state, age_hours). state is one of: ok, stale, missing."""
    path = os.path.expanduser(entry["artifact"])
    if not os.path.isabs(path):
        path = os.path.join(ROOT, path)
    if not os.path.exists(path):
        return "missing", None
    age = (now - os.path.getmtime(path)) / 3600.0
    return ("stale" if age > entry["maxAgeH"] else "ok"), age


def main():
    args = sys.argv[1:]
    verbose = "--all" in args or "--coverage" in args
    path = manifest_path(args)

    if not os.path.exists(path):
        # Not configured yet. Not an error, and not something to wake a model
        # over on every heartbeat.
        if verbose:
            print(f"no manifest at {path}")
            print("start from managed/ops/job-outcomes.example.json")
        return 0

    try:
        with open(path) as f:
            data = json.load(f)
    except Exception as e:
        # A broken manifest must be loud. Failing quiet here would recreate the
        # exact blind spot this script exists to close.
        print("OUTCOME_REAPER_BROKEN")
        print(f"could not read {path}: {e}")
        return 0

    outcomes = [e for e in data.get("outcomes", []) if not e.get("disabled")]
    now = time.time()
    results = [(e, *check(e, now)) for e in outcomes]

    if "--coverage" in args:
        print(f"manifest: {path}")
        print(f"tracked:  {len(outcomes)} job(s)")
        blind = [e["job"] for e in outcomes if not e.get("noOpWritesReceipt", True)]
        if blind:
            print()
            print("Tracked but NOT trustworthy. A quiet run and a dead job look identical")
            print("for these, so a green result proves nothing. Teach each one to write a")
            print("receipt on every run, including the run that found nothing:")
            for b in blind:
                print(f"  - {b}")
        print()
        print("Coverage is the number that matters, and this script cannot compute it for")
        print("you. List your scheduled jobs, and for each one ask what artifact would be")
        print("stale if it silently stopped. A job with no answer to that is a job whose")
        print("failure you will find out about from someone else.")
        return 0

    if "--all" in args:
        print(f"{'job':28} {'state':8} {'age(h)':>8} {'budget':>7}  artifact")
        print("-" * 92)
        for e, state, age in results:
            a = f"{age:8.1f}" if age is not None else "       -"
            print(f"{e['job']:28} {state:8} {a} {e['maxAgeH']:>7}  {e['artifact']}")
        return 0

    bad = [(e, s, a) for e, s, a in results if s != "ok"]
    if not bad:
        return 0

    print("JOB_OUTCOME_STALE")
    print(f"{len(bad)} tracked job(s) stopped producing their artifact. The scheduler")
    print("still reports these as healthy. That is the point. Do not trust it.")
    print()
    for e, state, age in bad:
        agetxt = "artifact missing entirely" if age is None else f"{age:.0f}h old (budget {e['maxAgeH']}h)"
        print(f"  {e['job']}  --  {agetxt}")
        print(f"      artifact: {e['artifact']}")
        print(f"      breaks:   {e['breaks']}")
        if not e.get("noOpWritesReceipt", True):
            print("      CAVEAT:   this job does not write a receipt when idle, so this may")
            print("                just be a quiet stretch. Verify before raising it, then")
            print("                fix the job to always write. The ambiguity is the bug.")
        if e.get("note"):
            print(f"      note:     {e['note']}")
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
