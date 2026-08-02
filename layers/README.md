# Layers

This directory is where one organization's own material lives. In the public
starter kit it holds nothing but this file, and it stays that way.

## Why layers exist

The kit already splits `managed/` from `user/`. That split answers "who owns
this file". It does not answer "where does a customization go that is neither
infrastructure nor personality", and until now the honest answer was "edit
`managed/` and hope the next update does not clobber it".

A layer is that missing third place. Everything specific to your organization
goes in `layers/<org>/`, so `managed/` can stay byte-identical to the kit. That
is the whole trick. Identical files merge silently. Edited files have to be
reconciled by hand, forever, on every update.

## The three trees

| Tree | Who owns it | Travels upstream | Purpose |
|------|-------------|------------------|---------|
| `managed/` | the starter kit | yes, via `kit-promote.sh` | infrastructure, scripts, operating rules |
| `user/` | you | never | personality, memory, custom rules |
| `layers/<org>/` | you | never | everything specific to your org |

## Shape of a layer

Create one with `managed/scripts/kit-layer.sh init <org-slug>`. Generate it
rather than hand-building it, so the `.gitignore` comes with it.

```text
layers/<org>/
  layer.conf         the manifest: slug, name, domains, aliases, repos
  scrub-terms.txt    words that must never reach the public kit
  .env.example       secret names, never values
  .env               local secret values, gitignored
  .gitignore         scaffolded, keeps .env and state out of git
  README.md          operator runbook for this org
  agents/            agent definitions built for this org
  skills/            skills built for this org
  scripts/           automation for this org's stack
  playbooks/         per-repo playbooks and runbooks
  ops/               policy and reaction overrides
```

`layer.conf` is plain `key=value` on purpose. No JSON parser, no new
dependency, and every value in it feeds the scrub check described below.

## What belongs in a layer

Anything that names or serves one client:

- agent definitions written for their stack
- skills that call their APIs
- deploy, backup and monitoring scripts pointed at their hosts
- per-repo playbooks
- policy overrides, because their auto-approve rules differ from the default

## What must never diverge

Everything under `managed/`. That is the contract. If you find yourself editing
a file in `managed/`, one of two things is true:

1. The change is generic and everyone benefits. Send it up with
   `managed/scripts/kit-promote.sh` and take it back on the next sync.
2. The change is specific to this client. It belongs in a layer.

`managed/scripts/kit-drift.sh` tells you when this rule has quietly broken.

## How a layer composes

`kit-layer.sh apply <org>` copies each subdirectory to its position at the
workspace root:

```text
layers/<org>/agents/     ->  <workspace>/agents/
layers/<org>/skills/     ->  <workspace>/skills/
layers/<org>/scripts/    ->  <workspace>/scripts/
layers/<org>/playbooks/  ->  <workspace>/playbooks/
layers/<org>/ops/        ->  <workspace>/ops/
```

`managed/` is the base library and the composed copy at the workspace root is
what actually runs. Where a layer defines something the kit also ships, the
layer wins, because the layer's copy is the one in the running position.

Three rules make this safe:

- **A layer never writes inside `managed/`.** Apply refuses and exits.
- **A layer never overwrites an existing `user/` file** without `--force`.
- **Overrides replace, they do not merge.** If you need one different rule in
  `ops/policies.json`, copy the whole file into the layer and edit your copy.
  Nothing has to parse or merge JSON, which is why this stays predictable.

Run `apply` after every change to the layer, and after every `kit-sync.sh`.
`kit-layer.sh check <org>` tells you whether the composed copies are current.

## The rule

Nothing under `layers/` reaches the public kit: not the config, not the
scripts, not the infrastructure coordinates, and not the names of the systems
or people inside them. `kit-promote.sh` refuses any path under `layers/` or
`user/` outright, and reads every layer's `layer.conf` and `scrub-terms.txt` to
block those names appearing anywhere in an outgoing change.

Secrets never enter git at all, here or anywhere else. They belong in a secret
store, with local values only in the gitignored `.env`.
