// Casberi's Privacy Pools engine (prd §1540): 0xBow's open TypeScript SDK,
// driven from Swift through one entry point, `casberiEngine.call(method,
// paramsJSON)`, which always resolves to a JSON envelope:
//   {"ok":true,"value":…}  or  {"ok":false,"error":{"name":…,"message":…}}
// (`PrivacyEngineWire.swift` decodes it.) BigInts travel as 0x-hex strings.
//
// What crosses back to Swift is PUBLIC: transactions to sign, commitments,
// labels, amounts, timings. The seed comes in once per `open`; the protocol
// keys derived from it, note secrets and prepared proofs stay in this page's
// memory (`prepared`, the sessions) and die with it. Nothing is persisted.
//
// Two networks: Sepolia (11155111, the DEBUG build's test money) and Ethereum
// (1, prd §1563: your private balance, earning on Aave through 0xBow's yield
// pools). `open` refuses any other chain, here and in Swift
// (`PrivacyNetwork.check`). Nothing here signs: a prepared transaction goes
// back to Swift, which has your account send it with Face ID.
import './net.js';
import {
  AddressSchema, CryptoService, HTTPClient, KeystoreManager, NoteManager, NoteStatus, PoolSessionBuilder, PoseidonHashService,
  ProofService, RelayerInteractor, ViemRPCInteractor, APP_IDENTIFIER,
} from '@0xbow/privacy-pools-v2-sdk';
import { syntheticInputs } from './synthetic.js';
import * as snarkjs from 'snarkjs';
import { getAddress } from 'viem';

const SDK_VERSION = '1.0.2';
const SNARKJS_VERSION = '0.7.5';
const NETWORKS = new Set([11155111, 1]);
const enc = new TextEncoder();
const now = () => performance.now();
const hex = (n) => `0x${BigInt(n).toString(16)}`;
const bytesFromHex = (h) => {
  const s = h.startsWith('0x') ? h.slice(2) : h;
  if (!/^[0-9a-fA-F]*$/.test(s) || s.length % 2) throw new Error('bad hex');
  return Uint8Array.from(s.match(/../g) ?? [], (b) => parseInt(b, 16));
};

// The engine's logger: warnings and errors reach the app's log (`engineLog`),
// with no arguments attached — an SDK object can carry a key.
function logger(service = 'sdk') {
  const say = (level) => (msg) => {
    try { globalThis.webkit.messageHandlers.engineLog.postMessage(`${level} [${service}] ${String(msg).slice(0, 300)}`); } catch {}
  };
  return { level: 'warn', child: (s) => logger(`${service}/${s}`), trace() {}, debug() {}, info() {}, warn: say('warn'), error: say('error'), fatal: say('fatal') };
}

// Circuits come from the app, which downloads each file once and checks its
// SHA-256 against the pin for this network before serving a byte
// (`PrivacyArtifacts.swift`). A file that fails the check never reaches here.
let lastCircuit = null;
const artifacts = {
  async fetchBytes(name, kind) {
    if (!/^[a-z0-9_]+$/.test(name)) throw new Error(`bad circuit name ${name}`);
    lastCircuit = name;
    const res = await fetch(`casberi-engine://engine/artifact/${name}/${kind}`);
    if (!res.ok) throw new Error(`artifact ${name}/${kind}: ${res.status} ${await res.text()}`);
    return new Uint8Array(await res.arrayBuffer());
  },
  getWasm(name) { return this.fetchBytes(name, 'wasm'); },
  getProvingKey(name) { return this.fetchBytes(name, 'zkey'); },
  getVerificationKey(name) { return this.fetchBytes(name, 'vkey'); },
};

// Every proof the SDK makes, timed: which circuit, and how long.
let proofs = [];
const timedProver = {
  async fullProve(input, wasm, zkey) {
    const circuit = lastCircuit;
    const t = now();
    const out = await snarkjs.groth16.fullProve(input, wasm, zkey);
    proofs.push({ circuit, ms: Math.round(now() - t) });
    return out;
  },
  verify(vkey, signals, proof) { return snarkjs.groth16.verify(vkey, signals, proof); },
};

let hashService = null;
async function poseidon() {
  hashService ??= await PoseidonHashService.create();
  return hashService;
}

// Poseidon(label) as a decimal string: the id 0xBow's ASP files a deposit
// under (`/labels/<id>/status`), never the label itself (prd §1554).
async function labelHashOf(label) {
  return BigInt((await poseidon()).hash([hex(label)])).toString(10);
}

// The open account: its keys, one session per relayer route, and the
// prepared transactions waiting for the app.
//
// A prepared handle BELONGS TO THE ACCOUNT IT WAS MADE UNDER (the review of
// 2026-10-26, finding 8): `open` no longer wipes it, and `relay` spends it
// through that account's own sessions, so a flow that opened another
// account between this one's prepare and relay cannot swap it. (The app
// also runs one flow at a time, `PrivacyEngine.exclusive`.) At most 16 are
// kept; `close` drops them all.
let account = null;
const prepared = new Map();
let nextHandle = 1;
function keep(value) {
  const h = `p${nextHandle++}`;
  prepared.set(h, { ...value, acct: account });
  while (prepared.size > 16) prepared.delete(prepared.keys().next().value);
  return h;
}

function deriveKeys(seedHex, revocableKeyIndex) {
  const seed = bytesFromHex(seedHex);
  if (seed.length !== 32) throw new Error('seed must be 32 bytes');
  const crypto = new CryptoService();
  // The SDK's own two-stage tree, entered at its root secret: a random
  // 32-byte seed made on the phone stands where the EIP-712 signature's
  // HKDF output stands for a wallet (a Safe cannot make that signature).
  const appSecret = crypto.deriveAppSecret(seed, enc.encode(APP_IDENTIFIER));
  try {
    return crypto.deriveKeys(appSecret, BigInt(revocableKeyIndex));
  } finally {
    appSecret.fill(0);
    seed.fill(0);
  }
}

async function session(route, acct = account) {
  if (!acct) throw new Error('no account is open');
  if (acct.sessions[route]) return acct.sessions[route];
  const n = acct.network;
  // PoolVault.transact checks that the proof names its caller: the relayer's
  // signer for a transfer, the PrivacyPoolRelay contract for a withdrawal.
  const processorAddress = route === 'transfer' ? n.transferProcessor : n.withdrawProcessor;
  const log = logger(route);
  const builder = PoolSessionBuilder.fromConfig({
    chainId: n.chainId,
    rpcUrl: n.rpcUrl,
    ownerAddress: acct.owner,
    deployment: { poolAddress: n.pool, entrypointAddress: n.entrypoint, keystoreAddress: n.keystore, aspRegistryAddress: n.aspRegistry },
    deploymentBlock: hex(n.fromBlock),
    aspUrl: n.aspUrl,
    relayers: [{ name: 'relayer', url: n.relayerUrl, address: n.relayerAddress, processorAddress, chainId: n.chainId, chainType: 'evm', status: 'active' }],
    logger: log,
  })
    .withKeystoreManager(acct.keystore)
    .withHashService(acct.hash)
    .withRpcInteractor(acct.rpc)
    .withNoteManager(acct.notes)
    .withCircuitArtifacts(artifacts)
    .withProofService(new ProofService({ circuitArtifacts: artifacts, groth16Prover: timedProver }, { logger: log }));
  // 0xBow's yield pools (prd §1563): what is private earns on Aave. Each
  // share token (ppETH, ppUSDC) has its router, which wraps on the way in
  // and unwraps on the way out; ppETH's takes and pays native ETH.
  const yields = yieldDeployments(n);
  if (yields.length) builder.withYieldDeployments(yields);
  acct.sessions[route] = await builder.create();
  return acct.sessions[route];
}

function yieldDeployments(n) {
  return (n.yield ?? []).map((y) => ({
    ppRouter: y.router, zap: y.zap, ppUSDC: y.share, ppUSDCDecimals: y.shareDecimals,
    underlying: y.underlying, underlyingDecimals: y.underlyingDecimals, underlyingSymbol: y.symbol,
    nativeMode: y.native === true, apyLabel: 'Aave',
  }));
}

// The yield pool serving a token: its share, or its underlying (USDC), or
// ETH for ppETH (whose router takes native ETH).
function yieldPool(tokenId) {
  const key = String(tokenId).toLowerCase();
  return (account.network.yield ?? []).find((y) => y.share.toLowerCase() === key || y.underlying.toLowerCase() === key
    || (y.native === true && key === '0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'));
}

function relayerInfo(route) {
  const n = account.network;
  return { name: 'relayer', url: n.relayerUrl, address: n.relayerAddress,
    processorAddress: route === 'transfer' ? n.transferProcessor : n.withdrawProcessor,
    chainId: n.chainId, chainType: 'evm', status: 'active' };
}

function publicTx(tx) {
  if (!tx) return null;
  return { to: tx.to, data: tx.data, value: hex(tx.value ?? 0) };
}

// A note's token id is compared without case: the SDK keeps whatever case
// the chain's event carried, and the app names ETH in its checksum case.
function activeNotes(tokenId) {
  return account.notes.getNotes({ status: NoteStatus.ACTIVE }).filter((n) => n.tokenId.toLowerCase() === tokenId.toLowerCase());
}

// Picks the fewest ACTIVE notes, largest first, that cover `amount`.
function inputsFor(tokenId, amount) {
  const notes = [...activeNotes(tokenId)].sort((a, b) => (BigInt(b.value) > BigInt(a.value) ? 1 : -1));
  const picked = [];
  let sum = 0n;
  for (const note of notes) {
    if (sum >= BigInt(amount)) break;
    picked.push(note.commitment); sum += BigInt(note.value);
  }
  if (sum < BigInt(amount)) throw Object.assign(new Error('the private balance does not cover this amount'), { name: 'InsufficientPrivateBalance' });
  return picked;
}

// A withdrawal from the yield pool, relayed (prd §1563): `amount` is what the
// recipient should get in the token (ETH or USDC, base units). It is turned
// into shares at today's rate, the relayer quotes its fee in shares and signs
// the payout, and the proof binds the router as the processor, so the router
// unwraps the shares and pays the recipient the token (native ETH for
// ppETH). The relayer posts it and pays the gas; `relay` hands it over.
async function prepareYieldWithdraw({ tokenId, amount, recipient }) {
  proofs = [];
  const t = now();
  const pool = yieldPool(tokenId);
  const s = await session('withdraw');
  const y = s.yieldFor(pool.share);
  if (!y) throw Object.assign(new Error(`the session has no yield pool for ${pool.share}`), { name: 'NoYieldPool' });
  // previewDeposit rounds down: one share more, so the recipient's ETH is
  // never a wei short of what the sentence said.
  const shares = (await y.deposit.sharesForUnderlying(BigInt(amount))) + 1n;
  const relayer = relayerInfo('withdraw');
  const quote = await account.relayer.getWithdrawalQuote(relayer, {
    asset: pool.share, commit: true, recipient: getAddress(recipient.toLowerCase()), extraGas: false, amount: hex(shares),
  });
  const amountSent = BigInt(quote.amountSent);
  const r = await y.withdraw.prepareYieldWithdrawRelay({
    inputCommitments: inputsFor(pool.share, amountSent),
    // The whole release, the relayer's fee in it: the router pays the fee
    // out of the shares (the proof's own fee is zero on this route).
    amount: amountSent,
    amountOut: amountSent,
    recipient: getAddress(recipient.toLowerCase()),
    signedFeeCommitment: quote.feeCommitment,
    extraGas: false,
  });
  return {
    handle: keep({ kind: 'yieldWithdraw', relayer, result: r }),
    fee: { feeAmount: hex(BigInt(quote.feeAmount)), amountSent: hex(amountSent), amountReceived: hex(BigInt(quote.amountReceived)),
      gasPrice: hex(BigInt(quote.gasPrice)), txCost: hex(BigInt(quote.txCost)), minUnderlyingOut: hex(r.minUnderlyingOut),
      quotedUnderlyingOut: hex(r.quotedUnderlyingOut) },
    ms: Math.round(now() - t),
    proofs,
  };
}

// ---------------------------------------------------------------- the methods
const methods = {
  async info() {
    return {
      sdk: SDK_VERSION,
      snarkjs: SNARKJS_VERSION,
      secureContext: globalThis.isSecureContext === true,
      webAssembly: typeof WebAssembly === 'object',
      workers: typeof Worker === 'function',
      cores: navigator.hardwareConcurrency ?? 0,
    };
  },

  async open({ seed, revocableKeyIndex = '0x0', owner, network }) {
    if (!NETWORKS.has(Number(network?.chainId))) throw Object.assign(new Error(`chain ${network?.chainId} is not a network this engine serves`), { name: 'NotServed' });
    const t = now();
    const keys = deriveKeys(seed, revocableKeyIndex);
    const keysMs = Math.round(now() - t);
    const hash = await poseidon();
    account = {
      owner: getAddress(owner.toLowerCase()),
      network,
      keystore: new KeystoreManager({ ...keys, revocableKeyIndex }),
      hash,
      rpc: ViemRPCInteractor.create({ rpcUrl: network.rpcUrl }, { logger: logger('rpc') }),
      notes: new NoteManager({}, { logger: logger('notes') }),
      sessions: {},
    };
    // The relayer, asked directly for a yield withdrawal's quote and handed
    // its proof (prd §1563): the SDK's own interactor and schemas.
    account.relayer = new RelayerInteractor({ relayers: [relayerInfo('withdraw')], httpClient: new HTTPClient(), addressSchema: AddressSchema }, { logger: logger('relayer') });
    const s = now();
    await session('withdraw');
    return { viewingPublicKey: keys.viewingPublicKey, keysMs, sessionMs: Math.round(now() - s) };
  },

  async close() {
    account = null;
    prepared.clear();
    return { closed: true };
  },

  async isRegistered() {
    const t = now();
    const registered = await (await session('withdraw')).isKeystoreRegistered();
    return { registered, ms: Math.round(now() - t) };
  },

  // The keystore's two legs (auth policy, then the viewing key), for the
  // person's own account to send. Nothing is sent here.
  async prepareRegister() {
    const t = now();
    const r = await (await session('withdraw')).prepareRegisterKeystore({ includeViewingKey: true });
    const txs = [r.keystoreCalldata, r.viewingKeyCalldata].filter(Boolean).map(publicTx);
    return { alreadyRegistered: !!r.alreadyRegistered, txs, ms: Math.round(now() - t) };
  },

  async prepareDeposit({ tokenId, value }) {
    proofs = [];
    const t = now();
    const r = await (await session('withdraw')).prepareDeposit({ tokenId, value });
    return {
      handle: keep({ kind: 'deposit', result: r }),
      tx: publicTx(r.depositTx),
      approvals: (r.approvalTxs ?? []).map(publicTx),
      commitment: r.pendingNote.commitment,
      label: hex(r.pendingNote.label),
      // The ASP keys a deposit by Poseidon(label), in decimal; asked with the
      // raw label it reads `unknown` forever (prd §1554).
      labelHash: await labelHashOf(r.pendingNote.label),
      ms: Math.round(now() - t),
      proofs,
    };
  },

  // Into the yield pool (prd §1563): what is private earns on Aave. `budget`
  // is the most of the token (ETH or USDC, base units) the deposit may
  // spend, the pool's vetting fee and the router's buffer included; the
  // shares are sized to fit it (`sizeSharesForBudget`). For ETH the router
  // takes the budget as the transaction's value and refunds what it did not
  // use; for a token the approvals come back too. Nothing is sent here.
  async prepareYieldDeposit({ tokenId, budget }) {
    proofs = [];
    const t = now();
    const pool = yieldPool(tokenId);
    if (!pool) throw Object.assign(new Error(`no yield pool for ${tokenId}`), { name: 'NoYieldPool' });
    const s = await session('withdraw');
    const y = s.yieldFor(pool.share);
    if (!y) throw Object.assign(new Error(`the session has no yield pool for ${pool.share}`), { name: 'NoYieldPool' });
    const sized = await y.deposit.sizeSharesForBudget(BigInt(budget));
    const r = await y.deposit.prepareYieldDeposit({ value: sized.shares, maxUnderlyingIn: sized.maxUnderlyingIn });
    return {
      handle: keep({ kind: 'deposit', result: r }),
      tx: publicTx(r.depositTx),
      approvals: (r.approvalTxs ?? []).map(publicTx),
      commitment: r.pendingNote.commitment,
      label: hex(r.pendingNote.label),
      labelHash: await labelHashOf(r.pendingNote.label),
      share: pool.share,
      shares: hex(r.sharesValue),
      underlyingNeeded: hex(r.underlyingNeeded),
      maxUnderlyingIn: hex(r.maxUnderlyingIn),
      ms: Math.round(now() - t),
      proofs,
    };
  },

  async labelHash({ label }) {
    return { labelHash: await labelHashOf(BigInt(label)) };
  },

  async discover() {
    const t = now();
    const s = await session('withdraw');
    await s.discoverNotes();
    const exported = await s.exportAccount();
    const notes = (exported.notes ?? []).map((n) => ({ commitment: n.commitment, tokenId: n.tokenId, value: hex(n.value), status: n.status, label: hex(n.label) }));
    const balances = {};
    for (const n of notes) if (n.status === NoteStatus.ACTIVE) balances[n.tokenId] = hex(BigInt(balances[n.tokenId] ?? 0) + BigInt(n.value));
    return { notes, balances: Object.entries(balances).map(([tokenId, value]) => ({ tokenId, value })), ms: Math.round(now() - t) };
  },

  // Balance to balance (prd §1567): the recipient's own private account,
  // found by its owner's address in the keystore. The SDK reads the
  // recipient's viewing key there and refuses an address with none
  // (`RecipientViewingKeyUnregistered`), never falling back to secrets the
  // app would have to deliver. On a yield pool (Ethereum) the note holds
  // SHARES: `amount` is what the recipient should hold in the token, turned
  // into shares at today's rate (one more, so it is never a wei short).
  // 0xBow's relayer posts it and pays the gas for a fee from the change.
  async prepareTransfer({ tokenId, amount, recipient }) {
    proofs = [];
    const t = now();
    const s = await session('transfer');
    let token = tokenId;
    let value = BigInt(amount);
    const pool = yieldPool(tokenId);
    if (pool) {
      const y = (await session('withdraw')).yieldFor(pool.share);
      if (!y) throw Object.assign(new Error(`the session has no yield pool for ${pool.share}`), { name: 'NoYieldPool' });
      token = pool.share;
      value = (await y.deposit.sharesForUnderlying(value)) + 1n;
    }
    const r = await s.prepareTransfer({ inputCommitments: inputsFor(token, value), amount: hex(value), tokenId: token,
      recipientDiscoveryData: { evmAddress: getAddress(recipient.toLowerCase()) } });
    const option = r.relayOptions?.[0];
    return { handle: keep({ kind: 'transfer', result: r }), fee: option ? JSON.parse(JSON.stringify(option.selectedQuote.quote, (_, v) => (typeof v === 'bigint' ? hex(v) : v))) : null, ms: Math.round(now() - t), proofs };
  },

  async prepareWithdraw({ tokenId, amount, recipient }) {
    if (yieldPool(tokenId)) return prepareYieldWithdraw({ tokenId, amount, recipient });
    proofs = [];
    const t = now();
    const s = await session('withdraw');
    const r = await s.prepareWithdraw({ inputCommitments: inputsFor(tokenId, amount), amount, tokenId, recipientAddress: recipient });
    const option = r.relayerOptions?.[0];
    return { handle: keep({ kind: 'withdraw', result: r }), fee: option ? JSON.parse(JSON.stringify(option.selectedQuote?.quote ?? null, (_, v) => (typeof v === 'bigint' ? hex(v) : v))) : null, ms: Math.round(now() - t), proofs };
  },

  // Take it back (prd §1561): the ragequit, a public exit of one whole note
  // to the address that owns the account (the circuit fixes the recipient).
  // It needs no approval from 0xBow, so it is the way back for a deposit
  // the ASP refused or never answered. `discover` must have run, so the note
  // is in this page's NoteManager. The transaction is for the owner to sign.
  async prepareRagequit({ commitment }) {
    proofs = [];
    const t = now();
    const s = await session('withdraw');
    const want = String(commitment).toLowerCase();
    const note = account.notes.getNotes().find((n) => String(n.commitment).toLowerCase() === want);
    if (!note) throw Object.assign(new Error('the pool holds no such note for this account'), { name: 'NoNote' });
    const r = await s.prepareRageQuit({ commitment: note.commitment });
    return {
      handle: keep({ kind: 'ragequit', result: r }),
      tx: publicTx(r.ragequitTx),
      value: hex(r.value),
      recipient: r.recipientAddress,
      ms: Math.round(now() - t),
      proofs,
    };
  },

  // Hands a prepared withdrawal or transfer to the relayer, which posts it
  // and pays its gas (prd §1554): the handle is spent either way, so a second
  // tap cannot post one proof twice. Returns the transaction's hash.
  async relay({ handle }) {
    const p = prepared.get(handle);
    if (!p || !['withdraw', 'transfer', 'yieldWithdraw'].includes(p.kind)) throw Object.assign(new Error('nothing prepared under that handle'), { name: 'NoPrepared' });
    prepared.delete(handle);
    const t = now();
    // Through the account the handle was prepared under, never whichever
    // is open now (finding 8).
    if (p.kind === 'yieldWithdraw') {
      const tx = await p.acct.relayer.relayWithdrawal(p.relayer, p.result.relayParams);
      return { tx, ms: Math.round(now() - t) };
    }
    const s = await session(p.kind, p.acct);
    if (p.kind === 'withdraw') {
      const option = p.result.relayerOptions?.[0];
      if (!option) throw Object.assign(new Error('the relayer quoted nothing'), { name: 'NoQuote' });
      const r = await s.relayWithdraw(option);
      return { tx: r.txHash, ms: Math.round(now() - t) };
    }
    const option = p.result.relayOptions?.[0];
    if (!option) throw Object.assign(new Error('the relayer quoted nothing'), { name: 'NoQuote' });
    const r = await s.relayTransfer(option);
    return { tx: r.txReceipt.txHash, ms: Math.round(now() - t) };
  },

  // A proof with the network's real circuit and keys, on synthetic inputs
  // that satisfy it (own keystore, state and association trees, the trial's
  // `prove-bench.mjs`): it costs what a real one costs and verifies against
  // the circuit's key, but names roots no pool holds, so it is never sent.
  async bench({ circuit, singleThread = false }) {
    if (!/^(deposit|ragequit|transact_[1-5]x[1-5])$/.test(circuit)) throw new Error(`unknown circuit ${circuit}`);
    const t0 = now();
    const [wasm, zkey, vkeyBytes] = await Promise.all([artifacts.getWasm(circuit), artifacts.getProvingKey(circuit), artifacts.getVerificationKey(circuit)]);
    const loadMs = Math.round(now() - t0);
    const h = await poseidon();
    const input = syntheticInputs(circuit, (xs) => BigInt(h.hash(xs.map((x) => hex(x)))));
    const wtns = { type: 'mem' };
    const t1 = now();
    await snarkjs.wtns.calculate(input, wasm, wtns);
    const t2 = now();
    const { proof, publicSignals } = await snarkjs.groth16.prove(zkey, wtns, undefined, singleThread ? { singleThread: true } : undefined);
    const t3 = now();
    const verifies = await snarkjs.groth16.verify(JSON.parse(new TextDecoder().decode(vkeyBytes)), publicSignals, proof);
    return { circuit, loadMs, witnessMs: Math.round(t2 - t1), proveMs: Math.round(t3 - t2), verifies, wasmBytes: wasm.length, zkeyBytes: zkey.length };
  },
};

// ------------------------------------------------------------- the entry point
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
