// Casberi's Aztec wallet ENGINE, for a hidden web view no app page can reach:
// Aztec's own wallet-sdk background handler (key exchange, session keys) in
// front of Aztec's own EmbeddedWallet (a PXE on this device) on the V6 TESTNET.
// Spike only: never shipped, testnet only.
//
// The account is Aztec's stock Schnorr account. Its secret and signing key are
// made here once and kept in this view's storage; in Casberi they would come
// from the private-money root in iCloud Keychain (prd §1562).
import './console-bridge.js';
import { BackgroundConnectionHandler, ContentScriptConnectionHandler } from '@aztec-labs/wallet-sdk/extension/handlers';
import { hashToEmoji } from '@aztec-labs/wallet-sdk/crypto';
import { BrowserEmbeddedWallet } from '@aztec-labs/wallets/embedded';
import { Fr, GrumpkinScalar } from '@aztec-labs/aztec.js/fields';
import { WalletSchema } from '@aztec-labs/aztec.js/wallet';
import { jsonStringify } from '@aztec-labs/foundation/json-rpc';
import { getSchemaParameters, parseWithOptionals, schemaHasMethod } from '@aztec-labs/foundation/schemas';

const NODE_URL = new URLSearchParams(location.search).get('node') ?? 'https://aztec-testnet.drpc.org';
const WALLET = { walletId: 'casberi', walletName: 'Casberi', walletVersion: '0.0.3-spike' };
// Methods an app may call without the person saying yes each time: reads.
const READS = new Set([
  'getChainInfo', 'getAccounts', 'getAddressBook', 'getContractMetadata', 'getContractClassMetadata',
  'registerSender', 'registerContract', 'getPrivateEvents', 'executeUtility', 'simulateTx', 'requestCapabilities',
]);

const native = (name, value) => window.webkit?.messageHandlers?.[name]?.postMessage(JSON.stringify(value));
const t0 = performance.now();
const ms = () => Math.round(performance.now() - t0);
function log(event, detail) {
  native('engineLog', { event, detail, ms: ms() });
  console.log('[engine]', event, JSON.stringify(detail ?? null));
}

// --- the wallet ---------------------------------------------------------------
let walletPromise = null;
let accountAddress = null;
function getWallet() {
  walletPromise ??= (async () => {
    log('walletStarting', { node: NODE_URL });
    const wallet = await BrowserEmbeddedWallet.create(NODE_URL, {
      logger: undefined,
      pxe: { proverEnabled: true },
      nodeClientOptions: { maxBatchSize: 3 }, // dRPC's free plan refuses larger batches
    });
    log('pxeReady', { chain: summarise(await wallet.getChainInfo()) });
    const { secret, signingKey } = await accountKeys();
    const manager = await wallet.createSchnorrInitializerlessAccount(secret, Fr.ZERO, signingKey, 'Casberi');
    accountAddress = manager.address.toString();
    log('accountReady', { address: accountAddress });
    return wallet;
  })();
  return walletPromise;
}

// The account's two keys, derived from the one root the shell keeps in iCloud
// Keychain (SHA-512 of the root and a label, reduced into each field). Outside
// the app (desktop debugging) a random root is kept in this page's storage.
let rootResolve;
const rootPromise = new Promise(r => (rootResolve = r));
async function accountKeys() {
  let hex;
  if (window.webkit) {
    native('engineNeedsRoot', {});
    hex = await rootPromise;
  } else {
    hex = localStorage.getItem('casberi.aztec.root');
    if (!hex) {
      hex = [...crypto.getRandomValues(new Uint8Array(32))].map(b => b.toString(16).padStart(2, '0')).join('');
      localStorage.setItem('casberi.aztec.root', hex);
    }
  }
  const root = Uint8Array.from(hex.match(/../g).map(h => parseInt(h, 16)));
  const derive = async label => {
    const input = new Uint8Array([...root, ...new TextEncoder().encode(label)]);
    return Buffer.from(await crypto.subtle.digest('SHA-512', input));
  };
  return {
    secret: Fr.fromBufferReduce(await derive('casberi/aztec/v1/secret')),
    signingKey: GrumpkinScalar.fromBufferReduce(await derive('casberi/aztec/v1/signing')),
  };
}

async function callWallet(method, args, origin) {
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
    // Anything else needs the person's yes. The native shell raises the sheet (the
    // spike's shell approves on testnet and logs it); a no refuses the call.
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

// --- approval -------------------------------------------------------------------
let asks = 0;
const connecting = new Map();
const waiting = new Map();
// What the sheet says about a transaction, read from the request itself: each
// call's function and contract, whether it runs privately or in public, and who
// pays the fee. (A private call can start public steps of its own; the spike
// does not read those yet, so the sheet does not claim to.)
const SPONSOR_FUNCTION = 'sponsor_unconditionally';
const tail = a => '...' + String(a ?? '').slice(-4);
function describe(method, args) {
  const calls = (args?.[0]?.calls ?? []).map(c => ({ name: c.name, to: tail(c.to), type: c.type }));
  const sponsored = calls.some(c => c.name === SPONSOR_FUNCTION);
  const shown = calls.filter(c => c.name !== SPONSOR_FUNCTION);
  return {
    calls: shown,
    fee: sponsored ? 'The testnet sponsor pays the fee' : 'Paid from your Fee Juice',
    private: shown.filter(c => c.type === 'private').map(c => c.name),
    public: shown.filter(c => c.type === 'public').map(c => c.name),
  };
}

function askPerson(method, args, origin) {
  const id = ++asks;
  if (!window.webkit) return Promise.resolve(true); // desktop debugging: no shell to ask
  native('engineApprove', { id, method, origin, ...describe(method, args) });
  return new Promise(resolve => waiting.set(id, resolve));
}

// --- the connection -------------------------------------------------------------
let contentListener = null;
const background = new BackgroundConnectionHandler(
  { ...WALLET, walletIcon: 'https://casberi.app/favicon.ico' },
  {
    sendToTab: (tabId, message) => (window.webkit ? native('engineToTab', { tabId, message }) : queueMicrotask(() => window.webkitShim?.(message))),
    addContentListener: handler => {
      contentListener = handler;
    },
  },
  {
    onPendingDiscovery: discovery => {
      log('discovery', { appId: discovery?.appId, origin: discovery?.origin, chain: discovery?.chainInfo });
      // The shell asks the person, naming the site; desktop debugging (no shell) says yes.
      if (!window.webkit) return background.approveDiscovery(discovery.requestId);
      connecting.set(discovery.requestId, true);
      native('engineConnect', { requestId: discovery.requestId, origin: discovery.origin, appId: discovery.appId });
    },
    onSessionEstablished: session => {
      const emoji = hashToEmoji(session.verificationHash);
      log('session', { emoji, origin: session.origin });
      native('engineEmoji', { emoji, origin: session.origin });
    },
    onSessionTerminated: requestId => log('terminated', requestId),
    onWalletMessage: async (session, message) => {
      const { messageId, type, args } = message;
      const started = ms();
      let result;
      let error;
      try {
        result = await callWallet(type, args, session.origin);
      } catch (e) {
        error = { message: String(e?.message ?? e).slice(0, 400) };
      }
      log(error ? 'refused' : 'answered', { type, origin: session.origin, took: ms() - started, result: summarise(result), error });
      await background.sendResponse(session.sessionId ?? session.requestId, { messageId, result, error, walletId: WALLET.walletId });
    },
  },
);
background.initialize();

window.casberiEngine = {
  fromContent(json, tabId, url) {
    contentListener?.(JSON.parse(json), { tab: { id: tabId, url } });
  },
  setRoot(hex) {
    rootResolve(hex);
  },
  answerConnect(requestId, yes) {
    if (!connecting.delete(requestId)) return;
    log('connectAnswer', { yes });
    if (yes) background.approveDiscovery(requestId);
    else background.rejectDiscovery(requestId);
  },
  answerApproval(id, yes) {
    waiting.get(id)?.(yes);
    waiting.delete(id);
  },
};

// Desktop debugging (?local=1): the relay and a test app in THIS page, wired in
// memory, so the whole send path runs where its console can be read.
if (new URLSearchParams(location.search).get('local') === '1') {
  let deliver = null;
  const relay = new ContentScriptConnectionHandler({
    sendToBackground: m => queueMicrotask(() => contentListener?.(m, { tab: { id: 1, url: location.href } })),
    addBackgroundListener: h => { deliver = h; },
  });
  relay.start();
  window.webkitShim = m => { console.log('[engine] toPage', m.type, JSON.stringify(m.content ?? '').length); deliver?.(m); };
  const s = document.createElement('script');
  s.src = '/dapp.js';
  document.head.appendChild(s);
}

window.casberiEngine.debugCall = (m, a) => callWallet(m, a);

function summarise(value) {
  try {
    const s = jsonStringify(value);
    return s && s.length > 300 ? s.slice(0, 300) + '…' : s;
  } catch {
    return String(value);
  }
}

log('engineReady', { origin: location.origin, isolated: self.crossOriginIsolated, secure: self.isSecureContext });
// Start the PXE at once so the first app call doesn't wait for it.
getWallet().catch(e => log('walletFailed', { error: String(e?.stack ?? e).slice(0, 900) }));
