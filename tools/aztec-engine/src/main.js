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
import { BrowserEmbeddedWallet } from '@aztec-labs/wallets/embedded';
import { Fr, GrumpkinScalar } from '@aztec-labs/aztec.js/fields';
import { WalletSchema } from '@aztec-labs/aztec.js/wallet';
import { Contract } from '@aztec-labs/aztec.js/contracts';
import { AztecAddress } from '@aztec-labs/aztec.js/addresses';
import { getCanonicalFeeJuice } from '@aztec-labs/protocol-contracts/fee-juice/lazy';
import { computeSecretHash } from '@aztec-labs/aztec.js/crypto';
import { FeeJuicePaymentMethodWithClaim } from '@aztec-labs/aztec.js/fee';
import { isL1ToL2MessageReady } from '@aztec-labs/aztec.js/messaging';
import { jsonStringify } from '@aztec-labs/foundation/json-rpc';
import { getSchemaParameters, parseWithOptionals, schemaHasMethod } from '@aztec-labs/foundation/schemas';

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

// A deposit's claim secret: the root, a label and the deposit's nonce.
async function depositSecret(nonce) {
  if (!rootBytes) await getWallet();
  const input = new Uint8Array([...rootBytes, ...new TextEncoder().encode(`casberi/aztec/v1/feejuice/${nonce}`)]);
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
        const decimalsRaw = await view(['decimals', 'public_get_decimals', 'private_get_decimals']);
        const symbolRaw = await view(['symbol', 'public_get_symbol', 'private_get_symbol']);
        out.push({
          kind: 'token', address: address.toString(), name: artifact.name,
          symbol: fieldText(symbolRaw),
          decimals: decimalsRaw == null ? null : Number(BigInt((decimalsRaw.value ?? decimalsRaw).toString())),
          private: await read(token, 'balance_of_private'),
          public: names.has('balance_of_public') ? await read(token, 'balance_of_public') : null,
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
    return { tx: receipt.txHash.toString(), status: String(receipt.status) };
  },
  async chain() {
    const c = await (await getWallet()).getChainInfo();
    return { chainId: c.chainId.toBigInt().toString(), version: c.version.toBigInt().toString() };
  },
};

// --- apps' calls --------------------------------------------------------------------
let asks = 0;
const waiting = new Map();
const connecting = new Set();
// Sessions whose emoji the person has not confirmed: their calls, waiting.
const held = new Map();

// What the sheet says about a transaction, read from the request itself: each
// call's function and contract, private or public, and who pays the fee. (A
// private call can start public steps of its own; they are not read yet, so
// the sheet does not claim to know them.)
const tail = a => '...' + String(a ?? '').slice(-4);
function describe(args) {
  const calls = (args?.[0]?.calls ?? []).map(c => ({ name: c.name, to: tail(c.to), type: c.type }));
  return { calls, fee: 'Paid from your Fee Juice' };
}

function askPerson(method, args, origin) {
  const id = ++asks;
  native('engineApprove', { id, method, origin, ...describe(args) });
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
  if (!READS.has(method)) {
    const yes = await askPerson(method, args, origin);
    log('approval', { method, yes });
    if (!yes) throw new Error(`The person declined ${method}`);
  }
  const parsed = schemaHasMethod(WalletSchema, method)
    ? await parseWithOptionals(args ?? [], getSchemaParameters(WalletSchema[method]))
    : args ?? [];
  const result = await wallet[method](...parsed);
  return result === undefined ? undefined : JSON.parse(jsonStringify(result));
}

let contentListener = null;
const background = new BackgroundConnectionHandler(
  { ...WALLET, walletIcon: 'https://casberi.app/favicon.ico' },
  {
    sendToTab: (tabId, message) => native('engineToTab', { tabId, message }),
    addContentListener: handler => {
      contentListener = handler;
    },
  },
  {
    onPendingDiscovery: discovery => {
      connecting.add(discovery.requestId);
      native('engineConnect', { requestId: discovery.requestId, origin: discovery.origin, appId: discovery.appId });
    },
    onSessionEstablished: session => {
      const id = session.sessionId ?? session.requestId;
      held.set(id, []);
      native('engineEmoji', { sessionId: id, emoji: hashToEmoji(session.verificationHash), origin: session.origin });
    },
    onSessionTerminated: requestId => log('terminated', { requestId }),
    onWalletMessage: async (session, message) => {
      // The emoji check holds every call of the site's until the person says
      // the two grids match (prd §1700 item 6, C1; Nulo's verification hold).
      const id = session.sessionId ?? session.requestId;
      if (held.has(id)) {
        held.get(id).push(() => answerApp(session, message));
        return;
      }
      await answerApp(session, message);
    },
  },
);
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
  answerConnect(requestId, yes) {
    if (!connecting.delete(requestId)) return;
    if (yes) background.approveDiscovery(requestId);
    else background.rejectDiscovery(requestId);
  },
  // The person compared the two grids: they match (calls run) or not (the
  // session ends and its waiting calls with it).
  confirmEmoji(sessionId, match) {
    const waiting = held.get(sessionId);
    if (!waiting) return;
    held.delete(sessionId);
    log('emojiAnswer', { match });
    if (match) for (const run of waiting) run();
    else background.terminateSession(sessionId);
  },
  answerApproval(id, yes) {
    waiting.get(id)?.(yes);
    waiting.delete(id);
  },
};

log('engineReady', { isolated: self.crossOriginIsolated, secure: self.isSecureContext });
native('engineReady', {});
