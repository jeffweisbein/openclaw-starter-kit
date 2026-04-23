# Shipping an AI Playbook per repo

When your agent works across multiple repos, a per-repo `AI_PLAYBOOK.md` gives it ground truth about that product's shape, risks, and verification steps. This beats cross-repo guessing and cuts down on whole classes of "I touched the wrong thing" incidents.

## What goes in it

- **Product** — what it does, what reliability means here
- **Stack** — framework, auth, data, providers (brief)
- **Core commands** — dev, build, lint, test, smoke
- **The rules** — plan first, verify, document gotchas
- **Highest-risk areas** — where a bad change has outsized blast radius
- **Known gotchas** — things that will be got wrong without context
- **Required verification** — what to run before shipping
- **Incidents** — rolling log of what happened and how to prevent recurrence

See `managed/templates/AI_PLAYBOOK-template.md` for a starting skeleton.

## Smoke script

Every web-facing repo should have a `scripts/smoke-web.sh` (or equivalent) your agent can run to verify production is alive after a deploy. It should:

- Hit the top user-facing pages and `robots.txt` / `sitemap.xml`
- Fail loud on non-200 or on a body that looks like a runtime error
- Optionally verify the Vercel / Fly / hosting alias is current

See `managed/templates/smoke-web.sh.template`.

## Rollout pattern

For each repo:

1. Copy `AI_PLAYBOOK-template.md` to the repo root as `AI_PLAYBOOK.md` and fill in real stack, risk areas, and gotchas.
2. Copy `smoke-web.sh.template` to `scripts/smoke-web.sh` and edit the `BASE_URL` default and `PAGES` array.
3. Add `"smoke:web": "bash scripts/smoke-web.sh"` to `package.json` (or your equivalent).
4. Point your agent's per-repo rules at `AI_PLAYBOOK.md` so it's loaded into context when working in that repo.
5. When you hit a new incident, add a one-line entry under `## Incidents` in the playbook.

## Why these two files specifically

The playbook gives the agent *prior knowledge* so it doesn't rediscover architecture by grep every session. The smoke script gives the agent *posterior verification* so it can confirm a change didn't break production. Together they turn "trust me" deploys into "verified" deploys, and every new incident makes the next one less likely.
