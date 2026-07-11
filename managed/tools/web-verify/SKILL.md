---
name: web-verify
description: Browser-driven smoke test. Drive a real browser through a deployed web app, capture screenshots + console/network errors, return deterministic pass/fail. Use after a deploy to prove the live app actually works (not just returns 200), or to verify a preview URL before merge. The teeth behind the ship-loop smoke step.
---

# web-verify

Runs a real Chromium browser through a **flow spec** against a live or preview URL and
returns pass/fail with screenshot evidence. This is what catches render bugs, broken
auth redirects, dead buttons, and client-side exceptions that a `curl` check sails past.

Lives at `managed/tools/web-verify`. One-time setup: `cd managed/tools/web-verify && npm install`.

## Run a flow

```bash
node managed/tools/web-verify/verify.mjs managed/tools/web-verify/flows/<flow>.json
```

Point it at a preview deploy instead of prod with `--base`:

```bash
node managed/tools/web-verify/verify.mjs flows/<flow>.json --base https://preview.example.com
```

Logged-in flow (reuses a Chrome profile set via `WV_AUTH_PROFILE`):

```bash
WV_AUTH_PROFILE="$HOME/path/to/chrome-profile" node .../verify.mjs flows/<flow>.json --auth
```

If your agent's compute lives on a remote box, run the same command over SSH there.

## Reading the result

- **Exit 0** = pass, **exit 1** = fail. Check `$?`.
- Result JSON prints to stdout and saves to `runs/<name>-<ts>/result.json`.
- Key fields: `ok`, `failures[]`, `pageErrors[]`, `consoleErrors[]`, `networkErrors[]`, `screenshots[]`.
- Screenshots are the evidence — pull the `FAIL-*.png` or `final` frame back to show what the page looked like.

## Adding a flow for an app

Drop a JSON spec in `flows/`. Schema + step reference in `README.md`. Start from
`flows/example-home.json` (public) or `flows/example-login.json` (authed). Keep
assertions on **stable copy or test ids**, not brittle layout selectors. Minimum useful
smoke: `goto` the page, one or two `expectText` on hero copy, a `screenshot`.

## Ship-loop integration

The ship-loop's smoke step should call web-verify against the deployed URL after the
host reports ready:

1. Deploy lands ("Ready").
2. `node verify.mjs flows/<app>.json --base <deployed-url>`
3. Exit 0 → report success + attach the `final` screenshot. Exit 1 → block the "done"
   claim, surface `failures[]` + the `FAIL-*` screenshot.
