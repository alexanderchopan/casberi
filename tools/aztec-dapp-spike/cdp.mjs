// Drives a headless Chrome over the DevTools protocol: injects dist/inject.js
// before any page script (what a WKUserScript at documentStart does on iOS),
// opens an Aztec app, and runs steps from the command line.
//
//   node cdp.mjs <url> [step ...]
//   steps: wait:<ms> | click:<visible text> | shot:<name> | log | dom
//
// Screenshots land in $OUT (default: ./out). Nothing is signed: the injected
// wallet is read-only (web/inject.js).
import { spawn } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const [url, ...steps] = process.argv.slice(2);
const out = process.env.OUT ?? join(here, 'out');
mkdirSync(out, { recursive: true });
const script = readFileSync(join(here, 'dist/inject.js'), 'utf8');
const profile = mkdtempSync(join(tmpdir(), 'casberi-cdp-'));
const port = 9300 + Math.floor(Math.random() * 500);
const chrome = spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', [
  '--headless=new', `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`,
  '--no-first-run', '--no-default-browser-check', '--window-size=1280,900', 'about:blank',
], { stdio: 'ignore' });
const cleanup = () => { try { chrome.kill('SIGKILL'); } catch {} try { rmSync(profile, { recursive: true, force: true }); } catch {} };
process.on('exit', cleanup);

const sleep = ms => new Promise(r => setTimeout(r, ms));
let target;
for (let i = 0; i < 50 && !target; i++) {
  await sleep(200);
  try { target = (await (await fetch(`http://127.0.0.1:${port}/json`)).json()).find(t => t.type === 'page'); } catch {}
}
if (!target) { console.error('chrome did not start'); process.exit(1); }

const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise(r => ws.addEventListener('open', r, { once: true }));
let id = 0; const pending = new Map();
ws.addEventListener('message', ev => {
  const m = JSON.parse(ev.data);
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
  if (m.method === 'Runtime.exceptionThrown') {
    const d = m.params.exceptionDetails;
    console.log('exception:', (d.exception?.description ?? d.text).slice(0, 900));
  }
  if (m.method === 'Runtime.consoleAPICalled') {
    const text = m.params.args.map(a => a.value ?? a.description ?? '').join(' ');
    if (text.includes('[casberi]') || text.includes('[dapp]') || text.includes('[engine]') || m.params.type === 'error') console.log('console:', text.slice(0, 900));
  }
});
const send = (method, params = {}) => new Promise(r => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
const evaluate = async expr => (await send('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true })).result?.result?.value;

await send('Page.enable');
await send('Runtime.enable');
if (process.env.NO_INJECT !== '1') await send('Page.addScriptToEvaluateOnNewDocument', { source: script });
await send('Page.navigate', { url });
await sleep(6000);

for (const step of steps) {
  const [kind, ...rest] = step.split(':');
  const arg = rest.join(':');
  if (kind === 'wait') await sleep(Number(arg));
  if (kind === 'shot') {
    const { result } = await send('Page.captureScreenshot', { format: 'png' });
    writeFileSync(join(out, `${arg}.png`), Buffer.from(result.data, 'base64'));
    console.log('shot:', join(out, `${arg}.png`));
  }
  if (kind === 'click') {
    const hit = await evaluate(`(() => {
      const want = ${JSON.stringify(arg)}.toLowerCase();
      const els = [...document.querySelectorAll('button, a, [role=button], div, span, li')]
        .filter(e => e.offsetParent !== null && (e.innerText || '').trim().toLowerCase() === want);
      const el = els.at(-1) ?? [...document.querySelectorAll('button, a, [role=button]')]
        .find(e => e.offsetParent !== null && (e.innerText || '').toLowerCase().includes(want));
      if (!el) return 'not found';
      el.scrollIntoView({ block: 'center' }); el.click(); return el.tagName + ' ' + (el.innerText || '').trim().slice(0, 60);
    })()`);
    console.log(`click ${arg}:`, hit);
    await sleep(2500);
  }
  if (kind === 'xy') {
    const [x, y] = arg.split(',').map(Number);
    for (const type of ['mousePressed', 'mouseReleased']) {
      await send('Input.dispatchMouseEvent', { type, x, y, button: 'left', clickCount: 1 });
    }
    console.log(`xy ${arg}`);
    await sleep(2500);
  }
  if (kind === 'eval') {
    const r = await send('Runtime.evaluate', { expression: `(async () => { try { return JSON.stringify(await (${arg})); } catch (e) { return 'THREW ' + (e?.stack ?? e); } })()`, awaitPromise: true, returnByValue: true });
    console.log('eval:', String(r.result?.result?.value ?? JSON.stringify(r.result)).slice(0, 6000));
  }
  if (kind === 'log') console.log('log:', JSON.stringify(await evaluate('window.__casberiLog ?? null'), null, 1)?.slice(0, 8000));
  if (kind === 'dom') console.log('buttons:', await evaluate(`[...document.querySelectorAll('button,[role=button],a')].filter(e=>e.offsetParent!==null).map(e=>(e.innerText||e.getAttribute('aria-label')||'').trim().replace(/\\s+/g,' ')).filter(Boolean).slice(0,60).join(' | ')`));
}
ws.close();
cleanup();
process.exit(0);
