// Can the note's OWNER ragequit a deposit SENT by another address? Sepolia only.
//   node ragequit-sender.mjs deposit   A prepares a deposit for A's own account; F (a throwaway key) sends it
//   node ragequit-sender.mjs status    ASP status of that deposit's label
//   node ragequit-sender.mjs quit      A prepares the ragequit; eth_call it from A and from F; SEND=A|F posts it
// F's key lives in state/keys-f.json (gitignored, 0600). Prints addresses, never a key.
// Run through rpc-router.mjs (SEPOLIA_RPC=http://127.0.0.1:8547): discovery scans old logs.
import { buildPoseidon } from 'circomlibjs';
import { appendFileSync, chmodSync, existsSync, readFileSync, writeFileSync } from 'node:fs';
import { createPublicClient, createWalletClient, decodeErrorResult, formatEther, http, keccak256, parseEther, toBytes, toHex } from 'viem';
import { generatePrivateKey, privateKeyToAccount } from 'viem/accounts';
import { sepolia } from 'viem/chains';
import * as sdk from '@0xbow/privacy-pools-v2-sdk';
import { APP_IDENTIFIER, CryptoService, KeystoreManager, PoolSessionBuilder } from '@0xbow/privacy-pools-v2-sdk';
import { ASP_URL, RELAYER_URL, RPC, SEPOLIA, assertTestnet } from './config.mjs';
import { loadKeys } from './keys.mjs';

const MODE = process.argv[2] ?? 'status';
const DEPOSIT = parseEther(process.env.DEPOSIT_ETH ?? '0.00002');
const F_FUND = parseEther(process.env.F_FUND_ETH ?? '0.000025');
const hex = (n) => `0x${BigInt(n).toString(16)}`;
const j = (o) => JSON.stringify(o, (_, v) => (typeof v === 'bigint' ? v.toString() : v));
const STATE = new URL('./state/ragequit-sender.json', import.meta.url);
const FKEY = new URL('./state/keys-f.json', import.meta.url);
const LOG = new URL('./state/results.jsonl', import.meta.url);
const record = (step, data) => { appendFileSync(LOG, j({ at: new Date().toISOString(), step: `rqs.${step}`, ...data }) + '\n'); console.log(`[${step}]`, j(data)); };

const pub = createPublicClient({ chain: sepolia, transport: http(RPC) });
assertTestnet(await pub.getChainId());
const { A } = loadKeys();
if (!existsSync(FKEY)) { writeFileSync(FKEY, JSON.stringify({ note: 'SEPOLIA TEST KEY ONLY. Never commit.', F: generatePrivateKey() })); chmodSync(FKEY, 0o600); }
const F = privateKeyToAccount(JSON.parse(readFileSync(FKEY, 'utf8')).F);
const wallet = (acct) => createWalletClient({ account: acct, chain: sepolia, transport: http(RPC) });
const bal = (a) => pub.getBalance({ address: a });
const state = () => (existsSync(STATE) ? JSON.parse(readFileSync(STATE, 'utf8')) : {});
const save = (o) => writeFileSync(STATE, j({ ...state(), ...o }, null, 2));

const errorAbi = Object.entries(sdk).filter(([k, v]) => k.endsWith('_ABI') && Array.isArray(v)).flatMap(([, v]) => v).filter((x) => x.type === 'error');
function revertOf(e) {
  let data; e.walk?.((x) => { if (typeof x?.data === 'string' && x.data.startsWith('0x')) data = x.data; else if (typeof x?.data?.data === 'string') data = x.data.data; return false; });
  data ??= e.data ?? e.cause?.data;
  let name = null; try { const d = decodeErrorResult({ abi: errorAbi, data }); name = `${d.errorName}(${(d.args ?? []).join(',')})`; } catch {}
  return { data: data ?? null, decoded: name, message: (e.shortMessage ?? e.message).slice(0, 200) };
}
async function simulate(from, tx) {
  try { await pub.call({ account: from, to: tx.to, data: tx.data, value: BigInt(tx.value ?? 0) }); return { ok: true, gas: String(await pub.estimateGas({ account: from, to: tx.to, data: tx.data, value: BigInt(tx.value ?? 0) })) }; } catch (e) { return { ok: false, ...revertOf(e) }; }
}

// Same derivation as trial.mjs: A's EIP-712 signature seeds A's protocol keys.
async function sessionA() {
  const addressHash = keccak256(toBytes(A.address));
  const signature = await A.signTypedData({
    domain: { name: 'Standardized Secret Derivation', version: '1', verifyingContract: '0x0000000000000000000000000000000000000000', salt: keccak256(toHex(APP_IDENTIFIER)) },
    types: { SecretDerivation: [{ name: 'purpose', type: 'string' }, { name: 'addressHash', type: 'bytes32' }] },
    primaryType: 'SecretDerivation',
    message: { purpose: 'This signature is used to deterministically derive application-specific secrets from your master seed. It is not a transaction and will not cost any gas.', addressHash },
  });
  const km = await KeystoreManager.fromSignature({ signature, signerAddress: A.address, addressHash, revocableKeyIndex: '0x0' }, { cryptoService: new CryptoService() });
  const details = await (await fetch(`${RELAYER_URL}/v1/details/evm/11155111`)).json();
  const quiet = { level: 'warn', child: () => quiet, debug() {}, info() {}, warn: (m) => console.warn(`  warn ${m}`.slice(0, 200)), error: (m) => console.warn(`  error ${m}`.slice(0, 200)), fatal() {} };
  return PoolSessionBuilder.fromConfig({
    chainId: 11155111, rpcUrl: RPC, ownerAddress: A.address, deploymentBlock: hex(SEPOLIA.fromBlock), aspUrl: ASP_URL,
    relayers: [{ url: RELAYER_URL, name: 'staging', chainId: 11155111, chainType: 'evm', status: 'active', address: details.relayerAddress, processorAddress: SEPOLIA.relay }],
    circuitArtifactsDir: new URL(process.env.CEREMONY ? './circuits-cache/' : './circuits-cache-sepolia-dev/', import.meta.url).pathname,
    logger: quiet,
  }).withKeystoreManager(km).withRelayerDetails(details).create();
}

const poseidon = await buildPoseidon();
const labelHash = (label) => poseidon.F.toObject(poseidon([BigInt(label)])).toString();

record('env', { mode: MODE, A: A.address, F: F.address, balA: formatEther(await bal(A.address)), balF: formatEther(await bal(F.address)) });

if (MODE === 'deposit') {
  if (state().depositTx) throw new Error(`already deposited: ${state().depositTx}`);
  const S = await sessionA();
  const dep = await S.prepareDeposit({ tokenId: SEPOLIA.eth, value: hex(DEPOSIT) });
  const tx = dep.depositTx;
  const need = BigInt(tx.value ?? 0);
  record('prepared', { to: tx.to, msgValue: need, label: dep.pendingNote.label, commitment: dep.pendingNote.commitment });
  // F must cover msg.value plus gas; A keeps at least half its balance.
  const balA = await bal(A.address);
  if (await bal(F.address) < need + parseEther('0.000001')) {
    const amt = F_FUND > need + parseEther('0.000001') ? F_FUND : need + parseEther('0.000002');
    if (balA - amt < balA / 2n) throw new Error(`funding F with ${formatEther(amt)} would leave A under half`);
    const h = await wallet(A).sendTransaction({ to: F.address, value: amt });
    const r = await pub.waitForTransactionReceipt({ hash: h });
    record('fund.F', { tx: h, value: formatEther(amt), gasUsed: r.gasUsed, status: r.status });
  }
  const simF = await simulate(F.address, tx);
  record('simulate.deposit', { fromF: simF });
  if (!simF.ok) throw new Error('deposit from F does not simulate');
  const h = await wallet(F).sendTransaction({ to: tx.to, data: tx.data, value: need });
  const r = await pub.waitForTransactionReceipt({ hash: h });
  const block = await pub.getBlock({ blockNumber: r.blockNumber });
  save({ depositTx: h, sender: F.address, owner: A.address, label: dep.pendingNote.label, labelHash: labelHash(dep.pendingNote.label), commitment: dep.pendingNote.commitment, value: String(DEPOSIT), minedAt: new Date(Number(block.timestamp) * 1000).toISOString() });
  record('deposit', { tx: h, from: r.from, status: r.status, gasUsed: r.gasUsed, block: r.blockNumber, labelHash: labelHash(dep.pendingNote.label) });
} else if (MODE === 'status') {
  const s = state();
  const r = await fetch(`${ASP_URL}/labels/${s.labelHash}/status`).then((x) => x.json()).catch((e) => ({ error: e.message }));
  record('asp', { labelHash: s.labelHash, minedAt: s.minedAt, ...r });
} else if (MODE === 'quit') {
  const s = state();
  const S = await sessionA();
  const found = await S.discoverNotes();
  const mine = found.find((n) => BigInt(n.commitment) === BigInt(s.commitment));
  record('discover', { notes: found.length, foundDeposit: !!mine, status: mine?.status, ownerAddress: mine?.ownerAddress });
  const asp = await fetch(`${ASP_URL}/labels/${s.labelHash}/status`).then((x) => x.json()).catch(() => ({}));
  const q = await S.prepareRageQuit({ commitment: s.commitment });
  record('prepared', { aspStatus: asp.status, recipient: q.recipientAddress, value: q.value, to: q.ragequitTx.to, nullifierHash: q.nullifierHash });
  const fromA = await simulate(A.address, q.ragequitTx);
  const fromF = await simulate(F.address, q.ragequitTx);
  record('simulate.ragequit', { aspStatus: asp.status, fromA, fromF });
  const who = process.env.SEND;
  if (who === 'A' || who === 'F') {
    const acct = who === 'A' ? A : F;
    const before = { A: await bal(A.address), F: await bal(F.address) };
    const h = await wallet(acct).sendTransaction({ to: q.ragequitTx.to, data: q.ragequitTx.data, value: 0n });
    const r = await pub.waitForTransactionReceipt({ hash: h });
    const after = { A: await bal(A.address), F: await bal(F.address) };
    const fee = r.gasUsed * r.effectiveGasPrice;
    save({ ragequitTx: h, ragequitFrom: who });
    record('ragequit', { tx: h, from: who, status: r.status, gasUsed: r.gasUsed, feeWei: fee, deltaA: after.A - before.A, deltaF: after.F - before.F });
  }
}
process.exit();
