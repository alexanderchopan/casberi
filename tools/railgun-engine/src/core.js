// SPIKE (not in the app): Railgun's open TypeScript wallet SDK, driven the
// same way in Node and in a web view, so the two runs can be set side by
// side. Sepolia only. The caller hands in the database (memdown in Node,
// IndexedDB through level-js in the page) and where circuit files live.
//
// One entry point, `spike(opts)`, which runs the steps in order and reports
// each one's result and time through `opts.log(step, fields)`. Nothing here
// sends a transaction: a shield is PREPARED and its gas estimated; a funded
// run (opts.shieldKey) hands the signed send to the caller.
import {
  ArtifactStore, startRailgunEngine, getProver, loadProvider, createRailgunWallet, refreshBalances,
  setOnUTXOMerkletreeScanCallback, setOnTXIDMerkletreeScanCallback, setOnBalanceUpdateCallback,
  getShieldPrivateKeySignatureMessage, populateShieldBaseToken, getRailgunAddress, awaitWalletScan, getEngine,
} from '@railgun-community/wallet';
import { NetworkName, NETWORK_CONFIG, TXIDVersion, EVMGasType } from '@railgun-community/shared-models';
import { RailgunEngine, Merkletree } from '@railgun-community/engine';
import { setLoggers } from '@railgun-community/wallet';
import { Wallet, keccak256, JsonRpcProvider, getBytes, Interface } from 'ethers';
import * as snarkjs from 'snarkjs';

const RPCS = { [NetworkName.EthereumSepolia]: 'https://ethereum-sepolia-rpc.publicnode.com', [NetworkName.Ethereum]: 'https://ethereum-rpc.publicnode.com' };
let NETWORK = NetworkName.EthereumSepolia, CHAIN = NETWORK_CONFIG[NETWORK].chain, RPC = RPCS[NETWORK];
export const POI_NODES = ['https://ppoi.fdi.network'];
const SQUIDS = { [NetworkName.EthereumSepolia]: 'https://rail-squid.squids.live/squid-railgun-eth-sepolia-v2/graphql', [NetworkName.Ethereum]: 'https://rail-squid.squids.live/squid-railgun-ethereum-v2/graphql' };

const now = () => (globalThis.performance ?? Date).now();

// A brand-new private wallet owns nothing in Railgun's full trees, so it can
// start at the CURRENT tree: `startBlock` is that tree's first block, handed
// to the engine as if it were the contract's deployment (the one patch).
// The tree built from there is checked against the contract's own root
// history at the end, so the start block need not be trusted.
export async function spike({ db, artifactStore, mnemonic, encryptionKey, log, shieldWei = 1_000_000_000_000_000n, send, network = 'Ethereum_Sepolia', syncCapMs = 240000, startBlock, txidStartTree, creationBlock, then }) {
  if (!RPCS[network]) throw new Error(`no network ${network}`);
  NETWORK = network; CHAIN = NETWORK_CONFIG[NETWORK].chain; RPC = RPCS[NETWORK];
  if (startBlock) {
    NETWORK_CONFIG[NETWORK].deploymentBlock = startBlock;
    // The second half of the patch: the engine checks EVERY tree's root from
    // 0 up, and the skipped trees are empty here. An empty tree (latest index
    // -1) has nothing to check; every tree with leaves still goes on-chain.
    const validate = RailgunEngine.validateMerkleroot;
    RailgunEngine.validateMerkleroot = (v, c, tree, index, root) => (index < 0 ? Promise.resolve(true) : validate.call(RailgunEngine, v, c, tree, index, root));
    // And the third: the engine finds its latest tree by counting up from 0
    // to the first empty one, so with 0-3 skipped it never sees tree 4 (and
    // its chain scan restarts from the start block). Look past empty trees.
    Merkletree.prototype.latestTree = async function latestTree() {
      let latest = 0;
      for (let t = 0; t < 32; t++) if ((await this.getTreeLength(t)) > 0) latest = t;
      return latest;
    };
  }
  setLoggers((m) => { if (/invalid|incomplete|merkleroot|startScanning|quick ?sync|gap|queue|error/i.test(String(m))) log('engineLog', { msg: String(m).slice(0, 300) }); },
    (e) => log('engineError', { error: String(e?.message ?? e).slice(0, 300) }));
  log('network', { network, startBlock: startBlock ?? NETWORK_CONFIG[NETWORK].deploymentBlock });
  const t0 = now();
  const step = async (name, fn) => {
    const t = now();
    try { const r = await fn(); log(name, { ok: true, ms: Math.round(now() - t), ...(r ?? {}) }); return r; }
    catch (e) { log(name, { ok: false, ms: Math.round(now() - t), error: String(e?.message ?? e).slice(0, 400) }); throw e; }
  };

  let utxo = null, txid = null, balances = null;
  await step('engine', async () => {
    await startRailgunEngine('casberispike', db, true, artifactStore, false, false, POI_NODES);
    getProver().setSnarkJSGroth16(snarkjs.groth16);
  });
  // Progress, timed: a line whenever a tree's status changes or it moves 5%.
  const seen = {};
  const progress = (tree, e) => {
    const p = Math.floor((e.progress ?? 0) * 20), key = `${e.scanStatus}:${p}`;
    if (seen[tree] === key) return; seen[tree] = key;
    const mem = globalThis.process?.memoryUsage?.().rss;
    log('progress', { tree, status: e.scanStatus, pct: Math.round((e.progress ?? 0) * 100), s: Math.round((now() - t0) / 1000), ...(mem ? { rssMB: Math.round(mem / 1048576) } : {}) });
  };
  setOnUTXOMerkletreeScanCallback((e) => { if (e.chain?.id === CHAIN.id) { utxo = e; progress('utxo', e); } });
  setOnTXIDMerkletreeScanCallback((e) => { if (e.chain?.id === CHAIN.id) { txid = e; progress('txid', e); } });
  setOnBalanceUpdateCallback((e) => { if (e.chain?.id === CHAIN.id) balances = e; });

  const head = await step('provider', async () => {
    const r = await loadProvider({ chainId: CHAIN.id, providers: [{ provider: RPC, priority: 1, weight: 2, maxLogsPerBatch: 10, stallTimeout: 4000 }] }, NETWORK, 15000);
    const block = await new JsonRpcProvider(RPC, CHAIN.id, { staticNetwork: true }).getBlockNumber();
    return { block, shieldFeeBps: r.feesSerialized?.shieldFeeV2, unshieldFeeBps: r.feesSerialized?.unshieldFeeV2 };
  });

  // The TXID tree, started the same way. Its entries chain (each verification
  // hash is built on the one before) and take their positions from order, so
  // an empty tree is told it ends just before `txidStartTree`, and its latest
  // entry is the indexer's record for the one before that: the cursor and the
  // hash to chain from. Every root the engine writes is still checked against
  // the screening node, so a wrong seed fails rather than passes.
  if (txidStartTree) await step('txid-seed', async () => {
    const before = txidStartTree * 65536 - 1;
    const res = await (await fetch(SQUIDS[NETWORK], { method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ query: `{ transactions(orderBy: id_ASC, offset: ${before}, limit: 1) { id blockNumber verificationHash } }` }) })).json();
    const prev = res.data?.transactions?.[0];
    if (!prev) throw new Error(`no indexer record at ${before}: ${JSON.stringify(res.errors ?? res).slice(0, 200)}`);
    const tt = getEngine().getTXIDMerkletree(TXIDVersion.V2_PoseidonMerkle, CHAIN);
    const latestTreeAndIndex = tt.getLatestTreeAndIndex.bind(tt);
    const latestTransaction = tt.getLatestRailgunTransaction.bind(tt);
    const empty = async () => (await latestTreeAndIndex()).index < 0;
    tt.getLatestTreeAndIndex = async () => ((await empty()) ? { tree: txidStartTree - 1, index: 65535 } : latestTreeAndIndex());
    tt.getLatestRailgunTransaction = async () => ((await empty())
      ? { graphID: prev.id, verificationHash: prev.verificationHash, version: 'V2', blockNumber: Number(prev.blockNumber) }
      : latestTransaction());
    return { from: before + 1, prevBlock: Number(prev.blockNumber) };
  });

  // Profiling (spike): where the TXID tree's time goes, timed per method.
  const P = {};
  const wrap = (obj, name, label = name) => {
    const f = obj[name]; if (typeof f !== 'function') return;
    obj[name] = async function wrapped(...a) { const t = now(); try { return await f.apply(this, a); } finally { const p = (P[label] ??= { n: 0, ms: 0 }); p.n += 1; p.ms += now() - t; } };
  };
  {
    const eng = getEngine();
    const ut = eng.getUTXOMerkletree(TXIDVersion.V2_PoseidonMerkle, CHAIN), tt = eng.getTXIDMerkletree(TXIDVersion.V2_PoseidonMerkle, CHAIN);
    wrap(eng, 'performSyncRailgunTransactionsV2', 'txidSyncTotal');
    wrap(eng, 'quickSyncRailgunTransactionsV2', 'txidFetch');
    wrap(eng, 'handleNewRailgunTransactionsV2', 'txidHandle');
    wrap(eng, 'decryptBalancesAllWallets', 'decryptBalances');
    wrap(eng, 'getLatestValidatedTxidIndex');
    for (const m of ['getCommitmentSafe', 'updateData', 'getAllUnshieldEventsForTxid', 'updateUnshieldEvent', 'addUnshieldEvents']) wrap(ut, m, `utxo.${m}`);
    for (const m of ['queueRailgunTransactions', 'updateTreesFromWriteQueue', 'getLatestRailgunTransaction', 'getRoot']) wrap(tt, m, `txid.${m}`);
    const { getRailgunTxidLeafHash } = await import('@railgun-community/engine');
    const b = now(); for (let i = 1; i <= 5000; i++) getRailgunTxidLeafHash(BigInt(i) * 7919n, 0n, BigInt(i));
    log('bench', { leafHash5000ms: Math.round(now() - b) });
  }
  const profile = () => Object.fromEntries(Object.entries(P).map(([k, v]) => [k, `${v.n}x ${Math.round(v.ms)}ms`]));
  globalThis.__railgunProfile = profile;

  const wallet = await step('wallet', async () => {
    const info = await createRailgunWallet(encryptionKey, mnemonic, { [NETWORK]: creationBlock ?? head.block });
    return { id: info.id.slice(0, 8) + '…', address: info.railgunAddress };
  });
  const walletID = (await createRailgunWallet(encryptionKey, mnemonic, { [NETWORK]: creationBlock ?? head.block })).id;

  await step('sync', async () => {
    const scan = awaitWalletScan(walletID, CHAIN);
    await refreshBalances(CHAIN, [walletID]);
    await Promise.race([scan, new Promise((r) => setTimeout(r, syncCapMs))]);
    // The wallet's scan can finish before the TXID tree does; wait for both.
    const until = now() + syncCapMs;
    while (!(utxo?.scanStatus === 'Complete' && txid?.scanStatus === 'Complete') && now() < until) await new Promise((r) => setTimeout(r, 1000));
    const done = utxo?.scanStatus === 'Complete' && txid?.scanStatus === 'Complete';
    log('profile', profile());
    return { done, utxo: utxo && { status: utxo.scanStatus, progress: utxo.progress }, txid: txid && { status: txid.scanStatus, progress: txid.progress },
      balance: balances ? balances.erc20Amounts.map((a) => `${a.tokenAddress.slice(0, 8)}…=${a.amount}`) : [] };
  });

  // The check that makes the start block safe: every tree the engine built
  // must end in a root the contract has recorded (`rootHistory`).
  await step('root-check', async () => {
    const tree = getEngine().getUTXOMerkletree(TXIDVersion.V2_PoseidonMerkle, CHAIN);
    const { tree: latest } = await tree.getLatestTreeAndIndex();
    const out = [];
    for (let t = 0; t <= latest; t++) {
      const length = await tree.getTreeLength(t);
      if (!length) { out.push({ tree: t, length: 0 }); continue; }
      const root = await tree.getRoot(t);
      const iface = new Interface(['function rootHistory(uint256, bytes32) view returns (bool)']);
      const data = iface.encodeFunctionData('rootHistory', [t, root.startsWith('0x') ? root : '0x' + root]);
      const res = await (await fetch(RPC, { method: 'POST', headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'eth_call', params: [{ to: NETWORK_CONFIG[NETWORK].proxyContract, data }, 'latest'] }) })).json();
      out.push({ tree: t, length, onChain: res.result ? BigInt(res.result) === 1n : `error ${res.error?.message}` });
    }
    if (!out.some((o) => o.onChain === true)) throw new Error(`no tree matched the contract: ${JSON.stringify(out)}`);
    const txidTree = getEngine().getTXIDMerkletree(TXIDVersion.V2_PoseidonMerkle, CHAIN);
    const txid = [];
    for (let t = 0; t < 8; t++) { const length = await txidTree.getTreeLength(t); if (length) txid.push({ tree: t, length }); }
    const poi = await (await fetch(POI_NODES[0], { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'ppoi_node_status', params: {} }) })).json();
    const poiIndex = poi.result?.forNetwork?.[NETWORK]?.txidStatus?.validatedTxidIndex;
    const { tree: tt, index: ti } = await txidTree.getLatestTreeAndIndex();
    // The TXID tree's own root, asked of the screening node at our index.
    let txidRootValid = null;
    if (ti >= 0) {
      const merkleroot = await txidTree.getRoot(tt);
      const v = await (await fetch(POI_NODES[0], { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ jsonrpc: '2.0', id: 1,
        method: 'ppoi_validate_txid_merkleroot', params: { chainType: String(CHAIN.type), chainID: String(CHAIN.id), txidVersion: TXIDVersion.V2_PoseidonMerkle, tree: tt, index: ti, merkleroot } }) })).json();
      txidRootValid = v.result ?? `error ${JSON.stringify(v.error).slice(0, 120)}`;
    }
    return { trees: out, txidTrees: txid, txidLocalIndex: tt * 65536 + ti, txidScreeningNodeIndex: poiIndex, txidRootValid };
  });

  // A caller with its own steps (mainnet-test.mjs) takes over here.
  if (then) {
    const r = await then({ walletID, eoa: Wallet.fromPhrase(mnemonic), network: NETWORK, chain: CHAIN, rpc: RPC, step, encryptionKey, headBlock: head.block });
    log('total', { ms: Math.round(now() - t0) });
    return r;
  }

  // The shield: the account (here a test EOA from the same phrase) signs
  // Railgun's fixed message once; its hash is the shield key. Prepared only.
  const eoa = Wallet.fromPhrase(mnemonic);
  const prepared = await step('shield-prepare', async () => {
    const shieldPrivateKey = keccak256(await eoa.signMessage(getShieldPrivateKeySignatureMessage()));
    const railgunAddress = getRailgunAddress(walletID);
    const wrapped = NETWORK_CONFIG[NETWORK].baseToken.wrappedAddress;
    const { transaction } = await populateShieldBaseToken(TXIDVersion.V2_PoseidonMerkle, NETWORK, railgunAddress, shieldPrivateKey,
      { tokenAddress: wrapped, amount: shieldWei }, { evmGasType: EVMGasType.Type2, gasEstimate: 1_000_000n, maxFeePerGas: 2_000_000_000n, maxPriorityFeePerGas: 100_000_000n });
    return { to: transaction.to, value: String(transaction.value), dataBytes: getBytes(transaction.data).length, from: eoa.address, transaction };
  });

  // Gas, with the EOA given enough test ETH by a state override: proves the
  // prepared shield would land, with no money.
  await step('shield-estimate', async () => {
    const t = prepared.transaction;
    const body = { jsonrpc: '2.0', id: 1, method: 'eth_estimateGas', params: [
      { from: eoa.address, to: t.to, data: t.data, value: '0x' + BigInt(t.value).toString(16) }, 'latest',
      { [eoa.address]: { balance: '0x' + (10n ** 19n).toString(16) } }] };
    const res = await (await fetch(RPC, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) })).json();
    if (res.error) throw new Error(res.error.message);
    return { gas: Number(BigInt(res.result)) };
  });

  if (send) await step('shield-send', () => send(eoa, prepared.transaction));
  log('total', { ms: Math.round(now() - t0) });
  return { walletID, eoa: eoa.address };
}

export { ArtifactStore };
