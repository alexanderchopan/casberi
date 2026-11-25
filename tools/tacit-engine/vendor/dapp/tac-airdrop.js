
import { bodyType } from './rpc-body.js';

export const AIRDROP_DEPLOYMENTS = Object.freeze({
  1: Object.freeze({
    address: '0x4b4cb98D0C836c2783Ac46f0078b904dab533AE8',
    root: '0x27451b320d5aa9631f7a3fd8adcfa537db8d792dd49aad9ab0951af0c2986a10',
    deadline: 1797803449,
    token: '0xA1313eb9f3A445606D9583bcAc3ebeB56a858279',
    decimals: 18,
    unitScale: '10000000000',
    pool: '0x000000000Ed1eabD231Be41d93b719056F7febFC',
    assetId: '0xf0bbe868af10c6c67652a99709bf32048d1aa7194efe3e9a1ef1bde43f94762b',
  }),
});

const PROOFS_COMMIT = '1b2eedde8490801c9ef4406020530059162e6d47';
export const PROOF_HOSTS = Object.freeze({
  sameOrigin: '/airdrop/v1/proofs',
  cdn: `https://cdn.jsdelivr.net/gh/src-company/tacit@${PROOFS_COMMIT}/dapp/airdrop/v1/proofs`,
  mirror: `https://raw.githubusercontent.com/src-company/tacit/${PROOFS_COMMIT}/dapp/airdrop/v1/proofs`,
});
export const PUBLIC_PROOF_HOSTS = Object.freeze([PROOF_HOSTS.cdn, PROOF_HOSTS.mirror]);

export const MULTICALL3 = '0xcA11bde05977b3631167028862bE2a173976CA11';

const SEL = {
  claim: '2e7ba6ef',
  claimTo: '4f54d47c',
  claimAndShield: 'ad8b9781',
  isClaimed: '9e34070f',
  verify: '6cc1a533',
  paused: '5c975abb',
  balanceOf: '70a08231',
  depositStatus: '7da9874f',
  aggregate3: '82ad56cb',
  blockTimestamp: '0f28c97d',
};

const REVERTS = {
  '9e87fac8': 'paused',
  'f0f25a33': 'closed',
  '646cf558': 'claimed',
  '7ca55c77': 'bad-proof',
  '67a2cc26': 'bad-recipient',
  '9c63840c': 'not-aligned',
  '09bf2e90': 'zero-commit',
};

const REASON = {
  'not-deployed': 'The TAC airdrop is not deployed on this network.',
  'not-listed': 'This address is not in the airdrop.',
  claimed: 'This allocation has already been claimed.',
  paused: 'Claims are paused.',
  closed: 'The claim window has closed.',
  unfunded: 'The airdrop contract does not hold enough TAC to pay this claim.',
  'bad-recipient': 'The TAC cannot be sent to that address.',
  'not-aligned': 'This amount has sub-unit dust, so it cannot be shielded. Claim it as public TAC instead.',
  'bad-proof': 'The airdrop contract does not accept this proof.',
  'zero-commit': 'The shield commit is empty.',
  'bad-commit': 'The shield commit must be a 32-byte hex value.',
};

export class AirdropError extends Error {
  constructor(code, message, extra = {}) {
    super(message);
    this.name = 'AirdropError';
    this.code = code;
    Object.assign(this, extra);
  }
}

const enc = new TextEncoder();
const hexOf = (u8) => Array.from(u8, (x) => x.toString(16).padStart(2, '0')).join('');
const bytesOf = (hex) => Uint8Array.from((String(hex).replace(/^0x/, '').match(/../g) || []).map((h) => parseInt(h, 16)));
const cat = (a, b) => { const o = new Uint8Array(a.length + b.length); o.set(a); o.set(b, a.length); return o; };
const strip = (h) => String(h).replace(/^0x/, '').toLowerCase();
const lc = (a) => String(a == null ? '' : a).toLowerCase();
const word = (n) => BigInt(n).toString(16).padStart(64, '0');
const addrWord = (a) => strip(a).padStart(64, '0');
const padTo32 = (hex) => hex + '0'.repeat((64 - (hex.length % 64)) % 64);
const ADDR = /^0x[0-9a-fA-F]{40}$/;
const B32 = /^0x[0-9a-fA-F]{64}$/;
const isZero32 = (h) => /^0x0{64}$/i.test(h);
const timeoutSignal = (ms) => (typeof AbortSignal !== 'undefined' && typeof AbortSignal.timeout === 'function' ? AbortSignal.timeout(ms) : undefined);

export function formatTac(wei, decimals = 18) {
  const v = BigInt(wei);
  if (v < 0n) throw new RangeError('formatTac: negative amount');
  const s = v.toString().padStart(decimals + 1, '0');
  const cut = s.length - decimals;
  const frac = s.slice(cut).replace(/0+$/, '');
  return frac ? `${s.slice(0, cut)}.${frac}` : s.slice(0, cut);
}

export function makeRpcCall({ rpcs, fetchImpl, timeoutMs = 10000 } = {}) {
  const list = (Array.isArray(rpcs) ? rpcs : [rpcs]).filter(Boolean);
  const f = fetchImpl || (typeof fetch === 'function' ? fetch.bind(globalThis) : null);
  return async function call({ to, data, from }) {
    if (!f) throw new AirdropError('rpc', 'no fetch implementation');
    if (!list.length) throw new AirdropError('rpc', 'no RPC endpoint configured');
    const tx = { to: lc(to), data };
    if (from) tx.from = lc(from);
    const body = JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'eth_call', params: [tx, 'latest'] });
    let lastErr = null;
    for (const url of list) {
      try {
        const r = await f(url, { method: 'POST', headers: { 'content-type': bodyType(url) }, body, signal: timeoutSignal(timeoutMs) });
        if (!r.ok) { lastErr = new Error(`rpc ${r.status}`); continue; }
        const j = await r.json();
        if (j && j.error) {
          const d = j.error.data;
          if (j.error.code === 3 || (typeof d === 'string' && /^0x/i.test(d))) {
            throw Object.assign(new Error(j.error.message || 'execution reverted'), { code: 3, data: typeof d === 'string' ? d : null });
          }
          lastErr = new Error(j.error.message || 'rpc error');
          continue;
        }
        return j ? j.result : '0x';
      } catch (e) {
        if (e && e.code === 3) throw e;
        lastErr = e;
      }
    }
    throw new AirdropError('rpc', `could not reach Ethereum (${(lastErr && lastErr.message) || 'all endpoints failed'})`);
  };
}

const isRevert = (e) => !!e && (e.code === 3 || e.name === 'CallRevert' || (typeof e.data === 'string' && /^0x/i.test(e.data)) || /revert/i.test(e.message || ''));

const proofTail = (proof) => word(proof.length) + proof.map(strip).join('');

function encAggregate3(calls) {
  const elems = calls.map(({ to, data }) => addrWord(to) + word(0) + word(0x60) + word(strip(data).length / 2) + padTo32(strip(data)));
  let off = calls.length * 32;
  const offs = elems.map((e) => { const o = word(off); off += e.length / 2; return o; });
  return '0x' + SEL.aggregate3 + word(0x20) + word(calls.length) + offs.join('') + elems.join('');
}

function decAggregate3(out) {
  const h = strip(out);
  const bad = () => new AirdropError('bad-response', 'Unexpected reply from the node.');
  const at = (i) => { if (h.length < 64 * (i + 1)) throw bad(); return Number(BigInt('0x' + h.slice(64 * i, 64 * (i + 1)))); };
  const arr = at(0) / 32;
  const n = at(arr);
  const res = [];
  for (let i = 0; i < n; i++) {
    const e = arr + 1 + at(arr + 1 + i) / 32;
    if (at(e) !== 1) throw bad();
    const b = e + at(e + 1) / 32;
    const len = at(b);
    const data = h.slice(64 * (b + 1), 64 * (b + 1) + len * 2);
    if (data.length !== len * 2) throw bad();
    res.push('0x' + data);
  }
  return res;
}

const wordOf = (out, i = 0) => {
  const h = strip(out);
  if (h.length < 64 * (i + 1)) throw new AirdropError('bad-response', 'Unexpected reply from the node (is the RPC on the right network?).');
  return BigInt('0x' + h.slice(64 * i, 64 * (i + 1)));
};

export function makeTacAirdrop({
  call, keccak256, fetchImpl, proofsBase = PROOF_HOSTS.sameOrigin, chainId = 1,
  contract, root, deadline, token, unitScale, pool, assetId, decimals,
  send = null, ux = null, multicall = true, timeoutMs = 10000,
  now = () => Math.floor(Date.now() / 1000), sleep = (ms) => new Promise((r) => setTimeout(r, ms)),
} = {}) {
  if (typeof call !== 'function') throw new Error('tac-airdrop: call is required');
  if (typeof keccak256 !== 'function') throw new Error('tac-airdrop: keccak256 is required');
  const f = fetchImpl || (typeof fetch === 'function' ? fetch.bind(globalThis) : null);

  const dep = contract ? {} : (AIRDROP_DEPLOYMENTS[chainId] || {});
  if (contract && (!root || !deadline || !token || !unitScale)) throw new Error('tac-airdrop: a custom contract needs root, deadline, token and unitScale');
  const deadlineSec = Number(deadline || dep.deadline || 0);
  const claimByISO = deadlineSec ? new Date(deadlineSec * 1000).toISOString().replace(/\.\d{3}Z$/, 'Z') : null;
  const bases = (Array.isArray(proofsBase) ? proofsBase : [proofsBase]).filter(Boolean).map((b) => String(b).replace(/\/+$/, ''));
  const cfg = {
    chainId: Number(chainId),
    deployed: !!(contract || dep.address),
    address: contract || dep.address || null,
    root: lc(root || dep.root || ''),
    deadline: deadlineSec || null,
    claimByISO,
    token: token || dep.token || null,
    decimals: decimals == null ? (dep.decimals ?? 18) : decimals,
    unitScale: String(unitScale || dep.unitScale || '0'),
    pool: pool || dep.pool || null,
    assetId: lc(assetId || dep.assetId || '') || null,
    proofsBase: bases,
  };
  const config = Object.freeze({ ...cfg, proofsBase: Object.freeze(bases.slice()) });

  const checksum = (lower) => {
    const h = hexOf(keccak256(enc.encode(lower)));
    return '0x' + [...lower].map((c, i) => (parseInt(h[i], 16) >= 8 ? c.toUpperCase() : c)).join('');
  };
  function toAddress(a) {
    const s = String(a == null ? '' : a).trim();
    if (!ADDR.test(s)) throw new AirdropError('bad-address', 'Not an Ethereum address.');
    const body = s.slice(2);
    if (body !== body.toLowerCase() && body !== body.toUpperCase() && checksum(body.toLowerCase()) !== s) {
      throw new AirdropError('bad-address', 'The address has a bad checksum. Check it for typos.');
    }
    return s.toLowerCase();
  }
  const requireDeployed = () => { if (!cfg.deployed) throw new AirdropError('not-deployed', REASON['not-deployed']); };

  const leafOf = (index, account, amount) => keccak256(keccak256(bytesOf(word(index) + addrWord(account) + word(amount))));
  function foldProof(leaf, proof) {
    let h = leaf;
    for (const p of proof) {
      const s = bytesOf(p);
      let cmp = 0;
      for (let i = 0; i < 32 && cmp === 0; i++) cmp = h[i] - s[i];
      h = keccak256(cmp <= 0 ? cat(h, s) : cat(s, h));
    }
    return h;
  }
  function checkEntry(account, c) {
    if (!c || typeof c !== 'object') throw new Error('malformed entry');
    if (!Number.isSafeInteger(c.index) || c.index < 0) throw new Error('bad index');
    if (typeof c.amount !== 'string' || !/^[1-9][0-9]{0,77}$/.test(c.amount) || BigInt(c.amount) >= 1n << 256n) throw new Error('bad amount');
    if (!Array.isArray(c.proof) || c.proof.length > 64 || !c.proof.every((p) => typeof p === 'string' && B32.test(p))) throw new Error('bad proof');
    const top = '0x' + hexOf(foldProof(leafOf(c.index, account, BigInt(c.amount)), c.proof));
    if (top !== cfg.root) throw new Error('the proof does not recompute to the airdrop root');
    return { index: c.index, amountWei: BigInt(c.amount).toString(), proof: c.proof.map(lc) };
  }

  const files = new Map();
  function getJson(url, check) {
    if (!files.has(url)) {
      files.set(url, (async () => {
        if (!f) throw new Error('no fetch implementation');
        const res = await f(url, { signal: timeoutSignal(timeoutMs) });
        if (res.status === 404) throw Object.assign(new Error('not found'), { missing: true });
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        return check(await res.json());
      })().catch((e) => { files.delete(url); throw e; }));
    }
    return files.get(url);
  }
  const getShard = (url) => getJson(url, (j) => {
    if (!j || typeof j.claims !== 'object' || j.claims === null) throw new Error('not a proof file');
    if (lc(j.root) !== cfg.root) throw new Error('the file is for a different root');
    return j;
  });
  const getManifest = (base) => getJson(`${base}/manifest.json`, (j) => {
    if (!j || !Array.isArray(j.shards) || lc(j.root) !== cfg.root) throw new Error('not the airdrop manifest');
    return j;
  });

  async function lookup(account) {
    const xx = account.slice(2, 4);
    const problems = [];
    let missing = 0;
    for (const base of bases) {
      const url = `${base}/${xx}.json`;
      let shard;
      try { shard = await getShard(url); } catch (e) {
        if (e && e.missing) {
          try {
            if ((await getManifest(base)).shards.includes(xx)) problems.push(`${url}: in the manifest but not served`);
            else missing++;
          } catch (me) { problems.push(`${url}: not found, and the manifest cannot say whether it should be (${me.message})`); }
        } else problems.push(`${url}: ${e.message}`);
        continue;
      }
      if (!Object.prototype.hasOwnProperty.call(shard.claims, account)) return null;
      try { return checkEntry(account, shard.claims[account]); } catch (e) { problems.push(`${url}: ${e.message}`); }
    }
    if (!problems.length && missing) return null;
    throw new AirdropError(problems.length ? 'shard-fetch' : 'no-proof-host', `Could not load the proof file${problems.length ? ` (${problems.join('; ')})` : ': no proof host is configured.'}`);
  }

  const verifyData = (account, e) => '0x' + SEL.verify + word(e.index) + addrWord(account) + word(e.amountWei) + word(0x80) + proofTail(e.proof);
  async function readChain(account, e) {
    const reads = [
      { to: cfg.address, data: '0x' + SEL.isClaimed + word(e.index) },
      { to: cfg.address, data: '0x' + SEL.paused },
      { to: cfg.token, data: '0x' + SEL.balanceOf + addrWord(cfg.address) },
      { to: cfg.address, data: verifyData(account, e) },
    ];
    let outs = null, timestamp = null;
    if (multicall) {
      try {
        const r = decAggregate3(await call({ to: MULTICALL3, data: encAggregate3([...reads, { to: MULTICALL3, data: '0x' + SEL.blockTimestamp }]) }));
        if (r.length === reads.length + 1) { timestamp = Number(wordOf(r[reads.length])); outs = r.slice(0, reads.length); }
      } catch { }
    }
    if (!outs) { outs = await Promise.all(reads.map((r) => call(r))); timestamp = now(); }
    if (wordOf(outs[3]) !== 1n) throw new AirdropError('chain-rejects-proof', 'The airdrop contract does not accept this proof. This page may be out of date.');
    return { claimed: wordOf(outs[0]) !== 0n, paused: wordOf(outs[1]) !== 0n, balance: wordOf(outs[2]), timestamp };
  }

  const head = (account) => ({
    address: account, contract: cfg.address, chainId: cfg.chainId, deployed: cfg.deployed, eligible: false, claimable: false,
    root: cfg.root || null, deadline: cfg.deadline, claimByISO: cfg.claimByISO,
  });

  async function status(address) {
    let account = null;
    try {
      account = toAddress(address);
      if (!cfg.deployed) return { ...head(account), reason: 'not-deployed', message: REASON['not-deployed'] };
      const e = await lookup(account);
      if (!e) return { ...head(account), reason: 'not-listed', message: REASON['not-listed'] };
      const c = await readChain(account, e);
      const amount = BigInt(e.amountWei);
      const open = c.timestamp <= cfg.deadline;
      const funded = c.balance >= amount;
      const reason = c.claimed ? 'claimed' : c.paused ? 'paused' : !open ? 'closed' : !funded ? 'unfunded' : null;
      return {
        ...head(account), eligible: true, claimable: reason === null, reason, message: reason ? REASON[reason] : null,
        index: e.index, amountWei: e.amountWei, amountTac: formatTac(amount, cfg.decimals),
        claimed: c.claimed, paused: c.paused, open, funded, canShield: amount % BigInt(cfg.unitScale) === 0n,
        secondsLeft: Math.max(0, cfg.deadline - c.timestamp), proof: e.proof,
      };
    } catch (e) {
      return { ...head(account), reason: 'error', message: e.message, error: { code: e.code || 'error', message: e.message } };
    }
  }

  async function entryFor(address) {
    const account = toAddress(address);
    requireDeployed();
    const e = await lookup(account);
    if (!e) throw new AirdropError('not-listed', REASON['not-listed']);
    return { account, ...e };
  }

  const mkTx = (data, from) => ({ ...(from ? { from } : {}), to: cfg.address, data, value: '0x0' });
  const txClaim = (e, from) => mkTx('0x' + SEL.claim + word(e.index) + addrWord(e.account) + word(e.amountWei) + word(0x80) + proofTail(e.proof), from);
  function txClaimTo(e, to) {
    const dest = toAddress(to);
    if (/^0x0{40}$/.test(dest) || [cfg.address, cfg.token, cfg.pool].some((a) => a && lc(a) === dest)) throw new AirdropError('bad-recipient', REASON['bad-recipient']);
    return mkTx('0x' + SEL.claimTo + word(e.index) + word(e.amountWei) + word(0x80) + addrWord(dest) + proofTail(e.proof), e.account);
  }
  function txShield(e, commit) {
    if (!B32.test(String(commit))) throw new AirdropError('bad-commit', REASON['bad-commit']);
    if (isZero32(commit)) throw new AirdropError('zero-commit', REASON['zero-commit']);
    if (BigInt(e.amountWei) % BigInt(cfg.unitScale) !== 0n) throw new AirdropError('not-aligned', REASON['not-aligned']);
    return mkTx('0x' + SEL.claimAndShield + word(e.index) + word(e.amountWei) + word(0x80) + strip(commit) + proofTail(e.proof), e.account);
  }

  const buildClaim = async (address) => txClaim(await entryFor(address));
  const buildClaimTo = async (address, to) => txClaimTo(await entryFor(address), to);
  const buildClaimAndShield = async (address, commit) => txShield(await entryFor(address), commit);

  async function claimableStatus(address) {
    const st = await status(address);
    if (st.error) throw new AirdropError(st.error.code, st.error.message);
    if (st.reason) throw new AirdropError(st.reason, st.message);
    return st;
  }
  const entryOf = (st) => ({ account: st.address, index: st.index, amountWei: st.amountWei, proof: st.proof });

  function revertCode(data) {
    const sel = strip(data).slice(0, 8);
    return REVERTS[sel] || null;
  }
  async function simulate(t) {
    try { await call({ to: t.to, data: t.data, ...(t.from ? { from: t.from } : {}) }); } catch (e) {
      if (!isRevert(e)) throw new AirdropError('rpc', `Could not check the transaction before sending it (${e.message}). Nothing was sent.`);
      const code = revertCode(e.data);
      const why = code ? REASON[code] : `The contract would reject this transaction (${e.data || e.message}).`;
      throw new AirdropError(code || 'simulation-failed', `${why} Nothing was sent.`, { data: e.data || null });
    }
  }
  async function submit(t, sender) {
    const s = sender || send;
    if (typeof s !== 'function') throw new AirdropError('no-sender', 'No wallet is connected to send the claim.');
    await simulate(t);
    return s(t);
  }
  const sent = (txHash, t, st) => ({ txHash, tx: t, index: st.index, amountWei: st.amountWei });

  async function claim(address, { send: sender, from } = {}) {
    const st = await claimableStatus(address);
    const t = txClaim(entryOf(st), from);
    return sent(await submit(t, sender), t, st);
  }

  async function claimTo(address, to, { send: sender } = {}) {
    const st = await claimableStatus(address);
    const t = txClaimTo(entryOf(st), to);
    return sent(await submit(t, sender), t, st);
  }

  async function claimAndShield(plan, { send: sender } = {}) {
    if (!plan || plan.kind !== 'tac-airdrop-shield' || !plan.record) throw new AirdropError('bad-plan', 'Pass the result of shieldPlan().');
    const st = await claimableStatus(plan.record.account);
    if (st.index !== plan.record.airdropIndex || st.amountWei !== plan.record.amountWei) throw new AirdropError('bad-plan', 'The plan does not match the allocation. Build it again.');
    const t = txShield(entryOf(st), plan.record.commit);
    return sent(await submit(t, sender), t, st);
  }

  async function waitClaimed(address, { timeoutMs: limit = 180000, intervalMs = 4000 } = {}) {
    const e = await entryFor(address);
    let lastError = null;
    for (let waited = 0; ; waited += intervalMs) {
      try {
        if (wordOf(await call({ to: cfg.address, data: '0x' + SEL.isClaimed + word(e.index) })) !== 0n) return { claimed: true };
        lastError = null;
      } catch (err) { lastError = err; }
      if (waited + intervalMs > limit) return { claimed: false, timedOut: true, error: lastError ? lastError.message : null };
      await sleep(intervalMs);
    }
  }

  const needUx = (u) => {
    if (!u || ['buildWrap', 'nextWrapIndex', 'submitWrapSettle'].some((k) => typeof u[k] !== 'function')) {
      throw new AirdropError('no-ux', 'Shielding needs the confidential pool ux (makeConfidentialPoolUx).');
    }
    if (!cfg.pool || !u.cfg || lc(u.cfg.pool) !== lc(cfg.pool)) {
      throw new AirdropError('pool-mismatch', 'The pool this page is configured for is not the pool the airdrop deposits into.');
    }
  };

  async function shieldPlan({ ux: u = ux, walletPriv, address, index, allowUnproven = false } = {}) {
    if (!allowUnproven) throw new AirdropError('shield-unproven', 'Shielding an airdrop claim has not been run end to end on mainnet. Pass allowUnproven: true to build the plan anyway.');
    needUx(u);
    const st = await claimableStatus(address);
    if (!st.canShield) throw new AirdropError('not-aligned', REASON['not-aligned']);
    const wrapIndex = index != null ? index : await u.nextWrapIndex({ walletPriv, ticker: 'TAC' });
    const built = u.buildWrap({ walletPriv, amountWei: st.amountWei, ticker: 'TAC', index: wrapIndex });
    if (!built || !built.wrapArgs || lc(built.wrapArgs.assetId) !== cfg.assetId || String(built.wrapArgs.amount) !== st.amountWei) {
      throw new AirdropError('asset-mismatch', 'The wrap does not deposit the airdrop asset.');
    }
    const t = txShield(entryOf(st), built.commit);
    const record = {
      contract: cfg.address, pool: cfg.pool, account: st.address, airdropIndex: st.index, amountWei: st.amountWei,
      wrapIndex, commit: built.commit, depositId: built.depositId,
    };
    return { kind: 'tac-airdrop-shield', tx: t, record, built };
  }

  async function settleShield({ ux: u = ux, walletPriv, record, built, waitOpts } = {}) {
    needUx(u);
    if (!record || !B32.test(String(record.depositId)) || !B32.test(String(record.commit))) throw new AirdropError('bad-record', 'Pass the record from shieldPlan().');
    if (lc(record.pool) !== lc(cfg.pool)) throw new AirdropError('pool-mismatch', 'The record is for a different pool.');
    const state = Number(wordOf(await call({ to: cfg.pool, data: '0x' + SEL.depositStatus + strip(record.depositId) })));
    if (state === 2) return { settled: true, alreadySettled: true };
    if (state !== 1) throw new AirdropError('deposit-not-found', 'The pool holds no pending deposit for this claim yet. Wait for the claimAndShield transaction to be mined. If a plain claim landed first, the TAC was paid to the recipient\'s own address instead.');
    const b = built || u.buildWrap({ walletPriv, amountWei: record.amountWei, ticker: 'TAC', index: record.wrapIndex });
    if (lc(b.commit) !== lc(record.commit) || lc(b.depositId) !== lc(record.depositId)) throw new AirdropError('wrong-key', 'This wallet key does not derive the deposit\'s commit.');
    return { settled: true, alreadySettled: false, result: await u.submitWrapSettle({ built: b, waitOpts }) };
  }

  return {
    config, status, entryFor, buildClaim, buildClaimTo, buildClaimAndShield,
    claim, claimTo, claimAndShield, waitClaimed, shieldPlan, settleShield, formatTac: (w) => formatTac(w, cfg.decimals),
  };
}
