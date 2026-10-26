// CasberiKeyAccount trial driver (TESTNET ONLY: Aztec v6 testnet on Sepolia, test keys, test tokens).
//
// Software P-256 keys stand in for the phone (signing) and a recovery device. The account is never deployed:
// no class publication, no instance publication, no initializer. Steps are resumable; state lives in ./state.json
// (gitignored: P-256 test keys, account secrets and salts, one Sepolia test key). Nothing here prints a private key.
//
//   node run.mjs              run every step not yet done (L1 steps only once the Sepolia test address holds ETH)
//   node run.mjs status       print state (public parts only)
//   node run.mjs info         node, sponsored FPC, Sepolia balance
//   node run.mjs claimable    poll until the L2->L1 withdrawal can be consumed on L1, and record how long it took
import { createPrivateKey, generateKeyPairSync, sign as nodeSign } from 'node:crypto';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

import { BaseAccount, NO_FROM } from '@aztec-labs/aztec.js/account';
import { Contract } from '@aztec-labs/aztec.js/contracts';
import { FeeJuicePaymentMethodWithClaim } from '@aztec-labs/aztec.js/fee';
import { SponsoredFeePaymentMethod } from '@aztec-labs/aztec.js/fee/testing';
import { Fr } from '@aztec-labs/aztec.js/fields';
import { L1FeeJuicePortalManager, generateClaimSecret } from '@aztec-labs/aztec.js/ethereum';
import { waitForL1ToL2MessageReady } from '@aztec-labs/aztec.js/messaging';
import { AccountManager } from '@aztec-labs/aztec.js/wallet';
import { computeAuthWitMessageHash } from '@aztec-labs/aztec.js/authorization';
import { DefaultAccountContract } from '@aztec-labs/accounts/defaults';
import { DefaultAccountEntrypoint } from '@aztec-labs/entrypoints/account';
import { DefaultMultiCallEntrypoint } from '@aztec-labs/entrypoints/multicall';
import { createExtendedL1Client } from '@aztec-labs/ethereum/client';
import { poseidon2Hash, poseidon2HashBytes } from '@aztec-labs/foundation/crypto/poseidon';
import { sha256ToField } from '@aztec-labs/foundation/crypto/sha256';
import { EthAddress } from '@aztec-labs/foundation/eth-address';
import { createLogger } from '@aztec-labs/foundation/log';
import { SponsoredFPCContract } from '@aztec-labs/noir-contracts.js/SponsoredFPC';
import { TokenContract } from '@aztec-labs/noir-contracts.js/Token';
import { TokenBridgeContract } from '@aztec-labs/noir-contracts.js/TokenBridge';
import { STANDARD_MULTI_CALL_ENTRYPOINT_ADDRESS } from '@aztec-labs/standard-contracts/multi-call-entrypoint/constants';
import { loadContractArtifact } from '@aztec-labs/stdlib/abi';
import { AuthWitness } from '@aztec-labs/stdlib/auth-witness';
import { AztecAddress } from '@aztec-labs/stdlib/aztec-address';
import { getContractInstanceFromInstantiationParams } from '@aztec-labs/stdlib/contract';
import { computeL2ToL1MessageHash } from '@aztec-labs/stdlib/hash';
import { getL2ToL1MessageLeafId } from '@aztec-labs/stdlib/messaging';
import { ExecutionPayload, TxHash, TxStatus, collectOffchainEffects, mergeExecutionPayloads } from '@aztec-labs/stdlib/tx';
import { BaseWallet, getGasLimits } from '@aztec-labs/wallet-sdk/base-wallet';
import { NodeEmbeddedWallet } from '@aztec-labs/wallets/embedded';
import { OutboxAbi } from '@aztec-foundation/l1-artifacts/OutboxAbi';
import { TestERC20Abi } from '@aztec-foundation/l1-artifacts/TestERC20Abi';
import { TestERC20Bytecode } from '@aztec-foundation/l1-artifacts/TestERC20Bytecode';
import { TokenPortalAbi } from '@aztec-foundation/l1-artifacts/TokenPortalAbi';
import { TokenPortalBytecode } from '@aztec-foundation/l1-artifacts/TokenPortalBytecode';
import { createPublicClient, createWalletClient, decodeEventLog, encodeDeployData, formatEther, getContractAddress, http, toFunctionSelector } from 'viem';
import { generatePrivateKey, privateKeyToAccount } from 'viem/accounts';
import { sepolia } from 'viem/chains';

const DIR = new URL('.', import.meta.url).pathname;
const NODE_URL = process.env.AZTEC_NODE_URL ?? 'https://aztec-testnet.drpc.org';
const L1_RPC = process.env.L1_RPC ?? 'https://ethereum-sepolia-rpc.publicnode.com';
const STATE = process.env.STATE_FILE ?? join(DIR, 'state.json');
// The public drpc endpoint refuses JSON-RPC batches of more than 3 on its free plan.
const NODE_OPTS = { maxBatchSize: Number(process.env.AZTEC_MAX_BATCH ?? 3) };
const ARTIFACT = loadContractArtifact(JSON.parse(readFileSync(join(DIR, 'contract/target/casberi_key_account-CasberiKeyAccount.json'), 'utf8')));
const say = (...a) => console.log(new Date().toISOString().slice(11, 19), '·', ...a);
const sleep = ms => new Promise(r => setTimeout(r, ms));
const FJ = v => (v === undefined ? undefined : Number(v) / 1e18); // fee juice has 18 decimals

// Test token amounts (6 decimals, "cUSD").
const MINT = 1_000_000000n, TO_B = 100_000000n, EXIT = 50_000000n, DEPOSIT = 200_000000n;

// ---------- P-256 (software stand-ins for the Secure Enclave) ----------
const N = 0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551n;
function newKey() {
  const { privateKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
  return privateKey.export({ format: 'jwk' }); // { x, y, d } base64url
}
const xy = jwk => ({ x: Buffer.from(jwk.x, 'base64url'), y: Buffer.from(jwk.y, 'base64url') });
const hexKey = jwk => { const { x, y } = xy(jwk); return Buffer.concat([x, y]).toString('hex'); };
// P-256 over sha256(32-byte big-endian field), r||s, low-S — exactly what the phone returns.
function p256Sign(jwk, field) {
  const msg = Buffer.from(field.toString().slice(2).padStart(64, '0'), 'hex');
  const sig = nodeSign('sha256', msg, { key: createPrivateKey({ key: jwk, format: 'jwk' }), dsaEncoding: 'ieee-p1363' });
  let s = BigInt('0x' + sig.subarray(32).toString('hex'));
  if (s > N / 2n) s = N - s;
  return Buffer.concat([sig.subarray(0, 32), Buffer.from(s.toString(16).padStart(64, '0'), 'hex')]);
}
// EcdsaPublicKeyNote.pack(): [x[0..31] big-endian, x[31], y[0..31], y[31]]
function pack(jwk) {
  const { x, y } = xy(jwk);
  const f = b => new Fr(BigInt('0x' + b.toString('hex')));
  return [f(x.subarray(0, 31)), new Fr(x[31]), f(y.subarray(0, 31)), new Fr(y[31])];
}
const bytes = b => Array.from(b);

// ---------- the account contract, TS side ----------
class CasberiKeyAccountContract extends DefaultAccountContract {
  constructor(initial, recovery) { super(); this.initial = initial; this.recovery = recovery; this.signer = initial; this.signatures = 0; }
  getContractArtifact() { return Promise.resolve(ARTIFACT); }
  getInitializationFunctionAndArgs() { return Promise.resolve(undefined); } // no initializer: nothing to deploy
  getImmutablesHash() { return poseidon2Hash([...pack(this.initial), ...pack(this.recovery)]); }
  getAuthWitnessProvider() {
    return { createAuthWit: async messageHash => { this.signatures++; return new AuthWitness(messageHash, [...p256Sign(this.signer, messageHash)]); } };
  }
}

const makeStep = state => async (name, fn) => {
  if (state.done[name]) { say(name, 'already done'); return state.done[name]; }
  const t = Date.now();
  const out = await fn();
  state.done[name] = { ...out, seconds: Math.round((Date.now() - t) / 1000) }; save(state);
  say(name, JSON.stringify(state.done[name]));
  return state.done[name];
};
const load = () => (existsSync(STATE) ? JSON.parse(readFileSync(STATE, 'utf8')) : {});
const save = s => writeFileSync(STATE, JSON.stringify(s, null, 1));
const newAccount = () => ({ keys: { initial: newKey(), recovery: newKey(), second: newKey(), third: newKey() }, secret: Fr.random().toString(), salt: Fr.random().toString() });

// ---------- timing: every proof the PXE makes is recorded ----------
let lastProof;
let strictSim = false; // refusal checks: a failed simulation is the refusal, never fall back to sending
function instrument(wallet) {
  const pxe = wallet.pxe;
  const prove = pxe.proveTx.bind(pxe);
  pxe.proveTx = async (...a) => {
    const t = Date.now();
    const r = await prove(...a);
    const tm = r.stats?.timings ?? {};
    lastProof = { proveWallMs: Date.now() - t, provingMs: Math.round(tm.proving ?? 0), witgenMs: Math.round((tm.perFunction ?? []).reduce((n, f) => n + (f.time ?? 0), 0)), circuits: (tm.perFunction ?? []).length };
    return r;
  };
}

async function open(state) {
  const wallet = await NodeEmbeddedWallet.create(NODE_URL, { nodeClientOptions: NODE_OPTS, pxe: { proverEnabled: true, dataDirectory: join(DIR, 'pxe') } });
  instrument(wallet);
  const accounts = {};
  for (const name of ['a', 'b']) {
    const s = state[name];
    const contract = new CasberiKeyAccountContract(s.keys.initial, s.keys.recovery);
    const manager = await AccountManager.create(wallet, Fr.fromString(s.secret), contract, { salt: Fr.fromString(s.salt) });
    const instance = manager.getInstance();
    const address = instance.address;
    if (!(await wallet.getContractMetadata(address)).instance) await wallet.registerContract(instance, ARTIFACT, manager.getSecretKey());
    const complete = await manager.getCompleteAddress();
    const account = new BaseAccount(new DefaultAccountEntrypoint(address, contract.getAuthWitnessProvider()), contract.getAuthWitnessProvider(), complete);
    accounts[name] = { contract, address, account, self: await Contract.at(address, ARTIFACT, wallet) };
  }
  for (const { address } of Object.values(accounts)) await wallet.registerSender(address);
  const original = wallet.getAccountFromAddress.bind(wallet);
  wallet.getAccountFromAddress = async a => Object.values(accounts).find(x => x.address.equals(a))?.account ?? original(a);

  // The embedded wallet's sendTx estimates gas by swapping every account for a stub class; the stub has none of this
  // account's functions. So: simulate with the REAL account (it signs; software keys), take the gas it used and any
  // authwits the simulation asked for, then prove + send through the base wallet. Falls back to network max limits.
  // The embedded wallet also simulates through that stub (it looks accounts up in its own DB, where ours are not);
  // simulate through the real account entrypoint instead.
  wallet.simulateViaEntrypoint = BaseWallet.prototype.simulateViaEntrypoint;
  wallet.sendTx = async (payload, opts) => {
    await wallet.pxe.sync();
    let gasSettings = opts.fee?.gasSettings;
    try {
      const sim = await BaseWallet.prototype.simulateTx.call(wallet, payload, { from: opts.from, additionalScopes: opts.additionalScopes, sendMessagesAs: opts.sendMessagesAs, skipTxValidation: true, fee: opts.fee });
      for (const effect of collectOffchainEffects(sim.privateExecutionResult)) {
        try {
          const { CallAuthorizationRequest } = await import('@aztec-labs/aztec.js/authorization');
          const req = await CallAuthorizationRequest.fromFields(effect.data);
          payload.authWitnesses.push(await wallet.createAuthWit(req.onBehalfOf, { consumer: effect.contractAddress, innerHash: req.innerHash }));
        } catch { /* not an authorization request */ }
      }
      const est = getGasLimits(sim.gasUsed, await wallet.getMaxTxGasLimits(), 0.15);
      gasSettings = { ...gasSettings, gasLimits: est.gasLimits, teardownGasLimits: est.teardownGasLimits };
    } catch (e) {
      if (strictSim) throw e;
      say('  (gas estimate failed, sending with network max limits:', String(e.message ?? e).split('\n')[0].slice(0, 160) + ')');
    }
    lastProof = undefined;
    return BaseWallet.prototype.sendTx.call(wallet, payload, { ...opts, fee: { ...opts.fee, gasSettings }, wait: opts.wait ?? { waitForStatus: TxStatus.PROPOSED, timeout: 1800 } });
  };
  const fpc = await getContractInstanceFromInstantiationParams(SponsoredFPCContract.artifact, { salt: new Fr(0) });
  await wallet.registerContract(fpc, SponsoredFPCContract.artifact);
  const sponsored = { paymentMethod: new SponsoredFeePaymentMethod(fpc.address) };
  return { wallet, accounts, sponsored, fpc };
}

async function onchain(wallet, address) {
  const m = await wallet.getContractMetadata(address);
  const cls = await wallet.aztecNode.getContractClass(m.instance.currentContractClassId).catch(() => undefined);
  return { initializationStatus: String(m.initializationStatus), instancePublished: m.isContractPublished, classPublished: !!cls };
}

async function expectRefused(label, fn) {
  strictSim = true;
  try { await fn(); throw new Error(`${label}: UNEXPECTEDLY SUCCEEDED`); }
  catch (e) {
    if (String(e.message).includes('UNEXPECTEDLY')) throw e;
    const msg = String(e.message ?? e).split('\n')[0].slice(0, 220);
    say(`${label}: refused as expected —`, msg);
    return msg;
  } finally { strictSim = false; }
}

const receiptOf = r => ({
  block: Number(r.blockNumber), epoch: r.epochNumber === undefined ? undefined : Number(r.epochNumber), tx: r.txHash.toString(), status: String(r.status),
  feeFJ: FJ(r.transactionFee), ...(lastProof ?? {}),
});

// ---------- L1 (Sepolia) ----------
function l1Clients(state) {
  const account = privateKeyToAccount(state.l1.key);
  return {
    account,
    pub: createPublicClient({ chain: sepolia, transport: http(L1_RPC) }),
    wal: createWalletClient({ account, chain: sepolia, transport: http(L1_RPC) }),
  };
}
// Sepolia now prices state growth high (a 3 KB contract deploy is ~5M gas) and anvil forks under-estimate it, so
// every L1 tx declares its estimate plus 50%.
const pad = g => (g * 3n) / 2n;
async function l1Deploy(pub, wal, abi, bytecode, args) {
  const data = encodeDeployData({ abi, bytecode, args });
  return wal.sendTransaction({ data, gas: pad(await pub.estimateGas({ account: wal.account, data })) });
}
async function l1Write(pub, wal, req) {
  return wal.writeContract({ ...req, gas: pad(await pub.estimateContractGas({ ...req, account: wal.account })) });
}
const l1Receipt = async (pub, hash) => {
  const r = await pub.waitForTransactionReceipt({ hash, timeout: 600_000 });
  if (r.status !== 'success') throw new Error(`L1 tx ${hash} reverted`);
  return { l1Tx: hash, l1Block: Number(r.blockNumber), l1GasUsed: Number(r.gasUsed), l1CostEth: Number(formatEther(r.gasUsed * r.effectiveGasPrice)) };
};
// The portal is deployed by the test address's SECOND tx (nonce 1), the test ERC20 by its first (nonce 0). The L2
// bridge is deployed before either, pointing at the predicted portal, so the L2->L1 leg can be measured before
// Sepolia ETH arrives.
const predicted = funder => ({ erc20: getContractAddress({ from: funder, nonce: 0n }), portal: getContractAddress({ from: funder, nonce: 1n }) });

function withdrawContent(recipient, amount, callerOnL1 = EthAddress.ZERO) {
  return sha256ToField([
    Buffer.from(toFunctionSelector('withdraw(address,uint256,address)').substring(2), 'hex'),
    EthAddress.fromString(recipient).toBuffer32(), new Fr(amount).toBuffer(), callerOnL1.toBuffer32(),
  ]);
}

async function main() {
  const cmd = process.argv[2] ?? 'all';
  let state = load();
  if (!state.l1) { const key = generatePrivateKey(), rk = generatePrivateKey(); state.l1 = { key, address: privateKeyToAccount(key).address, recipientKey: rk, recipient: privateKeyToAccount(rk).address }; }
  if (!state.a) state.a = newAccount();
  if (!state.b) state.b = newAccount();
  state.done ??= {};
  save(state);
  const pubOnly = s => JSON.stringify(s, (k, v) => (['d', 'key', 'recipientKey', 'secret', 'salt', 'claimSecret', 'depositSecret'].includes(k) ? undefined : v), 1);
  if (cmd === 'status') { console.log(pubOnly(state)); return; }

  const node = (await import('@aztec-labs/aztec.js/node')).createAztecNodeClient(NODE_URL, NODE_OPTS);
  const info = await node.getNodeInfo();
  const { pub, wal, account: funder } = l1Clients(state);
  const ethBalance = await pub.getBalance({ address: funder.address });
  const pred = predicted(funder.address);
  if (cmd === 'info') {
    const fpc = await getContractInstanceFromInstantiationParams(SponsoredFPCContract.artifact, { salt: new Fr(0) });
    console.log(JSON.stringify({ nodeVersion: info.nodeVersion, rollupVersion: info.rollupVersion, l1ChainId: info.l1ChainId, l2Block: await node.getBlockNumber(),
      sponsoredFPC: fpc.address.toString(), sponsoredFPCOnChain: !!(await node.getContract(fpc.address)),
      sepoliaTestAddress: funder.address, sepoliaEth: formatEther(ethBalance), sepoliaNonce: await pub.getTransactionCount({ address: funder.address }), predicted: pred, withdrawRecipient: state.l1.recipient }, null, 1));
    return;
  }
  if (cmd === 'claimable') { await claimable(state, node, pub, info); return; }
  // L1 legs alone, no PXE: for a rehearsal against an anvil fork of Sepolia (L1_RPC=http://127.0.0.1:8545,
  // STATE_FILE=a copy of state.json). Steps that need an L2 tx are skipped.
  if (cmd === 'l1only') {
    if (ethBalance === 0n) throw new Error('test address holds no ETH on ' + L1_RPC);
    await l1Legs({ state, step: makeStep(state), node, info, pub, wal, funder, A: { address: AztecAddress.fromStringUnsafe(state.a.address) }, bridge: { address: AztecAddress.fromStringUnsafe(state.bridge) }, l1Only: true });
    return;
  }

  const t0 = Date.now();
  const { wallet, accounts, sponsored } = await open(state);
  const A = accounts.a, B = accounts.b;
  state.a.address = A.address.toString(); state.b.address = B.address.toString(); save(state);
  say('account A', A.address.toString(), '· account B', B.address.toString(), '· node', info.nodeVersion);
  say('A on chain before anything:', JSON.stringify(await onchain(wallet, A.address)));

  // Local, no tx: hand this PXE the immutables' preimage (both public keys), checked against the address.
  for (const [name, acct] of [['a', A], ['b', B]]) {
    const { x: ix, y: iy } = xy(state[name].keys.initial), { x: rx, y: ry } = xy(state[name].keys.recovery);
    await acct.self.methods.register_keys(bytes(ix), bytes(iy), bytes(rx), bytes(ry)).simulate({ from: acct.address });
  }
  say('register_keys (utility, local only) for A and B: ok');

  const step = makeStep(state);
  const signWith = name => { A.contract.signer = state.a.keys[name]; };
  const currentKey = () => (state.done.r5_recover ? 'third' : state.done.r1_rotate ? 'second' : 'initial');
  signWith(currentKey());

  // S1: A's FIRST tx deploys the test token (the token is deployed; the account is not). The entrypoint proves the
  // initial key against the immutables and creates the key note in this same tx. Fees: Sponsored FPC.
  await step('s1_first_tx_deploy_token', async () => {
    const { contract: token, receipt } = await TokenContract.deploy(wallet, A.address, 'Casberi Test USD', 'cUSD', 6).send({ from: A.address, fee: sponsored });
    state.token = token.address.toString(); save(state);
    return { ...receiptOf(receipt), token: state.token };
  });
  const token = await TokenContract.at(AztecAddress.fromStringUnsafe(state.token), wallet);
  say('A on chain after its first tx:', JSON.stringify(await onchain(wallet, A.address)));

  // S2: the L2 half of the token bridge, pointing at the L1 portal the Sepolia test address will deploy (nonce 1).
  await step('s2_deploy_bridge', async () => {
    const { contract: bridge, receipt } = await TokenBridgeContract.deploy(wallet, token.address, EthAddress.fromString(pred.portal)).send({ from: A.address, fee: sponsored });
    state.bridge = bridge.address.toString(); state.portal = pred.portal; state.erc20 = pred.erc20; save(state);
    return { ...receiptOf(receipt), bridge: state.bridge, portal: pred.portal };
  });
  const bridge = await TokenBridgeContract.at(AztecAddress.fromStringUnsafe(state.bridge), wallet);
  await step('s3_bridge_is_minter', async () => receiptOf((await token.methods.set_minter(bridge.address, true).send({ from: A.address, fee: sponsored })).receipt));

  // S4: a private balance (minted by the admin, standing in for an L1 deposit until Sepolia ETH arrives).
  await step('s4_mint_private', async () => receiptOf((await token.methods.mint_to_private(A.address, MINT).send({ from: A.address, fee: sponsored })).receipt));

  // S5: private send to ANOTHER Aztec account (B: a second, undeployed CasberiKeyAccount).
  await step('s5_private_send_to_b', async () => {
    const { receipt } = await token.methods.transfer(B.address, TO_B).send({ from: A.address, fee: sponsored });
    const { result: bBal } = await token.methods.balance_of_private(B.address).simulate({ from: B.address });
    return { ...receiptOf(receipt), bPrivateBalance: String(bBal) };
  });

  // S6: private send OUT to a plain Sepolia address: burn privately through the bridge, emitting an L2->L1 message.
  // The bridge burns A's notes with an authwit A signs; the recipient address and amount are public in the message.
  await step('s6_exit_to_l1_private', async () => {
    const nonce = Fr.random();
    const action = token.methods.burn_private(A.address, EXIT, nonce);
    const hash = await computeAuthWitMessageHash({ caller: bridge.address, action }, await wallet.getChainInfo());
    const witness = await A.contract.getAuthWitnessProvider().createAuthWit(hash);
    const { receipt } = await bridge.methods.exit_to_l1_private(token.address, EthAddress.fromString(state.l1.recipient), EXIT, EthAddress.ZERO, nonce)
      .send({ from: A.address, fee: sponsored, authWitnesses: [witness] });
    const leaf = computeL2ToL1MessageHash({ l2Sender: bridge.address, l1Recipient: EthAddress.fromString(state.portal), content: withdrawContent(state.l1.recipient, EXIT), rollupVersion: new Fr(info.rollupVersion), chainId: new Fr(info.l1ChainId) });
    const block = await node.getBlockData(receipt.blockNumber);
    return { ...receiptOf(receipt), leaf: leaf.toString(), recipient: state.l1.recipient, amount: String(EXIT), includedAt: Number(block?.header?.globalVariables?.timestamp ?? 0), sentAt: Math.round(Date.now() / 1000) };
  });

  // R: rotation and recovery on v6 (the v5 trial, repeated).
  await step('r1_rotate', async () => {
    signWith('initial');
    const { x, y } = xy(state.a.keys.second);
    return receiptOf((await A.self.methods.rotate_signing_key(bytes(x), bytes(y)).send({ from: A.address, fee: sponsored })).receipt);
  });
  await step('r2_initial_key_refused', async () => {
    signWith('initial');
    return { error: await expectRefused('initial key after rotation', () => token.methods.transfer(A.address, 1n).send({ from: A.address, fee: sponsored })) };
  });
  await step('r3_second_key_transfer', async () => { signWith('second'); return receiptOf((await token.methods.transfer(A.address, 10n).send({ from: A.address, fee: sponsored })).receipt); });

  // R5: phone "lost": the recovery key replaces the signing key with `third`. No account sends this: the multicall
  // entrypoint calls the Sponsored FPC and then recover(); only the recovery signature authorises it.
  await step('r5_recover', async () => {
    const { x, y } = xy(state.a.keys.third);
    const nonce = Fr.random();
    const { chainId, version } = await wallet.getChainInfo();
    const domain = await poseidon2HashBytes(Buffer.from('CASBERI_KEY_ACCOUNT_RECOVER'));
    const local = await poseidon2Hash([domain, A.address.toField(), chainId, version, ...pack(state.a.keys.third), nonce]);
    const { result: fromContract } = await A.self.methods.recovery_message(bytes(x), bytes(y), nonce).simulate({ from: A.address });
    const message = new Fr(BigInt(fromContract));
    say('recovery message', local.equals(message) ? '(TS recomputation matches the contract)' : `(TS recomputation DIFFERS: ${local} vs ${message})`);
    const recoverCall = await A.self.methods.recover(bytes(x), bytes(y), nonce).request();
    const witness = new AuthWitness(message, [...p256Sign(state.a.keys.recovery, message)]);
    const merged = mergeExecutionPayloads([await sponsored.paymentMethod.getExecutionPayload(), new ExecutionPayload(recoverCall.calls, [witness], [], recoverCall.extraHashedArgs ?? [])]);
    const wrapped = await new DefaultMultiCallEntrypoint().wrapExecutionPayload(merged, await wallet.getChainInfo());
    const { receipt } = await wallet.sendTx(wrapped, { from: NO_FROM, additionalScopes: [A.address], sendMessagesAs: A.address });
    return { ...receiptOf(receipt), sentBy: 'multicall entrypoint (no account)', localMessageMatches: local.equals(message) };
  });
  await step('r6_second_key_refused', async () => {
    signWith('second');
    return { error: await expectRefused('second key after recovery', () => token.methods.transfer(A.address, 1n).send({ from: A.address, fee: sponsored })) };
  });
  await step('r7_third_key_transfer', async () => { signWith('third'); return receiptOf((await token.methods.transfer(A.address, 5n).send({ from: A.address, fee: sponsored })).receipt); });

  // R8/R9: the AUTHWIT path (verify_private_authwit, a static call). A third party (the multicall entrypoint, no
  // account) spends A's private tokens with an authwit. The rotated-away key must not authorise it.
  const viaAuthwit = async keyName => {
    const nonce = Fr.random();
    const action = token.methods.transfer_in_private(A.address, A.address, 1n, nonce);
    const hash = await computeAuthWitMessageHash({ caller: STANDARD_MULTI_CALL_ENTRYPOINT_ADDRESS, action }, await wallet.getChainInfo());
    const witness = new AuthWitness(hash, [...p256Sign(state.a.keys[keyName], hash)]);
    const req = await action.request();
    const merged = mergeExecutionPayloads([await sponsored.paymentMethod.getExecutionPayload(), new ExecutionPayload(req.calls, [witness], [], req.extraHashedArgs ?? [])]);
    const wrapped = await new DefaultMultiCallEntrypoint().wrapExecutionPayload(merged, await wallet.getChainInfo());
    const { receipt } = await wallet.sendTx(wrapped, { from: NO_FROM, additionalScopes: [A.address], sendMessagesAs: A.address });
    return receiptOf(receipt);
  };
  await step('r8_authwit_second_key_refused', async () => ({ error: await expectRefused('authwit signed by the rotated-away key', () => viaAuthwit('second')) }));
  await step('r9_authwit_third_key', async () => ({ ...(await viaAuthwit('third')), sentBy: 'multicall entrypoint, authwit from the account' }));
  signWith(currentKey());

  // ---------- L1 legs: need Sepolia ETH on the test address ----------
  if (ethBalance === 0n) {
    say(`Sepolia test address ${funder.address} holds no ETH: L1 legs skipped (fund it, then rerun).`);
  } else {
    await l1Legs({ state, step, node, info, pub, wal, funder, wallet, A, B, token, bridge, signWith });
  }

  const { result: bal } = await token.methods.balance_of_private(A.address).simulate({ from: A.address });
  const { result: bBal } = await token.methods.balance_of_private(B.address).simulate({ from: B.address });
  say('private balances: A', String(bal), '· B', String(bBal));
  say('A on chain at the end:', JSON.stringify(await onchain(wallet, A.address)));
  state.finalPrivateBalance = { a: String(bal), b: String(bBal) };
  state.totalSeconds = (state.totalSeconds ?? 0) + Math.round((Date.now() - t0) / 1000); save(state);
  await wallet.stop();
}

async function l1Legs({ state, step, node, info, pub, wal, funder, A, B, token, bridge, l1Only }) {
  const l1 = info.l1ContractAddresses;
  // L1-1/2: deploy the test ERC20 (nonce 0) and the portal (nonce 1) at the addresses the L2 bridge already names.
  await step('l1_deploy_erc20', async () => {
    const nonce = await pub.getTransactionCount({ address: funder.address });
    if (nonce !== 0) throw new Error(`test address nonce is ${nonce}, not 0: the predicted ERC20/portal addresses are gone`);
    const hash = await l1Deploy(pub, wal, TestERC20Abi, TestERC20Bytecode, ['Casberi Test USD', 'cUSD', funder.address]);
    const r = await l1Receipt(pub, hash);
    const at = (await pub.getTransactionReceipt({ hash })).contractAddress;
    if (at.toLowerCase() !== state.erc20.toLowerCase()) throw new Error(`ERC20 landed at ${at}, expected ${state.erc20}`);
    return { ...r, erc20: at };
  });
  await step('l1_deploy_portal', async () => {
    const hash = await l1Deploy(pub, wal, TokenPortalAbi, TokenPortalBytecode, []);
    const r = await l1Receipt(pub, hash);
    const at = (await pub.getTransactionReceipt({ hash })).contractAddress;
    if (at.toLowerCase() !== state.portal.toLowerCase()) throw new Error(`portal landed at ${at}, expected ${state.portal}`);
    return { ...r, portal: at };
  });
  await step('l1_init_portal', async () => {
    const hash = await l1Write(pub, wal, { address: state.portal, abi: TokenPortalAbi, functionName: 'initialize', args: [l1.registryAddress.toString(), state.erc20, bridge.address.toString()] });
    return l1Receipt(pub, hash);
  });

  // F: Fee Juice from our own L1 address (no sponsor): mint test FJ from the public FeeAssetHandler, deposit through
  // the Fee Juice portal to A, claim it on L2 in a tx A pays for itself.
  await step('f1_bridge_fee_juice', async () => {
    const ext = createExtendedL1Client([L1_RPC], state.l1.key, sepolia, 1000);
    const mgr = await L1FeeJuicePortalManager.new(node, ext, createLogger('casberi:fj'));
    const before = await pub.getTransactionCount({ address: funder.address });
    const claim = await mgr.bridgeTokensPublic(A.address, undefined, true);
    state.fjClaim = { claimAmount: String(claim.claimAmount), claimSecret: claim.claimSecret.toString(), messageHash: claim.messageHash, messageLeafIndex: String(claim.messageLeafIndex) }; save(state);
    const after = await pub.getTransactionCount({ address: funder.address });
    return { amountFJ: FJ(claim.claimAmount), l1Txs: after - before, messageHash: claim.messageHash, sentAt: Math.round(Date.now() / 1000) };
  });
  if (!l1Only) await step('f2_claim_and_pay_with_own_fee_juice', async () => {
    const t = Date.now();
    await waitForL1ToL2MessageReady(node, Fr.fromHexString(state.fjClaim.messageHash), { timeoutSeconds: 3600 });
    const waitedForMessage = Math.round((Date.now() - t) / 1000);
    const c = state.fjClaim;
    const paymentMethod = new FeeJuicePaymentMethodWithClaim(A.address, { claimAmount: BigInt(c.claimAmount), claimSecret: Fr.fromString(c.claimSecret), messageLeafIndex: BigInt(c.messageLeafIndex) });
    const { receipt } = await token.methods.transfer(B.address, 1_000000n).send({ from: A.address, fee: { paymentMethod } });
    return { ...receiptOf(receipt), l1ToL2MessageWaitSeconds: waitedForMessage, payer: 'A (claimed fee juice in the same tx)' };
  });
  if (!l1Only) await step('f3_tx_paid_from_own_fee_juice', async () => receiptOf((await token.methods.transfer(B.address, 1_000000n).send({ from: A.address })).receipt));

  // D: bridge the test token IN through our portal, privately (amount public, recipient not), claim on L2.
  await step('d1_l1_deposit_private', async () => {
    const [secret, secretHash] = await generateClaimSecret();
    const r1 = await l1Receipt(pub, await l1Write(pub, wal, { address: state.erc20, abi: TestERC20Abi, functionName: 'mint', args: [funder.address, DEPOSIT] }));
    const r2 = await l1Receipt(pub, await l1Write(pub, wal, { address: state.erc20, abi: TestERC20Abi, functionName: 'approve', args: [state.portal, DEPOSIT] }));
    const hash = await l1Write(pub, wal, { address: state.portal, abi: TokenPortalAbi, functionName: 'depositToAztecPrivate', args: [DEPOSIT, secretHash.toString()] });
    const r3 = await l1Receipt(pub, hash);
    const logs = (await pub.getTransactionReceipt({ hash })).logs.filter(l => l.address.toLowerCase() === state.portal.toLowerCase());
    const ev = logs.map(l => { try { return decodeEventLog({ abi: TokenPortalAbi, ...l }); } catch { return undefined; } }).find(e => e?.eventName === 'DepositToAztecPrivate');
    state.deposit = { depositSecret: secret.toString(), key: ev.args.key, index: String(ev.args.index) }; save(state);
    return { l1GasUsed: r1.l1GasUsed + r2.l1GasUsed + r3.l1GasUsed, l1CostEth: r1.l1CostEth + r2.l1CostEth + r3.l1CostEth, depositTx: hash, sentAt: Math.round(Date.now() / 1000) };
  });
  if (!l1Only) await step('d2_l2_claim_private', async () => {
    const t = Date.now();
    await waitForL1ToL2MessageReady(node, Fr.fromHexString(state.deposit.key), { timeoutSeconds: 3600 });
    const waited = Math.round((Date.now() - t) / 1000);
    const { receipt } = await bridge.methods.claim_private(A.address, DEPOSIT, Fr.fromString(state.deposit.depositSecret), BigInt(state.deposit.index)).send({ from: A.address });
    return { ...receiptOf(receipt), l1ToL2MessageWaitSeconds: waited, paidBy: 'A own fee juice' };
  });

  // W: the L1 claim of the S6 withdrawal, submitted by our own funded test address (no relayer).
  await step('w1_l1_claim_withdrawal', async () => {
    const w = state.done.s6_exit_to_l1_private;
    const wit = await node.getL2ToL1MembershipWitness(TxHash.fromString(w.tx), Fr.fromString(w.leaf));
    if (!wit) throw new Error('withdrawal not claimable yet (epoch not proven): run `node run.mjs claimable`');
    const before = await pub.readContract({ address: state.erc20, abi: TestERC20Abi, functionName: 'balanceOf', args: [state.l1.recipient] });
    const hash = await l1Write(pub, wal, { address: state.portal, abi: TokenPortalAbi, functionName: 'withdraw',
      args: [state.l1.recipient, EXIT, false, BigInt(wit.epochNumber), BigInt(wit.numCheckpointsInEpoch), wit.leafIndex, wit.siblingPath.toBufferArray().map(b => `0x${b.toString('hex')}`)] });
    const r = await l1Receipt(pub, hash);
    const after = await pub.readContract({ address: state.erc20, abi: TestERC20Abi, functionName: 'balanceOf', args: [state.l1.recipient] });
    return { ...r, recipient: state.l1.recipient, recipientGot: String(after - before), submittedBy: 'our own Sepolia test address' };
  });
}

// Poll until the S6 withdrawal is consumable on L1. Without a deployed portal, consumability is checked with an
// eth_call of Outbox.consume FROM the predicted portal address (the Outbox only checks msg.sender == recipient).
async function claimable(state, node, pub, info) {
  const w = state.done.s6_exit_to_l1_private;
  if (!w) throw new Error('run the L2 steps first (s6)');
  const outbox = info.l1ContractAddresses.outboxAddress.toString();
  const t = Date.now();
  for (;;) {
    const receipt = await node.getTxReceipt(TxHash.fromString(w.tx));
    const wit = await node.getL2ToL1MembershipWitness(TxHash.fromString(w.tx), Fr.fromString(w.leaf)).catch(e => { say('witness error', String(e.message).slice(0, 120)); return undefined; });
    const elapsed = Math.round(Date.now() / 1000) - w.sentAt; // local clock at inclusion (the L2 block timestamp is the slot's, not ours)
    if (wit) {
      const path = wit.siblingPath.toBufferArray().map(b => `0x${b.toString('hex')}`);
      const message = { sender: { actor: state.bridge, version: BigInt(info.rollupVersion) }, recipient: { actor: state.portal, chainId: BigInt(info.l1ChainId) }, content: withdrawContent(state.l1.recipient, EXIT).toString() };
      let l1Ok, l1Err;
      try { await pub.simulateContract({ address: outbox, abi: OutboxAbi, functionName: 'consume', args: [message, BigInt(wit.epochNumber), BigInt(wit.numCheckpointsInEpoch), wit.leafIndex, path], account: state.portal }); l1Ok = true; }
      catch (e) { l1Ok = false; l1Err = e.shortMessage ?? String(e.message).slice(0, 160); }
      const root = await pub.readContract({ address: outbox, abi: OutboxAbi, functionName: 'getRootData', args: [BigInt(wit.epochNumber), BigInt(wit.numCheckpointsInEpoch)] }).catch(() => undefined);
      say('witness available: epoch', Number(wit.epochNumber), 'numCheckpoints', Number(wit.numCheckpointsInEpoch), 'leafId', String(getL2ToL1MessageLeafId(wit)), '· L1 consume simulates:', l1Ok, l1Err ?? '', '· root', String(root));
      if (l1Ok) {
        state.done.s7_withdrawal_claimable = { status: String(receipt.status), epoch: Number(wit.epochNumber), numCheckpointsInEpoch: Number(wit.numCheckpointsInEpoch), secondsFromL2InclusionToClaimable: elapsed, checkedBy: 'eth_call Outbox.consume from the predicted portal', at: new Date().toISOString() };
        save(state); say('CLAIMABLE', JSON.stringify(state.done.s7_withdrawal_claimable)); return;
      }
    } else {
      say(`not yet claimable: tx ${String(receipt.status)}, ${Math.round(elapsed / 60)} min since L2 inclusion, proven block ${await node.getBlockNumber('proven')}`);
    }
    if (Date.now() - t > 4 * 3600_000) throw new Error('gave up after 4 hours');
    await sleep(60_000);
  }
}

main().then(() => process.exit(0), e => { console.error('✗', e.stack ?? e); process.exit(1); });
