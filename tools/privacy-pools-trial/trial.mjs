// Steps 3+: the measured trial on Sepolia through the published SDK.
//   node trial.mjs prep      everything that needs NO funds (default)
//   node trial.mjs run       funded path: register, deposit, wait for the ASP, transfer, withdraw
// Results append to state/results.jsonl. Sepolia only (assertTestnet), and `run` refuses to
// spend more than MAX_SPEND from account A.
import { buildPoseidon } from 'circomlibjs';
import { appendFileSync, mkdirSync } from 'node:fs';
import { createPublicClient, createWalletClient, decodeErrorResult, formatEther, http, keccak256, parseEther, toBytes, toHex } from 'viem';
import { sepolia } from 'viem/chains';
import {
  APP_IDENTIFIER, CryptoService, KeystoreManager, PoolSessionBuilder, NoteStatus,
} from '@0xbow/privacy-pools-v2-sdk';
import { ASP_URL, RELAYER_URL, RPC, SEPOLIA, assertTestnet } from './config.mjs';
import { loadKeys } from './keys.mjs';

const MODE = process.argv[2] ?? 'prep';
const DEPOSIT = parseEther(process.env.DEPOSIT_ETH ?? '0.004');
const TRANSFER = parseEther(process.env.TRANSFER_ETH ?? '0.0015');
const WITHDRAW = parseEther(process.env.WITHDRAW_ETH ?? '0.001');
const MAX_SPEND = parseEther('0.02');
const hex = (n) => `0x${BigInt(n).toString(16)}`;

const pub = createPublicClient({ chain: sepolia, transport: http(RPC) });
assertTestnet(await pub.getChainId());
mkdirSync(new URL('./state/', import.meta.url), { recursive: true });
const RESULTS = new URL('./state/results.jsonl', import.meta.url);
const record = (step, data) => {
  const row = { at: new Date().toISOString(), step, ...data };
  appendFileSync(RESULTS, JSON.stringify(row, (_, v) => (typeof v === 'bigint' ? v.toString() : v)) + '\n');
  console.log(`[${step}]`, JSON.stringify(data, (_, v) => (typeof v === 'bigint' ? v.toString() : v)));
};
const timed = async (fn) => { const t = performance.now(); const v = await fn(); return [v, Math.round(performance.now() - t)]; };

// Quiet logger, but keep warnings and errors, and time every proof the SDK makes.
const proofTimes = [];
const mk = (svc) => ({
  level: 'debug', child: (s) => mk(`${svc}/${s}`),
  debug: (m, o) => { if (/proof generated|Proof generated|generateProof/i.test(m)) proofTimes.push({ svc, m, o }); },
  info: () => {}, warn: (m) => console.warn(`  warn [${svc}] ${m}`.slice(0, 220)), error: (m) => console.warn(`  error [${svc}] ${m}`.slice(0, 220)), fatal: () => {},
});

// The canonical v2 derivation: ONE EIP-712 signature from the owner EOA seeds every protocol key.
// A Safe cannot produce this (no deterministic ECDSA signature), which is the key-model gap.
async function keystoreFor(account) {
  const addressHash = keccak256(toBytes(account.address));
  const signature = await account.signTypedData({
    domain: { name: 'Standardized Secret Derivation', version: '1', verifyingContract: '0x0000000000000000000000000000000000000000', salt: keccak256(toHex(APP_IDENTIFIER)) },
    types: { SecretDerivation: [{ name: 'purpose', type: 'string' }, { name: 'addressHash', type: 'bytes32' }] },
    primaryType: 'SecretDerivation',
    message: { purpose: 'This signature is used to deterministically derive application-specific secrets from your master seed. It is not a transaction and will not cost any gas.', addressHash },
  });
  return KeystoreManager.fromSignature({ signature, signerAddress: account.address, addressHash, revocableKeyIndex: '0x0' }, { cryptoService: new CryptoService() });
}

const details = await (await fetch(`${RELAYER_URL}/v1/details/evm/11155111`)).json();
const relayer = (processorAddress) => ({ url: RELAYER_URL, name: 'staging', chainId: 11155111, chainType: 'evm', status: 'active', address: details.relayerAddress, processorAddress });

async function sessionFor(account, { processor = SEPOLIA.relay, withWallet = false } = {}) {
  const km = await keystoreFor(account);
  const b = PoolSessionBuilder.fromConfig({
    chainId: 11155111, rpcUrl: RPC, ownerAddress: account.address,
    deploymentBlock: hex(SEPOLIA.fromBlock), aspUrl: ASP_URL,
    relayers: [relayer(processor)],
    // Sepolia's verifiers are the SDK 1.0.0 dev keys (see README), so on-chain proofs need that set.
    circuitArtifactsDir: new URL(process.env.CEREMONY ? './circuits-cache/' : './circuits-cache-sepolia-dev/', import.meta.url).pathname,
    logger: mk('root'),
    ...(withWallet ? { walletInteractor: { type: 'viem', walletClient: createWalletClient({ account, chain: sepolia, transport: http(RPC) }) } } : {}),
  }).withKeystoreManager(km).withRelayerDetails(details);
  const [s, ms] = await timed(() => b.create());
  return { s, ms, km };
}

const keys = loadKeys();
const bal = async (a) => pub.getBalance({ address: a });
record('env', { mode: MODE, node: process.version, A: keys.A.address, B: keys.B.address, C: keys.C.address, balanceA: formatEther(await bal(keys.A.address)) });

// ---------------------------------------------------------------------------------- prep (no funds)
async function prep() {
  const { s: A, ms } = await sessionFor(keys.A);
  record('session.create', { ms });
  const [regA, regMs] = await timed(() => A.isKeystoreRegistered());
  record('keystore.isRegistered', { account: 'A', registered: regA, ms: regMs });

  // Registration calldata (two legs: setAuthPolicy, then the viewing key), and its gas.
  try {
    const [r, ms2] = await timed(() => A.prepareRegisterKeystore({ includeViewingKey: true }));
    const gas = {};
    for (const [k, tx] of Object.entries({ keystore: r.keystoreCalldata, viewingKey: r.viewingKeyCalldata })) {
      if (!tx) continue;
      try { gas[k] = String(await pub.estimateGas({ account: keys.A.address, to: tx.to, data: tx.data, value: tx.value ? BigInt(tx.value) : 0n })); } catch (e) { gas[k] = `estimate failed: ${(e.shortMessage ?? e.message).slice(0, 120)}`; }
    }
    record('keystore.prepareRegister', { ms: ms2, alreadyRegistered: r.alreadyRegistered, legs: { keystore: !!r.keystoreCalldata, viewingKey: !!r.viewingKeyCalldata }, keystoreTo: r.keystoreCalldata?.to, gas });
  } catch (e) { record('keystore.prepareRegister', { error: e.message.slice(0, 300) }); }

  // Gasless (relayed) registration: the owner signs EIP-712, the relayer posts it.
  try {
    const deadline = hex(Math.floor(Date.now() / 1000) + 3600);
    const [r, ms3] = await timed(() => A.prepareRelayedRegistration({ deadline, sign: false }));
    record('keystore.prepareRelayedRegistration', { ms: ms3, primaryType: r.typedData?.primaryType, domain: r.typedData?.domain, signed: !!r.signature });
  } catch (e) { record('keystore.prepareRelayedRegistration', { error: e.message.slice(0, 300) }); }

  // Note discovery for an empty account: what a phone pays every launch (log scan from the pool's block).
  const [found, dms] = process.env.SKIP_DISCOVER ? [[], -1] : await timed(() => A.discoverNotes());
  record('notes.discover', { notes: found.length, ms: dms, fromBlock: String(SEPOLIA.fromBlock), head: String(await pub.getBlockNumber()) });

  // Deposit: does it need registration first, and what does it cost?
  try {
    const [d, ms4] = await timed(() => A.prepareDeposit({ tokenId: SEPOLIA.eth, value: hex(DEPOSIT) }));
    let gas;
    // Unfunded: estimate with a balance override, so the number is the deposit's own gas.
    try { gas = String(await pub.estimateGas({ account: keys.A.address, to: d.depositTx.to, data: d.depositTx.data, value: BigInt(d.depositTx.value ?? 0), stateOverride: [{ address: keys.A.address, balance: parseEther('1') }] })); } catch (e) {
      gas = `estimate failed: ${(e.shortMessage ?? e.message).slice(0, 140)}`;
      // Name the revert: eth_call returns its data, decoded against every SDK ABI.
      try {
        await pub.call({ account: keys.A.address, to: d.depositTx.to, data: d.depositTx.data, value: BigInt(d.depositTx.value ?? 0), stateOverride: [{ address: keys.A.address, balance: parseEther('1') }] });
      } catch (ce) {
        const data = ce.data ?? ce.cause?.data ?? ce.walk?.((x) => x?.data)?.data;
        const sdk = await import('@0xbow/privacy-pools-v2-sdk');
        const abi = Object.entries(sdk).filter(([k, v]) => k.endsWith('_ABI') && Array.isArray(v)).flatMap(([, v]) => v).filter((x) => x.type === 'error');
        try { gas += ` → ${decodeErrorResult({ abi, data }).errorName}`; } catch { gas += ` → raw ${String(data).slice(0, 12)}`; }
      }
    }
    record('deposit.prepare', { ms: ms4, to: d.depositTx.to, value: String(d.depositTx.value), gas, proofs: proofTimes.splice(0) });
  } catch (e) { record('deposit.prepare', { error: e.message.slice(0, 300) }); }

  // Relayer fee quotes, no proof needed.
  const post = async (path, body) => { const [r, ms5] = await timed(async () => { const res = await fetch(`${RELAYER_URL}${path}`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) }); return { status: res.status, body: await res.json().catch(() => null) }; }); return { ...r, ms: ms5 }; };
  const tq = await post('/v1/quote/evm/11155111/transfer', { asset: SEPOLIA.eth, commit: false });
  record('relayer.quote.transfer', tq);
  const wq = await post('/v1/quote/evm/11155111/receive', { asset: SEPOLIA.eth, commit: false, recipient: keys.C.address, extraGas: false, amount: String(WITHDRAW) });
  record('relayer.quote.withdraw', wq);
  // Payment request: is it local, or does it need a registered keystore?
  try {
    const [pr, pms] = await timed(() => A.generatePaymentRequest({ amount: hex(TRANSFER), tokenId: SEPOLIA.eth }));
    record('paymentRequest.generate', { ms: pms, fields: Object.keys(pr ?? {}) });
  } catch (e) { record('paymentRequest.generate', { error: `${e.name}: ${e.message}`.slice(0, 300) }); }

  const gasPrice = await pub.getGasPrice();
  record('gasPrice', { wei: String(gasPrice), gwei: Number(gasPrice) / 1e9 });
}

// ---------------------------------------------------------------------------------- run (funded)
async function waitTx(hash) { const t = performance.now(); const r = await pub.waitForTransactionReceipt({ hash }); return { r, ms: Math.round(performance.now() - t) }; }
const cost = (r) => r.gasUsed * r.effectiveGasPrice;

async function run() {
  const startA = await bal(keys.A.address);
  if (startA < DEPOSIT + parseEther(process.env.GAS_BUFFER_ETH ?? '0.004')) throw new Error(`A holds ${formatEther(startA)} SepoliaETH; fund ${keys.A.address} with ~0.02 Sepolia ETH first`);
  const spent = () => bal(keys.A.address).then((b) => { if (startA - b > MAX_SPEND) throw new Error('MAX_SPEND exceeded, stopping'); return startA - b; });
  const walletA = createWalletClient({ account: keys.A, chain: sepolia, transport: http(RPC) });

  // B needs gas to register its keystore (or a relayed registration); give it a little.
  const bGas = parseEther(process.env.B_GAS_ETH ?? '0.002');
  if (await bal(keys.B.address) < (bGas * 3n) / 4n) {
    const h = await walletA.sendTransaction({ to: keys.B.address, value: bGas });
    await waitTx(h); record('fund.B', { tx: h });
  }

  const { s: A } = await sessionFor(keys.A, { withWallet: true });
  const { s: B } = await sessionFor(keys.B, { withWallet: true });
  for (const [name, S] of [['A', A], ['B', B]]) {
    if (await S.isKeystoreRegistered()) { record('register', { account: name, already: true }); continue; }
    const t = performance.now();
    const receipts = await S.registerKeystore({ includeViewingKey: true });
    record('register', { account: name, ms: Math.round(performance.now() - t), txs: receipts.map((x) => x.txHash ?? x.transactionHash), gasUsed: receipts.map((x) => String(x.gasUsed ?? '')) });
  }
  await spent();

  // Deposit (RESUME=1 picks up an earlier run's deposit instead of making another).
  let t = performance.now();
  if (process.env.RESUME) return resume(A, B);
  const dep = await A.prepareDeposit({ tokenId: SEPOLIA.eth, value: hex(DEPOSIT) });
  const proveMs = Math.round(performance.now() - t);
  const depRcpt = await A.executeDeposit(dep);
  const depMs = Math.round(performance.now() - t);
  const depFull = await pub.getTransactionReceipt({ hash: depRcpt.txHash });
  record('deposit', { value: formatEther(DEPOSIT), prepareAndProveMs: proveMs, wallMs: depMs, tx: depRcpt.txHash, gasUsed: depFull.gasUsed, feeEth: formatEther(cost(depFull)), label: dep.pendingNote.label });
  await spent();

  // ASP approval wait: poll the label until it is in the association set.
  const approvedAt = performance.now();
  // The ASP keys a label by its hash, Poseidon(label); the raw label always reads "unknown".
  const labelHash = await poseidonOf(BigInt(dep.pendingNote.label));
  let status = 'unknown', polls = 0;
  for (;;) {
    polls++;
    const r = await fetch(`${ASP_URL}/labels/${labelHash}/status`).then((x) => x.json()).catch(() => ({}));
    status = r?.status ?? JSON.stringify(r).slice(0, 80);
    if (/approved|accepted|included/i.test(status)) break;
    if (/reject|declin|denied/i.test(status)) break;
    if (performance.now() - approvedAt > 60 * 60_000) { status += ' (gave up after 60 min)'; break; }
    await new Promise((res) => setTimeout(res, 15_000));
  }
  const waitMs = Math.round(performance.now() - approvedAt);
  record('asp.approval', { status, waitMs, waitMin: +(waitMs / 60000).toFixed(1), polls });
  if (!/approved|accepted|included/i.test(status)) return;
  await transferAndWithdraw(A, B, dep.pendingNote.commitment);
}

const poseidon = await buildPoseidon();
const poseidonOf = async (x) => poseidon.F.toObject(poseidon([x])).toString();

async function resume(A, B) {
  const [found] = await timed(() => A.discoverNotes());
  const notes = (await A.exportAccount()).notes ?? [];
  const n = notes.find((x) => x.status === NoteStatus.ACTIVE) ?? notes[0];
  if (!n) { record('resume', { error: 'no note found', discovered: found.length }); return; }
  const r = await fetch(`${ASP_URL}/labels/${await poseidonOf(BigInt(n.label))}/status`).then((x) => x.json());
  record('resume', { notes: notes.length, status: r.status, approvedAt: r.timestamp ? new Date(r.timestamp).toISOString() : null });
  if (r.status !== 'approved') return;
  await transferAndWithdraw(A, B, n.commitment);
}

async function transferAndWithdraw(A, B, fallbackCommitment) {
  let t;
  // Private transfer A -> B via the relayer (transfers are posted by the relayer's signer EOA).
  await A.discoverNotes();
  const { s: Ar } = await sessionFor(keys.A, { processor: SEPOLIA.relayerSigner });
  await Ar.discoverNotes();
  const note = (await Ar.exportAccount()).notes?.find?.((n) => n.status === NoteStatus.ACTIVE) ?? null;
  t = performance.now();
  const prepT = await Ar.prepareTransfer({ inputCommitments: note ? [note.commitment] : [fallbackCommitment], amount: hex(TRANSFER), tokenId: SEPOLIA.eth, recipientDiscoveryData: { evmAddress: keys.B.address } });
  const proveT = Math.round(performance.now() - t);
  const opt = prepT.relayOptions[0];
  const tRes = await Ar.relayTransfer(opt);
  const tFull = await pub.getTransactionReceipt({ hash: tRes.txReceipt.txHash });
  record('transfer', { amount: formatEther(TRANSFER), prepareAndProveMs: proveT, wallMs: Math.round(performance.now() - t), tx: tRes.txReceipt.txHash, gasUsed: tFull.gasUsed, relayerPaidEth: formatEther(cost(tFull)), quote: opt.selectedQuote.quote });

  // B sees it?
  const [bNotes, bMs] = await timed(() => B.discoverNotes());
  record('transfer.discoveredByB', { notes: bNotes.length, ms: bMs });

  // Withdraw A's change to C (plain address) via PrivacyPoolRelay.
  await A.discoverNotes();
  const change = (await A.exportAccount()).notes?.filter?.((n) => n.status === NoteStatus.ACTIVE) ?? [];
  t = performance.now();
  const prepW = await A.prepareWithdraw({ inputCommitments: change.slice(0, 1).map((n) => n.commitment), amount: hex(WITHDRAW), tokenId: SEPOLIA.eth, recipientAddress: keys.C.address });
  const wOpt = prepW.relayerOptions[0];
  const wR = await A.relayWithdraw(wOpt);
  const wFull = await pub.getTransactionReceipt({ hash: wR.txHash });
  record('withdraw', { amount: formatEther(WITHDRAW), wallMs: Math.round(performance.now() - t), tx: wR.txHash, gasUsed: wFull.gasUsed, relayerPaidEth: formatEther(cost(wFull)), quote: wOpt.selectedQuote.quote, Creceived: formatEther(await bal(keys.C.address)) });
  record('balance.A', { eth: formatEther(await bal(keys.A.address)) });
}

try { await (MODE === 'run' ? run() : prep()); } catch (e) { record('fatal', { error: (e.stack ?? e.message).slice(0, 600) }); process.exitCode = 1; }
process.exit();
