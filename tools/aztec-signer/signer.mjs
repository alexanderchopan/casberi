// Casberi's Aztec testnet signer — the computer half (2026-10-11, prd §1276).
//
// Aztec has no Swift client, so the phone cannot run an account: this tool
// does (Aztec's own EcdsaRAccount and its PXE, proving here), and the phone
// holds the ONLY key the account accepts, in its Secure Enclave. Whenever the
// account must authorise something, this hands the phone the whole request —
// calls, nonce, chain, account, hash — as a casberi://aztec/sign link; the
// phone rebuilds the hash from the calls, shows them, and signs only if they
// match. The signature comes back as a `casberi-aztec-sig:` line, which this
// verifies against the phone's key before it is used.
//
// TESTNET ONLY: the phone refuses any chain but an Aztec testnet. This reaches
// Aztec's v6 testnet (node 6.0.0, rollup 679261766 on Sepolia) through the
// `@aztec-labs/*` 6.0.0 packages (the `@aztec/*` scope stops at 5.2.1).
//
//   node signer.mjs account <phone public key hex>   make + deploy the account
//   node signer.mjs once                             one signed tx: deploy a token
//   node signer.mjs demo                             a token: deploy, mint, shield
//   node signer.mjs status                           the account and its balances
//
// Handoff: --sim <udid> drives a simulator (openurl + pbpaste); otherwise the
// link is shown as a QR code for the iPhone's camera (prd §1419) AND copied to
// this Mac's clipboard (Universal Clipboard carries it to the phone: paste it
// on the Aztec page), and the tool waits for the signature to come back on the
// clipboard.
import { execFileSync } from 'node:child_process';
import { createPublicKey, verify } from 'node:crypto';
import { chmodSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import QRCode from 'qrcode';

import { NO_FROM } from '@aztec-labs/aztec.js/account';
import { SponsoredFeePaymentMethod } from '@aztec-labs/aztec.js/fee/testing';
import { Fr } from '@aztec-labs/aztec.js/fields';
import { AccountManager } from '@aztec-labs/aztec.js/wallet';
import { EcdsaRSSHAccountContract } from '@aztec-labs/accounts/ecdsa';
import { EncodedAppEntrypointCalls } from '@aztec-labs/entrypoints/encoding';
import { SponsoredFPCContract } from '@aztec-labs/noir-contracts.js/SponsoredFPC';
import { TokenContract } from '@aztec-labs/noir-contracts.js/Token';
import { FunctionSelector, decodeFunctionSignature } from '@aztec-labs/stdlib/abi';
import { AuthWitness } from '@aztec-labs/stdlib/auth-witness';
import { AztecAddress } from '@aztec-labs/stdlib/aztec-address';
import { getContractInstanceFromInstantiationParams } from '@aztec-labs/stdlib/contract';
import { NodeEmbeddedWallet } from '@aztec-labs/wallets/embedded';

const NODE_URL = process.env.AZTEC_NODE_URL ?? 'https://aztec-testnet.drpc.org';
// The public endpoint refuses JSON-RPC batches of more than three.
const NODE_OPTS = { maxBatchSize: Number(process.env.AZTEC_MAX_BATCH ?? 3) };
// One directory per testnet: a v5 PXE cannot open on v6, and the stock
// account's address moved with its artifact.
const HOME = process.env.AZTEC_SIGNER_HOME ?? join(homedir(), '.casberi-aztec-signer', 'v6');
const STATE = join(HOME, 'state.json');
const args = process.argv.slice(2);
const sim = args.includes('--sim') ? args[args.indexOf('--sim') + 1] : null;
const say = (...a) => console.log('·', ...a);

// The calls the entrypoint is about to hash, kept so the phone gets the
// request itself, never a bare hash.
let pending = null;
const create = EncodedAppEntrypointCalls.create;
EncodedAppEntrypointCalls.create = async function (calls, txNonce) {
  const encoded = await create.call(this, calls, txNonce);
  pending = { calls, txNonce: encoded.tx_nonce };
  return encoded;
};

function loadState() { return existsSync(STATE) ? JSON.parse(readFileSync(STATE, 'utf8')) : null; }
// The account's secret key lives here (testnet only): readable by you alone.
function saveState(s) { mkdirSync(HOME, { recursive: true, mode: 0o700 }); writeFileSync(STATE, JSON.stringify(s, null, 1), { mode: 0o600 }); chmodSync(STATE, 0o600); }

function spki(hex) {
  // DER SubjectPublicKeyInfo prefix for a P-256 uncompressed point.
  const prefix = Buffer.from('3059301306072a8648ce3d020106082a8648ce3d030107034200', 'hex');
  return createPublicKey({ key: Buffer.concat([prefix, Buffer.from([0x04]), Buffer.from(hex, 'hex')]), format: 'der', type: 'spki' });
}

function clipboard() { try { return execFileSync('pbpaste', { encoding: 'utf8' }); } catch { return ''; } }
function simClipboard() { try { return execFileSync('xcrun', ['simctl', 'pbpaste', sim], { encoding: 'utf8' }); } catch { return ''; } }

async function askPhone(request, publicKeyHex) {
  const json = Buffer.from(JSON.stringify(request)).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  const link = `casberi://aztec/sign#${json}`;
  // The last request, kept beside the state: what the phone was shown.
  mkdirSync(HOME, { recursive: true, mode: 0o700 });
  writeFileSync(join(HOME, 'last-request.json'), JSON.stringify(request, null, 1));
  const before = sim ? simClipboard() : clipboard();
  if (sim) {
    // A relaunch through the app's `-deeplink` hook (DEBUG builds): `simctl
    // openurl` stops at iOS's "Open in Casberi?" prompt.
    execFileSync('xcrun', ['simctl', 'launch', '--terminate-running-process', sim, 'com.casberi.app',
      '-onboarded', 'YES', '-demo.corpusAllowed', 'NO', '-aztecAutoSign', 'YES', '-deeplink', link]);
    say('sent to the simulator; waiting for its signature…');
  } else {
    execFileSync('pbcopy', { input: link });
    // The same link as a QR code, opened in Preview: the camera hands it to
    // Casberi, which shows the request before anything is signed.
    const png = join(HOME, 'request.png');
    mkdirSync(HOME, { recursive: true, mode: 0o700 });
    await QRCode.toFile(png, link, { errorCorrectionLevel: 'L', margin: 2, scale: 6 });
    try { execFileSync('open', [png]); } catch {}
    say(`scan the QR code (${png}) with the iPhone camera, or paste the link from your clipboard on the Aztec page in Casberi, then Sign.`);
  }
  const deadline = Date.now() + 5 * 60_000;
  while (Date.now() < deadline) {
    const now = (sim ? simClipboard() : clipboard()).trim();
    if (now !== before.trim() && now.startsWith('casberi-aztec-sig:')) {
      const sig = Buffer.from(now.slice('casberi-aztec-sig:'.length), 'hex');
      if (sig.length !== 64) throw new Error('the phone returned a malformed signature');
      const digest = Buffer.from(request.messageHash.slice(2).padStart(64, '0'), 'hex');
      // P-256 over sha256(hash): node's verify hashes `digest` with sha256.
      const ok = verify('sha256', digest, { key: spki(publicKeyHex), dsaEncoding: 'ieee-p1363' }, sig);
      if (!ok) throw new Error('the signature does not verify against the phone key — not used');
      say('signed on the phone and verified here');
      return sig;
    }
    await new Promise(r => setTimeout(r, 1000));
  }
  throw new Error('no signature came back within five minutes');
}

// Each call's full signature, so the phone can check the name it shows against
// the selector the signature covers (prd §1446). Found in the contracts this
// tool knows; a call to any other goes without one and the phone says the
// name is this computer's word.
const signatures = new Map();
async function signatureOf(selector) {
  if (!signatures.size) {
    for (const a of [TokenContract.artifact, SponsoredFPCContract.artifact]) {
      for (const f of [...a.functions, ...(a.nonDispatchPublicFunctions ?? [])]) {
        const sig = decodeFunctionSignature(f.name, f.parameters);
        signatures.set((await FunctionSelector.fromSignature(sig)).toString(), sig);
      }
    }
  }
  return signatures.get(selector.toString());
}

class PhoneAccountContract extends EcdsaRSSHAccountContract {
  constructor(publicKeyHex, address) { super(Buffer.from(publicKeyHex, 'hex')); this.hex = publicKeyHex; this.address = address; }
  getAuthWitnessProvider() {
    const hex = this.hex, self = this;
    return {
      async createAuthWit(messageHash) {
        if (!pending) throw new Error('an authorisation with no request behind it — the phone signs nothing blind');
        const info = await self.wallet.getChainInfo();
        const request = {
          account: self.address.toString(), chainId: info.chainId.toString(), version: info.version.toString(),
          txNonce: pending.txNonce.toString(), messageHash: messageHash.toString(),
          calls: await Promise.all(pending.calls.map(async c => ({ name: c.name, signature: await signatureOf(c.selector),
            to: c.to.toString(), selector: c.selector.toField().toString(),
            type: String(c.type), hideMsgSender: !!c.hideMsgSender, isStatic: !!c.isStatic, args: c.args.map(a => a.toString()) }))),
        };
        pending = null;
        const sig = await askPhone(request, hex);
        return new AuthWitness(messageHash, [...sig]);
      },
    };
  }
}

async function open(state) {
  const wallet = await NodeEmbeddedWallet.create(NODE_URL, { nodeClientOptions: NODE_OPTS, pxe: { proverEnabled: true, dataDirectory: join(HOME, 'pxe') } });
  const contract = new PhoneAccountContract(state.publicKey);
  const manager = await AccountManager.create(wallet, Fr.fromString(state.secret), contract, { salt: Fr.fromString(state.salt) });
  const address = manager.getInstance().address;
  contract.address = address; contract.wallet = wallet;
  if (!(await wallet.getContractMetadata(address)).instance) {
    await wallet.registerContract(manager.getInstance(), await contract.getContractArtifact(), manager.getSecretKey());
  }
  await wallet.walletDB.storeAccount(address, { type: 'ecdsasecp256r1', secretKey: manager.getSecretKey(),
    salt: Fr.fromString(state.salt), alias: 'phone', signingKey: Buffer.from(state.publicKey, 'hex') });
  const account = await manager.getAccount();
  const original = wallet.getAccountFromAddress.bind(wallet);
  wallet.getAccountFromAddress = async a => (a.equals(address) ? account : original(a));
  const fpc = await getContractInstanceFromInstantiationParams(SponsoredFPCContract.artifact, { salt: new Fr(0) });
  await wallet.registerContract(fpc, SponsoredFPCContract.artifact);
  return { wallet, manager, address, fee: { paymentMethod: new SponsoredFeePaymentMethod(fpc.address) } };
}

const [command, value] = args.filter((a, i) => !(a === '--sim' || args[i - 1] === '--sim'));
try {
  if (command === 'account') {
    if (!value || !/^[0-9a-fA-F]{128}$/.test(value)) throw new Error('usage: node signer.mjs account <the 128-hex public key from the Aztec page>');
    const state = loadState()?.publicKey === value.toLowerCase() ? loadState()
      : { publicKey: value.toLowerCase(), secret: Fr.random().toString(), salt: Fr.random().toString() };
    saveState(state);
    const { wallet, manager, address, fee } = await open(state);
    say('account', address.toString());
    const meta = await wallet.getContractMetadata(address);
    if (String(meta.initializationStatus) !== 'INITIALIZED') {
      say('deploying it (fees sponsored by the testnet)…');
      const { receipt } = await (await manager.getDeployMethod()).send({ from: NO_FROM, fee });
      say('deployed, block', receipt.blockNumber, 'tx', receipt.txHash.toString());
    } else say('already deployed');
    state.address = address.toString(); saveState(state);
    await wallet.stop();
  } else if (command === 'demo' || command === 'once') {
    const state = loadState(); if (!state?.address) throw new Error('run `account` first');
    const { wallet, address, fee } = await open(state);
    say('tx 1: deploy a token from the account');
    const { contract: token, receipt: r1 } = await TokenContract.deploy(wallet, address, 'Casberi', 'CSB', 18).send({ from: address, fee });
    say('token', token.address.toString(), 'block', r1.blockNumber, 'tx', r1.txHash.toString());
    state.token = token.address.toString(); saveState(state);
    if (command === 'once') { await wallet.stop(); process.exit(0); }
    say('tx 2: mint 100 publicly');
    const { receipt: r2 } = await token.methods.mint_to_public(address, 100n).send({ from: address, fee });
    say('block', r2.blockNumber);
    say('tx 3: move 25 into the private balance');
    const { receipt: r3 } = await token.methods.transfer_to_private(address, 25n).send({ from: address, fee });
    say('block', r3.blockNumber);
    const { result: priv } = await token.methods.balance_of_private(address).simulate({ from: address });
    const { result: pub } = await token.methods.balance_of_public(address).simulate({ from: address });
    say('balances — private', String(priv), 'public', String(pub));
    state.token = token.address.toString(); saveState(state);
    await wallet.stop();
  } else if (command === 'status') {
    const state = loadState(); if (!state) throw new Error('no account yet');
    say('phone key', state.publicKey.slice(0, 16) + '…', 'account', state.address ?? '(not deployed)', 'token', state.token ?? '-');
  } else {
    console.log(readFileSync(new URL(import.meta.url)).toString().split('\n').filter(l => l.startsWith('//')).slice(0, 24).join('\n'));
  }
  process.exit(0);
} catch (e) {
  console.error('✗', e.message ?? e);
  process.exit(1);
}
