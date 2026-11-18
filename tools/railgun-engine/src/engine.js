// Casberi's Railgun engine (prd §1713): Railgun's open wallet SDK, driven from
// Swift through one entry point, `casberiRailgun.call(method, paramsJSON)`,
// which always resolves to a JSON envelope:
//   {"ok":true,"value":…}  or  {"ok":false,"error":{"name":…,"message":…}}
// (`RailgunEngineWire.swift` decodes it.) BigInts travel as 0x-hex strings.
//
// What crosses back to Swift is PUBLIC: transactions to send, amounts,
// timings, the 0zk address. The mnemonic and the encryption key come in once
// per `open`; the wallet's spending keys, its notes and every proof stay in
// this page's memory and die with it. Nothing is persisted yet: the trees are
// rebuilt from the current-tree checkpoint on every open (§1713 item 9).
//
// Nothing here signs or sends. A shield is the proxy call (and its approval)
// for your account to send; an unshield is the proxy call carrying the proof,
// for your account — a Safe — to send as a plain call. Ethereum only.
import { say } from './net.js';
import { Buffer } from 'buffer';
globalThis.Buffer ??= Buffer;

import {
  ArtifactStore, startRailgunEngine, getProver, loadProvider, createRailgunWallet, refreshBalances, awaitWalletScan, getEngine,
  setOnUTXOMerkletreeScanCallback, setOnTXIDMerkletreeScanCallback, setOnBalanceUpdateCallback, setLoggers,
  getRailgunAddress, walletForID, loadWalletByID, unloadWalletByID, deleteWalletByID, balanceForERC20Token, populateShield, populateShieldBaseToken,
  gasEstimateForUnprovenUnshield, generateUnshieldProof, populateProvedUnshield,
  gasEstimateForUnprovenUnshieldBaseToken, generateUnshieldBaseTokenProof, populateProvedUnshieldBaseToken,
  calculateBroadcasterFeeERC20Amount,
  gasEstimateForUnprovenCrossContractCalls, generateCrossContractCallsProof, populateProvedCrossContractCalls,
  gasEstimateForUnprovenTransfer, generateTransferProof, populateProvedTransfer, validateRailgunAddress,
} from '@railgun-community/wallet';
import { WakuBroadcasterClient, BroadcasterTransaction } from '@railgun-community/waku-broadcaster-client-web';
import { NetworkName, NETWORK_CONFIG, TXIDVersion, EVMGasType } from '@railgun-community/shared-models';
import { RailgunEngine, Merkletree } from '@railgun-community/engine';
import memdown from 'memdown';
import leveljs from 'level-js';
import axios from 'axios';
import * as snarkjs from 'snarkjs';
import { Wallet, Mnemonic, keccak256, concat, toUtf8Bytes, getAddress, Interface, JsonRpcProvider } from 'ethers';

const SDK = { wallet: '11.3.0', engine: '9.9.1', snarkjs: '0.7.5' };
const V2 = TXIDVersion.V2_PoseidonMerkle;
const NETWORK = NetworkName.Ethereum;
const CHAIN = NETWORK_CONFIG[NETWORK].chain;
const PROXY = NETWORK_CONFIG[NETWORK].proxyContract;
// The CLASSIC relay adapter: a private swap runs through it (prd §1875). The
// screening node clears a shield it makes at once when the same transaction's
// unshields are already valid (measured 2026-11-18 in the node's source,
// `handleRelayAdaptUnknownShield`); its 7702 twin is not covered there, so the
// swap never goes through that one. The SDK takes the classic one on Ethereum
// while `relayAdaptContract` is set.
const RELAY_ADAPT = NETWORK_CONFIG[NETWORK].relayAdaptContract;
const ETH = '0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';
// The screening node (§1713 item 5) and Railgun's indexer of the pool's trees.
const POI_NODES = ['https://ppoi.fdi.network'];
const SQUID = 'https://rail-squid.squids.live/squid-railgun-ethereum-v2/graphql';
// The current-tree checkpoint (§1713 item 9): a wallet made after tree 4's
// first leaf owns nothing in trees 0–3, so the sync starts at tree 4's first
// block and TXID tree 2. Every root is checked afterwards (`sync`), so the
// checkpoint is never trusted on its own.
const UTXO_TREE_START_BLOCK = 25849756;
const TXID_START_TREE = 2;
const SHIELD_KEY_LABEL = 'casberi railgun shield v1';

const now = () => performance.now();
const hex = (n) => `0x${BigInt(n).toString(16)}`;
const plainJSON = (value) => JSON.stringify(value, (k, v) => (typeof v === 'bigint' ? hex(v) : v));
const erc20 = new Interface(['function approve(address spender, uint256 amount)']);

// ---- State: the engine is started once; a wallet is open or not.
let started = false;
let storage = null;
let providerLoaded = false;
let fees = null;
let walletID = null;
let openedRandom = false;
let encryptionKey = null;
let utxo = null;
let txid = null;
let seen = null;
const artifacts = new Map();
const store = new ArtifactStore(
  async (p) => artifacts.get(p) ?? null,
  async (d, p, item) => { artifacts.set(p, item); },
  async (p) => artifacts.has(p),
);

// The SDK asks the screening node through axios, whose browser default is
// XMLHttpRequest — which the page's CSP blocks and `net.js` never sees
// (measured 2026-11-07: "POI request error" on every TXID sync). Its fetch
// adapter goes through the app's door like everything else.
// Measured 2026-11-07: axios 1.7.2's own fetch adapter fails before it calls
// fetch here, so the page's door is axios's whole adapter: the request axios
// has already transformed goes through `fetch` (net.js), and the answer comes
// back for axios to transform (JSON) or as bytes (`responseType: arraybuffer`,
// the proving files).
axios.defaults.adapter = async (config) => {
  const url = axios.getUri(config);
  const headers = {};
  const given = typeof config.headers?.toJSON === 'function' ? config.headers.toJSON() : (config.headers ?? {});
  for (const [k, v] of Object.entries(given)) if (v != null && typeof v !== 'object') headers[k] = String(v);
  const method = (config.method ?? 'get').toUpperCase();
  let res;
  try {
    res = await fetch(url, { method, headers, body: method === 'GET' || method === 'HEAD' ? undefined : config.data, signal: config.signal });
  } catch (e) {
    throw new axios.AxiosError(String(e?.message ?? e), 'ERR_NETWORK', config);
  }
  const data = config.responseType === 'arraybuffer' ? await res.arrayBuffer() : await res.text();
  const response = { data, status: res.status, statusText: res.statusText ?? '', headers: Object.fromEntries(res.headers.entries()), config, request: {} };
  if (!config.validateStatus || config.validateStatus(res.status)) return response;
  throw new axios.AxiosError(`Request failed with status code ${res.status}`, res.status >= 500 ? 'ERR_BAD_RESPONSE' : 'ERR_BAD_REQUEST', config, {}, response);
};

function patchTreesForCheckpoint() {
  NETWORK_CONFIG[NETWORK].deploymentBlock = UTXO_TREE_START_BLOCK;
  // The engine checks every tree's root from 0 up; the skipped trees are
  // empty here, and an empty tree has nothing to check. A tree with leaves
  // still goes on chain.
  const validate = RailgunEngine.validateMerkleroot;
  RailgunEngine.validateMerkleroot = (v, c, tree, index, root) => (index < 0 ? Promise.resolve(true) : validate.call(RailgunEngine, v, c, tree, index, root));
  // The engine finds its latest tree by counting up from 0 to the first empty
  // one, so with 0–3 skipped it would never see tree 4. Look past empty trees.
  Merkletree.prototype.latestTree = async function latestTree() {
    let latest = 0;
    for (let t = 0; t < 32; t++) if ((await this.getTreeLength(t)) > 0) latest = t;
    return latest;
  };
}

// The TXID tree's entries chain (each verification hash is built on the one
// before) and take their positions from order, so an empty tree is told it
// ends just before `TXID_START_TREE`, and its latest entry is the indexer's
// record for the one before that. Its root is checked against the screening
// node in `sync`, so a wrong seed fails rather than passes.
async function seedTxidTree() {
  const before = TXID_START_TREE * 65536 - 1;
  const res = await (await fetch(SQUID, { method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ query: `{ transactions(orderBy: id_ASC, offset: ${before}, limit: 1) { id blockNumber verificationHash } }` }) })).json();
  const prev = res.data?.transactions?.[0];
  if (!prev) throw new Error(`no indexer record at ${before}`);
  const tt = getEngine().getTXIDMerkletree(V2, CHAIN);
  const latestTreeAndIndex = tt.getLatestTreeAndIndex.bind(tt);
  const latestTransaction = tt.getLatestRailgunTransaction.bind(tt);
  const empty = async () => (await latestTreeAndIndex()).index < 0;
  tt.getLatestTreeAndIndex = async () => ((await empty()) ? { tree: TXID_START_TREE - 1, index: 65535 } : latestTreeAndIndex());
  tt.getLatestRailgunTransaction = async () => ((await empty())
    ? { graphID: prev.id, verificationHash: prev.verificationHash, version: 'V2', blockNumber: Number(prev.blockNumber) }
    : latestTransaction());
  return Number(prev.blockNumber);
}

// The trees live in IndexedDB, in the engine's own persistent WebKit store
// (`RailgunEngine`): the first open builds them from the checkpoint, every
// later one resumes from the last block it read (prd §1713 item 9). A probe
// can ask for memory instead (`persist: false`), which keeps nothing.
async function startOnce(persist) {
  if (started) return;
  patchTreesForCheckpoint();
  setLoggers(
    (m) => { if (/invalid|incomplete|merkleroot|error|quick ?sync|fail/i.test(String(m))) say(`sdk ${String(m).slice(0, 300)}`); },
    (e) => say(`sdkError ${String(e?.message ?? e).slice(0, 300)}`),
  );
  await startRailgunEngine('casberi', persist ? leveljs('casberi-railgun') : memdown(), false, store, false, false, POI_NODES);
  storage = persist ? 'indexeddb' : 'memory';
  getProver().setSnarkJSGroth16(snarkjs.groth16);
  // A line whenever a tree's status changes or it moves 5%, so a sync that
  // stalls is seen stalling.
  const lastSaid = {};
  const progress = (name, e) => {
    const key = `${e.scanStatus}:${Math.floor((e.progress ?? 0) * 20)}`;
    if (lastSaid[name] === key) return;
    lastSaid[name] = key;
    say(`progress ${name} ${e.scanStatus} ${Math.round((e.progress ?? 0) * 100)}%`);
  };
  setOnUTXOMerkletreeScanCallback((e) => { if (e.chain?.id === CHAIN.id) { utxo = e; progress('utxo', e); } });
  setOnTXIDMerkletreeScanCallback((e) => { if (e.chain?.id === CHAIN.id) { txid = e; progress('txid', e); } });
  setOnBalanceUpdateCallback((e) => { if (e.chain?.id === CHAIN.id) seen = e; });
  started = true;
}

const tree = (e) => (e ? { status: e.scanStatus, progress: Math.round((e.progress ?? 0) * 100) } : null);
let rpcUrl = null;
const rpc = async (method, params) => {
  const res = await (await fetch(rpcUrl, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params }) })).json();
  if (res.error) throw new Error(res.error.message);
  return res.result;
};
const poi = async (method, params) => {
  const res = await (await fetch(POI_NODES[0], { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params }) })).json();
  if (res.error) throw new Error(JSON.stringify(res.error).slice(0, 200));
  return res.result;
};

function requireOpen() {
  if (!walletID) throw Object.assign(new Error('no wallet is open'), { name: 'NotOpen' });
}

// Every token the engine has seen a note for, with the whole balance and the
// spendable part (listed by the screening node). Hex base units.
async function balanceList() {
  requireOpen();
  const wallet = walletForID(walletID);
  const tokens = (seen?.erc20Amounts ?? []).map((a) => a.tokenAddress);
  const out = [];
  for (const token of tokens) {
    const [amount, spendable] = await Promise.all([
      balanceForERC20Token(V2, wallet, NETWORK, token, false),
      balanceForERC20Token(V2, wallet, NETWORK, token, true),
    ]);
    out.push({ token: getAddress(token), amount: hex(amount), spendable: hex(spendable) });
  }
  return out;
}

// ---- Railgun's broadcasters (prd §1721 item 3). A send to someone else is
// submitted by a broadcaster, who pays the gas and takes its fee in a token
// out of this wallet, so no account of yours appears on the transaction.
// They are found over Waku, through the three relays only (no DNS discovery:
// every socket goes through Swift, which refuses any other host).
let broadcasting = null;
let quoted = null;
let quotedSwap = null;
let quotedTransfer = null;

// A private send's parts, checked (prd §1877): the token and its amount, a
// private address that is not this wallet's own, and a note of at most 140
// characters, which only the receiver can read. Nothing leaves Railgun.
function transferParts(p) {
  const amount = BigInt(p.amount);
  if (amount <= 0n) throw new Error('amount must be positive');
  const token = getAddress(p.token);
  const to = String(p.to ?? '').trim();
  if (!validateRailgunAddress(to)) throw Object.assign(new Error('not a private address'), { name: 'NotPrivateAddress' });
  if (to === getRailgunAddress(walletID)) throw Object.assign(new Error('that is your own private address'), { name: 'NotPrivateAddress' });
  const memo = p.memo ? String(p.memo).slice(0, 140) : undefined;
  return { token, amount, to, memo, recipients: [{ tokenAddress: token, amount, recipientAddress: to }] };
}
const transferKey = (p) => plainJSON([getAddress(p.token), BigInt(p.amount), String(p.to).trim(), p.memo ? String(p.memo).slice(0, 140) : null]);

// A swap's parts, checked: the token out and its amount, the token back, and
// the calls the adapter makes. No call may touch Railgun's own contracts or
// carry ETH (the adapter holds none to give), and every call's target is a
// contract address the caller named; what each call does is Swift's to write
// and check (`RailgunSwap`).
function swapParts(p) {
  const amount = BigInt(p.amount);
  if (amount <= 0n) throw new Error('amount must be positive');
  const token = getAddress(p.token);
  const buyToken = getAddress(p.buyToken);
  if (token === buyToken) throw new Error('a swap needs two tokens');
  if (!Array.isArray(p.calls) || p.calls.length === 0 || p.calls.length > 4) throw new Error('a swap is one to four calls');
  const calls = p.calls.map((c) => {
    const to = getAddress(c.to);
    if (to === getAddress(PROXY) || to === getAddress(RELAY_ADAPT)) throw Object.assign(new Error('a swap call may not touch Railgun'), { name: 'NotRailgun' });
    if (BigInt(c.value ?? 0) !== 0n) throw Object.assign(new Error('a swap call may not carry ETH'), { name: 'NotRailgun' });
    if (!/^0x[0-9a-fA-F]{8,}$/.test(c.data)) throw new Error('a swap call needs data');
    return { to, data: c.data, value: 0n };
  });
  return {
    token, amount, buyToken, calls,
    unshields: [{ tokenAddress: token, amount }],
    shields: [{ tokenAddress: buyToken, recipientAddress: getRailgunAddress(walletID) }],
  };
}
const swapKey = (p) => plainJSON([getAddress(p.token), BigInt(p.amount), getAddress(p.buyToken),
  p.calls.map((c) => [getAddress(c.to), String(c.data).toLowerCase()])]);

async function startBroadcasters() {
  broadcasting ??= WakuBroadcasterClient.start(CHAIN, {
    poiActiveListKeys: [], useDNSDiscovery: false, feeExpirationTimeout: 60000, peerDiscoveryTimeout: 30000,
  }, () => {}, { log: (m) => { if (/error|fail|connected/i.test(String(m))) say(`waku ${String(m).slice(0, 200)}`); }, error: (e) => say(`wakuError ${String(e?.message ?? e).slice(0, 200)}`) })
    .catch((e) => { broadcasting = null; throw e; });
  await broadcasting;
}

// Every fee token a broadcaster takes right now, with its rate (token base
// units per 10^18 wei of gas) and how many broadcasters offer it.
function broadcasterTokens() {
  const all = WakuBroadcasterClient.findAllBroadcastersForChain(CHAIN, false) ?? [];
  const byToken = new Map();
  for (const b of all) {
    const token = getAddress(b.tokenAddress);
    if (!byToken.has(token)) byToken.set(token, new Set());
    byToken.get(token).add(b.railgunAddress);
  }
  const out = [];
  for (const [token, who] of byToken) {
    const best = WakuBroadcasterClient.findBestBroadcaster(CHAIN, token, false);
    if (best) out.push({ token, feePerUnitGas: hex(BigInt(best.tokenFee.feePerUnitGas)), broadcasters: who.size });
  }
  return out;
}

const gasDetails = (p, gasEstimate = 0n) => ({
  evmGasType: EVMGasType.Type2, gasEstimate,
  maxFeePerGas: BigInt(p.maxFeePerGas ?? '0x77359400'), maxPriorityFeePerGas: BigInt(p.maxPriorityFeePerGas ?? '0x5f5e100'),
});

const methods = {
  info() {
    return {
      sdk: SDK.wallet, engine: SDK.engine, snarkjs: SDK.snarkjs,
      secureContext: !!globalThis.isSecureContext, webAssembly: typeof WebAssembly !== 'undefined',
      workers: typeof Worker !== 'undefined', cores: navigator.hardwareConcurrency ?? 1,
    };
  },

  // Opens the 0zk wallet: the mnemonic and the encryption key from the
  // Keychain (or, in a probe, a random pair made here and never kept). The
  // node is the account's own (§1713 item 9).
  async open(p) {
    const t = now();
    if (!p.rpcUrl) throw new Error('rpcUrl required');
    rpcUrl = p.rpcUrl;
    await startOnce(p.persist !== false);
    if (!providerLoaded) {
      const r = await loadProvider({ chainId: CHAIN.id, providers: [{ provider: rpcUrl, priority: 1, weight: 2, maxLogsPerBatch: 10, stallTimeout: 4000 }] }, NETWORK, 15000);
      fees = { shieldFeeBps: r.feesSerialized?.shieldFeeV2 ?? null, unshieldFeeBps: r.feesSerialized?.unshieldFeeV2 ?? null };
      await seedTxidTree();
      providerLoaded = true;
    }
    // A probe's wallet: random, unless the store already keeps it by id.
    // Your wallet: a BIP-39 phrase from 32 bytes the app derives from your
    // private root (prd §1713), made here and never sent back. A probe's:
    // random, unless the store already keeps it by id.
    const generated = !p.mnemonic && !p.entropy && !p.walletID;
    const mnemonic = p.mnemonic ?? (p.entropy ? Mnemonic.fromEntropy(p.entropy).phrase : Wallet.createRandom().mnemonic.phrase);
    encryptionKey = p.encryptionKey ?? Buffer.from(crypto.getRandomValues(new Uint8Array(32))).toString('hex');
    const head = Number(await rpc('eth_blockNumber', []));
    // A wallet kept in the store opens by its id; a new one is made, and a
    // probe's random one is deleted again on close.
    let info = null;
    if (p.walletID) info = await loadWalletByID(encryptionKey, p.walletID, false).catch(() => null);
    const loaded = !!info;
    info ??= await createRailgunWallet(encryptionKey, mnemonic, { [NETWORK]: p.creationBlock ?? head });
    walletID = info.id;
    // A random wallet in memory goes on close; one in the store stays, for
    // the next open by its id.
    openedRandom = generated && storage === 'memory';
    const ut = getEngine().getUTXOMerkletree(V2, CHAIN);
    const kept = await ut.getTreeLength(4);
    return { address: info.railgunAddress, walletID: info.id, loaded, generated, storage, keptLeaves: kept, headBlock: head, ...fees,
      relayAdapt: getAddress(RELAY_ADAPT), ms: Math.round(now() - t) };
  },

  // Builds the trees from the checkpoint, scans the wallet, then checks every
  // root: the UTXO trees against the proxy's `rootHistory`, the TXID tree
  // against the screening node at our own index.
  async sync(p) {
    requireOpen();
    const t = now();
    const cap = Number(p.capMs ?? 600000);
    const scan = awaitWalletScan(walletID, CHAIN);
    await refreshBalances(CHAIN, [walletID]);
    await Promise.race([scan, new Promise((r) => setTimeout(r, cap))]);
    const until = now() + cap;
    const complete = () => utxo?.scanStatus === 'Complete' && txid?.scanStatus === 'Complete';
    while (!complete() && now() < until) await new Promise((r) => setTimeout(r, 1000));
    const synced = Math.round(now() - t);

    const engine = getEngine();
    const ut = engine.getUTXOMerkletree(V2, CHAIN);
    const { tree: latest } = await ut.getLatestTreeAndIndex();
    const trees = [];
    const roots = new Interface(['function rootHistory(uint256, bytes32) view returns (bool)']);
    for (let i = 0; i <= latest; i++) {
      const length = await ut.getTreeLength(i);
      if (!length) continue;
      const root = await ut.getRoot(i);
      const result = await rpc('eth_call', [{ to: PROXY, data: roots.encodeFunctionData('rootHistory', [i, root.startsWith('0x') ? root : `0x${root}`]) }, 'latest']);
      trees.push({ tree: i, length, onChain: BigInt(result) === 1n });
    }
    const tt = engine.getTXIDMerkletree(V2, CHAIN);
    const { tree: tTree, index: tIndex } = await tt.getLatestTreeAndIndex();
    let txidRootValid = null;
    if (tIndex >= 0) {
      const merkleroot = await tt.getRoot(tTree);
      txidRootValid = await poi('ppoi_validate_txid_merkleroot', { chainType: String(CHAIN.type), chainID: String(CHAIN.id), txidVersion: V2, tree: tTree, index: tIndex, merkleroot });
    }
    const status = await poi('ppoi_node_status', {});
    const screeningIndex = status?.forNetwork?.[NETWORK]?.txidStatus?.validatedTxidIndex ?? null;
    return {
      done: complete(), utxo: tree(utxo), txid: tree(txid), trees,
      utxoRootsValid: trees.length > 0 && trees.every((x) => x.onChain),
      txidIndex: tTree * 65536 + tIndex, screeningIndex, txidRootValid: txidRootValid === true,
      balances: await balanceList(), syncMs: synced, ms: Math.round(now() - t),
    };
  },

  async balances() {
    return { balances: await balanceList() };
  },

  // The shield of `amount` of `token` into this wallet: the proxy call for
  // your account to send, and the approval it needs first (none for ETH,
  // which is wrapped by the proxy). The shield key only encrypts the note
  // for its receiver; it is derived from the wallet's own secret, never a
  // Safe signature (§1713 item 3).
  async prepareShield(p) {
    requireOpen();
    const t = now();
    const amount = BigInt(p.amount);
    if (amount <= 0n) throw new Error('amount must be positive');
    const shieldPrivateKey = keccak256(concat([toUtf8Bytes(SHIELD_KEY_LABEL), `0x${encryptionKey}`]));
    const address = getRailgunAddress(walletID);
    const isETH = p.token.toLowerCase() === ETH;
    const token = isETH ? NETWORK_CONFIG[NETWORK].baseToken.wrappedAddress : getAddress(p.token);
    const { transaction } = isETH
      ? await populateShieldBaseToken(V2, NETWORK, address, shieldPrivateKey, { tokenAddress: token, amount }, undefined)
      : await populateShield(V2, NETWORK, shieldPrivateKey, [{ tokenAddress: token, amount, recipientAddress: address }], [], undefined);
    if (getAddress(transaction.to) !== getAddress(PROXY)) throw new Error(`shield goes to ${transaction.to}, not Railgun`);
    return {
      tx: { to: getAddress(transaction.to), data: transaction.data, value: hex(transaction.value ?? 0n) },
      approve: isETH ? null : { to: token, data: erc20.encodeFunctionData('approve', [PROXY, amount]), value: '0x0' },
      token, amount: hex(amount), fee: fees?.shieldFeeBps ? hex(amount * BigInt(fees.shieldFeeBps) / 10000n) : null,
      ms: Math.round(now() - t),
    };
  },

  // An unshield of `amount` of `token` to `to`, proved: the proxy call for
  // your account to send. `forSafe` (the default) refuses anything but a
  // plain call to the proxy — the SDK writes an EIP-7702 transaction for a
  // base-token unshield, which only a plain wallet can send, so a Safe
  // unshields WETH as a token (§1713 item 3).
  async prepareUnshield(p) {
    requireOpen();
    const t = now();
    const amount = BigInt(p.amount);
    if (amount <= 0n) throw new Error('amount must be positive');
    const to = getAddress(p.to);
    const forSafe = p.forSafe !== false;
    const isETH = p.token.toLowerCase() === ETH;
    const token = isETH ? NETWORK_CONFIG[NETWORK].baseToken.wrappedAddress : getAddress(p.token);
    const recipients = [{ tokenAddress: token, amount, recipientAddress: to }];
    let est, proofMs, transaction;
    if (isETH) {
      if (forSafe) throw Object.assign(new Error('a Safe unshields WETH as a token; ETH needs a plain wallet'), { name: 'NotForSafe' });
      est = await gasEstimateForUnprovenUnshieldBaseToken(V2, NETWORK, to, walletID, encryptionKey, { tokenAddress: token, amount }, gasDetails(p), undefined, true);
      const pt = now();
      say('step proving');
      await generateUnshieldBaseTokenProof(V2, NETWORK, to, walletID, encryptionKey, { tokenAddress: token, amount }, undefined, true, undefined, () => {});
      proofMs = Math.round(now() - pt);
      ({ transaction } = await populateProvedUnshieldBaseToken(V2, NETWORK, to, walletID, { tokenAddress: token, amount }, undefined, true, undefined, gasDetails(p, est.gasEstimate)));
    } else {
      est = await gasEstimateForUnprovenUnshield(V2, NETWORK, walletID, encryptionKey, recipients, [], gasDetails(p), undefined, true);
      const pt = now();
      say('step proving');
      await generateUnshieldProof(V2, NETWORK, walletID, encryptionKey, recipients, [], undefined, true, undefined, () => {});
      proofMs = Math.round(now() - pt);
      ({ transaction } = await populateProvedUnshield(V2, NETWORK, walletID, recipients, [], undefined, true, undefined, gasDetails(p, est.gasEstimate)));
    }
    const plain = transaction.type !== 4 && getAddress(transaction.to) === getAddress(PROXY);
    if (forSafe && !plain) throw Object.assign(new Error(`unshield is type ${transaction.type} to ${transaction.to}: not a plain call to Railgun`), { name: 'NotForSafe' });
    return {
      tx: { to: getAddress(transaction.to), data: transaction.data, value: hex(transaction.value ?? 0n) },
      type: transaction.type ?? 2, delegate: transaction.authorizationList?.[0]?.address ?? null,
      gasEstimate: hex(est.gasEstimate), token, amount: hex(amount), to,
      fee: fees?.unshieldFeeBps ? hex(amount * BigInt(fees.unshieldFeeBps) / 10000n) : null,
      proofMs, ms: Math.round(now() - t),
    };
  },

  // Starts listening for broadcasters (once) and waits up to `waitMs` for a
  // fee to arrive. Reads nothing about this wallet.
  async broadcasters(p) {
    const t = now();
    await startBroadcasters();
    const until = now() + Number(p.waitMs ?? 45000);
    let tokens = broadcasterTokens();
    while (!tokens.length && now() < until) {
      await new Promise((r) => setTimeout(r, 1000));
      tokens = broadcasterTokens();
    }
    return { tokens, ms: Math.round(now() - t) };
  },

  // What a send of `amount` of `token` to `to` costs through the best
  // broadcaster taking `feeToken`: the gas estimated with a dummy proof, the
  // fee in `feeToken`. Kept in this page for `broadcastSend`; nothing is
  // proved or sent here.
  async quoteBroadcast(p) {
    requireOpen();
    const t = now();
    await startBroadcasters();
    const amount = BigInt(p.amount);
    if (amount <= 0n) throw new Error('amount must be positive');
    const to = getAddress(p.to);
    const token = getAddress(p.token);
    const feeToken = getAddress(p.feeToken);
    const selected = WakuBroadcasterClient.findBestBroadcaster(CHAIN, feeToken, false);
    if (!selected) throw Object.assign(new Error(`no broadcaster takes ${feeToken}`), { name: 'NoBroadcaster' });
    // Type 1 (a broadcast batch carries a minimum gas price), at the node's
    // price and a third over it, so a block's rise does not strand it.
    const gasPrice = (BigInt(await rpc('eth_gasPrice', [])) * 4n) / 3n;
    const feeTokenDetails = { tokenAddress: feeToken, feePerUnitGas: BigInt(selected.tokenFee.feePerUnitGas) };
    const recipients = [{ tokenAddress: token, amount, recipientAddress: to }];
    const estimating = { evmGasType: EVMGasType.Type1, gasEstimate: 0n, gasPrice };
    const est = await gasEstimateForUnprovenUnshield(V2, NETWORK, walletID, encryptionKey, recipients, [], estimating, feeTokenDetails, false);
    const details = { evmGasType: EVMGasType.Type1, gasEstimate: est.gasEstimate, gasPrice };
    const fee = calculateBroadcasterFeeERC20Amount(feeTokenDetails, details).amount;
    quoted = { token, amount, to, feeToken, fee, details, gasPrice, selected, at: Date.now() };
    return {
      token, amount: hex(amount), to, feeToken, fee: hex(fee), gasEstimate: hex(est.gasEstimate), gasPrice: hex(gasPrice),
      broadcaster: selected.railgunAddress, expiration: Number(selected.tokenFee.expiration ?? 0), ms: Math.round(now() - t),
    };
  },

  // Proves the quoted send and hands it to its broadcaster: the proof pays
  // the broadcaster `fee` of `feeToken` inside Railgun, and the unshield
  // sends `amount` to `to` from Railgun's proxy. Refuses a quote that moved:
  // another send, another fee, or older than its broadcaster's offer.
  async broadcastSend(p) {
    requireOpen();
    const t = now();
    const q = quoted;
    if (!q) throw Object.assign(new Error('nothing quoted'), { name: 'NotQuoted' });
    if (getAddress(p.token) !== q.token || BigInt(p.amount) !== q.amount || getAddress(p.to) !== q.to
        || getAddress(p.feeToken) !== q.feeToken || BigInt(p.fee) !== q.fee) {
      throw Object.assign(new Error('the send is not the one quoted'), { name: 'NotQuoted' });
    }
    if (q.selected.tokenFee.expiration && Date.now() > Number(q.selected.tokenFee.expiration)) {
      throw Object.assign(new Error('the broadcaster offer expired'), { name: 'QuoteExpired' });
    }
    const recipients = [{ tokenAddress: q.token, amount: q.amount, recipientAddress: q.to }];
    const feeRecipient = { tokenAddress: q.feeToken, amount: q.fee, recipientAddress: q.selected.railgunAddress };
    const pt = now();
    // The steps Move's rows show (prd §1728, §1700x): the proof, then the hand-over.
    say('step proving');
    await generateUnshieldProof(V2, NETWORK, walletID, encryptionKey, recipients, [], feeRecipient, false, q.gasPrice, () => {});
    const proofMs = Math.round(now() - pt);
    const populated = await populateProvedUnshield(V2, NETWORK, walletID, recipients, [], feeRecipient, false, q.gasPrice, q.details);
    const tx = populated.transaction;
    if (getAddress(tx.to) !== getAddress(PROXY)) throw Object.assign(new Error(`broadcast goes to ${tx.to}, not Railgun`), { name: 'NotRailgun' });
    const sending = await BroadcasterTransaction.create(V2, tx.to, tx.data, q.selected.railgunAddress, q.selected.tokenFee.feesID,
      CHAIN, populated.nullifiers ?? [], q.gasPrice, false, populated.preTransactionPOIsPerTxidLeafPerList ?? {});
    // From here the broadcaster may already have the send: a failure is
    // "not confirmed", never "nothing was sent".
    let txHash;
    say('step sent');
    try {
      txHash = await sending.send();
    } catch (e) {
      quoted = null;
      throw Object.assign(new Error(String(e?.message ?? e)), { name: 'BroadcastUnconfirmed' });
    }
    quoted = null;
    return { txHash, proofMs, ms: Math.round(now() - t) };
  },

  // ---- A private swap (prd §1875): `amount` of `token` leaves the wallet to
  // the classic relay adapter, the adapter makes `calls` (an exact approval
  // and one exchange call, written in Swift with the adapter as receiver),
  // and whatever `buyToken` it then holds goes back into this wallet, all in
  // one transaction. Railgun takes its unshield fee on the way out and its
  // shield fee on the way in; the calls swap what is left after the first.

  // What the swap costs through the best broadcaster that carries relay-adapt
  // sends and takes `feeToken`. Kept for `broadcastSwap`; nothing is proved.
  async quoteSwap(p) {
    requireOpen();
    const t = now();
    await startBroadcasters();
    const s = swapParts(p);
    const feeToken = getAddress(p.feeToken);
    const selected = WakuBroadcasterClient.findBestBroadcaster(CHAIN, feeToken, true);
    if (!selected) throw Object.assign(new Error(`no broadcaster carries a swap for ${feeToken}`), { name: 'NoBroadcaster' });
    const gasPrice = (BigInt(await rpc('eth_gasPrice', [])) * 4n) / 3n;
    const feeTokenDetails = { tokenAddress: feeToken, feePerUnitGas: BigInt(selected.tokenFee.feePerUnitGas) };
    const estimating = { evmGasType: EVMGasType.Type1, gasEstimate: 0n, gasPrice };
    const est = await gasEstimateForUnprovenCrossContractCalls(V2, NETWORK, walletID, encryptionKey, s.unshields, [], s.shields, [],
      s.calls, estimating, feeTokenDetails, false, undefined);
    const details = { evmGasType: EVMGasType.Type1, gasEstimate: est.gasEstimate, gasPrice };
    const fee = calculateBroadcasterFeeERC20Amount(feeTokenDetails, details).amount;
    quotedSwap = { ...s, key: swapKey(p), feeToken, fee, details, gasPrice, selected };
    return {
      token: s.token, amount: hex(s.amount), buyToken: s.buyToken, feeToken, fee: hex(fee),
      gasEstimate: hex(est.gasEstimate), gasPrice: hex(gasPrice), broadcaster: selected.railgunAddress,
      expiration: Number(selected.tokenFee.expiration ?? 0), ms: Math.round(now() - t),
    };
  },

  // Proves the quoted swap and hands it to its broadcaster, which sends it to
  // the relay adapter. Refuses anything but the swap quoted.
  async broadcastSwap(p) {
    requireOpen();
    const t = now();
    const q = quotedSwap;
    if (!q || swapKey(p) !== q.key || getAddress(p.feeToken) !== q.feeToken || BigInt(p.fee) !== q.fee) {
      throw Object.assign(new Error('the swap is not the one quoted'), { name: 'NotQuoted' });
    }
    if (q.selected.tokenFee.expiration && Date.now() > Number(q.selected.tokenFee.expiration)) {
      throw Object.assign(new Error('the broadcaster offer expired'), { name: 'QuoteExpired' });
    }
    const feeRecipient = { tokenAddress: q.feeToken, amount: q.fee, recipientAddress: q.selected.railgunAddress };
    const pt = now();
    say('step proving');
    await generateCrossContractCallsProof(V2, NETWORK, walletID, encryptionKey, q.unshields, [], q.shields, [], q.calls,
      feeRecipient, false, q.gasPrice, undefined, () => {});
    const proofMs = Math.round(now() - pt);
    const populated = await populateProvedCrossContractCalls(V2, NETWORK, walletID, q.unshields, [], q.shields, [], q.calls,
      feeRecipient, false, q.gasPrice, q.details);
    const tx = populated.transaction;
    if (getAddress(tx.to) !== getAddress(RELAY_ADAPT)) throw Object.assign(new Error(`swap goes to ${tx.to}, not the relay adapter`), { name: 'NotRailgun' });
    const sending = await BroadcasterTransaction.create(V2, tx.to, tx.data, q.selected.railgunAddress, q.selected.tokenFee.feesID,
      CHAIN, populated.nullifiers ?? [], q.gasPrice, true, populated.preTransactionPOIsPerTxidLeafPerList ?? {});
    let txHash;
    say('step sent');
    try {
      txHash = await sending.send();
    } catch (e) {
      quotedSwap = null;
      throw Object.assign(new Error(String(e?.message ?? e)), { name: 'BroadcastUnconfirmed' });
    }
    quotedSwap = null;
    return { txHash, proofMs, ms: Math.round(now() - t) };
  },

  // The same swap, proved for a public sender (a fresh address of yours,
  // prd §1726): no broadcaster, no fee inside Railgun; the transaction to the
  // relay adapter comes back for Swift to send.
  async prepareSwap(p) {
    requireOpen();
    const t = now();
    const s = swapParts(p);
    const est = await gasEstimateForUnprovenCrossContractCalls(V2, NETWORK, walletID, encryptionKey, s.unshields, [], s.shields, [],
      s.calls, gasDetails(p), undefined, true, undefined);
    const pt = now();
    say('step proving');
    await generateCrossContractCallsProof(V2, NETWORK, walletID, encryptionKey, s.unshields, [], s.shields, [], s.calls,
      undefined, true, undefined, undefined, () => {});
    const proofMs = Math.round(now() - pt);
    const { transaction } = await populateProvedCrossContractCalls(V2, NETWORK, walletID, s.unshields, [], s.shields, [], s.calls,
      undefined, true, undefined, gasDetails(p, est.gasEstimate));
    if (getAddress(transaction.to) !== getAddress(RELAY_ADAPT)) throw Object.assign(new Error(`swap goes to ${transaction.to}, not the relay adapter`), { name: 'NotRailgun' });
    return {
      tx: { to: getAddress(transaction.to), data: transaction.data, value: hex(transaction.value ?? 0n) },
      gasEstimate: hex(est.gasEstimate), token: s.token, amount: hex(s.amount), buyToken: s.buyToken, proofMs, ms: Math.round(now() - t),
    };
  },

  // ---- A private send (prd §1877): `amount` of `token` from this wallet to
  // another private address, inside Railgun: nothing public names either
  // side or the amount. Carried as a send to a public address is (§1723,
  // §1726): a broadcaster paid inside Railgun, or a fresh address of yours.

  async quoteTransfer(p) {
    requireOpen();
    const t = now();
    await startBroadcasters();
    const s = transferParts(p);
    const feeToken = getAddress(p.feeToken);
    const selected = WakuBroadcasterClient.findBestBroadcaster(CHAIN, feeToken, false);
    if (!selected) throw Object.assign(new Error(`no broadcaster takes ${feeToken}`), { name: 'NoBroadcaster' });
    const gasPrice = (BigInt(await rpc('eth_gasPrice', [])) * 4n) / 3n;
    const feeTokenDetails = { tokenAddress: feeToken, feePerUnitGas: BigInt(selected.tokenFee.feePerUnitGas) };
    const estimating = { evmGasType: EVMGasType.Type1, gasEstimate: 0n, gasPrice };
    const est = await gasEstimateForUnprovenTransfer(V2, NETWORK, walletID, encryptionKey, s.memo, s.recipients, [], estimating, feeTokenDetails, false);
    const details = { evmGasType: EVMGasType.Type1, gasEstimate: est.gasEstimate, gasPrice };
    const fee = calculateBroadcasterFeeERC20Amount(feeTokenDetails, details).amount;
    quotedTransfer = { ...s, key: transferKey(p), feeToken, fee, details, gasPrice, selected };
    return {
      token: s.token, amount: hex(s.amount), feeToken, fee: hex(fee), gasEstimate: hex(est.gasEstimate), gasPrice: hex(gasPrice),
      broadcaster: selected.railgunAddress, expiration: Number(selected.tokenFee.expiration ?? 0), ms: Math.round(now() - t),
    };
  },

  async broadcastTransfer(p) {
    requireOpen();
    const t = now();
    const q = quotedTransfer;
    if (!q || transferKey(p) !== q.key || getAddress(p.feeToken) !== q.feeToken || BigInt(p.fee) !== q.fee) {
      throw Object.assign(new Error('the send is not the one quoted'), { name: 'NotQuoted' });
    }
    if (q.selected.tokenFee.expiration && Date.now() > Number(q.selected.tokenFee.expiration)) {
      throw Object.assign(new Error('the broadcaster offer expired'), { name: 'QuoteExpired' });
    }
    const feeRecipient = { tokenAddress: q.feeToken, amount: q.fee, recipientAddress: q.selected.railgunAddress };
    const pt = now();
    say('step proving');
    await generateTransferProof(V2, NETWORK, walletID, encryptionKey, false, q.memo, q.recipients, [], feeRecipient, false, q.gasPrice, () => {});
    const proofMs = Math.round(now() - pt);
    const populated = await populateProvedTransfer(V2, NETWORK, walletID, false, q.memo, q.recipients, [], feeRecipient, false, q.gasPrice, q.details);
    const tx = populated.transaction;
    if (getAddress(tx.to) !== getAddress(PROXY)) throw Object.assign(new Error(`send goes to ${tx.to}, not Railgun`), { name: 'NotRailgun' });
    const sending = await BroadcasterTransaction.create(V2, tx.to, tx.data, q.selected.railgunAddress, q.selected.tokenFee.feesID,
      CHAIN, populated.nullifiers ?? [], q.gasPrice, false, populated.preTransactionPOIsPerTxidLeafPerList ?? {});
    let txHash;
    say('step sent');
    try {
      txHash = await sending.send();
    } catch (e) {
      quotedTransfer = null;
      throw Object.assign(new Error(String(e?.message ?? e)), { name: 'BroadcastUnconfirmed' });
    }
    quotedTransfer = null;
    return { txHash, proofMs, ms: Math.round(now() - t) };
  },

  async prepareTransfer(p) {
    requireOpen();
    const t = now();
    const s = transferParts(p);
    const est = await gasEstimateForUnprovenTransfer(V2, NETWORK, walletID, encryptionKey, s.memo, s.recipients, [], gasDetails(p), undefined, true);
    const pt = now();
    say('step proving');
    await generateTransferProof(V2, NETWORK, walletID, encryptionKey, false, s.memo, s.recipients, [], undefined, true, undefined, () => {});
    const proofMs = Math.round(now() - pt);
    const { transaction } = await populateProvedTransfer(V2, NETWORK, walletID, false, s.memo, s.recipients, [], undefined, true, undefined,
      gasDetails(p, est.gasEstimate));
    if (getAddress(transaction.to) !== getAddress(PROXY)) throw Object.assign(new Error(`send goes to ${transaction.to}, not Railgun`), { name: 'NotRailgun' });
    return {
      tx: { to: getAddress(transaction.to), data: transaction.data, value: hex(transaction.value ?? 0n) },
      gasEstimate: hex(est.gasEstimate), token: s.token, amount: hex(s.amount), proofMs, ms: Math.round(now() - t),
    };
  },

  async close() {
    quoted = null;
    quotedSwap = null;
    quotedTransfer = null;
    if (walletID && openedRandom) await deleteWalletByID(walletID).catch(() => {});
    if (walletID) unloadWalletByID(walletID);
    walletID = null;
    encryptionKey = null;
    seen = null;
    return {};
  },
};

globalThis.casberiRailgun = {
  async call(method, paramsJSON) {
    try {
      const fn = methods[method];
      if (!fn) throw Object.assign(new Error(`no method ${method}`), { name: 'NoMethod' });
      const value = await fn(paramsJSON ? JSON.parse(paramsJSON) : {});
      return plainJSON({ ok: true, value: value ?? {} });
    } catch (e) {
      return JSON.stringify({ ok: false, error: { name: String(e?.name ?? 'Error'), message: String(e?.message ?? e).slice(0, 500) } });
    }
  },
};
say('ready');
