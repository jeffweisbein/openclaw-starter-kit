# web-verify

Browser-driven verify loop. Drives a real Chromium browser through a **flow spec**,
captures screenshots + console/page/network errors, and returns a **deterministic
pass/fail** (exit 0/1).

This is the browser-level upgrade to a `curl` smoke test. A `curl` check confirms the
server returned 200; web-verify confirms the *page actually works* — it catches render
failures, broken auth redirects, dead buttons, and client-side JS exceptions that a
status-code check sails right past.

## Install

```bash
cd managed/tools/web-verify
npm install          # installs playwright + chromium (postinstall)
```

Run it wherever your agent has compute — locally or on a remote build box.

## Run

```bash
node verify.mjs flows/example-home.json                              # public smoke test
node verify.mjs flows/example-home.json --base https://preview.example.com   # test a preview deploy
node verify.mjs flows/example-login.json --auth                     # logged-in flow
node verify.mjs flows/example-home.json --headed                    # watch it run (debug)
```

Exit code: `0` pass, `1` fail, `2` bad usage. Full result JSON prints to stdout and is
saved to `runs/<name>-<ts>/result.json` alongside the screenshots.

## Flow spec

```json
{
  "name": "home",
  "baseUrl": "https://example.com",
  "viewport": { "width": 1280, "height": 800 },
  "auth": false,
  "steps": [
    { "goto": "/" },
    { "expectText": "Welcome" },
    { "click": "text=Sign in" },
    { "waitForUrl": "**/login" },
    { "screenshot": "login" }
  ]
}
```

### Steps
| step | meaning |
|---|---|
| `{ "goto": "/path" }` | navigate (relative resolves against baseUrl) |
| `{ "click": "selector" }` | click |
| `{ "fill": ["selector","value"] }` | type into a field |
| `{ "press": ["selector","Enter"] }` or `{ "press": "Enter" }` | key press |
| `{ "waitFor": "selector" }` | wait until visible |
| `{ "waitForUrl": "**/dashboard" }` | wait for URL (glob) |
| `{ "expectText": "text" }` | body must contain (case-insensitive) |
| `{ "expectNoText": "text" }` | body must NOT contain |
| `{ "expectSelector": "selector" }` | must be visible |
| `{ "expectUrl": "substr" }` | current URL contains |
| `{ "screenshot": "label" }` | full-page screenshot |
| `{ "scrollTo": "selector" }` | scroll element into view |
| `{ "wait": 800 }` | sleep ms |

## Auth (logged-in flows)

`--auth` (or `"auth": true` in the spec) launches Chromium on a **copy** of a logged-in
Chrome user-data-dir, so it inherits real sessions without fighting the live profile
lock or mutating cookies. Public flows use a clean context.

Point it at your profile with the `WV_AUTH_PROFILE` env var:

```bash
WV_AUTH_PROFILE="$HOME/Library/Application Support/Google/Chrome/Default" \
  node verify.mjs flows/example-login.json --auth
```

For CI-grade repeatability, prefer scripting the login into the flow with a dedicated
test account rather than relying on a synced session (sessions expire; some cookies are
`httpOnly` and don't carry over).

## Secrets

Any step string can reference a secret with `{{secret:app.field}}` or an env var with
`{{env:VAR}}`. Secrets resolve from a `0600` JSON file (default
`~/.config/openclaw/web-verify-creds.json`, override with `WV_CREDS`):

```json
{ "example": { "email": "test@your-app.example", "password": "..." } }
```

The **original** token — not the resolved value — is what gets recorded in
`result.json` / stdout, so credentials never leak into evidence.

## Pass rule

`ok = true` only when: every step ran, no step failed, and no uncaught page
(client-side JS) errors fired. Console errors and 4xx/5xx network responses are recorded
as evidence but don't auto-fail (they're often third-party noise — analytics, prefetch);
assert on them explicitly in a step when they matter.

## Ship-loop integration

Call web-verify as the smoke step *after* a deploy reports ready:

1. Deploy lands (host reports "Ready").
2. `node verify.mjs flows/<app>.json --base <deployed-url>`
3. Exit 0 → report success + attach the `final` screenshot as proof. Exit 1 → block the
   "done" claim and surface `failures[]` + the `FAIL-*` screenshot.

Keep assertions on **stable copy or test ids**, not brittle layout selectors. A minimum
useful smoke test is: `goto` the page, one or two `expectText` on hero copy, a
`screenshot`.
