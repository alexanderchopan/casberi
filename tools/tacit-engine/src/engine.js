// The Tacit engine: Tacit's own standalone private-ETH wallet
// (vendor/tacit-evm-pool-wallet.js, MIT), opened VIEW-ONLY.
//
// It is given no provider, so it has nothing to send with: `open` derives the
// account from a 32-byte key, `read` finds its notes on one network and adds
// them up. The prove worker (snarkjs) is never started, because nothing here
// proves. Making money private, sending and taking out are not built.
import './net.js';
import { makeEvmPoolWallet, CHAINS, POOL, ROUTER } from '../vendor/tacit-evm-pool-wallet.js';
// The Tacit chain, where private TAC is held as shares of one pool: Tacit's
// own chain wallet (vendor/dapp/, MIT), for its key derivation and its note
// scan ONLY. It is given no prover, so it cannot spend; nothing here calls
// `spend`, `publish` or `makeNote`.
import { makeChainWallet, worthOf } from '../vendor/dapp/tacit-chain-wallet.js';
import { chainSeed } from '../vendor/dapp/tacit-chain-lane.js';
import { secp, keccak_256, hexToBytes, bytesToHex } from '../vendor/dapp/vendor/tacit-deps.min.js';
import { poseidon2, poseidon3, poseidon4, poseidon5 } from '../vendor/dapp/vendor/tacit-poseidon.min.js';

const POSEIDON = { 2: poseidon2, 3: poseidon3, 4: poseidon4, 5: poseidon5 };
const poseidon = (xs) => POSEIDON[xs.length](xs);
const strip = (h) => String(h ?? '').replace(/^0x/, '');

const now = () => performance.now();
const hex = (n) => '0x' + BigInt(n).toString(16);

// One wallet per network, all from the one key. The key is held only inside
// Tacit's wallet objects, and goes when the page does (`close`, or the app
// dropping the web view).
let wallets = new Map();
let nodes = new Map();
// The key, for the chain read: the chain's keys are made from it
// (`chainSeed`). Zeroed and dropped by `close`.
let identity = null;
function forget() { identity?.fill(0); identity = null; }

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
    forget();
    identity = hexToBytes(key.slice(2));
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

  // Your private TAC on the Tacit chain. `blocks` is the chain's contract on
  // Ethereum, read at `rpcUrl`; `leader` is Tacit's server for the chain's
  // notes. Every note's memo is tried with your key, and a note counts only
  // if the leaf it opens to is the leaf the leader listed. The notes are
  // SHARES of one pool; `worth` is what they are worth in TAC (8 decimals) at
  // the pool's rate, read from the contract.
  //
  // The leader is believed for which notes exist and which are spent: this
  // read does not rebuild the chain's note tree to check it. A read, so a
  // lying leader could show a wrong figure and could move nothing.
  async chain({ rpcUrl, blocks, leader }) {
    if (!identity) throw Object.assign(new Error('the account is not open'), { name: 'NotOpen' });
    if (!/^0x[0-9a-fA-F]{40}$/.test(blocks ?? '') || !/^https:\/\//.test(leader ?? '')) throw Object.assign(new Error('the chain is not named'), { name: 'BadChain' });
    const t = now();
    const selector = (sig) => bytesToHex(keccak_256(new TextEncoder().encode(sig))).slice(0, 8);
    const call = async (sig) => {
      const r = await fetch(rpcUrl, { method: 'POST', headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'eth_call', params: [{ to: blocks, data: '0x' + selector(sig) }, 'latest'] }) });
      const j = await r.json();
      if (typeof j.result !== 'string' || strip(j.result).length !== 64) throw Object.assign(new Error(`the chain's contract did not answer ${sig}`), { name: 'ChainRead' });
      return strip(j.result);
    };
    const [chain, asset, pool, shares] = [await call('CHAIN()'), await call('TAC_ASSET()'), await call('pool()'), await call('shares()')];
    const w = makeChainWallet({ poseidon, prover: null, chain: '0x' + chain, asset: BigInt('0x' + asset) });
    const get = async (path) => {
      const r = await fetch(leader.replace(/\/$/, '') + path);
      if (!r.ok) throw Object.assign(new Error(`the leader answered ${r.status} for ${path.split('?')[0]}`), { name: 'Leader' });
      return r.json();
    };
    const seed = chainSeed(identity);
    let k;
    try { k = w.keys(seed); } finally { seed.fill(0); }
    // No `state` on this object, so the wallet records no tree and asks
    // `spent` for each note of yours.
    const found = await w.scan(k, {
      notes: (from, limit) => get(`/notes?from=${from}&limit=${limit}`),
      spent: async (nullifier) => (await get(`/spent/${nullifier}`)).spent === true,
    }, { from: 0, keep: false });
    const held = found.notes.reduce((a, n) => a + BigInt(n.value), 0n);
    const rate = { pool: BigInt('0x' + pool), shares: BigInt('0x' + shares) };
    // A PQ ID: the key's own record names another chain address, whose notes
    // are under a root this page does not hold. Said, never guessed at.
    let elsewhere = false;
    try {
      const record = await get(`/address/key/${bytesToHex(secp.getPublicKey(identity, true))}`);
      if (record?.address && 'tc1' + strip(record.address) !== w.encodeAddress(w.address(k))) elsewhere = true;
    } catch {}
    return {
      shares: hex(held), worth: hex(worthOf(held, rate)), notes: found.notes.length, spent: found.spent.length,
      leaves: Number(found.next), pool: hex(rate.pool), allShares: hex(rate.shares), elsewhere,
      ms: Math.round(now() - t),
    };
  },

  async close() {
    for (const w of wallets.values()) w.terminate();
    wallets = new Map();
    nodes = new Map();
    forget();
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
