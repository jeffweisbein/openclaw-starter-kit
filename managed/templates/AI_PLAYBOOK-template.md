# <product> AI Playbook

<!-- Copy this file to your repo root as AI_PLAYBOOK.md and fill it in. -->
<!-- Delete this header comment once you're done. -->
<!-- The goal: give an AI agent ground truth about this specific product's shape, risks, and verification steps — so it stops cross-repo guessing. -->

## Product

One or two sentences on what the product does and what reliability actually means here. Call out the top 2–3 risk categories (auth, billing, ingestion, correctness, etc.) rather than listing features.

## Stack

- Framework: (e.g. Next.js app router, FastAPI, Rails)
- Auth: (e.g. Clerk, Auth0, Supabase Auth, custom)
- Data: (e.g. Postgres via Prisma, Supabase, DynamoDB)
- Mobile / native shell (if any)
- External providers / integrations that matter

## Core Commands

- dev: `npm run dev` (or your equivalent)
- build: `npm run build`
- lint: `npm run lint`
- test: `npm run test`
- public smoke: `npm run smoke:web` (see `scripts/smoke-web.sh`)
- pre-deploy checks: `npm run pre-deploy` (if applicable)

## The Rules

1. Plan first for any non-trivial change.
2. Call out high-risk areas before touching them (see below).
3. Every integration / provider change needs a verification loop.
4. Verify production behavior, not just local code paths.
5. Document new gotchas immediately.

## Highest-Risk Areas

List the subsystems where a bad change has outsized blast radius. Common examples:

- Auth, organization membership, permissions
- Billing and upgrade flows
- Search / ingestion / background jobs
- Provider response normalization
- Mobile shell when web routes or auth flows change

## Known Gotchas

Things an agent will get wrong if it doesn't know them. Keep the list short and high-value. Examples:

- Credits or quota issues can look like app bugs.
- Provider payloads can change shape and break fast paths.
- Background-job persistence gaps create endless polling or missing result states.
- API failures can surface as generic client parse errors if the route never returns valid JSON.

## Required Verification Before Shipping

- Run `npm run lint` and `npm run build` locally.
- Run the public smoke script against your production URL.
- For auth / billing / search changes, manually walk the flow in production.
- Confirm no new console errors on the main user paths.

## Incidents

Log incident patterns here as you hit them. One line per entry: what happened, what fixed it, rule to prevent recurrence.
