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
// Testnet only: `open` refuses any chain but Sepolia (11155111), here and in
// Swift (`PrivacyNetwork.check`).
import './net.js';
import {
  CryptoService, KeystoreManager, NoteManager, NoteStatus, PoolSessionBuilder, PoseidonHashService,
  ProofService, ViemRPCInteractor, APP_IDENTIFIER,
} from '@0xbow/privacy-pools-v2-sdk';
import { syntheticInputs } from './synthetic.js';
import * as snarkjs from 'snarkjs';
import { getAddress } from 'viem';

const SDK_VERSION = '1.0.2';
const SNARKJS_VERSION = '0.7.5';
const TESTNETS = new Set([11155111]);
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

// The open account: its keys, one session per relayer route, and the
// prepared transactions waiting for the app.
let account = null;
const prepared = new Map();
let nextHandle = 1;
function keep(value) { const h = `p${nextHandle++}`; prepared.set(h, value); return h; }

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

async function session(route) {
  if (!account) throw new Error('no account is open');
  if (account.sessions[route]) return account.sessions[route];
  const n = account.network;
  // PoolVault.transact checks that the proof names its caller: the relayer's
  // signer for a transfer, the PrivacyPoolRelay contract for a withdrawal.
  const processorAddress = route === 'transfer' ? n.transferProcessor : n.withdrawProcessor;
  const log = logger(route);
  const builder = PoolSessionBuilder.fromConfig({
    chainId: n.chainId,
    rpcUrl: n.rpcUrl,
    ownerAddress: account.owner,
    deployment: { poolAddress: n.pool, entrypointAddress: n.entrypoint, keystoreAddress: n.keystore, aspRegistryAddress: n.aspRegistry },
    deploymentBlock: hex(n.fromBlock),
    aspUrl: n.aspUrl,
    relayers: [{ name: 'relayer', url: n.relayerUrl, address: n.relayerAddress, processorAddress, chainId: n.chainId, chainType: 'evm', status: 'active' }],
    logger: log,
  })
    .withKeystoreManager(account.keystore)
    .withHashService(account.hash)
    .withRpcInteractor(account.rpc)
    .withNoteManager(account.notes)
    .withCircuitArtifacts(artifacts)
    .withProofService(new ProofService({ circuitArtifacts: artifacts, groth16Prover: timedProver }, { logger: log }));
  account.sessions[route] = await builder.create();
  return account.sessions[route];
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
    if (!TESTNETS.has(Number(network?.chainId))) throw Object.assign(new Error(`chain ${network?.chainId} is not a testnet this engine serves`), { name: 'NotTestnet' });
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
    prepared.clear();
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
      ms: Math.round(now() - t),
      proofs,
    };
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

  async prepareTransfer({ tokenId, amount, recipient }) {
    proofs = [];
    const t = now();
    const s = await session('transfer');
    const r = await s.prepareTransfer({ inputCommitments: inputsFor(tokenId, amount), amount, tokenId, recipientDiscoveryData: { evmAddress: recipient } });
    const option = r.relayOptions?.[0];
    return { handle: keep({ kind: 'transfer', result: r }), fee: option ? JSON.parse(JSON.stringify(option.selectedQuote.quote, (_, v) => (typeof v === 'bigint' ? hex(v) : v))) : null, ms: Math.round(now() - t), proofs };
  },

  async prepareWithdraw({ tokenId, amount, recipient }) {
    proofs = [];
    const t = now();
    const s = await session('withdraw');
    const r = await s.prepareWithdraw({ inputCommitments: inputsFor(tokenId, amount), amount, tokenId, recipientAddress: recipient });
    const option = r.relayerOptions?.[0];
    return { handle: keep({ kind: 'withdraw', result: r }), fee: option ? JSON.parse(JSON.stringify(option.selectedQuote?.quote ?? null, (_, v) => (typeof v === 'bigint' ? hex(v) : v))) : null, ms: Math.round(now() - t), proofs };
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
