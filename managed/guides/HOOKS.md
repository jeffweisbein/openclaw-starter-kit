# Hooks: the layer underneath your permission settings

Permission rules, allowlists and autonomy levels are *posture*. They can be
relaxed, and in an autonomous workspace they get relaxed, because the whole
point is that the agent does not stop to ask about every command. Anything you
are relying on to prevent an unrecoverable action needs to sit below that.

Claude Code hooks are that layer. A `PreToolUse` hook runs before the tool does
and can deny it. It still runs under `--permission-mode bypassPermissions`,
which is what makes it worth wiring, and it is the only thing in the stack that
holds in every posture.

The kit ships two.

| Hook | Event | What it does |
|------|-------|--------------|
| `managed/scripts/guard-destructive.py` | `PreToolUse` on `Bash` | Denies deletion inside protected trees and destructive SQL against anything not provably local |
| `managed/scripts/screen-external.py --hook` | `PostToolUse` on web tools | Screens fetched content for prompt injection and annotates it as hostile |

## Which settings file

Claude Code reads settings from several scopes, most specific winning:

| Scope | File | Loaded when |
|-------|------|-------------|
| Enterprise | managed policy path | Always, and cannot be overridden |
| User | `~/.claude/settings.json` | Always |
| Project | `<project>/.claude/settings.json` | Working inside that project |
| Local | `<project>/.claude/settings.local.json` | Working inside that project, gitignored |

**Install these at user scope, in `~/.claude/settings.json`.**

Two reasons. First, a project-scoped hook only protects the project you are
sitting in, and the deletion you regret will happen from a session that was
started somewhere else. Second, OpenClaw's `claude-cli` backend invokes Claude
Code with `--setting-sources user`, so user scope is the only scope its agent
and cron sessions load at all. A hook in a project file is invisible to every
scheduled job you run. Confirm this against your own installed version before
you rely on it, since it is a property of the harness and not of the hook.

## Install

Create `~/.claude/settings.json` if it does not exist, then merge in the
`hooks` block. Replace `/path/to/workspace` with your workspace root.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "python3 /path/to/workspace/managed/scripts/guard-destructive.py"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "WebFetch|WebSearch",
        "hooks": [
          {
            "type": "command",
            "command": "python3 /path/to/workspace/managed/scripts/screen-external.py --hook"
          }
        ]
      }
    ]
  }
}
```

The path has to be absolute. A hook runs with whatever working directory the
session has, which is not your workspace.

Then configure the guard, because its built-in defaults are a guess at a
workspace layout and a protected list that does not match your directories
protects nothing:

```bash
mkdir -p ~/clawd/ops
cp managed/ops/guard-destructive.example.json ~/clawd/ops/guard-destructive.json
$EDITOR ~/clawd/ops/guard-destructive.json
```

Set `OPENCLAW_WORKSPACE` in your shell profile if your workspace is not
`~/clawd`. Both hooks read it.

## Verify it is on

Restart the session first. Hooks are read at startup, so an edit to
`settings.json` does nothing to a session that is already running. Then:

```bash
python3 managed/scripts/tests/test_guard_destructive.py
python3 managed/scripts/tests/test_screen_external.py
```

Both build their own throwaway workspace in a temp directory and clean up after
themselves. Nothing in your workspace is read or written.

To prove the hook is actually wired rather than merely present, ask the agent
to delete something inside a protected tree and watch it get denied. Then:

```bash
tail -5 ~/clawd/logs/guard-destructive.log
```

Every decision is logged, including allows.

## When it fails

Both hooks fail **open**. A crash allows the command, because a broken guard
that wedges every session on the machine is worse than no guard. A fail-open is
logged at its own level and echoed to stderr, so it is discoverable:

```bash
grep GUARD-FAILOPEN ~/clawd/logs/guard-destructive.log
```

An empty result is the answer you want. If that grep has been returning hits
for a month, the guard has been decorative for a month. Check it when you
change the config, upgrade python, or move your workspace.

## What these do not do

The guard reads a command string. An agent that writes a python script and runs
`python3 cleanup.py` has moved the deletion out of the command line, and the
guard cannot see it. This raises the cost of an accident, which is most of
them. It is not a sandbox, and it is not a defence against something trying to
get around it. If you need containment, see
[`managed/guides/SANDBOXES.md`](SANDBOXES.md).

The screener runs on `PostToolUse`, which is after the fetch. It cannot stop
content from arriving. What it does is stop the model from quietly treating
that content as instructions, which is the part that actually hurts.

## Adding your own

The same shape works for anything you want denied regardless of posture. Keep
to three rules and it will survive contact with a live workspace:

1. **Fail open, loudly.** Wrap `main()`, log the crash at a distinct level, and
   exit 0. Never let a hook bug become an outage.
2. **Do not deny reading, or writing about it.** An early version of the guard
   denied `grep -rn "rm -rf" scripts/`, because the policy word appeared in the
   string. A later one denied `git commit -F - <<'EOF'` on a commit message that
   described the guard. Getting denied for reading and for documenting teaches
   everyone to route around the guard, which costs you more than the rule was
   worth. Parse the command: only count a policy word in command position, mask
   quoted arguments, and treat a heredoc body as data unless whatever receives
   it can actually run it.
3. **Log every decision, allows included.** "Is this thing even running?" is the
   question you will have at the worst moment, and a log of denials alone cannot
   answer it.
