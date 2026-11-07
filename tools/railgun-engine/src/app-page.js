// SPIKE: the phone run of src/core.js, inside Casberi's web view (a DEBUG
// probe, `-railgunSpike YES`). Every outside request goes to Swift
// (`railgunNet`), as the Privacy Pools engine's does; every line goes to Swift
// (`railgunLog`). A fresh random wallet each run: the sync is what is measured,
// so no money and no phrase leave the Mac.
import { Buffer } from 'buffer';
globalThis.Buffer ??= Buffer;
globalThis.process ??= { env: {}, version: 'v20.0.0', versions: {}, nextTick: (f, ...a) => queueMicrotask(() => f(...a)), browser: true };

const pageFetch = globalThis.fetch.bind(globalThis);
globalThis.fetch = async (input, init = {}) => {
  const request = input instanceof Request ? input : null;
  const url = request ? request.url : String(input);
  if (!/^https:/.test(url)) return pageFetch(input, init);
  const method = (init.method ?? request?.method ?? 'GET').toUpperCase();
  const headers = {}; new Headers(init.headers ?? request?.headers ?? {}).forEach((v, k) => { headers[k] = v; });
  let body = init.body ?? (request && method !== 'GET' ? await request.arrayBuffer() : null);
  if (body instanceof Uint8Array || body instanceof ArrayBuffer) body = new TextDecoder().decode(body);
  let reply;
  try { reply = await globalThis.webkit.messageHandlers.railgunNet.postMessage({ url, method, headers, body }); }
  catch (e) { throw new TypeError(`Failed to fetch (${String(e?.message ?? e)})`); }
  const bytes = Uint8Array.from(atob(reply.body64 ?? ''), (c) => c.charCodeAt(0));
  return new Response([101, 204, 205, 304].includes(reply.status) ? null : bytes, { status: reply.status, headers: { 'content-type': reply.type ?? 'application/octet-stream' } });
};

const t0 = performance.now();
const say = (o) => { try { globalThis.webkit.messageHandlers.railgunLog.postMessage(JSON.stringify({ s: Math.round((performance.now() - t0) / 1000), ...o }, (k, v) => (k === 'transaction' ? undefined : typeof v === 'bigint' ? String(v) : v))); } catch {} };
const log = (step, f) => { if (step !== 'engineLog' || /error|incomplete|invalid/i.test(JSON.stringify(f))) say({ step, ...f }); };
globalThis.addEventListener('error', (e) => say({ step: 'pageError', error: String(e.message) }));
globalThis.addEventListener('unhandledrejection', (e) => say({ step: 'pageRejection', error: String(e.reason?.message ?? e.reason).slice(0, 400) }));
const beat = setInterval(() => say({ step: 'alive' }), 15000);

(async () => {
  try {
    say({ step: 'page', ua: navigator.userAgent });
    const { spike, ArtifactStore } = await import('./core.js');
    const { Wallet, hexlify, randomBytes } = await import('ethers');
    const memdown = (await import('memdown')).default;
    const artifacts = new Map();
    const store = new ArtifactStore(async (p) => artifacts.get(p) ?? null, async (d, p, item) => { artifacts.set(p, item); }, async (p) => artifacts.has(p));
    await spike({
      db: memdown(), artifactStore: store, mnemonic: Wallet.createRandom().mnemonic.phrase, encryptionKey: hexlify(randomBytes(32)).slice(2), log,
      network: 'Ethereum', syncCapMs: 1_200_000, startBlock: 25849756, txidStartTree: 2,
      then: async () => ({ synced: true }),
    });
    say({ step: 'done' });
  } catch (e) {
    say({ step: 'failed', error: String(e?.stack ?? e).slice(0, 800) });
  } finally { clearInterval(beat); }
})();
