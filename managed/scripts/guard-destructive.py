#!/usr/bin/env python3
"""PreToolUse guard: posture-independent hard denials for unrecoverable actions.

WHY THIS LAYER
--------------
Permission rules, allowlists and autonomy settings are all *posture*. They can
be relaxed, and the whole point of an autonomous workspace is that sometimes
they are. This file is the layer underneath all of that: a small set of denials
that hold in EVERY posture, including the most permissive one. There is no "yes
really" flag and no autonomy level that turns them off. An agent that hits one
of these is meant to stop and ask, not to find another way to run the same
thing.

Wired as a Claude Code PreToolUse hook in `~/.claude/settings.json` (USER
scope). User scope is the only scope OpenClaw's claude-cli backend loads, since
it forces `--setting-sources user`, so a hook installed there covers every agent
and cron session as well as interactive Claude Code. It also survives
`--permission-mode bypassPermissions`, which OpenClaw uses while
`tools.exec.security` is "full". Install instructions are in
`managed/guides/HOOKS.md`.

TWO DENIAL CLASSES
------------------
1. Deletion. A scheduled job deleted a generated file that existed in no
   backup, and nobody noticed for days. Policy: recoverable deletion only
   inside protected trees. `rm` there is denied with a message telling the
   agent to use the configured recoverable-delete command instead, so anything
   removed can be restored. Ephemeral paths (tmp, logs, build output,
   dependency dirs) are untouched so builds and scheduled jobs keep working.

2. Destructive SQL. A `prisma migrate reset` wiped a production database. That
   database was schema-push managed: no migration history, no deploy-migrate
   step, so a "reset" was a straight wipe, and recovery meant a point-in-time
   restore from the hosting provider. Policy: schema and bulk-data destruction
   is denied unless the target is *provably* local (localhost / 127.0.0.1 / a
   unix socket / an explicit --local flag). Reset-shaped ORM commands are
   denied unconditionally, because an ORM reads its connection string from the
   environment and a hook cannot see it.

   When in doubt, DENY. A false deny costs one message. A false allow cost
   somebody a production database.

CONFIGURATION
-------------
Protected and ephemeral directory lists, the workspace root, the
recoverable-delete command and a few policy switches are read from JSON, in
this order:

  1. $GUARD_DESTRUCTIVE_CONFIG
  2. <workspace>/ops/guard-destructive.json
  3. built-in defaults (below)

<workspace> is $OPENCLAW_WORKSPACE, or ~/clawd. Copy
`managed/ops/guard-destructive.example.json` to `<workspace>/ops/` and edit it;
your layout is not the same as anyone else's, and a protected list that does
not match your directories protects nothing.

PARSING
-------
Policy words only count in *command position*. Text inside a quoted argument is
masked before pattern matching, so `grep -rln "foo\\|rm -rf\\|bar" scripts/` is
allowed. Wrapper commands that carry another command line (sh/bash/zsh -c, ssh,
eval) are unwrapped and re-checked, so quoting is not an escape hatch.

Reads a hook payload on stdin, writes a decision on stdout. Fails OPEN: any
internal error allows the command, because a crashing guard must not wedge
every session on the machine. A fail-open is logged as GUARD-FAILOPEN with a
full traceback and echoed to stderr, so "the guard has been dead for months" is
discoverable. Every decision is appended to the log file.

Test it:  python3 managed/scripts/tests/test_guard_destructive.py
"""

import json
import os
import re
import shlex
import sys
import time
import traceback

HOME = os.path.expanduser("~")

# --------------------------------------------------------------------------
# Configuration.
# --------------------------------------------------------------------------

DEFAULTS = {
    # Trees whose contents are hand-made, generated-once, or otherwise not
    # reproducible by rerunning a build. Deletion here must be recoverable.
    "protectedDirs": [
        "agents", "assets", "data", "docs", "intel", "layers", "memory",
        "ops", "prompts", "scripts", "skills", "state", "user",
    ],
    # Ephemeral trees inside the workspace. Real build and job churn lives
    # here and `rm` stays allowed so nothing regresses.
    "ephemeralDirs": [
        ".git", ".next", "backups", "build", "dist", "logs", "node_modules",
        "target", "tmp",
    ],
    # Command that removes a file recoverably. macOS ships `trash` at
    # /usr/bin/trash; on Linux use "gio trash" or "trash-put".
    "recoverableDelete": "trash",
    "logPath": "logs/guard-destructive.log",
    # Off by default: `prisma migrate deploy` is the correct production deploy
    # step for a repo that HAS a migration history. Turn it on if your
    # production schema is push-managed, where a deploy replays migrations
    # that were never applied.
    "denyPrismaMigrateDeploy": False,
    # Off by default so the guard does not fight normal git usage. Turn it on
    # if agents have thrown away uncommitted work with a hard reset.
    "denyGitDiscard": True,
}


def load_config():
    workspace = os.environ.get("OPENCLAW_WORKSPACE") or os.path.join(HOME, "clawd")
    workspace = os.path.abspath(os.path.expanduser(workspace))

    candidates = []
    if os.environ.get("GUARD_DESTRUCTIVE_CONFIG"):
        candidates.append(os.path.expanduser(os.environ["GUARD_DESTRUCTIVE_CONFIG"]))
    candidates.append(os.path.join(workspace, "ops", "guard-destructive.json"))

    cfg = dict(DEFAULTS)
    for path in candidates:
        try:
            with open(path) as fh:
                loaded = json.load(fh)
        except Exception:
            continue
        cfg.update({k: v for k, v in loaded.items() if not k.startswith("_")})
        break

    if cfg.get("workspace"):
        workspace = os.path.abspath(os.path.expanduser(cfg["workspace"]))
    cfg["workspace"] = workspace

    log_path = cfg.get("logPath") or DEFAULTS["logPath"]
    if not os.path.isabs(os.path.expanduser(log_path)):
        log_path = os.path.join(workspace, log_path)
    cfg["logPath"] = os.path.expanduser(log_path)
    return cfg


CONFIG = load_config()
WORKSPACE = CONFIG["workspace"]
LOG_PATH = CONFIG["logPath"]
PROTECTED_DIRS = tuple(CONFIG["protectedDirs"])
EPHEMERAL_DIRS = tuple(CONFIG["ephemeralDirs"])
RECOVERABLE_DELETE = CONFIG["recoverableDelete"]

# Set as soon as the command is parsed so the fail-open handler can name the
# command that slipped through uninspected.
CURRENT_COMMAND = "<unparsed>"

# Commands that remove or clobber files. The recoverable-delete command is
# deliberately absent.
DESTRUCTIVE = re.compile(
    r"""(?:^|[;&|]|\$\(|`|\bthen\b|\belse\b|\bdo\b)\s*
        (?:sudo\s+)?
        (?P<cmd>rm|shred|unlink|srm)\b""",
    re.VERBOSE,
)

# Whole-command bans regardless of path. These wipe or rewrite history and have
# no recoverable form.
CATASTROPHIC = [
    (re.compile(r"\brm\s+(-[a-zA-Z]*\s+)*(-[a-zA-Z]*[rf][a-zA-Z]*\s+)*/\s*(?:$|[;&|])"),
     "rm targeting /"),
    (re.compile(r"\bmkfs\b|\bdiskutil\s+erase"), "disk format"),
]
if CONFIG.get("denyGitDiscard", True):
    CATASTROPHIC += [
        (re.compile(r"\bgit\s+clean\b.*-[a-zA-Z]*[fx]"), "git clean -f/-x (removes untracked files)"),
        (re.compile(r"\bgit\s+reset\s+--hard\b"), "git reset --hard (discards uncommitted work)"),
        (re.compile(r"\bgit\s+checkout\s+--\s"), "git checkout -- (discards uncommitted work)"),
    ]
CATASTROPHIC = tuple(CATASTROPHIC)

# --------------------------------------------------------------------------
# Shell parsing.
#
# Everything here exists so a policy word only counts when it is actually being
# run. The bare regexes above match text anywhere in the command string, which
# denied honest read-only commands like:
#     grep -rln "foo\|rm -rf\|bar" scripts/
# Getting denied for reading trains everyone to route around the guard, so the
# command is tokenized and quoted spans are masked before matching. Wrappers
# that carry a whole command line in a quoted argument are unwrapped instead of
# masked, so quoting cannot be used to smuggle a denied command past the guard.
# --------------------------------------------------------------------------

SEPARATOR_TOKENS = frozenset((
    ";", ";;", "&", "&&", "|", "||", "(", ")", "{", "}",
    "<", "<<", "<<<", ">", ">>", ">|", "|&", "&>", "\n",
))
SHELL_KEYWORDS = frozenset((
    "if", "then", "elif", "else", "fi", "for", "while", "until",
    "do", "done", "case", "esac", "in", "select", "function", "!",
))
# Wrappers that run another command; the real command name sits behind them.
COMMAND_PREFIXES = frozenset((
    "sudo", "doas", "env", "nohup", "time", "command", "builtin", "exec",
    "stdbuf", "nice", "ionice", "setsid", "caffeinate", "xargs", "timeout",
))
# Prefix flags that consume the next token, so `sudo -u postgres psql` does not
# read as the command `postgres`.
PREFIX_ARG_FLAGS = frozenset((
    "-u", "-g", "-n", "-I", "-i", "-P", "-s", "-k", "--user", "--group",
))
# Commands whose quoted argument is itself a command line. Re-parsed, not
# masked: `bash -c "rm -rf <workspace>/data"` must still be denied.
NESTED_SHELLS = frozenset(("sh", "bash", "zsh", "dash", "ksh", "ssh", "eval"))
ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
DESTRUCTIVE_VERBS = frozenset(("rm", "shred", "unlink", "srm"))


def mask_quoted(text):
    """Blank out the contents of quoted spans, preserving length and quotes.

    Length preservation matters: offsets into the masked string are used to
    slice the raw string when splitting a command line into statements.
    """
    out = []
    quote = None
    escaped = False
    for ch in text:
        if quote:
            if escaped:
                escaped = False
                out.append("x")
            elif ch == quote:
                quote = None
                out.append(ch)
            elif ch == "\\" and quote == '"':
                escaped = True
                out.append("x")
            else:
                out.append("\n" if ch == "\n" else "x")
        elif ch in "\"'":
            quote = ch
            out.append(ch)
        else:
            out.append(ch)
    return "".join(out)


def unquote(token):
    """Strip surrounding quotes and command-substitution punctuation."""
    tok = token.strip("`")
    while tok[:1] == "$" or tok[:1] == "(":
        tok = tok[1:]
    if len(tok) >= 2 and tok[0] == tok[-1] and tok[0] in "\"'":
        tok = tok[1:-1]
    return tok


def tokenize(text):
    """Token list with quotes preserved, or None if the line will not parse."""
    try:
        lexer = shlex.shlex(text, posix=False, punctuation_chars=True)
        lexer.whitespace_split = True
        raw = list(lexer)
    except ValueError:
        return None  # unbalanced quotes; caller falls back to raw matching
    tokens = []
    for tok in raw:
        if tok[:1] in "\"'" or "`" not in tok:
            tokens.append(tok)
            continue
        # A backtick both closes one command position and opens another.
        for i, part in enumerate(tok.split("`")):
            if i:
                tokens.append(";")
            if part:
                tokens.append(part)
    return tokens


def segments(tokens):
    """Split a token list into simple commands on operators and keywords."""
    out = [[]]
    for tok in tokens:
        bare = unquote(tok)
        if tok in SEPARATOR_TOKENS or bare in SHELL_KEYWORDS:
            if out[-1]:
                out.append([])
            continue
        out[-1].append(tok)
    return [seg for seg in out if seg]


def command_names(segment):
    """Command names invoked by one simple command, wrappers unwrapped."""
    names = []
    i = 0
    expect = True
    while i < len(segment):
        bare = unquote(segment[i])
        if expect:
            if not bare or ASSIGNMENT.match(bare) or bare == "\\":
                i += 1
                continue
            name = os.path.basename(bare)
            names.append(name)
            if name in COMMAND_PREFIXES:
                i += 1
                while i < len(segment):
                    flag = unquote(segment[i])
                    if not flag.startswith("-"):
                        break
                    i += 1
                    if flag in PREFIX_ARG_FLAGS:
                        i += 1
                continue  # still expecting a command name
            expect = False
            i += 1
            continue
        # Inside the argument list only find(1)-style exec flags reopen a
        # command position: `find . -exec rm {} \;`
        if bare in ("-exec", "-execdir", "-ok", "-okdir"):
            expect = True
        i += 1
    return names


def command_texts(command, depth=0):
    """The command plus every nested command line it carries, recursively."""
    texts = [command]
    if depth >= 3:
        return texts
    tokens = tokenize(command)
    if tokens is None:
        return texts
    for segment in segments(tokens):
        if not (set(command_names(segment)) & NESTED_SHELLS):
            continue
        for tok in segment[1:]:
            if tok[:1] in "\"'" and len(tok) >= 2:
                texts.extend(command_texts(unquote(tok), depth + 1))
    return texts


def statements(text):
    """Split a command line on top-level ; && || and newlines.

    A heredoc body is left intact: its `;` terminators are SQL, not shell, and
    splitting there would strip statements away from the client that runs them.
    """
    if "<<" in text:
        return [text]
    masked = mask_quoted(text)
    parts = []
    start = 0
    for match in re.finditer(r";|&&|\|\||\n", masked):
        parts.append(text[start:match.start()])
        start = match.end()
    parts.append(text[start:])
    return [p for p in parts if p.strip()]


# --------------------------------------------------------------------------
# Destructive SQL policy.
# --------------------------------------------------------------------------

# Clients that execute SQL against whatever connection string is in scope.
SQL_CLIENTS = frozenset((
    "psql", "pgcli", "mysql", "mariadb", "mysqlsh", "cockroach",
    "clickhouse-client", "usql", "pgbench",
))
# Multi-word invocations; matched as a contiguous token subsequence.
SQL_SUBCOMMANDS = (
    ("supabase", "db"),
    ("wrangler", "d1", "execute"),
    ("prisma", "db", "execute"),
    ("prisma", "db", "push"),
    ("prisma", "migrate"),
    ("turso", "db", "shell"),
)

# Reset-shaped ORM commands. Denied unconditionally: these tools resolve their
# connection string from the environment or a .env file, neither of which a
# PreToolUse hook can see, so "is this production?" is unanswerable here.
PRISMA_RULES = [
    (re.compile(r"\bprisma\s+migrate\s+reset\b", re.I),
     "prisma migrate reset (drops and recreates every table)"),
    (re.compile(r"\bprisma\s+db\s+push\b[^\n]*--force-reset", re.I),
     "prisma db push --force-reset (drops the database first)"),
    (re.compile(r"\bsupabase\s+db\s+reset\b[^\n]*--linked", re.I),
     "supabase db reset --linked (resets the REMOTE project database)"),
]
if CONFIG.get("denyPrismaMigrateDeploy"):
    PRISMA_RULES.append(
        (re.compile(r"\bprisma\s+migrate\s+deploy\b", re.I),
         "prisma migrate deploy (this workspace's production schema is push-managed "
         "and has no migration history to replay)"))
PRISMA_RULES = tuple(PRISMA_RULES)

# Statement-level destruction. Evaluated only inside a SQL client invocation,
# so `grep -r "DROP TABLE" migrations/` stays allowed.
SQL_RULES = (
    (re.compile(r"\bDROP\s+DATABASE\b", re.I), "DROP DATABASE"),
    (re.compile(r"\bDROP\s+SCHEMA\b", re.I), "DROP SCHEMA"),
    (re.compile(r"\bDROP\s+TABLE\b", re.I), "DROP TABLE"),
    (re.compile(r"\bTRUNCATE\b", re.I), "TRUNCATE"),
)
SQL_DELETE = re.compile(r"\bDELETE\s+FROM\b", re.I)
SQL_UPDATE = re.compile(r"\bUPDATE\b[\s\S]{0,400}?\bSET\b", re.I)
SQL_WHERE = re.compile(r"\bWHERE\b", re.I)
SQL_COMMENTS = re.compile(r"--[^\n]*|/\*[\s\S]*?\*/")
SQL_BLOCK_COMMENT = re.compile(r"/\*[\s\S]*?\*/")

CONNECTION_URL = re.compile(
    r"\b(?:postgres|postgresql|mysql|mariadb|mongodb)(?:\+\w+)?://[^\s\"'`;|]+", re.I)
URL_FLAG = re.compile(
    r"--(?:db-url|url|dsn|connection-string|database-url)(?:=|\s+)([^\s\"'`;|]+)", re.I)
HOST_FLAG = re.compile(
    r"(?:^|\s)(?:-h|--host|--hostname)(?:=|\s+)([^\s\"'`;|]+)")
DB_VAR = re.compile(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?")
LOCAL_HOST = re.compile(
    r"^(?:localhost|127(?:\.\d+){3}|0\.0\.0\.0|::1|\[::1\]|host\.docker\.internal)$",
    re.I)
REMOTE_FLAG = re.compile(r"--(?:linked|remote|production|prod)\b", re.I)
LOCAL_FLAG = re.compile(r"(?:^|\s)--local(?:\s|=|$)")


def url_host(url):
    """Host portion of a connection URL, or '' when it cannot be read."""
    rest = url.split("://", 1)[-1]
    rest = rest.split("/", 1)[0].split("?", 1)[0]
    if "@" in rest:
        rest = rest.rsplit("@", 1)[1]
    if rest.startswith("["):  # IPv6 literal
        return rest.split("]", 1)[0] + "]"
    return rest.split(":", 1)[0]


def connection_hosts(text):
    """Every host this statement might talk to. '?' means 'could not tell'."""
    hosts = []
    for url in CONNECTION_URL.findall(text):
        hosts.append(url_host(url))
    for value in URL_FLAG.findall(text) + HOST_FLAG.findall(text):
        if value.startswith("/"):
            hosts.append("localhost")  # unix socket path
        elif "://" in value:
            hosts.append(url_host(value))
        elif value.startswith("$"):
            hosts.append(env_host(value))
        else:
            hosts.append(value)
    # A bare `psql "$DATABASE_URL"` style argument.
    for name in DB_VAR.findall(text):
        if re.search(r"(URL|URI|DSN|DATABASE|CONN|PG|MYSQL)", name, re.I):
            hosts.append(env_host("$" + name))
    return hosts


def env_host(reference):
    """Resolve $VAR from the hook's own environment; '?' when unknown."""
    match = DB_VAR.search(reference)
    if not match:
        return "?"
    value = os.environ.get(match.group(1))
    if not value:
        return "?"  # unresolvable means unknown, and unknown means not local
    if "://" in value:
        return url_host(value)
    return value


def is_provably_local(text):
    """True only when every reachable target is demonstrably on this machine."""
    if REMOTE_FLAG.search(text):
        return False
    if LOCAL_FLAG.search(text):
        return True
    hosts = connection_hosts(text)
    if not hosts:
        return False  # no connection info at all: PGHOST could be anything
    return all(LOCAL_HOST.match(h or "?") for h in hosts)


def sql_file_bodies(text, cwd):
    """Contents of .sql files this statement feeds to a client.

    With `psql -f wipe.sql` the dangerous SQL is not in the command string, so
    the guard reads the file. That is legitimate: the hook runs locally as the
    same user, on a file the very next syscall is going to execute anyway, and
    it reads nothing it is not already about to run. Reads are capped at 512KB
    and any failure (missing file, permissions, binary) is skipped silently.
    An unreadable file falls through to the connection-host check, which denies
    anything not provably local.
    """
    bodies = []
    for token in re.findall(r"[^\s;&|<>()\"']+\.sql\b", text):
        path = os.path.expanduser(token)
        if not os.path.isabs(path):
            path = os.path.join(cwd, path)
        try:
            if os.path.getsize(path) > 512 * 1024:
                continue
            with open(path, "r", errors="replace") as fh:
                bodies.append(fh.read())
        except Exception:
            continue
    return bodies


def dangerous_sql(text, sql_only=False):
    """Label of the first destructive construct found, or None.

    sql_only=True means the text is known to be pure SQL (a .sql file), so
    `--` line comments can be stripped. On a shell command line `--` starts a
    flag, not a comment, and stripping it would swallow `--linked`/`--remote`
    along with the statement behind them.
    """
    body = SQL_COMMENTS.sub(" ", text) if sql_only else SQL_BLOCK_COMMENT.sub(" ", text)
    for pattern, label in SQL_RULES:
        if pattern.search(body):
            return label
    for stmt in body.split(";"):
        if SQL_WHERE.search(stmt):
            continue
        if SQL_DELETE.search(stmt):
            return "DELETE FROM with no WHERE clause"
        if SQL_UPDATE.search(stmt):
            return "UPDATE ... SET with no WHERE clause"
    return None


def sql_clients(segment):
    """SQL client label for one simple command, or None."""
    names = command_names(segment)
    for name in names:
        if name in SQL_CLIENTS:
            return name
    bare = [os.path.basename(unquote(t)) for t in segment]
    for phrase in SQL_SUBCOMMANDS:
        span = len(phrase)
        for i in range(len(bare) - span + 1):
            if tuple(bare[i:i + span]) == phrase:
                return " ".join(phrase)
    return None


HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")


def mask_heredoc_bodies(text):
    """Blank heredoc bodies whose receiving command cannot execute them.

    `git commit -F - <<'EOF' ... EOF` carries prose. Scanning that body for
    policy words denies honest commits, and getting denied for writing a commit
    message about the guard is exactly the kind of thing that teaches people to
    route around it.

    A body handed to a shell, to ssh, or to a SQL client is still scanned,
    because there it really is executable. Length is preserved so offsets stay
    valid for the caller.
    """
    if "<<" not in text:
        return text
    out = text
    for m in HEREDOC.finditer(text):
        line_start = text.rfind("\n", 0, m.start()) + 1
        head = text[line_start:m.start()]
        tokens = tokenize(head)
        if tokens is None:
            continue  # cannot tell who owns it; leave the body visible
        executable = False
        for seg in segments(tokens):
            if set(command_names(seg)) & NESTED_SHELLS or sql_clients(seg):
                executable = True
                break
        if executable:
            continue
        end = re.search(r"^[ \t]*%s[ \t]*$" % re.escape(m.group(2)),
                        text[m.end():], re.M)
        stop = m.end() + (end.start() if end else len(text) - m.end())
        out = out[:m.end()] + re.sub(r"[^\n]", "x", out[m.end():stop]) + out[stop:]
    return out


def check_sql(command, cwd):
    """Return (label, detail) for a denied SQL action, or None."""
    texts = command_texts(command)

    for text in texts:
        masked = mask_quoted(mask_heredoc_bodies(text))
        for pattern, label in PRISMA_RULES:
            if pattern.search(masked):
                return label, "reset-shaped, and the target database cannot be read from here"

    for text in texts:
        for stmt in statements(text):
            tokens = tokenize(stmt)
            if tokens is None:
                tokens = stmt.split()
            client = None
            for segment in segments(tokens):
                client = sql_clients(segment) or client
            if not client:
                continue
            local = is_provably_local(stmt)
            if client == "prisma db execute" and not local:
                return ("prisma db execute against a non-local database",
                        "no --url proving localhost")
            hit = dangerous_sql(stmt)
            for body in sql_file_bodies(stmt, cwd):
                hit = hit or dangerous_sql(body, sql_only=True)
            if not hit:
                continue
            if local:
                log("ALLOW", "%s via %s on a local host" % (hit, client), command)
                continue
            return ("%s via %s" % (hit, client),
                    "target is not provably local")
    return None


def log(decision, reason, command):
    try:
        os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
        stamp = time.strftime("%Y-%m-%dT%H:%M:%S%z")
        with open(LOG_PATH, "a") as fh:
            fh.write(f"{stamp}\t{decision}\t{reason}\t{command[:500]}\n")
    except Exception:
        pass


def deny(reason, command, guidance):
    log("DENY", reason, command)
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": guidance,
        }
    }))
    sys.exit(0)


def allow():
    sys.exit(0)


def resolve_targets(command):
    """Best-effort extraction of path-ish arguments from a destructive command."""
    targets = []
    for token in re.findall(r"[^\s;&|<>()\"']+", command):
        if token.startswith("-"):
            continue
        if "/" in token or token.startswith("~") or token.startswith("$"):
            targets.append(token)
    return targets


def classify(target):
    """Return 'protected', 'ephemeral', or 'outside' for one path token."""
    expanded = os.path.expanduser(target.replace("$HOME", HOME))
    expanded = expanded.split("*")[0]  # a glob's fixed prefix is enough to place it
    if not os.path.isabs(expanded):
        expanded = os.path.join(WORKSPACE, expanded)
    normalized = os.path.normpath(expanded)

    if not (normalized == WORKSPACE or normalized.startswith(WORKSPACE + os.sep)):
        return "outside"

    rel = os.path.relpath(normalized, WORKSPACE)
    head = rel.split(os.sep)[0]

    if any(part in EPHEMERAL_DIRS for part in rel.split(os.sep)):
        return "ephemeral"
    if head in PROTECTED_DIRS:
        return "protected"
    if rel == "." or (os.sep not in rel and rel.endswith(".md")):
        return "protected"  # workspace root itself and root-level docs
    return "outside"


def destructive_verb(texts):
    """The delete verb being invoked in command position, or None.

    Checked against parsed command positions first; if a line will not tokenize
    (unbalanced quotes) it falls back to the original regex over the
    quote-masked text, so a malformed line can never parse its way to allowed.
    """
    for text in texts:
        tokens = tokenize(text)
        if tokens is None:
            match = DESTRUCTIVE.search(mask_quoted(text))
            if match:
                return match.group("cmd")
            continue
        for segment in segments(tokens):
            names = command_names(segment)
            for name in names:
                if name in DESTRUCTIVE_VERBS:
                    return name
            # find(1) deletes without ever naming a delete command.
            if "find" in names and any(unquote(t) == "-delete" for t in segment):
                return "find -delete"
    return None


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception as exc:
        log("GUARD-FAILOPEN", f"unreadable hook payload: {exc!r}", "<no command>")
        sys.stderr.write("guard-destructive: unreadable payload, ALLOWED unchecked\n")
        allow()

    if payload.get("tool_name") != "Bash":
        allow()

    command = (payload.get("tool_input") or {}).get("command") or ""
    if not command:
        allow()
    globals()["CURRENT_COMMAND"] = command
    cwd = payload.get("cwd") or os.getcwd()

    texts = command_texts(command)
    # A heredoc body going somewhere that cannot execute it is data, not a
    # command line. See mask_heredoc_bodies.
    inert = [mask_heredoc_bodies(t) for t in texts]

    for pattern, label in CATASTROPHIC:
        # Matched against quote-masked text so that documenting or grepping for
        # one of these strings is not itself an offense, and against every
        # nested command line so `bash -c "..."` is not an escape hatch.
        if any(pattern.search(mask_quoted(t)) for t in inert):
            deny(label, command,
                 f"BLOCKED: {label}. This is never run unless the user asked for it by name. "
                 f"If they did ask, tell them this guard blocked it and have them confirm; "
                 f"do not work around it.")

    sql_hit = check_sql(command, cwd)
    if sql_hit:
        label, detail = sql_hit
        deny(
            f"destructive SQL: {label} ({detail})",
            command,
            f"BLOCKED: {label}. Schema and bulk-data destruction is denied in every security "
            f"posture, including bypassPermissions. There is no flag that turns this off.\n\n"
            f"Why: a reset-shaped migration command once wiped a production database that was "
            f"schema-push managed. There was no migration history to replay and no "
            f"deploy-migrate step, so the reset was a straight wipe, and recovery meant a "
            f"point-in-time restore from the hosting provider.\n\n"
            f"Detail: {detail}. If this really is a local database, prove it in the command "
            f"(-h localhost, a socket path, an explicit local connection URL, or --local) and "
            f"rerun. If it is production, stop and ask the user. Do not work around this guard, "
            f"and say what you were trying to do.",
        )

    verb = destructive_verb(inert)
    if not verb:
        allow()

    targets = resolve_targets(command)
    if not targets:
        allow()

    protected = [t for t in targets if classify(t) == "protected"]
    if not protected:
        log("ALLOW", f"{verb} outside protected trees", command)
        allow()

    deny(
        f"{verb} on protected path(s): {','.join(protected)}",
        command,
        f"BLOCKED: deleting files under {WORKSPACE}/{{{','.join(PROTECTED_DIRS)}}} requires the "
        f"user to explicitly ask for that deletion. A scheduled job once deleted a generated "
        f"file that existed in no backup, and nobody noticed for days.\n\n"
        f"If the user DID ask you to remove this: use `{RECOVERABLE_DELETE} <path>` instead, so "
        f"it can be restored. If they did not ask: do not delete it, do not work around this "
        f"guard, and say what you were trying to do.",
    )


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        # Fail OPEN: a broken guard must never wedge every session on the
        # machine. But say so loudly. GUARD-FAILOPEN is its own log level
        # precisely so that `grep GUARD-FAILOPEN <log>` answers "is the guard
        # actually running?" A silent fail-open is how you discover months
        # later that nothing has been checked.
        detail = traceback.format_exc().replace("\n", " | ")
        log("GUARD-FAILOPEN",
            "guard crashed; command ALLOWED WITHOUT POLICY EVALUATION (this is "
            "not a safety judgement): " + detail,
            CURRENT_COMMAND)
        sys.stderr.write(
            "guard-destructive: CRASHED, command allowed unchecked. "
            "This is a guard failure, not an approval.\n" + traceback.format_exc())
        allow()
