# Keeping an install in sync with the kit

Three tools maintain the boundary between the public starter kit and a private
install. They live in `managed/scripts/` and they are plain bash, so there is
nothing to install.

| Tool | Direction | What it does |
|------|-----------|--------------|
| `kit-drift.sh` | reports | says which `managed/` files no longer match the kit, and why |
| `kit-sync.sh` | kit into install | pulls the latest `managed/` without touching `user/` or `layers/` |
| `kit-promote.sh` | install into kit | sends a generic fix back, after scrubbing it for client identifiers |

`kit-layer.sh` is the fourth. It creates and composes the layer that keeps
`managed/` clean in the first place. See [`layers/README.md`](../../layers/README.md).

## The private downstream repo

If you run installs for other people, keep each one in its own private
repository whose `managed/` stays identical to the kit.

Make it with a plain clone. Never use GitHub's Fork button.

```bash
gh repo create <org>/clawd-private --private

git clone --bare https://github.com/jeffweisbein/openclaw-starter-kit kit-seed.git
git -C kit-seed.git push --mirror git@github.com:<org>/clawd-private
rm -rf kit-seed.git

git clone git@github.com:<org>/clawd-private
git -C clawd-private remote add upstream https://github.com/jeffweisbein/openclaw-starter-kit
```

The word "fork" here names the idea, a downstream copy that diverges
deliberately and merges from upstream. It does not mean the button.

A GitHub fork inherits the visibility of the repository it came from, so a fork
of a public repo cannot be made private. A GitHub fork also shares one object
network with its parent, so commits pushed to the fork stay fetchable by SHA
from the public side. Anyone who learns a commit hash can read it. Many
organizations disallow forking private repositories at all.

A plain clone has none of those problems. It costs one thing: the clone is an
ordinary repository, so any CI workflows from upstream run in your own account.
Supply the secrets they need or disable the ones you do not want running.

## Checking for drift

Run this before any support call, and on a schedule if you run more than one
install.

```bash
managed/scripts/kit-drift.sh --workspace ~/clawd
```

It classifies every file under `managed/`:

- **clean** matches the kit
- **locally modified** changed here since the last sync, kit unchanged
- **behind the kit** untouched here, changed upstream
- **conflict** both changed since the last sync
- **new in the kit** added upstream, missing here
- **not in the kit** added to `managed/` locally, which is what a layer is for

The classification needs a baseline, which is the kit's state at the last sync,
recorded at `<workspace>/.kit-baseline` by `kit-sync.sh`.

An install that has never been synced has no such file. In that case both tools
rebuild the baseline from the kit's git history, using the commit that shipped
the version in `managed/VERSION`. That is why a workspace still on v2.4 reads
correctly the first time you run either tool, with no false "you edited this"
on files the kit changed and you did not.

The rebuild needs history, so both tools clone the full repo rather than a
shallow copy. If the version is not in the history, the checker falls back to
reporting "differs" and says so, and the sync keeps every changed file rather
than guessing.

Exit code is 0 when there is no drift and 1 when there is, so it works as a
cron check.

## Pulling the kit forward

```bash
managed/scripts/kit-sync.sh --workspace ~/clawd --dry-run   # see the plan
managed/scripts/kit-sync.sh --workspace ~/clawd             # plan, confirm, write
```

It only ever writes inside `managed/`. It fingerprints `user/` and `layers/`
before and after and aborts loudly if either moved by a byte.

Files you changed locally are kept, not overwritten. Pass `--allow-overwrite`
to replace them anyway; the old copies go to `<workspace>/.kit-backups/<timestamp>/`
either way. Pass `--yes` to skip the prompt during provisioning.

After a sync, recompose your layer:

```bash
managed/scripts/kit-layer.sh apply <org>
```

## Sending a fix back

When a fix in a client install is useful to everyone, promote it. Only files
under `managed/` can travel, and only after the scrub passes.

```bash
managed/scripts/kit-promote.sh \
  --workspace ~/clawd \
  --kit ~/src/openclaw-starter-kit \
  --message "fix(health-check): handle a missing data directory" \
  managed/scripts/health-check.sh
```

The branch is cut from the kit's upstream default branch, not from whatever you
happen to have checked out, so the diff stays small. It commits and stops. It
never pushes and never opens a PR.

### What the scrub checks

Before anything is written it reads the outgoing file contents, the commit
message and the branch name, looking for:

- every org slug, name, domain, alias and repo in any `layers/*/layer.conf`
- every line of any `layers/*/scrub-terms.txt`
- API keys and tokens: Anthropic, OpenAI, GitHub, AWS, Slack, Tailscale, JWTs,
  private key blocks
- email addresses
- home directory paths like `/Users/dana`
- private and tailnet IP addresses
- phone numbers
- any domain that does not already appear in the kit

Anything that already appears verbatim in the public kit is not treated as a
client identifier, because it is already public. Terms from `layers/` get no
such exemption. They always fail.

A hit stops the promotion. Nothing is written and the kit checkout is left
untouched. The report gives file, line, category and the exact matched text.

Binaries are refused by default, because a screenshot cannot be scrubbed by
reading it. Check it by eye and pass `--allow-binary` if it is clean.

If a hit is genuinely not a client identifier, waive that one string with
`--allow '<exact string>'`. Every waiver is printed in the report, so a reviewer
can see what you overrode.

### If the scrub fails

Do not reach for `--allow` first. A failure usually means the change is not
actually generic yet. Rewrite the file so it stands on its own, move the
client-specific half into `layers/<org>/`, and promote what is left.

## Routine

Once a month, or whenever the kit ships a release:

```bash
managed/scripts/kit-drift.sh --workspace ~/clawd     # what moved
managed/scripts/kit-sync.sh  --workspace ~/clawd     # take the update
managed/scripts/kit-layer.sh apply <org>             # recompose
managed/scripts/kit-drift.sh --workspace ~/clawd     # confirm clean
```

Anything still showing as locally modified after that is a decision waiting to
be made: promote it, or move it into the layer.
