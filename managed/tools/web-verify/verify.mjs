#!/usr/bin/env node
// web-verify — drive a real browser through a flow spec and return deterministic pass/fail.
//
// Usage:
//   node verify.mjs <flow.json> [--auth] [--headed] [--out <dir>] [--base <url>] [--json]
//
// A flow spec is JSON:
//   {
//     "name": "home",
//     "baseUrl": "https://example.com",
//     "viewport": { "width": 1280, "height": 800 },   // optional
//     "auth": false,                                    // optional; or pass --auth
//     "steps": [ { "goto": "/" }, { "expectText": "Welcome" }, { "screenshot": "home" } ]
//   }
//
// Supported steps (one key per object):
//   { "goto": "/path" | "https://..." }   navigate (relative resolves against baseUrl)
//   { "click": "selector" }
//   { "fill": ["selector", "value"] }
//   { "press": ["selector", "Enter"] }  or  { "press": "Enter" }
//   { "waitFor": "selector" }             wait until visible
//   { "waitForUrl": "**/dashboard" }      glob match
//   { "expectText": "text" }              body must contain (case-insensitive)
//   { "expectNoText": "text" }            body must NOT contain
//   { "expectSelector": "selector" }      must be visible
//   { "expectUrl": "substr" }             current url must contain
//   { "screenshot": "label" }             full-page screenshot
//   { "scrollTo": "selector" }
//   { "wait": 800 }                       sleep ms
//
// Output: JSON result to stdout. Exit 0 = pass, 1 = fail, 2 = bad usage.
// Screenshots + result.json land in <out>/<name>-<ts>/.

import { chromium } from 'playwright';
import { readFileSync, mkdirSync, writeFileSync, cpSync, rmSync, existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { join, resolve } from 'node:path';

const STEP_TIMEOUT = 15000;      // per-step ceiling
const GLOBAL_BUDGET = 120000;    // whole-run ceiling
const AUTH_PROFILE = process.env.WV_AUTH_PROFILE || join(homedir(), '.agentcookie', 'chrome-profile');
const CREDS_PATH = process.env.WV_CREDS || join(homedir(), '.config', 'openclaw', 'web-verify-creds.json');

// {{secret:app.field}} in any step string pulls from the 0600 creds file at run time.
// The ORIGINAL token (not the resolved value) is what gets recorded in results, so
// credentials never leak into result.json / stdout.
let CREDS = {};
try { CREDS = JSON.parse(readFileSync(CREDS_PATH, 'utf8')); } catch { /* no creds file — secret refs resolve to '' */ }
function secretLookup(path) {
  return path.split('.').reduce((o, k) => (o == null ? o : o[k]), CREDS) ?? '';
}
function resolveSecrets(v) {
  if (typeof v === 'string') return v
    .replace(/\{\{secret:([^}]+)\}\}/g, (_, k) => String(secretLookup(k.trim())))
    .replace(/\{\{env:([^}]+)\}\}/g, (_, k) => String(process.env[k.trim()] ?? ''));
  if (Array.isArray(v)) return v.map(resolveSecrets);
  return v;
}

function parseArgs(argv) {
  const a = { auth: false, headed: false, out: 'runs', base: null, flow: null };
  for (let i = 0; i < argv.length; i++) {
    const v = argv[i];
    if (v === '--auth') a.auth = true;
    else if (v === '--headed') a.headed = true;
    else if (v === '--json') { /* default; kept for clarity */ }
    else if (v === '--out') a.out = argv[++i];
    else if (v === '--base') a.base = argv[++i];
    else if (!a.flow) a.flow = v;
  }
  return a;
}

function ts() {
  // local timestamp, filesystem-safe
  return new Date().toISOString().replace(/[:.]/g, '-');
}

const args = parseArgs(process.argv.slice(2));
if (!args.flow) {
  console.error('usage: node verify.mjs <flow.json> [--auth] [--headed] [--out dir] [--base url]');
  process.exit(2);
}

let flow;
try {
  flow = JSON.parse(readFileSync(args.flow, 'utf8'));
} catch (e) {
  console.error(`cannot read flow spec ${args.flow}: ${e.message}`);
  process.exit(2);
}

const baseUrl = (args.base || flow.baseUrl || '').replace(/\/$/, '');
const useAuth = args.auth || !!flow.auth;
const outDir = join(resolve(args.out), `${flow.name || 'flow'}-${ts()}`);
mkdirSync(outDir, { recursive: true });

const result = {
  name: flow.name || 'flow',
  baseUrl,
  auth: useAuth,
  ok: false,
  startedAt: new Date().toISOString(),
  finalUrl: null,
  durationMs: 0,
  stepsRun: 0,
  stepsTotal: (flow.steps || []).length,
  failures: [],
  consoleErrors: [],
  pageErrors: [],
  networkErrors: [],
  screenshots: [],
  outDir,
};

function resolveUrl(u) {
  if (/^https?:\/\//i.test(u)) return u;
  if (!baseUrl) throw new Error(`relative goto "${u}" but no baseUrl set`);
  return baseUrl + (u.startsWith('/') ? u : '/' + u);
}

async function shot(page, label) {
  const file = join(outDir, `${String(result.screenshots.length + 1).padStart(2, '0')}-${label.replace(/[^\w.-]+/g, '_')}.png`);
  try {
    await page.screenshot({ path: file, fullPage: true });
    result.screenshots.push(file);
  } catch (e) {
    // a screenshot failure shouldn't sink the run; note it
    result.failures.push({ step: 'screenshot', label, error: e.message });
  }
  return file;
}

const started = Date.now();
let tmpProfile = null;
let browser = null;
let context = null;

try {
  const launchOpts = { headless: !args.headed };

  if (useAuth) {
    // Reuse a logged-in Chrome user-data-dir (set WV_AUTH_PROFILE; defaults to an
    // agentcookie-style profile), on a copy so we never fight the live profile's
    // SingletonLock or mutate real cookies.
    if (!existsSync(AUTH_PROFILE)) throw new Error(`--auth set but no profile at ${AUTH_PROFILE}`);
    tmpProfile = join('/tmp', `wv-profile-${ts()}`);
    cpSync(AUTH_PROFILE, tmpProfile, { recursive: true, filter: (s) => !/SingletonLock|SingletonCookie|SingletonSocket/.test(s) });
    context = await chromium.launchPersistentContext(tmpProfile, launchOpts);
  } else {
    browser = await chromium.launch(launchOpts);
    context = await browser.newContext(
      flow.viewport ? { viewport: flow.viewport } : {}
    );
  }
  context.setDefaultTimeout(STEP_TIMEOUT);

  const page = context.pages()[0] || (await context.newPage());
  if (flow.viewport) await page.setViewportSize(flow.viewport).catch(() => {});

  // Evidence collectors — the stuff a curl smoke test can never see.
  page.on('console', (msg) => {
    if (msg.type() === 'error') result.consoleErrors.push(msg.text().slice(0, 500));
  });
  page.on('pageerror', (err) => result.pageErrors.push(String(err).slice(0, 500)));
  page.on('response', (r) => {
    const s = r.status();
    if (s >= 400) result.networkErrors.push({ status: s, url: r.url().slice(0, 300) });
  });
  page.on('requestfailed', (req) => {
    result.networkErrors.push({ status: 'failed', url: req.url().slice(0, 300), reason: req.failure()?.errorText });
  });

  for (const step of flow.steps || []) {
    if (Date.now() - started > GLOBAL_BUDGET) throw new Error('global time budget exceeded');
    const [op, val] = Object.entries(step)[0];
    const rval = resolveSecrets(val); // secrets applied to the action only, never recorded
    try {
      switch (op) {
        case 'goto':
          await page.goto(resolveUrl(rval), { waitUntil: 'domcontentloaded', timeout: STEP_TIMEOUT });
          await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
          break;
        case 'click': await page.click(rval); break;
        case 'fill': await page.fill(rval[0], rval[1]); break;
        case 'press':
          if (Array.isArray(rval)) await page.press(rval[0], rval[1]);
          else await page.keyboard.press(rval);
          break;
        case 'waitFor': await page.waitForSelector(rval, { state: 'visible' }); break;
        case 'waitForUrl': await page.waitForURL(rval); break;
        case 'expectText': {
          const body = (await page.textContent('body')) || '';
          if (!body.toLowerCase().includes(String(rval).toLowerCase()))
            throw new Error(`page does not contain text "${val}"`);
          break;
        }
        case 'expectNoText': {
          const body = (await page.textContent('body')) || '';
          if (body.toLowerCase().includes(String(rval).toLowerCase()))
            throw new Error(`page unexpectedly contains text "${val}"`);
          break;
        }
        case 'expectSelector': await page.waitForSelector(rval, { state: 'visible' }); break;
        case 'expectUrl':
          if (!page.url().includes(rval)) throw new Error(`url "${page.url()}" does not contain "${val}"`);
          break;
        case 'screenshot': await shot(page, String(rval || 'shot')); break;
        case 'scrollTo': await page.locator(rval).scrollIntoViewIfNeeded(); break;
        case 'wait': await page.waitForTimeout(Number(rval) || 0); break;
        default: throw new Error(`unknown step "${op}"`);
      }
      result.stepsRun++;
    } catch (e) {
      result.failures.push({ step: op, value: val, error: e.message });
      await shot(page, `FAIL-${op}`);
      break; // stop on first failure — deterministic
    }
  }

  // Always capture a final frame + landing URL as evidence.
  result.finalUrl = page.url();
  await shot(page, 'final');

  // Pass = every step ran, no hard failures, no uncaught page errors.
  result.ok = result.failures.length === 0 && result.stepsRun === result.stepsTotal && result.pageErrors.length === 0;
} catch (e) {
  result.failures.push({ step: 'fatal', error: e.message });
} finally {
  result.durationMs = Date.now() - started;
  try { if (context) await context.close(); } catch {}
  try { if (browser) await browser.close(); } catch {}
  if (tmpProfile) { try { rmSync(tmpProfile, { recursive: true, force: true }); } catch {} }
  writeFileSync(join(outDir, 'result.json'), JSON.stringify(result, null, 2));
  console.log(JSON.stringify(result, null, 2));
  process.exit(result.ok ? 0 : 1);
}
