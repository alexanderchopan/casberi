// The Tacit engine: Tacit's own standalone private-ETH wallet
// (vendor/tacit-evm-pool-wallet.js, MIT), opened VIEW-ONLY.
//
// It is given no provider, so it has nothing to send with: `open` derives the
// account from a 32-byte key, `read` finds its notes on one network and adds
// them up. The prove worker (snarkjs) is never started, because nothing here
// proves. Making money private, sending and taking out are not built.
import './net.js';
import { makeEvmPoolWallet, CHAINS, POOL, ROUTER } from '../vendor/tacit-evm-pool-wallet.js';

const now = () => performance.now();
const hex = (n) => '0x' + BigInt(n).toString(16);

// One wallet per network, all from the one key. The key is held only inside
// Tacit's wallet objects, and goes when the page does (`close`, or the app
// dropping the web view).
let wallets = new Map();
let nodes = new Map();

function wallet(chainId) {
  const w = wallets.get(Number(chainId));
  if (!w) throw Object.assign(new Error(`network ${chainId} is not open`), { name: 'NotOpen' });
  return w;
}

const methods = {
  async info() {
    return { pool: POOL, router: ROUTER, chains: Object.keys(CHAINS).map(Number) };
  },

  // `networks`: [{ chainId, rpcUrl, relayUrl }]. `relayUrl` is Tacit's history
  // feed for that network; the wallet keeps a page of it only if the tree it
  // builds is one the pool itself has held, so the feed is checked, not trusted.
  async open({ key, networks }) {
    if (!/^0x[0-9a-fA-F]{64}$/.test(key ?? '')) throw Object.assign(new Error('the key must be 32 bytes'), { name: 'BadKey' });
    for (const w of wallets.values()) w.terminate();
    wallets = new Map();
    nodes = new Map();
    const opened = [];
    for (const n of networks ?? []) {
      const chainId = Number(n.chainId);
      if (!Object.hasOwn(CHAINS, chainId)) throw Object.assign(new Error(`Tacit has no pool on network ${chainId}`), { name: 'UnknownNetwork' });
      const t = now();
      const w = await makeEvmPoolWallet({ chainId, identityKey: key, rpc: n.rpcUrl, relay: n.relayUrl ?? null });
      wallets.set(chainId, w);
      nodes.set(chainId, n.rpcUrl);
      opened.push({ chainId, address: String(w.address), receive: String(w.receive.address), ms: Math.round(now() - t) });
    }
    // One key, one address: every network answers with the same one.
    return { address: opened[0]?.address ?? null, networks: opened };
  },

  // Your notes on one network, from the pool's own history.
  async read({ chainId }) {
    const w = wallet(chainId);
    const t = now();
    const s = await w.sync();
    const notes = (w.notes() ?? []).length;
    let waiting = 0n;
    try { waiting = BigInt(await w.receive.waiting()); } catch {}
    // What the whole pool holds on this network: how much there is to hide
    // among. One public read of the pool's own balance; it names no one.
    let pool = null;
    try {
      const r = await fetch(nodes.get(Number(chainId)), { method: 'POST', headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'eth_getBalance', params: [POOL, 'latest'] }) });
      const j = await r.json();
      if (typeof j.result === 'string') pool = hex(BigInt(j.result));
    } catch {}
    return {
      chainId: Number(chainId), balance: hex(s.balance ?? 0n), waiting: hex(waiting), pool, notes,
      leaves: Number(s.leaves ?? 0), block: Number(s.block ?? 0), behind: Number(s.behind ?? 0),
      ms: Math.round(now() - t),
    };
  },

  async close() {
    for (const w of wallets.values()) w.terminate();
    wallets = new Map();
    nodes = new Map();
    return {};
  },
};

const bigintSafe = (_, v) => (typeof v === 'bigint' ? hex(v) : v);
globalThis.casberiEngine = {
  async call(method, paramsJSON) {
    try {
      const fn = Object.hasOwn(methods, method) ? methods[method] : null;
      if (!fn) throw Object.assign(new Error(`no method ${method}`), { name: 'UnknownMethod' });
      const value = await fn(paramsJSON ? JSON.parse(paramsJSON) : {});
      return JSON.stringify({ ok: true, value }, bigintSafe);
    } catch (error) {
      return JSON.stringify({ ok: false, error: { name: String(error?.name ?? 'Error'), message: String(error?.message ?? error).slice(0, 600) } });
    }
  },
};
try { globalThis.webkit.messageHandlers.engineLog.postMessage('ready'); } catch {}
