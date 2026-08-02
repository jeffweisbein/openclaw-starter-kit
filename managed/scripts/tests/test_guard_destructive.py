#!/usr/bin/env python3
"""Tests for managed/scripts/guard-destructive.py.

Plain python3, no pytest and no third-party imports, because the machine that
needs to run this is a fresh workspace with a system python.

Run:  python3 managed/scripts/tests/test_guard_destructive.py

Every case builds a throwaway workspace in a temp directory, points the guard
at it with OPENCLAW_WORKSPACE, and runs the guard as a real subprocess with a
real hook payload on stdin. What is under test is the thing Claude Code
actually executes, including the fail-open path, which cannot be exercised
in-process. Nothing outside the temp directory is read or written.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
GUARD = os.path.normpath(os.path.join(HERE, "..", "guard-destructive.py"))
PYTHON = sys.executable or "/usr/bin/python3"

RESULTS = []

# ── A throwaway workspace, laid out the way the example config describes ──
WS = tempfile.mkdtemp(prefix="guard-ws-")
for d in ("data", "memory", "intel", "docs", "skills", "state", "scripts", "ops",
          "tmp", "logs", "node_modules"):
    os.makedirs(os.path.join(WS, d), exist_ok=True)
with open(os.path.join(WS, "ops", "guard-destructive.json"), "w") as fh:
    json.dump({
        "protectedDirs": ["data", "docs", "intel", "memory", "ops", "scripts",
                          "skills", "state"],
        "ephemeralDirs": ["logs", "node_modules", "tmp", ".git"],
        "recoverableDelete": "trash",
        "denyGitDiscard": True,
        "denyPrismaMigrateDeploy": False,
    }, fh)

OUTSIDE = tempfile.mkdtemp(prefix="guard-outside-")
LOG = os.path.join(WS, "logs", "guard-destructive.log")

BASE_ENV = dict(os.environ)
BASE_ENV["OPENCLAW_WORKSPACE"] = WS
# The guard resolves $DATABASE_URL-shaped variables from its own environment to
# decide whether a target is local. Leave them unset so "unknown" is tested.
for _k in ("DATABASE_URL", "PGHOST", "POSTGRES_URL"):
    BASE_ENV.pop(_k, None)


def run(command, tool_name="Bash", cwd=None, script=GUARD, env=None):
    """Run the guard; return (decision, reason, stderr)."""
    payload = {"tool_name": tool_name, "tool_input": {"command": command}}
    if cwd:
        payload["cwd"] = cwd
    proc = subprocess.run(
        [PYTHON, script],
        input=json.dumps(payload),
        capture_output=True,
        text=True,
        env=env or BASE_ENV,
    )
    if not proc.stdout.strip():
        return "allow", "", proc.stderr
    out = json.loads(proc.stdout)["hookSpecificOutput"]
    return out["permissionDecision"], out["permissionDecisionReason"], proc.stderr


def check(name, condition, detail=""):
    RESULTS.append((name, bool(condition), detail))
    print("%s  %s%s" % ("PASS" if condition else "FAIL", name,
                        ("  <- " + detail) if (detail and not condition) else ""))


def expect_deny(name, command, must_mention=None, **kw):
    decision, reason, _ = run(command, **kw)
    ok = decision == "deny"
    if ok and must_mention:
        ok = must_mention.lower() in reason.lower()
    check(name, ok, "got %s: %s" % (decision, reason[:160]))


def expect_allow(name, command, **kw):
    decision, reason, _ = run(command, **kw)
    check(name, decision == "allow", "got %s: %s" % (decision, reason[:160]))


# --------------------------------------------------------------------------
# 1. Reset-shaped ORM commands.
# --------------------------------------------------------------------------
expect_deny("prisma migrate reset",
            "npx prisma migrate reset --force", "drops and recreates")
expect_deny("prisma migrate reset via pnpm",
            "pnpm prisma migrate reset")
expect_deny("prisma migrate reset inside bash -c",
            'bash -c "cd apps/api && npx prisma migrate reset"')
expect_deny("prisma db push --force-reset",
            "npx prisma db push --force-reset --accept-data-loss")
expect_deny("supabase db reset --linked",
            "supabase db reset --linked")
expect_allow("prisma generate is untouched",
             "npx prisma generate")
expect_allow("prisma db push without --force-reset",
             "npx prisma db push")
expect_allow("grepping for the reset command is not running it",
             'grep -rn "prisma migrate reset" docs/ || true')

# migrate deploy is the correct production step for a repo that has a migration
# history, so it is allowed unless the workspace opts in.
expect_allow("prisma migrate deploy is allowed by default",
             "npx prisma migrate deploy")

_strict = os.path.join(OUTSIDE, "strict.json")
with open(_strict, "w") as fh:
    json.dump({"workspace": WS, "denyPrismaMigrateDeploy": True}, fh)
_strict_env = dict(BASE_ENV)
_strict_env["GUARD_DESTRUCTIVE_CONFIG"] = _strict
expect_deny("prisma migrate deploy is denied when the workspace opts in",
            "npx prisma migrate deploy", env=_strict_env)

# --------------------------------------------------------------------------
# 2. Destructive SQL, every arrival path.
# --------------------------------------------------------------------------
expect_deny("DROP DATABASE via psql -c",
            'psql "$DATABASE_URL" -c "DROP DATABASE app;"', "DROP DATABASE")
expect_deny("DROP SCHEMA via psql on a hosted database",
            'psql postgres://dbuser@example.com:5432/app '
            '-c "DROP SCHEMA public CASCADE;"', "DROP SCHEMA")
expect_deny("DROP TABLE via mysql",
            'mysql -h example.com -e "DROP TABLE users;"', "DROP TABLE")
expect_deny("TRUNCATE piped into psql",
            'echo "TRUNCATE TABLE events;" | psql "$DATABASE_URL"', "TRUNCATE")
expect_deny("TRUNCATE via heredoc",
            'psql "$DATABASE_URL" <<SQL\nTRUNCATE events;\nSQL', "TRUNCATE")
expect_deny("heredoc with a safe first statement still caught",
            'psql "$DATABASE_URL" <<SQL\nSELECT 1;\nDROP TABLE users;\nSQL',
            "DROP TABLE")
expect_deny("DELETE FROM with no WHERE",
            'psql "$DATABASE_URL" -c "DELETE FROM contacts"', "WHERE")
expect_deny("UPDATE ... SET with no WHERE",
            'psql "$DATABASE_URL" -c "UPDATE orgs SET plan = \'free\'"', "WHERE")
expect_deny("supabase db execute path",
            'supabase db execute --linked --command "TRUNCATE profiles"')
expect_deny("wrangler d1 execute against remote",
            'wrangler d1 execute prod-db --remote --command "DROP TABLE sessions"')
expect_deny("prisma db execute with no proof of locality",
            "npx prisma db execute --file ./ops/backfill.sql --schema prisma/schema.prisma")

expect_allow("SELECT is not destruction",
             'psql "$DATABASE_URL" -c "SELECT count(*) FROM orgs;"')
expect_allow("DELETE FROM with a WHERE clause",
             'psql "$DATABASE_URL" -c "DELETE FROM jobs WHERE id = 42"')
expect_allow("UPDATE with a WHERE clause",
             'psql "$DATABASE_URL" -c "UPDATE orgs SET plan=\'pro\' WHERE id=1"')
expect_allow("DROP TABLE on a provably local host",
             'psql -h localhost -d dev -c "DROP TABLE scratch;"')
expect_allow("TRUNCATE on 127.0.0.1",
             'psql postgres://dev@127.0.0.1:5432/dev -c "TRUNCATE scratch;"')
expect_allow("wrangler d1 --local",
             'wrangler d1 execute dev-db --local --command "DROP TABLE scratch"')
expect_allow("SQL keywords in a non-client command",
             'grep -rn "DROP TABLE" prisma/migrations/')
expect_allow("editing a migration file is not executing it",
             'echo "DROP TABLE scratch;" > %s/m.sql' % OUTSIDE)

# The -f file.sql case: the SQL is not in the command string, so the guard
# reads the file (documented in sql_file_bodies).
_wipe = os.path.join(OUTSIDE, "wipe.sql")
with open(_wipe, "w") as fh:
    fh.write("-- nightly cleanup\nBEGIN;\nTRUNCATE TABLE coverage_items;\nCOMMIT;\n")
_safe = os.path.join(OUTSIDE, "safe.sql")
with open(_safe, "w") as fh:
    fh.write("-- this comment mentions DROP TABLE but does nothing\n"
             "UPDATE orgs SET seen_at = now() WHERE id = 1;\n")

expect_deny("psql -f file.sql: guard reads the file",
            'psql "$DATABASE_URL" -f %s' % _wipe, "TRUNCATE")
expect_allow("psql -f file.sql: safe file passes, comments ignored",
             'psql "$DATABASE_URL" -f %s' % _safe)
expect_deny("psql < file.sql redirect also read",
            'psql "$DATABASE_URL" < %s' % _wipe, "TRUNCATE")
expect_allow("cat of a destructive .sql file is not execution",
             "cat %s" % _wipe)

# A heredoc body going somewhere that cannot execute it is prose, not a command
# line. This exact case denied the commit that introduced the guard.
expect_allow("a commit message heredoc mentioning a denied command",
             "git commit -F - <<'EOF'\n"
             "feat: add the guard\n\n"
             "prisma migrate reset is denied in every posture, and so is\n"
             "git reset --hard and rm -rf %s/data.\n"
             "EOF" % WS)
expect_allow("heredoc body written to a file",
             "cat > %s/notes.md <<'EOF'\nrm -rf %s/data\nEOF" % (OUTSIDE, WS))
expect_deny("but a heredoc piped into a shell is still a command line",
            "ssh buildbox <<'EOF'\nnpx prisma migrate reset\nEOF")
expect_deny("and a heredoc piped into a SQL client is still SQL",
            'psql "$DATABASE_URL" <<SQL\nDROP TABLE users;\nSQL', "DROP TABLE")

# --------------------------------------------------------------------------
# 3. Quoting. A policy word inside a quoted argument is not a command.
# --------------------------------------------------------------------------
expect_allow("REGRESSION: grep with rm -rf inside a quoted alternation",
             'grep -rln "foo\\|rm -rf\\|bar" scripts/')
expect_allow("grep for rm in a protected tree",
             'grep -rn "rm -rf" %s/scripts/' % WS)
expect_allow("commit message mentioning rm",
             'git commit -m "guard: block rm -rf under data/"')
expect_allow("grep for git reset --hard",
             'grep -rn "git reset --hard" %s/docs/' % WS)
expect_allow("ripgrep with a quoted destructive pattern",
             "rg 'shred|unlink' %s/scripts/" % WS)
expect_deny("but a real quoted-path rm is still denied",
            'rm -rf "%s/data/reports"' % WS)
expect_deny("and bash -c cannot smuggle it past the quote mask",
            'bash -c "rm -rf %s/data/reports"' % WS)

# --------------------------------------------------------------------------
# 4. Protected trees.
# --------------------------------------------------------------------------
expect_deny("rm in data/", "rm -f data/report-2026-01-01.md", "trash")
expect_deny("rm in memory/", "rm %s/memory/notes.md" % WS)
expect_deny("rm in intel/", "rm -rf %s/intel/" % WS)
expect_deny("rm after &&", "cd %s && rm -rf state/cache" % WS)
expect_deny("rm via sudo", "sudo rm -rf %s/skills/foo" % WS)
expect_deny("rm in a then-branch", "if true; then rm -rf %s/docs/x; fi" % WS)
expect_deny("shred in a protected tree", "shred -u %s/state/keys.json" % WS)
expect_deny("find -exec rm in a protected tree",
            "find %s/data -name '*.bak' -exec rm {} \\;" % WS)
expect_deny("find -delete in a protected tree",
            "find %s/data -name '*.bak' -delete" % WS)
expect_deny("rm targeting /", "rm -rf /")
expect_deny("git clean -fd", "git clean -fd")
expect_deny("git reset --hard", "git reset --hard origin/master")

expect_allow("find -delete in tmp/", "find %s/tmp -name '*.tmp' -mtime +7 -delete" % WS)
expect_allow("rm in tmp/", "rm -rf %s/tmp/build" % WS)
expect_allow("rm in logs/", "rm -f %s/logs/old.log" % WS)
expect_allow("rm in node_modules/", "rm -rf %s/node_modules" % WS)
expect_allow("rm outside the workspace", "rm -f %s/scratch.zip" % OUTSIDE)
expect_allow("the recoverable command is the sanctioned path",
             "trash %s/data/old.md" % WS)
expect_allow("ls of a protected tree", "ls -la %s/data/" % WS)
expect_allow("non-Bash tools are ignored",
             "rm -rf %s/data" % WS, tool_name="Read")

# The protected list is configuration, not a constant: a directory this
# workspace did not list is not protected.
expect_allow("a directory not in protectedDirs is not protected",
             "rm -rf %s/vendor/cache" % WS)

# --------------------------------------------------------------------------
# 5. Fail-open path: a broken guard allows, but says so loudly.
# --------------------------------------------------------------------------
_broken = os.path.join(OUTSIDE, "broken-guard.py")
with open(GUARD) as fh:
    _src = fh.read()
# Force a crash inside main() after the command is captured.
_broken_src = _src.replace(
    "    texts = command_texts(command)\n",
    "    raise RuntimeError('simulated guard failure')\n", 1)
assert _broken_src != _src, "fail-open injection point not found"
with open(_broken, "w") as fh:
    fh.write(_broken_src)

_decision, _reason, _stderr = run("rm -rf %s/data/everything" % WS, script=_broken)
check("fail-open: a crashing guard still allows", _decision == "allow",
      "got %s" % _decision)
check("fail-open: crash is loud on stderr",
      "CRASHED" in _stderr and "not an approval" in _stderr,
      "stderr was %r" % _stderr[:200])
check("fail-open: traceback is preserved",
      "simulated guard failure" in _stderr, _stderr[:200])

try:
    with open(LOG) as fh:
        _tail = fh.read()[-4000:]
    check("fail-open: logged at its own GUARD-FAILOPEN level",
          "GUARD-FAILOPEN" in _tail and "WITHOUT POLICY EVALUATION" in _tail)
except IOError as exc:
    check("fail-open: logged at its own GUARD-FAILOPEN level", False, str(exc))

# Malformed payloads must not wedge anything.
_proc = subprocess.run([PYTHON, GUARD], input="not json at all",
                       capture_output=True, text=True, env=BASE_ENV)
check("malformed payload allows", not _proc.stdout.strip())
check("malformed payload is announced on stderr",
      "ALLOWED unchecked" in _proc.stderr, _proc.stderr[:200])

# Unbalanced quotes must not parse their way to allowed.
expect_deny("unbalanced quotes fall back to regex matching",
            'rm -rf %s/data/x "oops' % WS)

# A workspace with no config file at all still runs on the built-in defaults.
_bare = tempfile.mkdtemp(prefix="guard-bare-")
_bare_env = dict(os.environ)
_bare_env["OPENCLAW_WORKSPACE"] = _bare
_bare_env.pop("GUARD_DESTRUCTIVE_CONFIG", None)
expect_deny("no config file: built-in defaults still protect memory/",
            "rm -rf %s/memory/notes.md" % _bare, env=_bare_env)
expect_allow("no config file: built-in defaults still allow tmp/",
             "rm -rf %s/tmp/build" % _bare, env=_bare_env)

# --------------------------------------------------------------------------
shutil.rmtree(WS, ignore_errors=True)
shutil.rmtree(OUTSIDE, ignore_errors=True)
shutil.rmtree(_bare, ignore_errors=True)

_failed = [n for n, ok, _ in RESULTS if not ok]
print("\n%d/%d passed" % (len(RESULTS) - len(_failed), len(RESULTS)))
if _failed:
    print("FAILED: " + "; ".join(_failed))
sys.exit(1 if _failed else 0)
