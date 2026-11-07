// SPIKE: the web-view run of src/core.js. As in the app's Privacy Pools page
// (tools/privacy-pools-engine/src/net.js), every request to the outside goes
// through the host, here the spike's local server (`/net`), never straight
// from the page; results go to `/log`. The database is IndexedDB (level-js).
import { Buffer } from 'buffer';
globalThis.Buffer ??= Buffer;
globalThis.process ??= { env: {}, version: 'v20.0.0', versions: {}, nextTick: (f, ...a) => queueMicrotask(() => f(...a)), browser: true };

const pageFetch = globalThis.fetch.bind(globalThis);
const hosts = new Set();
globalThis.fetch = async (input, init = {}) => {
  const request = input instanceof Request ? input : null;
  const url = request ? request.url : String(input);
  if (url.startsWith(location.origin) || url.startsWith('/')) return pageFetch(input, init);
  hosts.add(new URL(url).host);
  const method = (init.method ?? request?.method ?? 'GET').toUpperCase();
  const headers = {}; new Headers(init.headers ?? request?.headers ?? {}).forEach((v, k) => { headers[k] = v; });
  let body = init.body ?? (request && method !== 'GET' ? await request.arrayBuffer() : null);
  if (body instanceof Uint8Array || body instanceof ArrayBuffer) body = new TextDecoder().decode(body);
  const res = await pageFetch('/net', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ url, method, headers, body }) });
  const status = Number(res.headers.get('x-status') ?? 502);
  return new Response(status === 204 || status === 304 ? null : await res.arrayBuffer(), { status, headers: { 'content-type': res.headers.get('x-content-type') ?? 'application/octet-stream' } });
};

const post = (o) => pageFetch('/log', { method: 'POST', body: JSON.stringify(o, (k, v) => (k === 'transaction' ? undefined : typeof v === 'bigint' ? String(v) : v)) }).catch(() => {});
const log = (step, f) => { post({ step, ...f }); document.body.insertAdjacentText('beforeend', `${step} ${JSON.stringify(f, (k, v) => (k === 'transaction' ? undefined : typeof v === 'bigint' ? String(v) : v))}\n`); };
globalThis.addEventListener('error', (e) => post({ step: 'pageError', error: String(e.message) }));
globalThis.addEventListener('unhandledrejection', (e) => post({ step: 'pageRejection', error: String(e.reason?.message ?? e.reason).slice(0, 400) }));

(async () => {
  try {
    post({ step: 'page', ua: navigator.userAgent });
    const { spike, ArtifactStore } = await import('./core.js');
    const leveljs = (await import('level-js')).default;
    const keys = await (await pageFetch('/keys')).json();
    const artifacts = new Map();
    const store = new ArtifactStore(async (p) => artifacts.get(p) ?? null, async (d, p, item) => { artifacts.set(p, item); }, async (p) => artifacts.has(p));
    const q = new URLSearchParams(location.search);
    const db = q.get('db') === 'mem' ? (await import('memdown')).default() : leveljs(`railgun-spike-${Date.now()}`);
    log('db', { kind: q.get('db') === 'mem' ? 'memory' : 'indexeddb' });
    await spike({ db, artifactStore: store, mnemonic: keys.mnemonic, encryptionKey: keys.encryptionKey, log, network: q.get('net') ?? 'Ethereum_Sepolia', syncCapMs: Number(q.get('cap') ?? 600000),
      startBlock: q.get('start') ? Number(q.get('start')) : undefined, txidStartTree: q.get('txid') ? Number(q.get('txid')) : undefined });
    post({ step: 'hosts', hosts: [...hosts].sort(), mem: performance.memory?.usedJSHeapSize ?? null });
  } catch (e) {
    post({ step: 'failed', error: String(e?.stack ?? e).slice(0, 800) });
  }
})();
