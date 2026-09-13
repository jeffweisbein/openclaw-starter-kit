# Backups: scope, failure and restoration

## Selected workspace files in a private Git repository

`auto-backup.sh` no longer runs blanket `git add -A`. Copy `backup.example.json` from
`managed/ops/` to `ops/backup.json`, choose explicit regular files, and review the
remote's private visibility, access and **entire existing Git history** before setting
`reviewedPrivateRemote` to true. This is an operator assertion, not an API visibility
check. A push transfers repository history, not just selected files. Prefer a dedicated
private backup repository. Never use the public starter-kit remote for personal data.

Hidden files, key files, live databases, directories, symlinks and parent traversal are
refused. Filename checks cannot detect secrets inside an ordinary Markdown file: review
content and access policy. No credentials belong in command arguments or config values;
use the host credential helper. The helper intentionally withholds Git error details.

```bash
managed/scripts/auto-backup.sh --workspace /path/to/private-workspace
```

Existing staged work causes refusal. Selected edits are committed; a push failure
returns nonzero and does not refresh `state/last-backup.json`. Re-running retries the
push even if the commit already exists. A commit failure can leave selected files staged;
inspect them locally before retrying. Serialize with interactive Git use: the helper lock
only excludes other helper runs, not arbitrary Git clients. Deletions must be reviewed
and committed manually; a missing selected file is an error, not an automatic delete.

A successful unchanged run pushes/reconciles and refreshes the receipt. This does not
back up databases, schedules, plugin state or unselected files.

## SQLite and runtime recovery

Prefer the installed runtime's native backup command for its databases and state.
For an ordinary supported SQLite database, this supplemental helper uses SQLite's backup
API (including committed WAL data), integrity checks and a disposable restore:

```bash
python3 managed/scripts/reliability.py sqlite-snapshot \
  --source /path/to/state.sqlite \
  --destination /path/to/private-backups/new-snapshot.sqlite
```

It refuses overwrites and never restores over the live source. Output files are private
(mode 0600). The result includes a SHA-256 digest. It does not make multiple databases
transactionally consistent, validate encrypted/vendor-specific databases, or prove the
application can boot from the backup. Large or busy databases may take time; configure
job timeouts using measured duration. Run an application-level restore in an isolated
instance before describing a backup as full disaster recovery.

Store backups outside synced/public directories. Use an existing encrypted off-host
backup destination with an explicit retention policy; local copies alone do not protect
against machine loss. Inventory all databases before snapshotting. If a plugin creates
a database during backup, rediscover and rerun rather than accepting a partial archive.
No automatic deletion or off-host upload is enabled by this kit.
