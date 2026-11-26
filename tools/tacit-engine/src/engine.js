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
import { secp, keccak_256, sha256, hexToBytes, bytesToHex } from '../vendor/dapp/vendor/tacit-deps.min.js';
// Tacit's DeFi pool, its private pool on Ethereum: Tacit's own pool library
// (vendor/dapp/confidential-pool-ux.js, MIT), for its `balance` read ONLY.
// It is where a Tacit-chain deposit the chain does not take goes back to.
import { makeConfidentialPoolUx } from '../vendor/dapp/confidential-pool-ux.js';
import { setActiveNetwork } from '../vendor/dapp/confidential-deployments.js';
import { poseidon2, poseidon3, poseidon4, poseidon5 } from '../vendor/dapp/vendor/tacit-poseidon.min.js';
// Making TAC private (prd §1971 item 20): Tacit's own chain client proves a
// deposit with Tacit's own prover on this phone, and hands it, with the
// permit your co-signer signs, to the Tacit chain's leader. The engine never
// signs and never sends a transaction: the permit is the wallet's, checked
// by the app before it is asked for (`TacitShield`).
import { makeChainClient } from '../vendor/dapp/tacit-chain-client.js';
import { makeTacitAddress } from '../vendor/dapp/tacit-address.js';
import { makeHalo2System } from '../vendor/dapp/btc-pool-halo2-prover.js';
import pin from '../vendor/dapp/btc-pool/pin.json';

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
let pool = null;
// The chain client for a deposit, and the one deposit being made: proved,
// waiting for the co-signer's permit. Both go with `close`.
let client = null;
let pending = null;
// The return path's next free slot, asked for as soon as a deposit is
// quoted: reading it takes about a minute, the proof about ten seconds.
let backIndex = null;
// The DeFi read in flight. Its pass of the pool holds every Wrap log, so the
// return path's slot waits for it and reads only what came after; asked at
// once, the two passes read the whole pool twice through Tor, and on a phone
// the second never ended (user, 2026-11-25: "just stays on this screen
// forever spinning").
let defiRead = null;
let outPending = null;
// The pool's PUBLIC logs, kept by the app between launches (the page keeps
// nothing: its store is non-persistent), so a read fetches only the blocks
// after the last one. Tacit's library checks what it is handed against the
// chain's trees and drops a store that does not add up. No key, note or memo
// passes through here.
const logStore = (() => {
  const h = globalThis.webkit?.messageHandlers?.engineLogs;
  if (!h) return null;
  const ask = async (m) => { const r = await h.postMessage(JSON.stringify(m)); return r ? JSON.parse(r) : undefined; };
  return {
    get: (key) => ask({ op: 'get', key }).catch(() => undefined),
    put: (key, value) => ask({ op: 'put', key, value }),
    del: (key) => ask({ op: 'del', key }),
  };
})();
function forget() { identity?.fill(0); identity = null; client = null; pending = null; backIndex = null; defiRead = null; outPending = null; }

function poolUx() {
  setActiveNetwork('mainnet');
  return (pool ||= makeConfidentialPoolUx({ secp, keccak256: keccak_256, sha256, network: 'mainnet', logStore }));
}

function nextBackIndex() {
  if (!backIndex) {
    const key = Uint8Array.from(identity);
    const warm = defiRead ? defiRead.catch(() => {}) : Promise.resolve();
    backIndex = warm.then(() => poolUx().nextWrapIndex({ walletPriv: key, ticker: 'TAC' })).finally(() => key.fill(0));
    backIndex.catch(() => { backIndex = null; });
  }
  return backIndex;
}

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
  // `from` and `known` resume a scan where the last one stopped: the notes it
  // found, kept by the app on this phone, and the next entry to try. Each
  // known note is asked again whether it is spent.
  async chain({ rpcUrl, blocks, leader, from = 0, known = [] }) {
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
    }, { from: Number(from) || 0, keep: false, known: (known || []).map((n) => ({ index: Number(n.index), value: BigInt(n.value), s: hexToBytes(strip(n.s)), leaf: BigInt(n.leaf) })) });
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
      next: Number(found.next),
      kept: found.notes.map((n) => ({ index: n.index, value: hex(n.value), s: '0x' + bytesToHex(n.s), leaf: hex(n.leaf) })),
      chainAddress: w.encodeAddress(w.address(k)),
      leaves: Number(found.next), pool: hex(rate.pool), allShares: hex(rate.shares), elsewhere,
      ms: Math.round(now() - t),
    };
  },

  // Your private TAC in Tacit's DeFi pool (cTAC), as Tacit's own page reads
  // it: the pool's notes tried with your key, in passes until the library
  // says it has read them all. 8 decimals, as on the Tacit chain.
  async defi() {
    if (!identity) throw Object.assign(new Error('the account is not open'), { name: 'NotOpen' });
    const read = readDefi();
    defiRead = read;
    try { return await read; } finally { if (defiRead === read) defiRead = null; }
  },


  // What a deposit of `units` (TAC, 8 decimals) costs and lands as now.
  async shieldQuote({ rpcUrl, blocks, leader, units }) {
    const c = await chainClient({ rpcUrl, blocks, leader });
    nextBackIndex();
    const q = await c.quote('shield', BigInt(units));
    return { fee: hex(q.fee), arrives: hex(q.arrives), cap: q.cap == null ? null : hex(q.cap), sweepFee: hex(q.sweepFee ?? 0n) };
  },

  // Proves a deposit of `units` on this phone and works out where it goes:
  // the inbox the permit names, and the return path ("back") a deposit the
  // chain does not take is given back to, in Tacit's DeFi pool under your
  // key. Nothing leaves the phone but reads.
  async shieldProve({ rpcUrl, blocks, leader, units }) {
    if (!identity) throw Object.assign(new Error('the account is not open'), { name: 'NotOpen' });
    const c = await chainClient({ rpcUrl, blocks, leader });
    const t = now();
    const s = await c.shield(BigInt(units));
    const proveMs = Math.round(now() - t);
    const index = await nextBackIndex();
    backIndex = null;
    const key = Uint8Array.from(identity);
    let back;
    try {
      back = '0x' + strip(poolUx().buildWrap({ walletPriv: key, amountWei: (BigInt(units) * 10n ** 10n).toString(), ticker: 'TAC', index }).commit).toLowerCase();
    } finally { key.fill(0); }
    const inbox = await s.inbox(back);
    const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600);
    const sweepFee = BigInt(s.sweepFee ?? 0n);
    pending = { s, back, inbox, deadline, sweepFee, units: BigInt(units) };
    return {
      inbox, back, index, deadline: Number(deadline), value: hex(s.permitValue(sweepFee)), sweepFee: hex(sweepFee),
      fee: hex(s.fee ?? 0n), shares: hex(s.deposit.shares), units: hex(BigInt(units)), proveMs,
      // The deposit's own words, so the app can ask the chain itself which
      // inbox they make before the permit names it.
      deposit: { shares: hex(s.deposit.shares), amount: hex(s.deposit.amount), cx: s.deposit.cx, cy: s.deposit.cy, body: s.deposit.body },
    };
  },

  // Hands the proved deposit to the leader with your co-signer's permit.
  // The leader sweeps exactly the permit's value into the inbox and puts
  // the deposit in a block; `kept` is what to ask again with if it is lost.
  async shieldHand({ owner, v, r, s: sig }) {
    if (!pending) throw Object.assign(new Error('nothing is proved'), { name: 'NothingProved' });
    const p = pending;
    const permit = { owner: String(owner).toLowerCase(), fee: String(p.sweepFee), deadline: String(p.deadline), v: Number(v), r, s: sig, back: p.back };
    const { id, kept } = await p.s.offer({ back: p.back, permit, meta: { inbox: p.inbox, src: 'casberi' } });
    pending = null;
    return { id, kept: JSON.stringify(kept) };
  },

  // The same hand-off with no permit, for TAC your Casberi account pays
  // into the inbox itself: the leader holds the deposit until the inbox is
  // funded, then puts it in a block. Asked BEFORE the account pays, so a
  // refusal costs nothing.
  async shieldOffer() {
    if (!pending) throw Object.assign(new Error('nothing is proved'), { name: 'NothingProved' });
    const p = pending;
    const { id, kept } = await p.s.offer({ back: p.back, meta: { inbox: p.inbox, src: 'casberi-account' } });
    pending = null;
    return { id, kept: JSON.stringify(kept) };
  },

  // BACK TO PUBLIC (prd §1977). Your private TAC on the Tacit chain, out to
  // an Ethereum address: proved on this phone with the Tacit key, handed to
  // the leader, and once it lands in a block the address is OWED it on
  // Tacit's contract, which anyone may pay out with `withdraw(address)`.
  // No wallet signs: the proof is the spend.
  //
  // What a withdrawal of `units` costs now, and the most that can go, after
  // the account's notes are read (the client keeps its own, in memory).
  async outQuote({ rpcUrl, blocks, leader, units }) {
    const c = await chainClient({ rpcUrl, blocks, leader });
    await c.scan();
    const q = await c.quote('withdraw', BigInt(units || 0));
    return { fee: hex(q.fee), holders: hex(q.holders ?? 0n), most: hex(q.most ?? 0n) };
  },

  // Proves the withdrawal of `units` to `to`; nothing leaves the phone.
  async outProve({ rpcUrl, blocks, leader, to, units }) {
    const c = await chainClient({ rpcUrl, blocks, leader });
    const t = now();
    outPending = await c.prepareWithdraw(String(to), BigInt(units));
    return { proveMs: Math.round(now() - t) };
  },

  // Hands the proved withdrawal to the leader; answers once it is queued
  // (the client keeps watching it land on its own).
  async outHand() {
    if (!outPending || !client) throw Object.assign(new Error('nothing is proved'), { name: 'NothingProved' });
    const p = outPending;
    outPending = null;
    return await new Promise((resolve, reject) => {
      let told = false;
      client.send(p, { onStatus: (st) => {
        if (!told && st && st.status === 'queued') { told = true; resolve({ id: String(st.id), kept: JSON.stringify(st.kept ?? null, (_, v) => (typeof v === 'bigint' ? v.toString() : v)) }); }
      } }).catch((e) => { if (!told) { told = true; reject(e); } });
    });
  },

  // SEND PRIVATELY (prd §1982). Private TAC on the Tacit chain to another
  // Tacit account: its chain address (`tc1…`) or its whole Tacit address
  // (`tacit1…`, whose chain lane names it). Proved with the Tacit key, handed
  // to the leader like a withdrawal (`outHand`), and nothing to collect: the
  // note is theirs once a block takes it.
  async payQuote({ rpcUrl, blocks, leader, units }) {
    const c = await chainClient({ rpcUrl, blocks, leader });
    await c.scan();
    const q = await c.quote('pay', BigInt(units || 0));
    return { fee: hex(q.fee), holders: hex(q.holders ?? 0n), most: hex(q.most ?? 0n) };
  },

  async payProve({ rpcUrl, blocks, leader, to, units }) {
    const c = await chainClient({ rpcUrl, blocks, leader });
    const recipient = await payRecipient(c, String(to).trim());
    const t = now();
    outPending = await c.preparePay(recipient, BigInt(units));
    return { proveMs: Math.round(now() - t) };
  },

  // Whether `to` names a Tacit account this send can reach, and its chain
  // lane's address, without proving anything.
  async payCheck({ rpcUrl, blocks, leader, to }) {
    const c = await chainClient({ rpcUrl, blocks, leader });
    await payRecipient(c, String(to).trim());
    return {};
  },

  // TAC Tacit's contract owes `address`, in wei, waiting for `withdraw`.
  async owed({ rpcUrl, blocks, leader, address }) {
    const c = await chainClient({ rpcUrl, blocks, leader });
    return { wei: hex(await c.owed(String(address))) };
  },

  // A handed deposit's state at the leader: queued, landed or refused.
  async shieldStatus({ leader, id }) {
    const r = await fetch(leader.replace(/\/$/, '') + '/receipt/' + encodeURIComponent(id));
    const j = await r.json().catch(() => ({}));
    return { ok: r.ok, http: r.status, status: j.status ?? null, error: j.error ?? null, height: Number.isSafeInteger(j.height) ? j.height : null };
  },

  async close() {
    for (const w of wallets.values()) w.terminate();
    wallets = new Map();
    nodes = new Map();
    forget();
    return {};
  },
};

// Tacit's chain client, made once per open account. Its prover loads its
// wasm, parameters and key from the app's own scheme; the key is checked
// against Tacit's pinned hash before it proves anything.
async function chainClient({ rpcUrl, blocks, leader }) {
  if (!identity) throw Object.assign(new Error('the account is not open'), { name: 'NotOpen' });
  if (client) return client;
  const bytes = async (name) => new Uint8Array(await (await fetch('casberi-tacit://engine/btc-pool/' + name)).arrayBuffer());
  const system = () => makeHalo2System({ wasm: () => bytes(pin.wasm), params: () => bytes(pin.params), vk: () => bytes(pin.vk), pinnedVkHash: pin.vk_hash, worker: null });
  const rpcCall = async (method, params) => {
    const r = await fetch(rpcUrl, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params }) });
    const j = await r.json();
    if (j.error) throw new Error(j.error.message || 'rpc error');
    return j.result;
  };
  const mem = new Map();
  const storage = { getItem: (k) => mem.get(k) ?? null, setItem: (k, v) => mem.set(k, String(v)), removeItem: (k) => mem.delete(k) };
  client = makeChainClient({ cfg: { blocks, leader }, rpcCall, priv: Uint8Array.from(identity), system, storage });
  return client;
}

// The DeFi read itself (`defi`), in passes until the library says it has
// read the whole pool.
async function readDefi() {
  const t = now();
  setActiveNetwork('mainnet');
  pool ||= makeConfidentialPoolUx({ secp, keccak256: keccak_256, sha256, network: 'mainnet', logStore });
  const key = Uint8Array.from(identity);
  try {
    let r = await pool.balance(key, { spent: true, positions: false, recent: 150 });
    let passes = 1;
    while (r.reading && passes < 6) { r = await pool.balance(key, { spent: true, positions: false, recent: 0 }); passes++; }
    const id = String(pool.assetByTicker.cTAC?.assetId || '').toLowerCase();
    const held = id ? r.byAsset?.[id] : null;
    return {
      worth: hex(held ? held.value : 0n), notes: held?.notes?.length ?? 0, leaves: Number(r.leafCount ?? 0),
      whole: !r.reading, errors: Object.keys(r.diag?.errors || {}), passes, ms: Math.round(now() - t),
    };
  } finally { key.fill(0); }
}

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

// A Tacit address as the chain client's recipient: a chain address decoded
// as it stands, a whole Tacit address through its chain lane (the key's
// record first, then the leader's directory, as Tacit's own payer asks).
async function payRecipient(c, to) {
  if (/^tc1[0-9a-f]+$/i.test(to)) {
    const w = makeChainWallet({ poseidon, prover: null, chain: '0x' + '0'.repeat(64), asset: 0n });
    return w.decodeAddress(to.toLowerCase());
  }
  if (/^tacit1[02-9ac-hj-np-z]+$/i.test(to)) {
    const d = makeTacitAddress({ secp }).decodeTacitAddress(to.toLowerCase());
    if (!d.lanes.chain && !d.lanes.evm && !d.lanes.btc) throw Object.assign(new Error('that Tacit address has no chain lane'), { name: 'BadAddress' });
    return await c.recipientOf(d.lanes);
  }
  throw Object.assign(new Error('not a Tacit address'), { name: 'BadAddress' });
}
