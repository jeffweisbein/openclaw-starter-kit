# Compatibility and activation

## Kit versus runtime

v2.6 is a workspace-template release. It does not bundle a patched OpenClaw core,
Codex harness or Cast build. Runtime features must be checked on the installed version;
no blanket "2026.4.18+ supports everything" claim is made.

| Component | Requirement / limit |
|---|---|
| Reliability and selected-file backup helpers | Python 3.9+ standard library; macOS/Linux (`fcntl`); Git for Git backup |
| Existing Apple sandbox script | Apple `container` 1.0+, macOS 26; opt-in |
| Optional isolation inspector | Existing Docker-compatible container, explicit Docker context, POSIX shell and `mktemp` inside it; no daemon installation |
| Hook integration | Claude Code harness loading the configured hook events and matching tool names; not protection for every backend |
| Scheduler integration | Installed supported automation API/CLI; map output to the documented normalized schema |
| Proof enforcement | Runtime-supported completion gate; receipt checker alone is not enforcement |
| Compaction / child delivery / exact final dedupe | Runtime and harness capability; verify through disposable sessions after upgrades |
| SQLite recovery | Ordinary SQLite readable by system Python; use native runtime backups for application-specific state |

The project tests use temporary files, local bare Git remotes and disposable SQLite
copies. They do not connect to accounts or install a gateway. Container-policy tests use
fixtures; a physical host still requires the actual inspector and a routed-agent test.
Python 3.9+ is the language requirement, not a claim every OS/Python combination was tested.

## Fresh installation

1. Keep the existing `managed/`, `user/` and `layers/<org>/` ownership split. Never copy
   someone else's `user/` or organization data into your install.
2. Configure the private memory root (`MEMORY.md` guide); run `memory-check` and inspect
   the actual runtime's indexing roots. Starter-kit setup must not create a second root
   just because an existing install uses a different layout.
3. Run the fixture tests below. Configure one outcome-monitored job and one delivery
   owner; verify one real delivery before enabling a fleet of scheduled tasks.
4. Configure backups explicitly. Test a disposable restore before claiming recovery.
5. Add isolation only for a dedicated worker; verify effective restrictions and actual
   agent routing. Do not apply a no-network policy to the personal assistant blindly.
6. Use the runtime's current onboarding and credential UI. The legacy bootstrap and
   provisioning scripts are historical conveniences, not certified against every new
   runtime. Inspect them before use; do not pipe an installer directly into a shell or
   provide secret values as command arguments. Do not run them over an existing gateway
   to adopt v2.6; template sync is sufficient.

## Upgrading from v2.5

1. Back up your workspace and keep the existing `.kit-baseline`.
2. In a separate kit checkout, inspect `kit-drift.sh` and the sync plan:

   ```bash
   managed/scripts/kit-sync.sh --workspace /path/to/workspace --kit /path/to/kit --dry-run
   managed/scripts/kit-sync.sh --workspace /path/to/workspace --kit /path/to/kit
   ```

3. The public `user/MEMORY.md` seed is corrected for fresh installs only. Existing
   user files are never synced; review any old "every conversation" wording in your
   own index manually and keep it private. Review preserved local edits. Sync changes only `managed/`, preserving `user/` and
   `layers/`; new opt-in settings are copied manually into `ops/`. Do not use blanket
   `rsync` over locally customized managed files.
4. **Backup behavior changes intentionally:** scheduled calls to `auto-backup.sh` now
   fail until `ops/backup.json` is reviewed/configured. Prepare that file before the next
   scheduled run, then verify a successful push and receipt. Do not bypass this with
   `reviewedPrivateRemote=true` unless remote visibility and history were actually checked.
5. Reconcile legacy memory paths manually; update automation payloads using the supported
   scheduler interface. Preserve their timing, delivery and unrelated configuration.
6. No runtime restart, new schedule, public message or user-data migration happens merely
   by syncing the kit. Hooks already loaded by a running harness may require a new session.

## Verify the update

```bash
python3 managed/scripts/tests/test_guard_destructive.py
python3 managed/scripts/tests/test_screen_external.py
python3 managed/scripts/tests/test_reliability.py
```

The upgrade test starts from v2.5 in Git history and verifies user files, organization
files and local managed edits survive sync, and that replacements have backups. Run from
an ordinary Git clone with history (a source ZIP cannot provide that historical fixture).

See `RELIABILITY.md` for live acceptance checks and runtime rollback. Scripts and prompts
cannot guarantee zero failures, prevent all prompt injection or replace access controls.

## Optional GitHub Actions

`managed/templates/fixtures-workflow.yml` runs the fixture suites on Ubuntu with
Python 3.9 and 3.12. A repository administrator with workflow permission can copy it to
`.github/workflows/test.yml`. It is a template, not installed CI. Public-repository
standard runners are generally free; verify billing before enabling it on private repos.
