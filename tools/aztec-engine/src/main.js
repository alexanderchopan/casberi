// CASBERI'S AZTEC ENGINE (prd §1700): your Aztec account's wallet, in a hidden
// web view no app page can load. Aztec's own `EmbeddedWallet` (a PXE on this
// device) on Aztec mainnet; every proof on Aztec's native iOS prover
// (native-backend.js); every request through the app (net-shim.js). Built from
// the spike that proved it (tools/aztec-dapp-spike).
//
// Two callers:
//   - Casberi itself (`casberiEngine.call`): the account, its balances.
//   - Aztec apps in Casberi's browser, through Aztec's wallet-sdk background
//     handler: the shell relays their messages and names their origin; every
//     connect and every transaction asks the person natively first.
import './net-shim.js';
import './console-bridge.js';
import { BackgroundConnectionHandler } from '@aztec-labs/wallet-sdk/extension/handlers';
import { hashToEmoji } from '@aztec-labs/wallet-sdk/crypto';
import { connectGate } from './connect-gate.js';
import { BrowserEmbeddedWallet } from '@aztec-labs/wallets/embedded';
import { Fr, GrumpkinScalar } from '@aztec-labs/aztec.js/fields';
import { WalletSchema } from '@aztec-labs/aztec.js/wallet';
import { Contract } from '@aztec-labs/aztec.js/contracts';
import { AztecAddress } from '@aztec-labs/aztec.js/addresses';
import { getCanonicalFeeJuice } from '@aztec-labs/protocol-contracts/fee-juice/lazy';
import { computeSecretHash } from '@aztec-labs/aztec.js/crypto';
import { FeeJuicePaymentMethodWithClaim } from '@aztec-labs/aztec.js/fee';
import { isL1ToL2MessageReady } from '@aztec-labs/aztec.js/messaging';
import { loadContractArtifact } from '@aztec-labs/aztec.js/abi';
import shieldTokenJSON from '../shield/token.json';
import shieldBridgeJSON from '../shield/bridge.json';
import shieldProxyJSON from '../shield/proxy.json';
import { EthAddress } from '@aztec-labs/aztec.js/addresses';
import { TxHash } from '@aztec-labs/aztec.js/tx';
import { computeL2ToL1MessageHash } from '@aztec-labs/stdlib/hash';
import { sha256ToField } from '@aztec-labs/foundation/crypto/sha256';
import { jsonStringify } from '@aztec-labs/foundation/json-rpc';
import { getSchemaParameters, parseWithOptionals, schemaHasMethod } from '@aztec-labs/foundation/schemas';
import { WALLET_ICON } from './icon.js';
import { receiptOut, sentOut, feePayer, feeUnits, transferCall, addressValid, describeCalls } from './aztec-tx.js';

const params = new URLSearchParams(location.search);
// Aztec mainnet through dRPC's public node unless the person set their own.
const NODE_URL = params.get('node') ?? 'https://aztec-mainnet.drpc.org';
const WALLET = { walletId: 'casberi', walletName: 'Casberi', walletVersion: '1.0' };
// What an app may call without asking: reads. Anything else is a transaction.
const READS = new Set([
  'getChainInfo', 'getAccounts', 'getAddressBook', 'getContractMetadata', 'getContractClassMetadata',
  'registerSender', 'registerContract', 'getPrivateEvents', 'executeUtility', 'simulateTx', 'requestCapabilities',
]);

const native = (name, value) => window.webkit?.messageHandlers?.[name]?.postMessage(JSON.stringify(value));
const t0 = performance.now();
const ms = () => Math.round(performance.now() - t0);
function log(event, detail) {
  native('engineLog', { event, detail, ms: ms() });
}

// --- the account ---------------------------------------------------------------
// Its two keys come from ONE root the app keeps in iCloud Keychain (prd §1562's
// model): SHA-512 of the root and a label, reduced into each field. The root
// reaches this page only; nothing here stores it.
let rootResolve;
let rootBytes = null;
const rootPromise = new Promise(r => (rootResolve = r));
async function accountKeys() {
  native('engineNeedsRoot', {});
  const hex = await rootPromise;
  const root = Uint8Array.from(hex.match(/../g).map(h => parseInt(h, 16)));
  rootBytes = root;
  const derive = async label => {
    const input = new Uint8Array([...root, ...new TextEncoder().encode(label)]);
    return Buffer.from(await crypto.subtle.digest('SHA-512', input));
  };
  return {
    secret: Fr.fromBufferReduce(await derive('casberi/aztec/v1/secret')),
    signingKey: GrumpkinScalar.fromBufferReduce(await derive('casberi/aztec/v1/signing')),
  };
}

let walletPromise = null;
let accountAddress = null;
function getWallet() {
  walletPromise ??= (async () => {
    log('walletStarting', { node: new URL(NODE_URL).host });
    const wallet = await BrowserEmbeddedWallet.create(NODE_URL, {
      pxe: { proverEnabled: true },
      nodeClientOptions: { maxBatchSize: 3 }, // dRPC's free plan refuses larger batches
    });
    const chain = await wallet.getChainInfo();
    log('pxeReady', { chainId: chain.chainId.toBigInt().toString(), version: chain.version.toBigInt().toString() });
    const { secret, signingKey } = await accountKeys();
    const manager = await wallet.createSchnorrInitializerlessAccount(secret, Fr.ZERO, signingKey, 'Casberi');
    accountAddress = manager.address.toString();
    log('accountReady', { address: accountAddress });
    return wallet;
  })();
  walletPromise.catch(() => (walletPromise = null)); // a failed start can be tried again
  return walletPromise;
}

// A compressed string a token returns (a field, or `{ value }`), as text.
function fieldText(raw) {
  if (raw == null) return null;
  try {
    let n = BigInt((raw.value ?? raw).toString());
    const bytes = [];
    while (n > 0n) { bytes.unshift(Number(n & 0xffn)); n >>= 8n; }
    const text = new TextDecoder().decode(new Uint8Array(bytes.filter(b => b !== 0))).trim();
    return /^[\x20-\x7e]{1,16}$/.test(text) ? text : null;
  } catch {
    return null;
  }
}

// SHIELD (prd §1700d): the bridge Move uses. Its interfaces come from its own
// web app (fetch-shield.mjs, pinned to mainnet's classes); here each contract
// is registered only when the node runs the pinned class at that address.
const SHIELD = {
  tokenClass: '0x2ff0939914ff64bd3f7979926dbe8cf3332bc2fee55928bf3cc9ca802568ea9f',
  bridgeClass: '0x28fe903cd306bbc46fd908cc03989601c32368c4694b508499f18516062fefd3',
  // The minter proxy the bridge burns through on the way out (exit_to_l1_private).
  proxyClass: '0x18fa95a66c31125278bf4d07166e30fff3ad7e12b232710bf7e376f36f2d4b8a',
  assets: [
    { symbol: 'USDC', decimals: 6, token: '0x30112e52178143b74cf6037d047bbba924f4b0db8aab587a340aacfc6ecb4f38',
      bridge: '0x023aafff7595c5698625486a010e385144a4a960d268df8ccb205f9134afd775',
      proxy: '0x05fcce110ae9d190e0808596af79ffb21031a3eaf854cf5c74bac3437e86a5fd', portal: '0x6c34d66633ffc36be2dfddc7b0c652fbb305e74c' },
    { symbol: 'WETH', decimals: 18, token: '0x2a36cedc4f7fa6bd9fbb77ab799737f30d12cd86ffa9d9d63737d51a6e7247fe',
      bridge: '0x267a10e5463760e88f487a719bd38f09c46ec87260c51b0affc88fd9ff1d9ef4',
      proxy: '0x1a90eeb03bbfff70d97e1290376c550fa911c4b0ecbb0a8483516f66f7d05bf3', portal: '0x477a911f76c44a5d3e5e692c59945263f61426c4' },
  ],
};
const shieldToken = loadContractArtifact(shieldTokenJSON);
const shieldBridge = loadContractArtifact(shieldBridgeJSON);
const shieldProxy = loadContractArtifact(shieldProxyJSON);
let shieldRegistered = null;
async function registerShield(wallet) {
  shieldRegistered ??= (async () => {
    for (const asset of SHIELD.assets) {
      for (const [address, artifact, pin] of [[asset.token, shieldToken, SHIELD.tokenClass], [asset.bridge, shieldBridge, SHIELD.bridgeClass], [asset.proxy, shieldProxy, SHIELD.proxyClass]]) {
        const at = AztecAddress.fromStringUnsafe(address);
        if ((await wallet.getContractMetadata(at)).instance) continue;
        const instance = await wallet.aztecNode.getContract(at);
        const cls = (instance?.currentContractClassId ?? instance?.originalContractClassId)?.toString();
        if (cls !== pin) { log('shieldRefused', { address, cls }); continue; } // a different contract: never called
        await wallet.registerContract(instance, artifact);
      }
    }
  })();
  shieldRegistered.catch(() => (shieldRegistered = null));
  return shieldRegistered;
}

// A deposit's claim secret: the root, a label and the deposit's nonce.
async function depositSecret(nonce) {
  return derivedSecret(`feejuice/${nonce}`);
}
async function derivedSecret(label) {
  if (!rootBytes) await getWallet();
  const input = new Uint8Array([...rootBytes, ...new TextEncoder().encode(`casberi/aztec/v1/${label}`)]);
  return Fr.fromBufferReduce(Buffer.from(await crypto.subtle.digest('SHA-512', input)));
}

// --- Casberi's own calls -----------------------------------------------------------
const own = {
  async account() {
    await getWallet();
    return { address: accountAddress };
  },
  // What the account holds (prd §1700, step 2): Fee Juice, the gas every
  // transaction pays, read from Aztec's own protocol contract; and every token
  // an app taught the wallet (an app registers its contracts, interface and
  // all, when it connects — Shield's USDC and WETH, measured 2026-11-04), read
  // privately and publicly. Nothing is hard-coded but Fee Juice.
  async holdings() {
    const wallet = await getWallet();
    await registerShield(wallet).catch(e => log('shieldSkipped', { error: String(e?.message ?? e).slice(0, 160) }));
    const me = AztecAddress.fromStringUnsafe(accountAddress);
    const out = [];
    const read = async (contract, fn) => {
      try {
        const { result } = await contract.methods[fn](me).simulate({ from: me });
        return BigInt(result.toString()).toString();
      } catch (e) {
        log('holdingSkipped', { fn, error: String(e?.message ?? e).slice(0, 160) });
        return null;
      }
    };
    const feeJuice = await getCanonicalFeeJuice();
    if (!(await wallet.getContractMetadata(feeJuice.address)).instance) {
      await wallet.registerContract(feeJuice.instance, feeJuice.artifact);
    }
    const fj = await Contract.at(feeJuice.address, feeJuice.artifact, wallet);
    out.push({ kind: 'feeJuice', address: feeJuice.address.toString(), symbol: 'Fee Juice', decimals: 18,
               public: await read(fj, 'balance_of_public'), private: null });
    for (const address of await wallet.pxe.getContracts()) {
      if (address.equals(feeJuice.address) || address.equals(me)) continue;
      try {
        const instance = await wallet.pxe.getContractInstance(address);
        const classId = instance?.currentContractClassId ?? instance?.originalContractClassId;
        const artifact = classId && (await wallet.pxe.getContractArtifact(classId));
        const names = new Set((artifact?.functions ?? []).map(f => f.name));
        if (!names.has('balance_of_private')) continue;
        const token = await Contract.at(address, artifact, wallet);
        // Its decimals and symbol from its own functions, whichever spelling it
        // uses; unknown stays null (the app then shows no amount, never a guess).
        const view = async candidates => {
          for (const fn of candidates.filter(n => names.has(n))) {
            try {
              const { result } = await token.methods[fn]().simulate({ from: me });
              return result;
            } catch {}
          }
          return null;
        };
        const known = SHIELD.assets.find(a => AztecAddress.fromStringUnsafe(a.token).equals(address));
        const decimalsRaw = known ? known.decimals : await view(['decimals', 'public_get_decimals', 'private_get_decimals']);
        const symbolRaw = known ? null : await view(['symbol', 'public_get_symbol', 'private_get_symbol']);
        out.push({
          kind: 'token', address: address.toString(), name: artifact.name,
          symbol: known ? known.symbol : fieldText(symbolRaw),
          decimals: decimalsRaw == null ? null : Number(BigInt((decimalsRaw.value ?? decimalsRaw).toString())),
          private: await read(token, 'balance_of_private'),
          public: names.has('balance_of_public') ? await read(token, 'balance_of_public') : null,
          // Whether Casberi can send it privately (prd §1711 item 3).
          sendable: transferCall(artifact) != null,
        });
      } catch (e) {
        log('holdingSkipped', { address: address.toString(), error: String(e?.message ?? e).slice(0, 160) });
      }
    }
    return out;
  },
  // GAS (prd §1700e item 2): your Safe deposits AZTEC into Aztec's own Fee
  // Juice portal for this account; the claim's secret is derived from the
  // root and the deposit's nonce, so a new phone can still claim it.
  async feeJuicePlan(nonce) {
    await getWallet();
    const secret = await depositSecret(nonce);
    return { to: accountAddress, secretHash: (await computeSecretHash(secret)).toString() };
  },
  // Whether Aztec has the deposit's message yet (minutes after it lands).
  async feeJuiceReady(messageHash) {
    const wallet = await getWallet();
    return { ready: await isL1ToL2MessageReady(wallet.aztecNode, Fr.fromString(messageHash)) };
  },
  // Claims it: a transaction whose own fee is paid from what it claims.
  async feeJuiceClaim(nonce, amount, leafIndex) {
    const wallet = await getWallet();
    const me = AztecAddress.fromStringUnsafe(accountAddress);
    const feeJuice = await getCanonicalFeeJuice();
    if (!(await wallet.getContractMetadata(feeJuice.address)).instance) {
      await wallet.registerContract(feeJuice.instance, feeJuice.artifact);
    }
    const paymentMethod = new FeeJuicePaymentMethodWithClaim(me, {
      claimAmount: BigInt(amount), claimSecret: await depositSecret(nonce), messageLeafIndex: BigInt(leafIndex),
    });
    const fj = await Contract.at(feeJuice.address, feeJuice.artifact, wallet);
    const { receipt } = await fj.methods.check_balance(0n).send({ from: me, fee: { paymentMethod }, wait: { waitForStatus: 'proposed', timeout: 1800 } });
    log('feeJuiceClaimed', { tx: receipt.txHash.toString(), status: receipt.status });
    return receiptOut(receipt);
  },
  // SHIELD INTO AZTEC (prd §1700e): the deposit's claim secret, derived from
  // the root and a nonce like gas's, and the claim on Aztec once the bridge's
  // message is there; its fee is the account's own Fee Juice.
  async shieldPlan(nonce) {
    await getWallet();
    const secret = await derivedSecret(`shield/${nonce}`);
    return { to: accountAddress, secretHash: (await computeSecretHash(secret)).toString() };
  },
  async messageReady(messageHash) {
    const wallet = await getWallet();
    return { ready: await isL1ToL2MessageReady(wallet.aztecNode, Fr.fromString(messageHash)) };
  },
  async shieldClaim(symbol, amount, nonce, leafIndex) {
    const wallet = await getWallet();
    await registerShield(wallet);
    const asset = SHIELD.assets.find(a => a.symbol === symbol);
    if (!asset) throw new Error(`no ${symbol} on Aztec`);
    const me = AztecAddress.fromStringUnsafe(accountAddress);
    const bridge = await Contract.at(AztecAddress.fromStringUnsafe(asset.bridge), shieldBridge, wallet);
    const { receipt } = await bridge.methods
      .claim_private(me, BigInt(amount), await derivedSecret(`shield/${nonce}`), BigInt(leafIndex))
      .send({ from: me, wait: { waitForStatus: 'proposed', timeout: 1800 } });
    log('shieldClaimed', { tx: receipt.txHash.toString(), status: receipt.status });
    return receiptOut(receipt);
  },
  // A private send inside Aztec (prd §1700e): Shield's token, account to
  // account, no one's permission; the app has asked Face ID before calling.
  async sendPrivately(symbol, to, units) {
    const asset = SHIELD.assets.find(a => a.symbol === symbol);
    if (!asset) throw new Error(`no ${symbol} on Aztec`);
    return own.sendToken(asset.token, to, units);
  },
  // ANY TOKEN THE ACCOUNT HOLDS (prd §1711 item 3): sent privately by its
  // contract, through the transfer its own interface offers (aztec-tx.js),
  // to an address anyone can receive at. A token whose interface offers no
  // private transfer is refused, never guessed at.
  async sendToken(tokenAddress, to, units) {
    const wallet = await getWallet();
    await registerShield(wallet).catch(() => {});
    if (!(await addressValid(AztecAddress, to))) throw new Error('No one can receive at this Aztec address');
    const address = AztecAddress.fromStringUnsafe(tokenAddress);
    const instance = await wallet.pxe.getContractInstance(address);
    const classId = instance?.currentContractClassId ?? instance?.originalContractClassId;
    const artifact = classId && (await wallet.pxe.getContractArtifact(classId));
    const transfer = artifact && transferCall(artifact);
    if (!transfer) throw new Error('This token cannot be sent from Casberi');
    const me = AztecAddress.fromStringUnsafe(accountAddress);
    const token = await Contract.at(address, artifact, wallet);
    const { receipt } = await token.methods[transfer.name](...transfer.args(me, AztecAddress.fromStringUnsafe(to), BigInt(units)))
      .send({ from: me, wait: { waitForStatus: 'proposed', timeout: 1800 } });
    log('sentPrivately', { tx: receipt.txHash.toString(), status: receipt.status, via: transfer.name });
    return receiptOut(receipt);
  },
  // Whether an Aztec address can receive at all (prd §1711 item 5).
  async addressValid(text) {
    return { valid: await addressValid(AztecAddress, text) };
  },
  // SHIELD OUT OF AZTEC (prd §1700b, §1700d): read from Shield's own client.
  // The bridge checks Shield's signed Passport limit (an Aztec signature over
  // this account), sends a message to the portal on Ethereum and burns the
  // tokens through its minter proxy, which this account authorises for
  // exactly this burn. Anyone may finish it on Ethereum (caller_on_l1 zero);
  // the money goes to `recipient` only.
  async shieldExit(symbol, units, recipient, passportJSON) {
    const wallet = await getWallet();
    await registerShield(wallet);
    const asset = SHIELD.assets.find(a => a.symbol === symbol);
    if (!asset) throw new Error(`no ${symbol} on Aztec`);
    const p = JSON.parse(passportJSON);
    if (!Array.isArray(p.signature) || p.signature.length !== 64) throw new Error('Shield gave no Aztec signature');
    const me = AztecAddress.fromStringUnsafe(accountAddress);
    const amount = BigInt(units);
    const token = await Contract.at(AztecAddress.fromStringUnsafe(asset.token), shieldToken, wallet);
    const bridge = await Contract.at(AztecAddress.fromStringUnsafe(asset.bridge), shieldBridge, wallet);
    const nonce = Fr.random();
    const burn = await token.methods.burn_private(me, amount, nonce).getFunctionCall();
    const witness = await wallet.createAuthWit(me, { caller: AztecAddress.fromStringUnsafe(asset.proxy), call: burn });
    const to = EthAddress.fromString(recipient);
    const exit = bridge.methods.exit_to_l1_private(
      to, amount, EthAddress.ZERO, nonce,
      { nonce: 0n, signature: Array(64).fill(0) },
      { max_amount: BigInt(p.maxAmount), nonce: BigInt(p.nonce), deadline: BigInt(p.deadline), signature: p.signature },
    ).with({ authWitnesses: [witness] });
    const { receipt } = await exit.send({ from: me, wait: { waitForStatus: 'proposed', timeout: 1800 } });
    const info = await wallet.aztecNode.getNodeInfo();
    // The message the portal will consume: sha256 of withdraw(address,uint256,address)'s
    // selector, the recipient, the amount and caller_on_l1 (zero).
    const content = sha256ToField([Buffer.from('69328dec', 'hex'), to.toBuffer32(), new Fr(amount).toBuffer(), EthAddress.ZERO.toBuffer32()]);
    const message = computeL2ToL1MessageHash({
      l2Sender: AztecAddress.fromStringUnsafe(asset.bridge), l1Recipient: EthAddress.fromString(asset.portal), content,
      rollupVersion: new Fr(BigInt(info.rollupVersion)), chainId: new Fr(BigInt(info.l1ChainId)),
    });
    log('shieldExited', { tx: receipt.txHash.toString(), status: receipt.status });
    return { tx: receipt.txHash.toString(), fee: receiptOut(receipt).fee, block: String(receipt.blockNumber ?? ''), message: message.toString(),
             outbox: info.l1ContractAddresses?.outboxAddress?.toString() ?? null };
  },
  // Once the epoch holding the exit is proven on Ethereum: where its message
  // sits in the outbox, for the portal's withdraw. Null until then.
  async exitWitness(txHash, message) {
    const wallet = await getWallet();
    const w = await wallet.aztecNode.getL2ToL1MembershipWitness(TxHash.fromString(txHash), Fr.fromString(message)).catch(() => undefined);
    if (!w) return null;
    return { epoch: String(w.epochNumber), checkpoints: String(w.numCheckpointsInEpoch), leaf: String(w.leafIndex),
             path: w.siblingPath.toBufferArray().map(b => '0x' + b.toString('hex')) };
  },
  // REVEAL KEY (prd §1700f item 6): what another Aztec wallet needs to open
  // this same account — its secret key, its Schnorr signing key, the salt and
  // the account's kind. Casberi's own call only (never an app's); the app has
  // asked Face ID and the co-signer before calling.
  async exportKeys() {
    await getWallet();
    const { secret, signingKey } = await accountKeys();
    return { address: accountAddress, secretKey: secret.toString(), signingKey: signingKey.toString(),
             salt: Fr.ZERO.toString(), kind: 'schnorr-initializerless' };
  },
  async chain() {
    const c = await (await getWallet()).getChainInfo();
    return { chainId: c.chainId.toBigInt().toString(), version: c.version.toBigInt().toString() };
  },
};

// --- apps' calls --------------------------------------------------------------------
let asks = 0;
const waiting = new Map();

// What the sheet says about a transaction, read from the request itself: each
// call's function and contract, private or public; who pays the fee; and,
// for a send, what it costs at today's prices from a simulation run first
// (prd §1711 item 2). (A private call can start public steps of its own;
// they are not read yet, so the sheet does not claim to know them.)
async function feeFor(wallet, payload, opts) {
  try {
    const simulated = wallet.simulateTx(payload, { from: opts?.from, additionalScopes: opts?.additionalScopes });
    const timeout = new Promise((_, no) => setTimeout(() => no(new Error('the simulation took too long')), 20000));
    const result = await Promise.race([simulated, timeout]);
    return feeUnits(result.gasUsed, await wallet.aztecNode.getCurrentMinFees());
  } catch (e) {
    log('feeUnknown', { error: String(e?.message ?? e).slice(0, 160) });
    return null;
  }
}

async function describe(wallet, method, parsed) {
  if (method !== 'sendTx') return { calls: [], feeBy: 'you', feeUnits: null };
  const [payload, opts] = parsed;
  const by = feePayer(payload, opts?.from);
  return { calls: describeCalls(payload), feeBy: by, feeUnits: by === 'app' ? null : await feeFor(wallet, payload, opts) };
}

function askPerson(method, origin, described) {
  const id = ++asks;
  native('engineApprove', { id, method, origin, ...described });
  return new Promise(resolve => waiting.set(id, resolve));
}

async function callForApp(method, args, origin) {
  const wallet = await getWallet();
  if (method === 'requestCapabilities') {
    const manifest = args?.[0] ?? {};
    const accounts = (await wallet.getAccounts()).map(a => ({ alias: a.alias, item: a.item.toString() }));
    return {
      version: '1.0',
      granted: (manifest.capabilities ?? []).map(c => (c.type === 'accounts' ? { ...c, accounts } : c)),
      wallet: { name: WALLET.walletName, version: WALLET.walletVersion },
    };
  }
  if (typeof wallet[method] !== 'function') throw new Error(`Unknown wallet method: ${method}`);
  const parsed = schemaHasMethod(WalletSchema, method)
    ? await parseWithOptionals(args ?? [], getSchemaParameters(WalletSchema[method]))
    : args ?? [];
  let described = null;
  if (!READS.has(method)) {
    described = await describe(wallet, method, parsed);
    const yes = await askPerson(method, origin, described);
    log('approval', { method, yes });
    if (!yes) throw new Error(`The person declined ${method}`);
  }
  const result = await wallet[method](...parsed);
  // A send an app made lands in the Wallet's Activity (prd §1711 item 1).
  if (method === 'sendTx') {
    const out = sentOut(result);
    if (out.tx) native('engineSent', { origin, ...out, calls: described?.calls ?? [] });
  }
  return result === undefined ? undefined : JSON.parse(jsonStringify(result));
}

let contentListener = null;
// Discovery is answered at once; Connect and the emoji check are asked when
// the person picks Casberi in the app, and hold its calls (connect-gate.js).
let gate = null;
const background = new BackgroundConnectionHandler(
  { ...WALLET, walletIcon: WALLET_ICON },
  {
    sendToTab: (tabId, message) => native('engineToTab', { tabId, message }),
    addContentListener: handler => {
      contentListener = handler;
    },
  },
  {
    onPendingDiscovery: discovery => {
      log('discovered', { origin: discovery.origin, appId: discovery.appId });
      gate.discovered(discovery.requestId);
    },
    onSessionEstablished: session => {
      const id = session.sessionId ?? session.requestId;
      gate.established(id, session.origin, hashToEmoji(session.verificationHash));
    },
    onSessionTerminated: requestId => {
      gate.terminated(requestId);
      log('terminated', { requestId });
    },
    onWalletMessage: async (session, message) => {
      const id = session.sessionId ?? session.requestId;
      if (!gate.message(id, () => answerApp(session, message))) {
        await background.sendResponse(id, {
          messageId: message.messageId, error: { message: 'Not connected to Casberi' }, walletId: WALLET.walletId,
        });
      }
    },
  },
);
gate = connectGate({
  approveDiscovery: requestId => background.approveDiscovery(requestId),
  terminateSession: sessionId => background.terminateSession(sessionId),
  askConnect: (requestId, origin) => native('engineConnect', { requestId, origin }),
  askEmoji: (sessionId, origin, emoji) => native('engineEmoji', { sessionId, emoji, origin }),
  log,
});
background.initialize();

async function answerApp(session, message) {
      const { messageId, type, args } = message;
      const started = ms();
      let result;
      let error;
      try {
        result = await callForApp(type, args, session.origin);
      } catch (e) {
        error = { message: String(e?.message ?? e).slice(0, 400) };
      }
      log(error ? 'refused' : 'answered', { type, origin: session.origin, took: ms() - started });
      await background.sendResponse(session.sessionId ?? session.requestId, { messageId, result, error, walletId: WALLET.walletId });
}

// --- the shell's door ------------------------------------------------------------
window.casberiEngine = {
  setRoot(hex) {
    rootResolve(hex);
  },
  // Casberi's own call: the answer comes back as `engineReply`.
  call(id, method, argsJSON) {
    const fn = own[method];
    const run = fn ? fn(...JSON.parse(argsJSON ?? '[]')) : Promise.reject(new Error(`unknown call ${method}`));
    run.then(
      result => native('engineReply', { id, result }),
      e => native('engineReply', { id, error: String(e?.message ?? e).slice(0, 400) }),
    );
  },
  fromContent(json, tabId, url) {
    contentListener?.(JSON.parse(json), { tab: { id: tabId, url } });
  },
  // The person's answer to Connect (the session's id is the discovery's).
  answerConnect(requestId, yes) {
    gate.answerConnect(requestId, yes);
  },
  // The person compared the two grids: they match, or the session ends and
  // its waiting calls with it.
  confirmEmoji(sessionId, match) {
    gate.confirmEmoji(sessionId, match);
  },
  answerApproval(id, yes) {
    waiting.get(id)?.(yes);
    waiting.delete(id);
  },
};

log('engineReady', { isolated: self.crossOriginIsolated, secure: self.isSecureContext });
native('engineReady', {});
