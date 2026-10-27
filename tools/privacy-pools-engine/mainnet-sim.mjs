// MAINNET, SIMULATED (prd §1563). Runs the app's own engine (src/engine.js,
// the code the phone's web view runs) in Node against Ethereum's REAL state,
// and proves every move private money makes on mainnet with `eth_simulateV1`
// — nothing is ever signed or sent. No key here can sign a mainnet
// transaction; the relayer's `/v1/relay/*` is refused before it leaves.
//
//   node mainnet-sim.mjs [scenario ...]     scenarios: eth usdc ragequit withdraw fresh transfer usdcsend
//                                           freshusdc roundups (default: all)
//   node mainnet-sim.mjs --mutate <name>    the same, with one thing broken on purpose: it must FAIL
//
// How. A fork made of simulation: every block the scenario "sends" is kept as
// a call list, and every read the engine makes is answered over the real head
// plus those blocks — `eth_call` by simulating them with the call appended,
// `eth_getLogs` by the real logs plus the simulated blocks' own logs,
// `eth_blockNumber` by the head plus their count. So the SDK prepares each
// step against the state the step before would have made: the keystore
// registered, the deposit in the state tree, its note discovered.
//
// The account is a real SafeL2 1.4.1 PROXY, created in the fork's first
// block by SafeProxyFactory 1.4.1 with the app's own setup (see "your
// account, as the app makes it" below), funded by state overrides. Each of
// its moves runs twice: as the app's check before Face ID
// (`YourAccountChain.check`: each call from the account, its code cold) and
// as the operation executes (the EntryPoint's `executeUserOp` through the
// 4337 module, one MultiSend). Until 2026-10-26 the "proxy" was SafeL2's own
// code, which hid that WETH's `withdraw` cannot pay a cold proxy.
//
// What cannot be real: 0xBow's approval. A withdrawal needs the deposit's
// label in 0xBow's association set, which only 0xBow publishes; the
// `withdraw` scenario puts the new label in a copy of the real set and serves
// its root from the ASP registry by a code override, then proves the relayer's
// own signed quote through the router, as the relayer would post it. Every
// other part of that call — the proof, the pool, the router, Aave — is
// mainnet's.
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_CIRCUIT_MANIFEST, MerkleService, PoseidonHashService } from '@0xbow/privacy-pools-v2-sdk';
import { decodeFunctionData, encodeFunctionData, getAddress, keccak256, pad, parseAbi, toHex } from 'viem';

const here = dirname(fileURLToPath(import.meta.url));
// Node's own fetch: the engine's net.js replaces the global one with the page's door.
const nodeFetch = globalThis.fetch.bind(globalThis);
const args = process.argv.slice(2);
const mutateAt = args.indexOf('--mutate');
const MUTATION = mutateAt >= 0 ? args[mutateAt + 1] : null;
const wanted = args.filter((a, i) => !a.startsWith('--') && (mutateAt < 0 || i !== mutateAt + 1));
const SCENARIOS = wanted.length ? wanted : ['eth', 'usdc', 'ragequit', 'withdraw', 'fresh', 'transfer', 'usdcsend', 'freshusdc', 'roundups'];

// ------------------------------------------------------------- the network
// Read 2026-10-26 from 0xBow's production relayer (/v1/details/evm/1), its
// ASP (/global/public/entrypoints) and the chain (PoolVault.keystore(),
// .aspRegistry(), each address's code). The SAME object `PrivacyNetwork.
// ethereum` encodes for the page.
export const ETHEREUM = {
  chainId: 1,
  rpcUrl: 'https://sim.rpc.invalid',
  aspUrl: 'https://api-v2.0xbow.io',
  relayerUrl: 'https://relayer-v2-prod-149184580131.us-east1.run.app',
  relayerAddress: '0x9e2f1B234953F46c6091636290E9035618EA3C07',
  transferProcessor: '0x9e2f1B234953F46c6091636290E9035618EA3C07',
  withdrawProcessor: '0x01a8Fa4dbb60187aD8d3c3d08E7Fb8C14198A461',
  entrypoint: '0xca1e072236D231130059eeA6Bfceb7F4e9a1F0C3',
  pool: '0x0Eb42804BF897662aF851370eaeAdcDBEC1b97ed',
  keystore: '0x6E463391c79b7e1A88eF26E0B023f9A6C9938a71',
  aspRegistry: '0x259C0BEa1d783c202509BD3b2688d23b8AEf58B0',
  // The keystore's first log (25,884,231): older than the PoolVault
  // (25,884,277) and the Entrypoint (25,884,284), and far older than the
  // ASP's own `fromBlock` (25,893,288), which would leave holes in the tree.
  fromBlock: 25884231,
  yield: [
    { symbol: 'WETH', native: true, share: '0x66051920D25af4E3596A8a46309F4D045F9D83B7', shareDecimals: 18,
      underlying: '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2', underlyingDecimals: 18,
      router: '0x77613D670BB9fD48A9898D0eac8ebf21B566F960', zap: '0x33c1eEf370bBb447414156CFc4fDABD434776EAf' },
    { symbol: 'USDC', native: false, share: '0xC246aFb23482fF9596E9cee5f1f678eFe0EB1ad6', shareDecimals: 18,
      underlying: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48', underlyingDecimals: 6,
      router: '0xe76E793d776c1e207aD7a7fa7C57d27420d85110', zap: '0x9Ea986BcDF6784D85B518b15bEEE1E65b585817B' },
  ],
};
const ETH = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE';
const USDC = ETHEREUM.yield[1].underlying;
const SAFE_L2 = '0x29fcB43b46531BcA003ddC8FCB67FFE91900C762';
const PROXY_FACTORY = '0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67';
// Nodes: state and simulation from PublicNode, logs from Tenderly's gateway
// (the whole range in one read). The phone reads logs through Tor from MEV
// Blocker in 50,000-block windows instead (measured, `PrivacyEngineWire`).
const STATE_RPC = process.env.STATE_RPC ?? 'https://ethereum-rpc.publicnode.com';
const LOGS_RPC = process.env.LOGS_RPC ?? 'https://gateway.tenderly.co/public/mainnet';

const say = (...a) => console.log(...a);
const record = { measured: new Date().toISOString(), mutation: MUTATION, scenarios: {} };

async function upstream(url, method, params) {
  for (let attempt = 0; attempt < 6; attempt++) {
    const res = await nodeFetch(url, { method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params }) });
    const text = await res.text();
    let json;
    try { json = JSON.parse(text); } catch { json = null; }
    if (res.status === 429 || json?.error?.code === -32005 || !json) { await new Promise((r) => setTimeout(r, 800 << attempt)); continue; }
    return json;
  }
  throw new Error(`${url} ${method}: no answer`);
}

// ----------------------------------------------------------- the sim fork
class SimFork {
  constructor(head, overrides) {
    this.head = head;
    this.overrides = overrides; // stateOverrides for the first block
    this.blocks = [];           // [{ label, calls }]
    this.results = [];          // eth_simulateV1's block per committed block
    this.extraOverrides = {};   // applied from a block on (the ASP root)
  }
  blockStateCalls(extra, extraOverrides) {
    const all = [...this.blocks, ...(extra ? [{ calls: extra, overrides: extraOverrides }] : [])];
    return all.map((b, i) => {
      const o = { ...(i === 0 ? this.overrides : {}), ...(b.overrides ?? {}) };
      const out = { calls: b.calls.map((c) => ({ from: c.from, to: c.to, data: c.data ?? '0x', value: c.value ?? '0x0', gas: c.gas ?? '0x1c9c380' })) };
      if (Object.keys(o).length) out.stateOverrides = o;
      return out;
    });
  }
  async simulate(extra, extraOverrides) {
    const calls = this.blockStateCalls(extra, extraOverrides);
    if (!calls.length) return [];
    const r = await upstream(STATE_RPC, 'eth_simulateV1', [{ blockStateCalls: calls, validation: false, traceTransfers: false }, toHex(this.head)]);
    if (r.error) throw new Error(`simulate: ${JSON.stringify(r.error).slice(0, 300)}`);
    return r.result;
  }
  // Sends a block: every call must succeed, or the scenario fails here.
  async commit(label, calls, overrides) {
    const result = await this.simulate([...calls], overrides);
    const block = result[result.length - 1];
    const bad = block.calls.findIndex((c) => c.status !== '0x1');
    this.blocks.push({ label, calls, overrides });
    this.results = result;
    if (bad >= 0) {
      const c = block.calls[bad];
      throw Object.assign(new Error(`${label}: call ${bad} (${calls[bad].note ?? calls[bad].to}) reverted: ${c.error?.message ?? ''} ${c.returnData ?? c.error?.data ?? ''}`), { block });
    }
    return block;
  }
  // The tip the engine is told: a fixed 32 blocks past the real head, so a
  // block number the SDK read before a step (and keeps as a scan's end)
  // still covers every simulated block made after it. Real logs stop at the
  // head; the simulated blocks are head+1, head+2, ….
  get number() { return this.head + 32; }
  logs() {
    const out = [];
    this.results.forEach((b) => b.calls.forEach((c) => (c.logs ?? []).forEach((l) => out.push(l))));
    return out;
  }
  async call(tx) {
    if (!this.blocks.length && !Object.keys(this.overrides).length) {
      return upstream(STATE_RPC, 'eth_call', [tx, toHex(this.head)]);
    }
    const result = await this.simulate([{ from: tx.from ?? '0x0000000000000000000000000000000000000001', to: tx.to, data: tx.data ?? tx.input, value: tx.value }]);
    const c = result[result.length - 1].calls[0];
    if (c.status !== '0x1') return { error: { code: 3, message: 'execution reverted', data: c.returnData } };
    return { result: c.returnData };
  }
}

let fork;
const relayCaptured = [];
const FAKE_HASH = `0x${'5'.repeat(64)}`;

function matches(log, filter) {
  const addrs = filter.address ? (Array.isArray(filter.address) ? filter.address : [filter.address]).map((a) => a.toLowerCase()) : null;
  if (addrs && !addrs.includes(log.address.toLowerCase())) return false;
  const from = filter.fromBlock && filter.fromBlock !== 'earliest' ? BigInt(filter.fromBlock) : 0n;
  const to = filter.toBlock && !['latest', 'safe', 'finalized', 'pending'].includes(filter.toBlock) ? BigInt(filter.toBlock) : BigInt(fork.number);
  const n = BigInt(log.blockNumber);
  if (n < from || n > to) return false;
  for (const [i, t] of (filter.topics ?? []).entries()) {
    if (t == null) continue;
    const set = (Array.isArray(t) ? t : [t]).map((x) => x.toLowerCase());
    if (!set.includes((log.topics[i] ?? '').toLowerCase())) return false;
  }
  return true;
}

async function rpcAnswer({ method, params, id }) {
  if (process.env.SIM_DEBUG) say('    rpc', method, JSON.stringify(params ?? []).slice(0, 160));
  const ok = (result) => ({ jsonrpc: '2.0', id, result });
  switch (method) {
    case 'eth_chainId': return ok('0x1');
    case 'eth_blockNumber': if (process.env.SIM_DEBUG) say('      blockNumber ->', toHex(fork.number)); return ok(toHex(fork.number));
    case 'eth_call': {
      const r = await fork.call(params[0]);
      return { jsonrpc: '2.0', id, ...r };
    }
    case 'eth_getLogs': {
      const f = params[0];
      const real = [];
      const from = f.fromBlock && f.fromBlock !== 'earliest' ? BigInt(f.fromBlock) : 0n;
      const toReal = f.toBlock && !['latest', 'safe', 'finalized', 'pending'].includes(f.toBlock) ? BigInt(f.toBlock) : BigInt(fork.head);
      if (from <= BigInt(fork.head)) {
        const r = await upstream(LOGS_RPC, 'eth_getLogs', [{ ...f, toBlock: toHex(toReal < BigInt(fork.head) ? toReal : BigInt(fork.head)) }]);
        if (r.error) return { jsonrpc: '2.0', id, error: r.error };
        real.push(...r.result);
      }
      const simulated = fork.logs().filter((l) => matches(l, f));
      if (process.env.SIM_DEBUG) say(`      logs ${f.address?.slice?.(0, 8)} ${f.fromBlock}..${f.toBlock}: ${real.length} real + ${simulated.length} simulated`);
      return ok([...real, ...simulated]);
    }
    case 'eth_getTransactionReceipt': {
      // A transfer the relayer was handed (never posted): the SDK waits for
      // its receipt, so the relayer's own call is committed to the fork now,
      // as the relayer would post it, and its receipt is that block's.
      if (params[0] === FAKE_HASH && relayCaptured.length && relayCaptured.at(-1).kind === 'transfer') {
        const block = await commitRelayedTransfer(relayCaptured.at(-1));
        const c = block.calls[0];
        return ok({ transactionHash: FAKE_HASH, status: c.status, logs: (c.logs ?? []).map((l, i) => ({ ...l, logIndex: toHex(i), transactionHash: FAKE_HASH })),
          blockNumber: block.number, blockHash: block.hash, gasUsed: c.gasUsed, cumulativeGasUsed: c.gasUsed, effectiveGasPrice: '0x1',
          from: ETHEREUM.relayerAddress, to: ETHEREUM.pool, transactionIndex: '0x0', type: '0x2', contractAddress: null, logsBloom: '0x' + '0'.repeat(512) });
      }
      return upstream(STATE_RPC, method, params).then((r) => ({ jsonrpc: '2.0', id, ...r }));
    }
    case 'eth_getBlockByNumber': {
      const tag = params[0];
      const n = ['latest', 'safe', 'finalized', 'pending'].includes(tag) ? fork.number : Number(BigInt(tag));
      if (n > fork.head) {
        const b = fork.results[Math.min(n - fork.head, fork.results.length) - 1] ?? fork.results.at(-1);
        if (!b) return upstream(STATE_RPC, method, [toHex(fork.head), params[1]]).then((r) => ({ jsonrpc: '2.0', id, ...r }));
        return ok({ ...b, transactions: params[1] ? [] : (b.transactions ?? []) });
      }
      return upstream(STATE_RPC, method, [toHex(n), params[1]]).then((r) => ({ jsonrpc: '2.0', id, ...r }));
    }
    default: {
      const r = await upstream(STATE_RPC, method, params);
      return { jsonrpc: '2.0', id, ...r };
    }
  }
}

// The ASP, as the engine reads it: real, except the withdraw scenario's
// label (approved, and in the set) — see the header.
const aspExtra = { labelHashes: [], root: null };

async function engineNet({ url, method, headers, body }) {
  const u = new URL(url);
  if (process.env.SIM_DEBUG && u.hostname !== 'sim.rpc.invalid') say('    net', method, url.slice(0, 160));
  if (u.hostname === 'sim.rpc.invalid') {
    const payload = JSON.parse(body);
    const answer = Array.isArray(payload) ? await Promise.all(payload.map(rpcAnswer)) : await rpcAnswer(payload);
    return { status: 200, headers: { 'content-type': 'application/json' }, body: JSON.stringify(answer) };
  }
  if (u.hostname === new URL(ETHEREUM.relayerUrl).hostname && u.pathname.startsWith('/v1/relay')) {
    // NEVER to the relayer: it would post. Kept, and simulated below.
    relayCaptured.push({ ...JSON.parse(body), kind: u.pathname.endsWith('/transfer') ? 'transfer' : 'withdrawal' });
    return { status: 200, headers: { 'content-type': 'application/json' }, body: JSON.stringify({ txHash: FAKE_HASH }) };
  }
  if (u.hostname === 'api-v2.0xbow.io') {
    const m = u.pathname.match(/^\/labels\/(\d+)\/status$/);
    if (m && aspExtra.labelHashes.includes(m[1])) {
      return { status: 200, headers: { 'content-type': 'application/json' }, body: JSON.stringify({ status: 'approved' }) };
    }
    if (aspExtra.labelHashes.length && u.pathname === '/association-set/leaves') {
      const real = await (await nodeFetch(url)).json();
      return { status: 200, headers: { 'content-type': 'application/json' }, body: JSON.stringify({ ...real, leaves: [...real.leaves, ...aspExtra.labelHashes] }) };
    }
    // The ASP's indexes run to the REAL head, past the fork's: a note made in
    // a simulated block would be taken for read already (or purged as a
    // phantom). Each claims only up to the fork's head, so the engine reads
    // the rest from the fork, as it reads a block newer than the ASP's.
    if (u.pathname === '/1/public/note-events' || u.pathname === '/1/public/event-snapshot/payload') {
      const real = await (await nodeFetch(url)).json();
      if (real.lastSyncedBlock && BigInt(real.lastSyncedBlock) > BigInt(fork.head)) real.lastSyncedBlock = toHex(fork.head);
      if (real.snapshotBlockNumber && BigInt(real.snapshotBlockNumber) > BigInt(fork.head)) real.snapshotBlockNumber = String(fork.head);
      return { status: 200, headers: { 'content-type': 'application/json' }, body: JSON.stringify(real) };
    }
    if (aspExtra.root && u.pathname === '/association-set/root') {
      return { status: 200, headers: { 'content-type': 'application/json' }, body: JSON.stringify({ root: BigInt(aspExtra.root).toString(10) }) };
    }
  }
  const res = await nodeFetch(url, { method, headers, body: method === 'GET' ? undefined : body });
  const out = {};
  res.headers.forEach((v, k) => { out[k] = v; });
  return { status: res.status, headers: out, body: await res.text() };
}

// ------------------------------------------- circuits: the ceremony keys
// Mainnet's verifiers hold the trusted-setup ceremony keys SDK 1.0.1+ ship
// (Sepolia's hold 1.0.0's dev keys). Each file is fetched by CID and refused
// unless it hashes to the manifest's SHA-256 — the pins `pins.mjs` writes.
const sha = (b) => createHash('sha256').update(b).digest('hex');
async function artifact(name, kind) {
  const e = DEFAULT_CIRCUIT_MANIFEST[name];
  const [cid, digest] = kind === 'wasm' ? [e.wasm, e.wasmSha256] : kind === 'zkey' ? [e.provingKey, e.provingKeySha256] : [e.verificationKey, e.verificationKeySha256];
  const dir = join(here, '.circuits'); mkdirSync(dir, { recursive: true });
  const path = join(dir, digest);
  if (existsSync(path)) { const b = readFileSync(path); if (sha(b) === digest) return b; }
  for (const g of ['https://gateway.pinata.cloud/ipfs/', 'https://ipfs.io/ipfs/']) {
    const res = await nodeFetch(g + cid).catch(() => null);
    if (!res?.ok) continue;
    const b = Buffer.from(await res.arrayBuffer());
    if (sha(b) !== digest) continue;
    writeFileSync(path, b);
    return b;
  }
  throw new Error(`no copy of ${name}.${kind} matched its pin`);
}

// ------------------------------------------------ the page, in Node
globalThis.fetch = async (input, init) => {
  const url = String(input instanceof Request ? input.url : input);
  const m = url.match(/^casberi-engine:\/\/engine\/artifact\/([a-z0-9_]+)\/(wasm|zkey|vkey)$/);
  if (m) {
    if (MUTATION === 'devkeys' && m[1] === 'deposit') {
      // The Sepolia DEV keys where mainnet's ceremony keys belong: a proof
      // mainnet's verifier must refuse.
      const swift = readFileSync(join(here, '../../Casberi/Casberi/Model/PrivacyArtifactPins.swift'), 'utf8');
      const block = swift.split('static let sepoliaPins')[1].match(/"deposit": Circuit\(([\s\S]*?)\)\),/)[1];
      const pick = { wasm: 'wasm', zkey: 'zkey', vkey: 'vkey' }[m[2]];
      const f = block.match(new RegExp(`${pick}: File\\(cid: "(\\w+)", sha256: "([0-9a-f]{64})"`));
      for (const g of ['https://gateway.pinata.cloud/ipfs/']) {
        const res = await nodeFetch(g + f[1]);
        return new Response(Buffer.from(await res.arrayBuffer()));
      }
    }
    return new Response(await artifact(m[1], m[2]));
  }
  return nodeFetch(input, init);
};
globalThis.webkit = { messageHandlers: {
  engineNet: { postMessage: engineNet },
  engineLog: { postMessage: (line) => { if (line !== 'ready' && !/warn \[(rpc|notes|withdraw|transfer)/.test(line)) say('    page:', line); } },
} };
// The `openclears` mutation runs the engine as it was before the review of
// 2026-10-26 (finding 8): `open` wiping every prepared handle, so a handle
// prepared under one account cannot be relayed after another was opened.
if (MUTATION === 'openclears') {
  const src = readFileSync(join(here, 'src/engine.js'), 'utf8');
  const anchor = "addressSchema: AddressSchema }, { logger: logger('relayer') });\n";
  if (!src.includes(anchor)) throw new Error('the openclears mutation found nothing to change');
  writeFileSync(join(here, 'src/.engine-mutated.js'), src.replace(anchor, anchor + '    prepared.clear();\n'));
  await import('./src/.engine-mutated.js');
} else {
  await import('./src/engine.js');
}
async function engine(method, params = {}) {
  const reply = JSON.parse(await globalThis.casberiEngine.call(method, JSON.stringify(params)));
  if (!reply.ok) throw Object.assign(new Error(`${method}: ${reply.error.name}: ${reply.error.message}`), { engine: reply.error });
  return reply.value;
}

// -------------------------------------------------------------- set up
const abi = parseAbi([
  'function balanceOf(address) view returns (uint256)',
  'function approve(address,uint256) returns (bool)',
  'function withdraw(uint256)',
  'function redeemToUnderlying(uint256 shares, address receiver) returns (uint256)',
  'function previewRedeem(uint256) view returns (uint256)',
  'function exchangeRate() view returns (uint256)',
  'function assets(address) view returns (address pool, uint256 minimumDepositAmount, uint256 vettingFeeBPS, uint256 maxRelayFeeBPS)',
]);

// ------------------------------------------- your account, as the app makes it
// THE ACCOUNT IS A REAL SAFE PROXY (the review of 2026-10-26, finding 1).
// Until then the harness read `ProxyCreation`'s DATA word for the proxy, but
// the proxy is the event's indexed topic and the data is the SINGLETON: the
// "account" carried SafeL2's whole code, whose `receive` is cheap, so a
// 2,300-gas `transfer` into it (WETH's `withdraw`) landed here and is
// refused for every real account. Now the account is made exactly as the
// app makes it (`YourAccount.initializer`): SafeProxyFactory 1.4.1's
// `createProxyWithNonce(SafeL2 1.4.1, setup(...), 0)` — the shared passkey
// signer the one owner, threshold 1, the 4337 module enabled and the
// fallback handler, the key configured, both set-up steps delegate-called
// through MultiSend — run in the fork's first block, so the account IS a
// 1.4.1 proxy with that storage. (The 7579 adapter is not installed: the app
// installs it only in simulation, `YourAccount7579`, so an account on
// mainnet has the 4337 module alone.)
//
// Each of the account's moves is then run twice, as production runs it:
// first as the app's own check before Face ID (`YourAccountChain.check`:
// each call top-level FROM the account, its code cold), then as the
// operation executes on chain (the EntryPoint calling the account's
// `executeUserOp` through the 4337 module: one delegatecall to MultiSend
// carrying every call and the key change). Both must land.
const MULTISEND = '0x38869bf66a61cF6bDB996A6aE40D5853Fd43B526';
const MODULE_4337 = '0x75cf11467937ce3F2f357CE24ffc3DBF8fD5c226';
const MODULE_SETUP = '0x2dd68b007B46fBe91B9A7c3EDa5A7a1063cB5b47';
const SHARED_SIGNER = '0x94a4F6affBd8975951142c3999aEAB7ecee555c2';
const ENTRYPOINT_07 = '0x0000000071727De22E5E9d8BAf0edAc6f37da032';
// `SafeWebAuthn.verifiersWord`: RIP-7212's precompile (0x0100) above Daimo's verifier.
const VERIFIERS = BigInt('0x0100c2b78104907F722DABAc4C69f826a522B2754De4');
const DEPLOYER = '0x00000000000000000000000000000000000De910';
const safeAbi = parseAbi([
  'function setup(address[] owners, uint256 threshold, address to, bytes data, address fallbackHandler, address paymentToken, uint256 payment, address paymentReceiver)',
  'function enableModules(address[] modules)',
  'function configure((uint256 x, uint256 y, uint176 verifiers) signer)',
  'function multiSend(bytes transactions)',
  'function createProxyWithNonce(address singleton, bytes initializer, uint256 saltNonce) returns (address)',
  'function executeUserOp(address to, uint256 value, bytes data, uint8 operation)',
  'function getOwners() view returns (address[])',
  'function getThreshold() view returns (uint256)',
  'function isModuleEnabled(address) view returns (bool)',
  'function transfer(address,uint256) returns (bool)',
  'function unwrapWETH9(uint256 amountMinimum, address recipient)',
]);
// Ethereum's pinned Uniswap SwapRouter02 (`YourAccountSwap.Book.ethereum`), the one that unwraps (prd §1559).
const SWAP_ROUTER02 = '0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45';

// MultiSend 1.4.1's packed transactions: operation, to, value, length, data.
function multiSendData(calls) {
  const packed = calls.map((c) => `${(c.operation ?? 0).toString(16).padStart(2, '0')}${c.to.slice(2).toLowerCase()}${pad(toHex(BigInt(c.value ?? 0))).slice(2)}${pad(toHex(BigInt((c.data.length - 2) / 2))).slice(2)}${c.data.slice(2)}`).join('');
  return encodeFunctionData({ abi: safeAbi, functionName: 'multiSend', args: [`0x${packed}`] });
}
const randomWord = () => BigInt(toHex(crypto.getRandomValues(new Uint8Array(32))));
const configureData = (x, y) => encodeFunctionData({ abi: safeAbi, functionName: 'configure', args: [{ x, y, verifiers: VERIFIERS }] });

// `YourAccount.initializer(x:y:)`, byte for byte.
function initializer(x, y) {
  const enable = encodeFunctionData({ abi: safeAbi, functionName: 'enableModules', args: [[MODULE_4337]] });
  const setupData = multiSendData([{ operation: 1, to: MODULE_SETUP, data: enable }, { operation: 1, to: SHARED_SIGNER, data: configureData(x, y) }]);
  return encodeFunctionData({ abi: safeAbi, functionName: 'setup', args: [[SHARED_SIGNER], 1n, MULTISEND, setupData, MODULE_4337,
    '0x0000000000000000000000000000000000000000', 0n, '0x0000000000000000000000000000000000000000'] });
}

// A new account: a random passkey (the shared signer only stores it), its
// address read from the factory's own simulated create.
async function makeAccount() {
  const init = initializer(randomWord(), randomWord());
  const data = encodeFunctionData({ abi: safeAbi, functionName: 'createProxyWithNonce', args: [SAFE_L2, init, 0n] });
  const r = await upstream(STATE_RPC, 'eth_call', [{ from: DEPLOYER, to: PROXY_FACTORY, data }, 'latest']);
  if (r.error) throw new Error(`the factory refused the account: ${JSON.stringify(r.error)}`);
  return { address: getAddress(`0x${r.result.slice(26, 66)}`), create: { from: DEPLOYER, to: PROXY_FACTORY, data, note: 'SafeProxyFactory.createProxyWithNonce' } };
}

// USDC's balance slot for an address (FiatTokenV2: mapping at slot 9).
const usdcSlot = (who) => keccak256(`0x${pad(who).slice(2)}${pad(toHex(9)).slice(2)}`);

// A fork whose first block creates the accounts (funded by overrides first:
// CREATE2 may land on an address that already holds ETH), then proves each
// is the app's account: a proxy of SafeL2 1.4.1, the shared signer its one
// owner, threshold 1, the 4337 module on.
async function newFork(accounts, { usdc } = {}) {
  const head = Number(BigInt((await upstream(STATE_RPC, 'eth_blockNumber', [])).result)) - 2;
  const overrides = {};
  for (const a of accounts) overrides[a.address] = { balance: toHex(10n ** 18n) };
  if (usdc) overrides[USDC] = { stateDiff: Object.fromEntries(accounts.map((a) => [usdcSlot(a.address), pad(toHex(usdc))])) };
  fork = new SimFork(head, overrides);
  await fork.commit('your account created (SafeL2 1.4.1 proxy, the app\'s setup)', accounts.map((a) => a.create));
  for (const a of accounts) {
    const q = async (fn, args = []) => (await fork.call({ to: a.address, data: encodeFunctionData({ abi: safeAbi, functionName: fn, args }) })).result;
    const singleton = (await fork.call({ to: a.address, data: '0xa619486e' })).result; // the proxy's masterCopy()
    const owners = await q('getOwners'), threshold = await q('getThreshold'), module = await q('isModuleEnabled', [MODULE_4337]);
    if (BigInt(singleton ?? 0) !== BigInt(SAFE_L2) || !owners?.toLowerCase().includes(SHARED_SIGNER.slice(2).toLowerCase())
        || BigInt(threshold ?? 0) !== 1n || BigInt(module ?? 0) !== 1n) {
      throw new Error(`${a.address} is not the app's account (singleton ${singleton}, threshold ${threshold}, module ${module})`);
    }
  }
  return fork;
}

// One operation of the account, as production runs it (see above): the app's
// check first, then the EntryPoint's `executeUserOp` through the 4337 module,
// one MultiSend with the calls and the key change. `check: false` only for a
// mutation that must be refused ON CHAIN (not by the check).
async function accountOp(label, from, calls, { check = true } = {}) {
  let checked = [];
  if (check) {
    const r = await fork.simulate(calls.map((c) => ({ from, to: c.to, data: c.data ?? '0x', value: c.value ?? '0x0' })));
    const bad = r.at(-1).calls.findIndex((c) => c.status !== '0x1');
    if (bad >= 0) {
      const c = r.at(-1).calls[bad];
      throw new Error(`${label}: the app's check before Face ID refuses call ${bad} (${calls[bad].note ?? calls[bad].to}): ${c.error?.message ?? ''} ${c.returnData ?? ''}`);
    }
    checked = r.at(-1).calls.map((c) => Number(BigInt(c.gasUsed)));
  }
  const batch = [...calls.map((c) => ({ operation: 0, to: c.to, value: c.value ?? 0, data: c.data ?? '0x' })),
    { operation: 1, to: SHARED_SIGNER, value: 0, data: configureData(randomWord(), randomWord()) }];
  const data = encodeFunctionData({ abi: safeAbi, functionName: 'executeUserOp', args: [MULTISEND, 0n, multiSendData(batch), 1] });
  const block = await fork.commit(`${label} (the operation, through the 4337 module)`, [{ from: ENTRYPOINT_07, to: from, data, note: `${label}: executeUserOp` }]);
  return { block, gas: Number(BigInt(block.calls[0].gasUsed)), checkGas: checked };
}

const read = async (to, fn, a = [], from) => {
  const r = await fork.call({ to, data: encodeFunctionData({ abi, functionName: fn, args: a }), from });
  if (r.error) throw new Error(`${fn}: reverted`);
  return BigInt(r.result.slice(0, 66));
};
const ethOf = async (who) => BigInt((await fork.simulate([{ from: who, to: '0xcA11bde05977b3631167028862bE2a173976CA11',
  data: encodeFunctionData({ abi: parseAbi(['function getEthBalance(address) view returns (uint256)']), functionName: 'getEthBalance', args: [who] }) }])).at(-1).calls[0].returnData);

const asCalls = (from, txs, note) => txs.map((tx, i) => ({ from, to: tx.to, data: tx.data, value: tx.value, note: `${note} ${i + 1}` }));


// ------------------------------------------------- shared by the new moves
// 0xBow's approval, stood in for (see the header): labels in a copy of the
// real association set, its root served by the registry through a code override.
async function approveStandIn(labelHashes) {
  aspExtra.labelHashes.push(...labelHashes);
  const leaves = (await (await nodeFetch(`${ETHEREUM.aspUrl}/association-set/leaves?chainId=1&entrypoint=${ETHEREUM.entrypoint}`)).json()).leaves;
  const merkle = new MerkleService({ hashService: await PoseidonHashService.create() });
  const all = [...leaves, ...aspExtra.labelHashes];
  const proof = await merkle.generateMerkleProof(all.map((x) => toHex(BigInt(x))), toHex(BigInt(labelHashes[0])));
  aspExtra.root = toHex(BigInt(proof.root));
  fork.overrides = { ...fork.overrides, [ETHEREUM.aspRegistry]: { code: `0x7f${pad(aspExtra.root).slice(2)}60005260206000f3` } };
  return leaves.length;
}

// A captured relay body's proof, in the contracts' layout (the SDK's
// `restructureTransactPubSignals`): nullifiers, commitments, then one-element
// rows for the roots, amount, token, context.
function proofArg(sent) {
  const pr = sent.proof;
  const sig = pr.publicSignals.map(BigInt);
  const n = sent.inputNullifierNumber, m = sent.outputCommitmentNumber;
  const pubs = [sig.slice(0, n), sig.slice(n, n + m), ...sig.slice(n + m, n + m + 6).map((x) => [x])];
  return {
    pA: pr.pi_a ? pr.pi_a.slice(0, 2).map(BigInt) : pr.pA.map(BigInt),
    pB: pr.pi_b ? [[BigInt(pr.pi_b[0][1]), BigInt(pr.pi_b[0][0])], [BigInt(pr.pi_b[1][1]), BigInt(pr.pi_b[1][0])]] : pr.pB.map((r) => r.map(BigInt)),
    pC: pr.pi_c ? pr.pi_c.slice(0, 2).map(BigInt) : pr.pC.map(BigInt),
    pubSignals: pubs.map((r) => r.map(BigInt)),
  };
}
const routerAbi = parseAbi(['function withdrawToUnderlying((uint256[2] pA, uint256[2][2] pB, uint256[2] pC, uint256[][] pubSignals) proof, (address processor, bytes data) transactParams, (bytes32 hint, bytes data)[] noteData, uint256 minUnderlyingOut) payable returns (uint256, uint256)']);
const vaultAbi = parseAbi(['function transact((uint256[2] pA, uint256[2][2] pB, uint256[2] pC, uint256[][] pubSignals) proof, (address processor, bytes data) transactParams, (bytes32 hint, bytes data)[] noteData)']);

// The router's withdrawal the relayer would post for a captured body.
function relayedWithdrawCall(sent) {
  const data = encodeFunctionData({ abi: routerAbi, functionName: 'withdrawToUnderlying', args: [
    proofArg(sent), { processor: sent.processorAddress, data: sent.signedFeeCommitment.data },
    sent.noteData.map((n) => ({ hint: n.hint, data: n.data })), BigInt(sent.minUnderlyingOut)] });
  return { from: ETHEREUM.relayerAddress, to: sent.processorAddress, data, note: 'router.withdrawToUnderlying' };
}

// A transfer, as the relayer posts it: PoolVault.transact from its signer.
async function commitRelayedTransfer(sent) {
  let commitment = sent.signedFeeCommitment;
  const data = encodeFunctionData({ abi: vaultAbi, functionName: 'transact', args: [
    proofArg(sent), { processor: ETHEREUM.transferProcessor, data: commitment.data },
    sent.noteData.map((n) => ({ hint: n.hint, data: n.data }))] });
  return fork.commit('relayed transfer', [{ from: ETHEREUM.relayerAddress, to: ETHEREUM.pool, data, note: 'PoolVault.transact' }]);
}

// Today's fees as a fresh address's send would offer them: the price, the
// tip, and the cap (twice the price plus the tip, `FreshTx.fees`).
async function fees() {
  const price = BigInt((await upstream(STATE_RPC, 'eth_gasPrice', [])).result);
  const tip = BigInt((await upstream(STATE_RPC, 'eth_maxPriorityFeePerGas', [])).result ?? '0x0');
  const t = tip > 0n ? tip : 1n;
  return { price, tip: t, maxFee: (2n * price > t ? 2n * price : t) + t };
}

// A yield pool's smallest deposit in its TOKEN: the Entrypoint's minimum
// (in shares) at today's rate, rounded up.
async function minimumUnderlying(pool) {
  const r = await fork.call({ to: ETHEREUM.entrypoint, data: encodeFunctionData({ abi, functionName: 'assets', args: [pool.share] }) });
  const minShares = BigInt('0x' + r.result.slice(66, 130));
  const rate = await read(pool.share, 'exchangeRate');
  return { minShares, rate, minUnderlying: (minShares * rate + 10n ** BigInt(pool.shareDecimals) - 1n) / 10n ** BigInt(pool.shareDecimals) };
}

// The fresh address's own transactions run with VALIDATION: its nonce, the
// fee cap over the block's base fee, and its balance paying the gas at the
// cap plus the value — what a node checks before it takes a signed one.
// Other accounts' calls in the same blocks are plain EOAs here (validation
// refuses a sender with code), each funded by an override.
async function validated(blocks, overrides) {
  const r = await upstream(STATE_RPC, 'eth_simulateV1', [{ blockStateCalls: blocks.map((calls, i) => ({
    ...(i === 0 ? { stateOverrides: overrides } : {}), calls })), validation: true }, toHex(fork.head)]);
  if (r.error) throw new Error(`validated: ${JSON.stringify(r.error).slice(0, 300)}`);
  return r.result;
}
const FRESH_GAS = 1_250_000n;
const FRESH_APPROVE_GAS = 80_000n;

// One seed per run: a new private account, nobody's.
const seed = toHex(crypto.getRandomValues(new Uint8Array(32)));
// Your account: a real SafeL2 1.4.1 proxy, made as the app makes it (above).
const A = await makeAccount();
const account = A.address;

async function openAndRegister() {
  const opened = await engine('open', { seed, revocableKeyIndex: '0x0', owner: account, network: ETHEREUM });
  const reg = await engine('prepareRegister');
  say(`  opened (keys ${opened.keysMs} ms); registration: ${reg.txs.length} calls, both to the keystore from the account`);
  for (const tx of reg.txs) if (tx.to.toLowerCase() !== ETHEREUM.keystore.toLowerCase()) throw new Error('registration not to the keystore');
  return reg;
}

async function yieldDeposit(token, budget, reg, note) {
  const d = await engine('prepareYieldDeposit', { tokenId: token, budget: toHex(budget) });
  say(`  ${note}: ${d.shares} shares for at most ${BigInt(d.maxUnderlyingIn)} (needs ${BigInt(d.underlyingNeeded)}); proof ${d.proofs.map((p) => `${p.circuit} ${p.ms} ms`).join(', ')}; to ${d.tx.to}`);
  let tx = d.tx;
  if (MUTATION === 'value' && token === ETH) tx = { ...tx, value: toHex(BigInt(d.underlyingNeeded) - 1n) };
  if (MUTATION === 'proof') tx = { ...tx, data: tx.data.slice(0, 20) + (tx.data[20] === 'a' ? 'b' : 'a') + tx.data.slice(21) };
  const calls = [...asCalls(account, reg?.txs ?? [], 'register'), ...asCalls(account, d.approvals, 'approve'), { from: account, ...tx, note: 'deposit' }];
  const op = await accountOp(note, account, calls);
  const gas = op.checkGas;
  say(`  ${note}: LANDS — the app's check (gas ${gas.join(' + ')} = ${gas.reduce((a, b) => a + b, 0)}) and the operation from the Safe proxy (${op.gas})`);
  return { d, gas, opGas: op.gas };
}

// ------------------------------------------------------------ scenarios
const out = {};
for (const name of SCENARIOS) {
  say(`\n${name}${MUTATION ? ` (mutation: ${MUTATION})` : ''}`);
  const t0 = performance.now();
  try {
    if (name === 'eth') {
      await newFork([A]);
      const reg = await openAndRegister();
      const before = await ethOf(account);
      const { d, gas, opGas } = await yieldDeposit(ETH, 10n ** 16n, reg, 'register + 0.01 ETH into ppETH');
      const spent = before - await ethOf(account);
      const shares = await read(ETHEREUM.yield[0].share, 'balanceOf', [ETHEREUM.pool]);
      // ppETH's router takes the budget as the value and pays back what it
      // did not use. Into a COLD Safe proxy (the app's check) a 2,300-gas
      // refund would revert the deposit (finding 1's question): it lands, so
      // the router refunds with a full-gas call — measured, the refund > 0.
      const refund = BigInt(d.tx.value) - spent;
      if (refund <= 0n) throw new Error(`no refund was made (value ${BigInt(d.tx.value)}, spent ${spent}): the refund path is unproven`);
      out.eth = { shares: BigInt(d.shares).toString(), value: BigInt(d.tx.value).toString(), spentWei: spent.toString(), refundWei: refund.toString(),
        underlyingNeeded: BigInt(d.underlyingNeeded).toString(), gas, opGas, poolShares: shares.toString() };
      say(`  the account spent ${spent} wei of the ${BigInt(d.tx.value)} sent: the router refunded ${refund} wei into the Safe proxy, cold, with a full-gas call`);
    }
    if (name === 'usdc') {
      await newFork([A], { usdc: 50_000_000n });
      const reg = await openAndRegister();
      const { d, gas } = await yieldDeposit(USDC, 20_000_000n, reg, 'register + 20 USDC into ppUSDC');
      const left = await read(USDC, 'balanceOf', [account]);
      out.usdc = { shares: BigInt(d.shares).toString(), usdcSpent: (50_000_000n - left).toString(), gas, approvals: d.approvals.length };
      say(`  the account spent ${(50_000_000n - left)} USDC units of a 20 USDC budget`);
    }
    if (name === 'ragequit') {
      await newFork([A]);
      const reg = await openAndRegister();
      const { d } = await yieldDeposit(ETH, 10n ** 16n, reg, 'register + 0.01 ETH into ppETH');
      if (process.env.SIM_DEBUG) say(`    head ${fork.head} (${toHex(fork.head)}); simulated logs at ${[...new Set(fork.logs().map((l) => l.blockNumber))]}; keystore topics ${fork.logs().filter((l) => l.address.toLowerCase() === ETHEREUM.keystore.toLowerCase()).map((l) => l.topics[0].slice(0, 10))}`);
      const found = await engine('discover');
      const note = found.notes.find((n) => n.commitment.toLowerCase() === d.commitment.toLowerCase());
      if (!note) throw new Error(`the deposit was not discovered (${found.notes.length} notes; ${fork.logs().length} simulated logs: ${JSON.stringify(fork.logs()[0] ?? {}).slice(0, 300)})`);
      say(`  discovered: ${found.notes.length} note(s), ${note.status}, ${BigInt(note.value)} shares`);
      const rq = await engine('prepareRagequit', { commitment: note.commitment });
      say(`  ragequit proved (${rq.proofs.map((p) => `${p.circuit} ${p.ms} ms`).join(', ')}); pays ${rq.recipient}`);
      if (rq.recipient.toLowerCase() !== account.toLowerCase()) throw new Error('ragequit does not pay the account');
      if (MUTATION === 'notowner') {
        // Someone other than the owner sends the ragequit: the pool refuses.
        await fork.commit('take it back, not the owner', [{ from: '0x000000000000000000000000000000000000bEEF', ...rq.tx, note: 'ragequit' }]);
      }
      const before = await ethOf(account);
      const pool = ETHEREUM.yield[0];
      const value = BigInt(rq.value);
      // Take it back as the app sends it (`PrivateOnEthereum.takeBack`,
      // `PrivateYield.takeBackCalls`): what the shares are worth is read
      // BEFORE Face ID (`previewRedeem`), then ONE operation — the ragequit,
      // the zap's approval and `redeemToUnderlying`, and the WETH unwrapped
      // through the pinned SwapRouter02 (WETH's `transfer` of exactly that
      // much to the router, then its `unwrapWETH9(worth, account)`, which
      // pays with a full-gas call). WETH's own `withdraw` pays a 2,300-gas
      // `transfer` the Safe proxy cannot take cold: the `wethwithdraw`
      // mutation sends it, and the app's check must refuse it.
      const worth = await read(pool.share, 'previewRedeem', [value]);
      const unwrap = MUTATION === 'wethwithdraw'
        ? [{ to: pool.underlying, data: encodeFunctionData({ abi, functionName: 'withdraw', args: [worth] }), note: "WETH's own withdraw" }]
        : [{ to: pool.underlying, data: encodeFunctionData({ abi: safeAbi, functionName: 'transfer', args: [SWAP_ROUTER02, worth] }), note: 'WETH to the router' },
           { to: SWAP_ROUTER02, data: encodeFunctionData({ abi: safeAbi, functionName: 'unwrapWETH9', args: [worth, account] }), note: 'router.unwrapWETH9' }];
      const calls = [
        { ...rq.tx, note: 'ragequit' },
        { to: pool.share, data: encodeFunctionData({ abi, functionName: 'approve', args: [pool.zap, value] }), note: 'approve zap' },
        { to: pool.zap, data: encodeFunctionData({ abi, functionName: 'redeemToUnderlying', args: [value, account] }), note: 'zap: shares to WETH' },
        ...unwrap,
      ];
      const op = await accountOp('take it back', account, calls);
      const back = await ethOf(account) - before;
      const wethLeft = await read(pool.underlying, 'balanceOf', [account]);
      if (back < worth) throw new Error(`the account got ${back} wei back for shares worth ${worth}`);
      out.ragequit = { shares: value.toString(), worth: worth.toString(), ethBack: back.toString(), wethLeft: wethLeft.toString(), gas: op.checkGas, opGas: op.gas, recipient: rq.recipient,
        calls: calls.map((c) => `${c.to.toLowerCase()} ${c.data.slice(0, 10)}`) };
      say(`  Take it back LANDS as one operation from the Safe proxy: ${value} shares -> ${back} wei of ETH (worth ${worth} read before; ${wethLeft} wei of WETH left; check gas ${op.checkGas.join(' + ')}, operation ${op.gas})`);
    }
    if (name === 'withdraw') {
      await newFork([A]);
      const reg = await openAndRegister();
      const { d } = await yieldDeposit(ETH, 10n ** 16n, reg, 'register + 0.01 ETH into ppETH');
      // 0xBow's approval, stood in for (see the header): the label in a copy
      // of the real set, its root served by the registry.
      aspExtra.labelHashes.push(d.labelHash);
      const leaves = (await (await nodeFetch(`${ETHEREUM.aspUrl}/association-set/leaves?chainId=1&entrypoint=${ETHEREUM.entrypoint}`)).json()).leaves;
      const merkle = new MerkleService({ hashService: await PoseidonHashService.create() });
      const proof = await merkle.generateMerkleProof([...leaves, d.labelHash].map((x) => toHex(BigInt(x))), toHex(BigInt(d.labelHash)));
      aspExtra.root = toHex(BigInt(proof.root));
      const rootCode = `0x7f${pad(aspExtra.root).slice(2)}60005260206000f3`;
      fork.overrides = { ...fork.overrides, [ETHEREUM.aspRegistry]: { code: rootCode } };
      say(`  approval stood in for: ${leaves.length} real leaves + this label, root ${aspExtra.root.slice(0, 12)}…`);
      const found = await engine('discover');
      const note = found.notes.find((n) => n.commitment.toLowerCase() === d.commitment.toLowerCase());
      say(`  discovered: ${note?.status} ${note ? BigInt(note.value) : '-'} shares`);
      const recipient = getAddress(toHex(crypto.getRandomValues(new Uint8Array(20))));
      const amount = 5n * 10n ** 15n; // 0.005 ETH to the recipient
      const w = await engine('prepareWithdraw', { tokenId: ETH, amount: toHex(amount), recipient });
      say(`  withdrawal proved (${w.proofs.map((p) => `${p.circuit} ${p.ms} ms`).join(', ')}); relayer fee ${BigInt(w.fee.feeAmount)} shares at ${BigInt(w.fee.gasPrice)} wei gas`);
      // Finding 8: another account is opened between this prepare and its
      // relay (the fresh watch, a second root): the handle still relays THIS
      // account's own proof, through its own sessions.
      const other = await makeAccount();
      await engine('open', { seed: toHex(crypto.getRandomValues(new Uint8Array(32))), revocableKeyIndex: '0x0', owner: other.address, network: ETHEREUM });
      await engine('relay', { handle: w.handle });
      say('  another account opened between the proof and its relay: the handle relayed its own account\'s proof');
      const sent = relayCaptured.at(-1);
      if (!sent) throw new Error('nothing was handed to the relayer');
      // What the relayer would post: the router's withdrawToUnderlying with
      // the proof, the relayer's own signed routing and the floor, sent from
      // the relayer's signer. The vault checks the processor (the router).
      const routerAbi = parseAbi(['function withdrawToUnderlying((uint256[2] pA, uint256[2][2] pB, uint256[2] pC, uint256[][] pubSignals) proof, (address processor, bytes data) transactParams, (bytes32 hint, bytes data)[] noteData, uint256 minUnderlyingOut) payable returns (uint256, uint256)']);
      const pr = sent.proof;
      if (process.env.SIM_DEBUG) say('    relay body', Object.keys(sent), 'proof', Object.keys(pr), JSON.stringify(pr).slice(0, 600));
      // The SDK's own layout (`restructureTransactPubSignals`): nullifiers,
      // commitments, then one-element rows for the roots, amount, token, context.
      const sig = pr.publicSignals.map(BigInt);
      const n = sent.inputNullifierNumber, m = sent.outputCommitmentNumber;
      const pubs = [sig.slice(0, n), sig.slice(n, n + m), ...sig.slice(n + m, n + m + 6).map((x) => [x])];
      let data = encodeFunctionData({ abi: routerAbi, functionName: 'withdrawToUnderlying', args: [
        { pA: pr.pi_a ? pr.pi_a.slice(0, 2).map(BigInt) : pr.pA.map(BigInt),
          pB: pr.pi_b ? [[BigInt(pr.pi_b[0][1]), BigInt(pr.pi_b[0][0])], [BigInt(pr.pi_b[1][1]), BigInt(pr.pi_b[1][0])]] : pr.pB.map((r) => r.map(BigInt)),
          pC: pr.pi_c ? pr.pi_c.slice(0, 2).map(BigInt) : pr.pC.map(BigInt),
          pubSignals: pubs.map((r) => r.map(BigInt)) },
        { processor: sent.processorAddress, data: sent.signedFeeCommitment.data },
        sent.noteData.map((n) => ({ hint: n.hint, data: n.data })),
        BigInt(sent.minUnderlyingOut),
      ] });
      if (MUTATION === 'recipient') {
        // A different recipient in the routing than the proof was made for.
        const routing = sent.signedFeeCommitment.data;
        const other = pad(recipient.replace(/.$/, recipient.endsWith('0') ? '1' : '0')).slice(2);
        data = data.replace(routing.slice(2), other + routing.slice(66));
      }
      const before = await ethOf(recipient);
      const block = await fork.commit('relayed withdraw', [{ from: ETHEREUM.relayerAddress, to: sent.processorAddress, data, note: 'router.withdrawToUnderlying' }]);
      const got = await ethOf(recipient) - before;
      out.withdraw = { amount: amount.toString(), received: got.toString(), relayedAfterAnotherOpen: true, gas: Number(BigInt(block.calls[0].gasUsed)), processor: sent.processorAddress,
        feeShares: BigInt(w.fee.feeAmount).toString(), minUnderlyingOut: BigInt(sent.minUnderlyingOut).toString() };
      say(`  relayed withdraw LANDS: the recipient got ${got} wei of native ETH (asked ${amount}); gas ${BigInt(block.calls[0].gasUsed)}`);
    }

    if (name === 'fresh') {
      // RECEIVE PRIVATELY ON ETHEREUM (prd §1567): a stranger pays a fresh
      // address; the fresh address — its key derived from the private root,
      // holding nothing but what it was paid — deposits it into ppETH for the
      // account, its gas out of what arrived. The account is registered first
      // (its first Face ID private move). "Too little to move" is computed
      // from the pool's minimum and today's fees, never a constant.
      await newFork([A]);
      const reg = await openAndRegister();
      await accountOp('register the account', account, asCalls(account, reg.txs, 'register'));
      const pool = ETHEREUM.yield[0];
      const { minShares, minUnderlying } = await minimumUnderlying(pool);
      const f = await fees();
      const reserve = FRESH_GAS * f.maxFee;
      const threshold = minUnderlying + reserve;
      say(`  today: gas ${f.price} wei (tip ${f.tip}), cap ${f.maxFee}; pool minimum ${minShares} shares = ${minUnderlying} wei; gas kept back ${reserve} wei`);
      say(`  too little to move below ${threshold} wei (${Number(threshold) / 1e18} ETH)`);
      // Below the pool's minimum the pool itself refuses the deposit.
      const underBudget = minUnderlying - minUnderlying / 50n;
      const under = await engine('prepareYieldDeposit', { tokenId: ETH, budget: toHex(underBudget) }).then((u) => u, () => null);
      if (under) {
        const r = await fork.simulate([{ from: account, ...under.tx }]);
        if (r.at(-1).calls[0].status === '0x1') throw new Error('a deposit under the pool minimum lands');
      }
      const fresh = getAddress(toHex(crypto.getRandomValues(new Uint8Array(20))));
      const payer = getAddress(toHex(crypto.getRandomValues(new Uint8Array(20))));
      const paid = threshold + threshold / 20n; // 5% over the threshold
      await fork.commit('a stranger pays the fresh address', [{ from: payer, to: fresh, value: toHex(paid), note: 'payment' }],
        { [payer]: { balance: toHex(10n ** 18n) } });
      const budget = MUTATION === 'freshgas' ? paid : paid - reserve;
      const d = await engine('prepareYieldDeposit', { tokenId: ETH, budget: toHex(budget) });
      if (d.tx.to.toLowerCase() !== pool.router.toLowerCase() || d.approvals.length || BigInt(d.tx.value) > budget) throw new Error('the deposit is not the plan');
      say(`  paid ${paid} wei; deposit of ${BigInt(d.shares)} shares for at most ${BigInt(d.tx.value)} wei to the router; proof ${d.proofs.map((p) => `${p.circuit} ${p.ms} ms`).join(', ')}`);
      // The node's own checks: nonce 0, the cap over the base fee, the balance
      // paying gas at the cap plus the value.
      const v = await validated([
        [{ from: payer, to: fresh, value: toHex(paid), nonce: '0x0', gas: toHex(21000n), maxFeePerGas: toHex(f.maxFee), maxPriorityFeePerGas: toHex(f.tip) }],
        [{ from: fresh, to: d.tx.to, data: d.tx.data, value: d.tx.value, nonce: '0x0', gas: toHex(FRESH_GAS), maxFeePerGas: toHex(f.maxFee), maxPriorityFeePerGas: toHex(f.tip) }],
      ], { [payer]: { balance: toHex(10n ** 18n) } });
      const vc = v[1].calls[0];
      if (vc.status !== '0x1') throw new Error(`the fresh address's deposit, validated, fails: ${vc.error?.message ?? vc.returnData}`);
      const block = await fork.commit('the fresh address deposits', [{ from: fresh, ...d.tx, gas: toHex(FRESH_GAS), note: 'fresh deposit' }]);
      const gasUsed = BigInt(block.calls[0].gasUsed);
      const left = await ethOf(fresh);
      if (left < gasUsed * f.maxFee) throw new Error(`the fresh address could not pay its gas: ${left} left for ${gasUsed * f.maxFee}`);
      const found = await engine('discover');
      const note = found.notes.find((n) => n.commitment.toLowerCase() === d.commitment.toLowerCase());
      if (!note) throw new Error('the account did not find the fresh deposit');
      out.fresh = { paid: paid.toString(), threshold: threshold.toString(), minUnderlying: minUnderlying.toString(), reserve: reserve.toString(),
        maxFee: f.maxFee.toString(), shares: BigInt(d.shares).toString(), gas: Number(gasUsed), validatedGas: Number(BigInt(vc.gasUsed)),
        dust: (left - gasUsed * f.maxFee).toString(), status: note.status, underRefused: true };
      say(`  validated as a node takes a signed one (gas ${BigInt(vc.gasUsed)}), then LANDS: ${gasUsed} gas; ${left - gasUsed * f.maxFee} wei of dust stays; the account found it (${note.status})`);
    }
    if (name === 'transfer') {
      // BALANCE TO BALANCE (prd §1567): A's private ETH to B's private
      // account, found by B's owner address in the keystore; 0xBow's relayer
      // posts PoolVault.transact; B finds the note. An address with no
      // private account is refused, so the app pays it out publicly instead.
      const B = await makeAccount();
      const accountB = B.address;
      const seedB = toHex(crypto.getRandomValues(new Uint8Array(32)));
      await newFork([A, B]);
      await engine('open', { seed: seedB, revocableKeyIndex: '0x0', owner: accountB, network: ETHEREUM });
      const regB = await engine('prepareRegister');
      await accountOp('B registers', accountB, asCalls(accountB, regB.txs, 'register B'));
      const reg = await openAndRegister();
      const { d } = await yieldDeposit(ETH, 10n ** 16n, reg, 'A: register + 0.01 ETH into ppETH');
      await approveStandIn([d.labelHash]);
      await engine('discover');
      const stranger = getAddress(toHex(crypto.getRandomValues(new Uint8Array(20))));
      const refused = await engine('prepareTransfer', { tokenId: ETH, amount: toHex(10n ** 15n), recipient: stranger }).then(() => null, (e) => e.engine?.name);
      if (refused !== 'RecipientViewingKeyUnregistered') throw new Error(`a transfer to an address with no private account was not refused (${refused})`);
      const amount = 5n * 10n ** 15n;
      const to = MUTATION === 'transferto' ? stranger : accountB;
      const t = await engine('prepareTransfer', { tokenId: ETH, amount: toHex(amount), recipient: to });
      say(`  transfer proved (${t.proofs.map((p) => `${p.circuit} ${p.ms} ms`).join(', ')})`);
      const relayed = await engine('relay', { handle: t.handle });
      const block = fork.results.at(-1);
      say(`  relayed transfer LANDS: PoolVault.transact from the relayer's signer, gas ${BigInt(block.calls[0].gasUsed)}`);
      await engine('open', { seed: seedB, revocableKeyIndex: '0x0', owner: accountB, network: ETHEREUM });
      const foundB = await engine('discover');
      const got = foundB.notes.filter((n) => n.tokenId.toLowerCase() === ETHEREUM.yield[0].share.toLowerCase()).reduce((a, n) => a + BigInt(n.value), 0n);
      if (got === 0n) throw new Error('B found no note');
      out.transfer = { amountWei: amount.toString(), sharesToB: got.toString(), notesB: foundB.notes.length, gas: Number(BigInt(block.calls[0].gasUsed)), refusedUnregistered: refused };
      say(`  B found ${got} shares (${foundB.notes.length} note(s)); an address with no private account: ${refused}`);
    }
    if (name === 'usdcsend') {
      // SEND PRIVATELY FROM PRIVATE USDC (prd §1567): 20 USDC into ppUSDC,
      // approved (stood in for), then 10 USDC to a plain address, relayed:
      // the router pays USDC.
      await newFork([A], { usdc: 50_000_000n });
      const reg = await openAndRegister();
      const { d } = await yieldDeposit(USDC, 20_000_000n, reg, 'register + 20 USDC into ppUSDC');
      await approveStandIn([d.labelHash]);
      await engine('discover');
      const recipient = getAddress(toHex(crypto.getRandomValues(new Uint8Array(20))));
      const amount = 10_000_000n;
      const w = await engine('prepareWithdraw', { tokenId: USDC, amount: toHex(amount), recipient });
      await engine('relay', { handle: w.handle });
      const block = await fork.commit('relayed USDC withdraw', [relayedWithdrawCall(relayCaptured.at(-1))]);
      const got = await read(USDC, 'balanceOf', [recipient]);
      if (got < amount) throw new Error(`the recipient got ${got} of ${amount} USDC units`);
      out.usdcsend = { amount: amount.toString(), received: got.toString(), feeShares: BigInt(w.fee.feeAmount).toString(), gas: Number(BigInt(block.calls[0].gasUsed)) };
      say(`  relayed USDC LANDS: the recipient got ${got} USDC units (asked ${amount}); fee ${BigInt(w.fee.feeAmount)} ppUSDC shares; gas ${BigInt(block.calls[0].gasUsed)}`);
    }
    if (name === 'freshusdc') {
      // PRIVATE USDC TO A FRESH ADDRESS, NO GATEKEEPER (prd §1567): USDC
      // arrives at a fresh address that holds no ETH. The private balance
      // pays its gas: a relayed private withdrawal of just enough ETH from
      // private ETH to the fresh address (nothing links it to the account),
      // then the fresh address approves and deposits the USDC into ppUSDC.
      await newFork([A]);
      const reg = await openAndRegister();
      const { d } = await yieldDeposit(ETH, 10n ** 16n, reg, 'register + 0.01 ETH into ppETH (private ETH)');
      await approveStandIn([d.labelHash]);
      await engine('discover');
      const fresh = getAddress(toHex(crypto.getRandomValues(new Uint8Array(20))));
      const arrived = 25_000_000n;
      fork.overrides[USDC] = { stateDiff: { ...(fork.overrides[USDC]?.stateDiff ?? {}), [usdcSlot(fresh)]: pad(toHex(arrived)) } };
      const f = await fees();
      const need = (FRESH_APPROVE_GAS + FRESH_GAS) * f.maxFee;
      const gasWei = MUTATION === 'usdcgas' ? need / 2n : need;
      const w = await engine('prepareWithdraw', { tokenId: ETH, amount: toHex(gasWei), recipient: fresh });
      await engine('relay', { handle: w.handle });
      await fork.commit('relayed: gas to the fresh address', [relayedWithdrawCall(relayCaptured.at(-1))]);
      const ethAt = await ethOf(fresh);
      say(`  the private balance paid the fresh address ${ethAt} wei for gas (asked ${gasWei}, cap ${f.maxFee})`);
      const usdcPool = ETHEREUM.yield[1];
      const y = await engine('prepareYieldDeposit', { tokenId: USDC, budget: toHex(arrived) });
      if (y.tx.to.toLowerCase() !== usdcPool.router.toLowerCase() || BigInt(y.maxUnderlyingIn) > arrived) throw new Error('the USDC deposit is not the plan');
      const approve = { to: USDC, data: encodeFunctionData({ abi, functionName: 'approve', args: [usdcPool.router, BigInt(y.maxUnderlyingIn)] }), value: '0x0' };
      const v = await validated([
        [{ from: fresh, ...approve, nonce: '0x0', gas: toHex(FRESH_APPROVE_GAS), maxFeePerGas: toHex(f.maxFee), maxPriorityFeePerGas: toHex(f.tip) },
         { from: fresh, to: y.tx.to, data: y.tx.data, value: y.tx.value, nonce: '0x1', gas: toHex(FRESH_GAS), maxFeePerGas: toHex(f.maxFee), maxPriorityFeePerGas: toHex(f.tip) }],
      ], { [fresh]: { balance: toHex(ethAt) }, [USDC]: { stateDiff: { [usdcSlot(fresh)]: pad(toHex(arrived)) } } });
      const bad = v[0].calls.findIndex((c) => c.status !== '0x1');
      if (bad >= 0) throw new Error(`the fresh address's USDC deposit, validated, fails at call ${bad}: ${v[0].calls[bad].error?.message ?? v[0].calls[bad].returnData}`);
      await fork.commit('the fresh address deposits USDC', [{ from: fresh, ...approve, note: 'approve' }, { from: fresh, ...y.tx, note: 'ppUSDC deposit' }]);
      // A new session reads the pool again from the start (the first one's
      // scan has passed the simulated blocks' numbers), as a new launch would.
      await engine('open', { seed, revocableKeyIndex: '0x0', owner: account, network: ETHEREUM });
      const found = await engine('discover');
      const note = found.notes.find((n) => n.commitment.toLowerCase() === y.commitment.toLowerCase());
      if (!note) throw new Error('the account did not find the USDC deposit');
      const gas = v[0].calls.map((c) => Number(BigInt(c.gasUsed)));
      out.freshusdc = { arrived: arrived.toString(), gasPaidWei: ethAt.toString(), needWei: need.toString(), shares: BigInt(y.shares).toString(), gas, status: note.status };
      say(`  validated (gas ${gas.join(' + ')}), then LANDS: ${BigInt(y.shares)} ppUSDC shares for the account (${note.status})`);
    }
    if (name === 'roundups') {
      // ROUND-UPS INTO PRIVATE ON ETHEREUM (prd §1567): a send of USDC you
      // approve with Face ID carries the batch — everything counted, once it
      // reaches the pool's smallest deposit — into ppUSDC, in ONE operation.
      await newFork([A], { usdc: 100_000_000n });
      const reg = await openAndRegister();
      await accountOp('the account registered (an earlier private move)', account, asCalls(account, reg.txs, 'register'));
      const usdcPool = ETHEREUM.yield[1];
      const { minUnderlying } = await minimumUnderlying(usdcPool);
      const batch = minUnderlying + 500_000n; // the count reached the pool's minimum
      const y = await engine('prepareYieldDeposit', { tokenId: USDC, budget: toHex(batch) });
      const friend = getAddress(toHex(crypto.getRandomValues(new Uint8Array(20))));
      const send = { from: account, to: USDC, data: encodeFunctionData({ abi: parseAbi(['function transfer(address,uint256) returns (bool)']), functionName: 'transfer', args: [friend, 4_300_000n] }), note: 'the send: 4.30 USDC' };
      const op = await accountOp('one Face ID operation: the send and the round-ups', account, [send, ...asCalls(account, y.approvals, 'approve'), { from: account, ...y.tx, note: 'round-ups into ppUSDC' }]);
      const found = await engine('discover');
      if (!found.notes.find((n) => n.commitment.toLowerCase() === y.commitment.toLowerCase())) throw new Error('the round-ups note was not found');
      const gas = op.checkGas;
      // Finding 5: a ride the node refuses is DROPPED and the send goes
      // alone. Here the ride is a deposit with no approval before it (the
      // router cannot pull the USDC): the app's check of the send with it
      // refuses the ride's call, and the send alone lands, as the check and
      // as the operation.
      const y2 = await engine('prepareYieldDeposit', { tokenId: USDC, budget: toHex(batch) });
      const send2 = { ...send, note: 'the next send: 4.30 USDC' };
      const withRide = await fork.simulate([send2, { from: account, ...y2.tx }].map((c) => ({ from: account, to: c.to, data: c.data, value: c.value ?? '0x0' })));
      if (withRide.at(-1).calls[1].status === '0x1') throw new Error('the broken ride was not refused: nothing proves a refused ride is dropped');
      await accountOp('the send alone, the refused ride dropped', account, [send2]);
      out.roundups = { batch: batch.toString(), minUnderlying: minUnderlying.toString(), shares: BigInt(y.shares).toString(), gas,
        refusedRideDroppedSendLands: true };
      say(`  ONE operation LANDS: 4.30 USDC sent, ${batch} USDC units of round-ups into ppUSDC (${BigInt(y.shares)} shares); gas ${gas.join(' + ')}`);
    }
    record.scenarios[name] = { ok: true, seconds: Math.round((performance.now() - t0) / 1000), ...out[name] };
  } catch (error) {
    say(`  FAILED: ${String(error.message).slice(0, 400)}`);
    record.scenarios[name] = { ok: false, error: String(error.message).slice(0, 400) };
  } finally {
    await engine('close').catch(() => {});
    aspExtra.labelHashes.length = 0; aspExtra.root = null;
  }
}

record.head = fork?.head;
record.account = { kind: 'SafeL2 1.4.1 proxy, made by SafeProxyFactory 1.4.1 with the app\'s setup', singleton: SAFE_L2, module: MODULE_4337,
  owner: SHARED_SIGNER, threshold: 1, checked: 'the app\'s check (each call from the account, cold), then the operation (EntryPoint -> executeUserOp -> MultiSend)' };
const failed = Object.values(record.scenarios).filter((s) => !s.ok).length;
say(`\n${Object.keys(record.scenarios).length - failed} of ${Object.keys(record.scenarios).length} landed in simulation${MUTATION ? ` under mutation ${MUTATION}` : ''}`);
if (!MUTATION && process.env.WRITE_RECORD) writeFileSync(join(here, 'mainnet-sim.json'), JSON.stringify(record, null, 2) + '\n');
process.exit(MUTATION ? (failed ? 0 : 1) : (failed ? 1 : 0));
