// CasberiKeyAccount spike driver (TESTNET ONLY: Aztec v5 testnet, Sponsored FPC, test keys).
//
// Software P-256 keys stand in for the phone (signing) and a recovery device. The account is never deployed:
// no class publication, no instance publication, no initializer. Steps are resumable; state lives in ./state.json.
//
//   node run.mjs            run every step not yet done
//   node run.mjs status     print state
import { createPrivateKey, generateKeyPairSync, randomBytes, sign as nodeSign } from 'node:crypto';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

import { BaseAccount, NO_FROM } from '@aztec/aztec.js/account';
import { Contract } from '@aztec/aztec.js/contracts';
import { SponsoredFeePaymentMethod } from '@aztec/aztec.js/fee/testing';
import { Fr } from '@aztec/aztec.js/fields';
import { AccountManager } from '@aztec/aztec.js/wallet';
import { DefaultAccountContract } from '@aztec/accounts/defaults';
import { DefaultAccountEntrypoint } from '@aztec/entrypoints/account';
import { DefaultMultiCallEntrypoint } from '@aztec/entrypoints/multicall';
import { poseidon2Hash, poseidon2HashBytes } from '@aztec/foundation/crypto/poseidon';
import { SponsoredFPCContract } from '@aztec/noir-contracts.js/SponsoredFPC';
import { TokenContract } from '@aztec/noir-contracts.js/Token';
import { loadContractArtifact } from '@aztec/stdlib/abi';
import { AuthWitness } from '@aztec/stdlib/auth-witness';
import { computeAuthWitMessageHash } from '@aztec/aztec.js/authorization';
import { STANDARD_MULTI_CALL_ENTRYPOINT_ADDRESS } from '@aztec/standard-contracts/multi-call-entrypoint/constants';
import { AztecAddress } from '@aztec/stdlib/aztec-address';
import { getContractInstanceFromInstantiationParams } from '@aztec/stdlib/contract';
import { ExecutionPayload, TxStatus, mergeExecutionPayloads } from '@aztec/stdlib/tx';
import { BaseWallet } from '@aztec/wallet-sdk/base-wallet';
import { NodeEmbeddedWallet } from '@aztec/wallets/embedded';

const DIR = new URL('.', import.meta.url).pathname;
const NODE_URL = process.env.AZTEC_NODE_URL ?? 'https://v5.testnet.rpc.aztec-labs.com';
const STATE = join(DIR, 'state.json');
const ARTIFACT = loadContractArtifact(JSON.parse(readFileSync(join(DIR, 'contract/target/casberi_key_account-CasberiKeyAccount.json'), 'utf8')));
const say = (...a) => console.log(new Date().toISOString().slice(11, 19), '·', ...a);

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

const load = () => (existsSync(STATE) ? JSON.parse(readFileSync(STATE, 'utf8')) : null);
const save = s => writeFileSync(STATE, JSON.stringify(s, null, 1));

async function open(state) {
  const wallet = await NodeEmbeddedWallet.create(NODE_URL, { pxe: { proverEnabled: true, dataDirectory: join(DIR, 'pxe') } });
  const contract = new CasberiKeyAccountContract(state.keys.initial, state.keys.recovery);
  const manager = await AccountManager.create(wallet, Fr.fromString(state.secret), contract, { salt: Fr.fromString(state.salt) });
  const instance = manager.getInstance();
  const address = instance.address;
  if (!(await wallet.getContractMetadata(address)).instance) await wallet.registerContract(instance, ARTIFACT, manager.getSecretKey());
  const complete = await manager.getCompleteAddress();
  const account = new BaseAccount(new DefaultAccountEntrypoint(address, contract.getAuthWitnessProvider()), contract.getAuthWitnessProvider(), complete);
  const original = wallet.getAccountFromAddress.bind(wallet);
  wallet.getAccountFromAddress = async a => (a.equals(address) ? account : original(a));
  // The embedded wallet's gas pre-simulation swaps every account for a stub class; the stub has no
  // rotate/recover functions, so send through the base wallet (prove + send, network max gas limits).
  wallet.sendTx = async (payload, opts) => {
    await wallet.pxe.sync();
    return BaseWallet.prototype.sendTx.call(wallet, payload, { ...opts, wait: opts.wait ?? { waitForStatus: TxStatus.PROPOSED, timeout: 900 } });
  };
  const fpc = await getContractInstanceFromInstantiationParams(SponsoredFPCContract.artifact, { salt: new Fr(0) });
  await wallet.registerContract(fpc, SponsoredFPCContract.artifact);
  const fee = { paymentMethod: new SponsoredFeePaymentMethod(fpc.address) };
  const self = await Contract.at(address, ARTIFACT, wallet);
  return { wallet, contract, address, fee, self, fpc };
}

async function onchain(wallet, address) {
  const m = await wallet.getContractMetadata(address);
  const cls = await wallet.aztecNode.getContractClass(m.instance.currentContractClassId).catch(() => undefined); // null (schema error) when unpublished
  return { initializerNullifier: String(m.initializationStatus), instancePublished: m.isContractPublished, classPublished: !!cls };
}

async function expectRefused(label, fn) {
  try { await fn(); throw new Error(`${label}: UNEXPECTEDLY SUCCEEDED`); }
  catch (e) {
    if (String(e.message).includes('UNEXPECTEDLY')) throw e;
    const msg = String(e.message ?? e).split('\n')[0].slice(0, 220);
    say(`${label}: refused as expected —`, msg);
    return msg;
  }
}

const receiptOf = r => ({ block: r.blockNumber, tx: r.txHash.toString(), status: String(r.status) });

async function main() {
  const cmd = process.argv[2] ?? 'all';
  let state = load();
  if (!state) {
    state = { keys: { initial: newKey(), recovery: newKey(), second: newKey(), third: newKey() }, secret: Fr.random().toString(), salt: Fr.random().toString(), done: {} };
    save(state);
  }
  if (cmd === 'status') { console.log(JSON.stringify({ ...state, keys: Object.fromEntries(Object.entries(state.keys).map(([k, v]) => [k, hexKey(v).slice(0, 16) + '…'])) }, null, 1)); return; }

  const t0 = Date.now();
  const { wallet, contract, address, fee, self } = await open(state);
  state.address = address.toString(); save(state);
  say('account', address.toString(), 'node', (await wallet.getNodeInfo()).nodeVersion);
  say('on chain before anything:', JSON.stringify(await onchain(wallet, address)));

  // Local, no tx: hand this PXE the immutables' preimage (both public keys), checked against the address.
  const { x: ix, y: iy } = xy(state.keys.initial), { x: rx, y: ry } = xy(state.keys.recovery);
  await self.methods.register_keys(bytes(ix), bytes(iy), bytes(rx), bytes(ry)).simulate({ from: address });
  say('register_keys (utility, local only): ok');

  const step = async (name, fn) => {
    if (state.done[name]) { say(name, 'already done', JSON.stringify(state.done[name])); return state.done[name]; }
    const t = Date.now();
    const out = await fn();
    state.done[name] = { ...out, seconds: Math.round((Date.now() - t) / 1000) }; save(state);
    say(name, JSON.stringify(state.done[name]));
    return state.done[name];
  };
  const signWith = name => { contract.signer = state.keys[name]; };
  const signerFor = () => {
    // the key the account currently expects, from what has been done
    if (state.done.t6_recover) return 'third';
    if (state.done.t3_rotate) return 'second';
    return 'initial';
  };

  // T1: the account's FIRST tx — deploys a test token (the token is deployed; the account is not). The account's
  // entrypoint proves the initial key against the immutables and creates its key note in this same tx.
  await step('t1_first_tx_deploy_token', async () => {
    signWith('initial');
    const { contract: token, receipt } = await TokenContract.deploy(wallet, address, 'Spike', 'SPK', 18).send({ from: address, fee });
    state.token = token.address.toString(); save(state);
    return { ...receiptOf(receipt), token: state.token };
  });
  const token = await TokenContract.at(AztecAddress.fromStringUnsafe(state.token), wallet);
  say('on chain after first tx:', JSON.stringify(await onchain(wallet, address)));

  // T2: a private action signed by the initial (phone) key.
  await step('t2_mint_private', async () => {
    signWith('initial');
    const { receipt } = await token.methods.mint_to_private(address, 100n).send({ from: address, fee });
    return receiptOf(receipt);
  });

  // T3: the current key rotates itself to `second`.
  await step('t3_rotate', async () => {
    signWith('initial');
    const { x, y } = xy(state.keys.second);
    const { receipt } = await self.methods.rotate_signing_key(bytes(x), bytes(y)).send({ from: address, fee });
    return receiptOf(receipt);
  });

  // T4: the rotated-away key no longer authorises.
  await step('t4_initial_key_refused', async () => {
    signWith('initial');
    return { error: await expectRefused('initial key after rotation', () => token.methods.transfer(address, 1n).send({ from: address, fee })) };
  });

  // T5: the new key does.
  await step('t5_second_key_transfer', async () => {
    signWith('second');
    const { receipt } = await token.methods.transfer(address, 10n).send({ from: address, fee });
    return receiptOf(receipt);
  });

  // T6: phone "lost": the recovery key replaces the signing key with `third`. No account sends this: the
  // multicall entrypoint calls the Sponsored FPC and then recover(); only the recovery signature authorises it.
  await step('t6_recover', async () => {
    const { x, y } = xy(state.keys.third);
    const nonce = Fr.random();
    const { chainId, version } = await wallet.getChainInfo();
    const domain = await poseidon2HashBytes(Buffer.from('CASBERI_KEY_ACCOUNT_RECOVER'));
    const local = await poseidon2Hash([domain, address.toField(), chainId, version, ...pack(state.keys.third), nonce]);
    const { result: fromContract } = await self.methods.recovery_message(bytes(x), bytes(y), nonce).simulate({ from: address });
    const message = new Fr(BigInt(fromContract));
    say('recovery message', message.toString(), local.equals(message) ? '(TS recomputation matches)' : `(TS recomputation DIFFERS: ${local})`);
    const recoverCall = await self.methods.recover(bytes(x), bytes(y), nonce).request();
    const witness = new AuthWitness(message, [...p256Sign(state.keys.recovery, message)]);
    const feePayload = await fee.paymentMethod.getExecutionPayload();
    const merged = mergeExecutionPayloads([feePayload, new ExecutionPayload(recoverCall.calls, [witness], [], recoverCall.extraHashedArgs ?? [])]);
    const wrapped = await new DefaultMultiCallEntrypoint().wrapExecutionPayload(merged, await wallet.getChainInfo());
    const { receipt } = await wallet.sendTx(wrapped, { from: NO_FROM, additionalScopes: [address], sendMessagesAs: address });
    return { ...receiptOf(receipt), sentBy: 'multicall entrypoint (no account)', localMessageMatches: local.equals(message) };
  });

  // T7: the phone's rotated key is now refused too.
  await step('t7_second_key_refused', async () => {
    signWith('second');
    return { error: await expectRefused('second key after recovery', () => token.methods.transfer(address, 1n).send({ from: address, fee })) };
  });

  // T8: the recovered key works.
  await step('t8_third_key_transfer', async () => {
    signWith('third');
    const { receipt } = await token.methods.transfer(address, 5n).send({ from: address, fee });
    return receiptOf(receipt);
  });

  // T9/T10: the AUTHWIT path (verify_private_authwit, a static call). A third party (here: the multicall entrypoint,
  // no account) spends the account's private tokens with an authwit. The rotated-away key must not authorise it.
  const viaAuthwit = async keyName => {
    const nonce = Fr.random();
    const action = token.methods.transfer_in_private(address, address, 1n, nonce);
    const hash = await computeAuthWitMessageHash({ caller: STANDARD_MULTI_CALL_ENTRYPOINT_ADDRESS, action }, await wallet.getChainInfo());
    const witness = new AuthWitness(hash, [...p256Sign(state.keys[keyName], hash)]);
    const req = await action.request();
    const merged = mergeExecutionPayloads([await fee.paymentMethod.getExecutionPayload(), new ExecutionPayload(req.calls, [witness], [], req.extraHashedArgs ?? [])]);
    const wrapped = await new DefaultMultiCallEntrypoint().wrapExecutionPayload(merged, await wallet.getChainInfo());
    const { receipt } = await wallet.sendTx(wrapped, { from: NO_FROM, additionalScopes: [address], sendMessagesAs: address });
    return receiptOf(receipt);
  };
  await step('t9_authwit_second_key_refused', async () => ({ error: await expectRefused('authwit signed by the rotated-away key', () => viaAuthwit('second')) }));
  await step('t10_authwit_third_key', async () => ({ ...(await viaAuthwit('third')), sentBy: 'multicall entrypoint, authwit from the account' }));

  signWith(signerFor());
  const { result: bal } = await token.methods.balance_of_private(address).simulate({ from: address });
  say('private balance', String(bal));
  say('on chain at the end:', JSON.stringify(await onchain(wallet, address)));
  state.finalPrivateBalance = String(bal); state.totalSeconds = (state.totalSeconds ?? 0) + Math.round((Date.now() - t0) / 1000); save(state);
  await wallet.stop();
}

main().then(() => process.exit(0), e => { console.error('✗', e.stack ?? e); process.exit(1); });
