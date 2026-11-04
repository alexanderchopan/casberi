// Casberi's Aztec wallet ENGINE, for a hidden web view no app page can reach:
// Aztec's own wallet-sdk background handler (key exchange, session keys) in
// front of Aztec's own EmbeddedWallet (a PXE on this device) on the V6 TESTNET.
// Spike only: never shipped, testnet only.
//
// The account is Aztec's stock Schnorr account. Its secret and signing key are
// made here once and kept in this view's storage; in Casberi they would come
// from the private-money root in iCloud Keychain (prd §1562).
import { BackgroundConnectionHandler } from '@aztec-labs/wallet-sdk/extension/handlers';
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
      pxe: { proverEnabled: false },
      nodeClientOptions: { maxBatchSize: 3 }, // dRPC's free plan refuses larger batches
    });
    log('pxeReady', { chain: summarise(await wallet.getChainInfo()) });
    let keys = JSON.parse(localStorage.getItem('casberi.aztec.spike') ?? 'null');
    if (!keys) {
      keys = { secret: Fr.random().toString(), signingKey: GrumpkinScalar.random().toString() };
      localStorage.setItem('casberi.aztec.spike', JSON.stringify(keys));
    }
    const manager = await wallet.createSchnorrAccount(
      Fr.fromString(keys.secret), Fr.ZERO, GrumpkinScalar.fromString(keys.signingKey), 'Casberi',
    );
    accountAddress = manager.address.toString();
    log('accountReady', { address: accountAddress });
    return wallet;
  })();
  return walletPromise;
}

async function callWallet(method, args) {
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
    // A real Casberi raises a native sheet here: who asks, what it does, what goes public.
    throw new Error(`Casberi spike answers reads only; ${method} needs the person's yes`);
  }
  const parsed = schemaHasMethod(WalletSchema, method)
    ? await parseWithOptionals(args ?? [], getSchemaParameters(WalletSchema[method]))
    : args ?? [];
  const result = await wallet[method](...parsed);
  return result === undefined ? undefined : JSON.parse(jsonStringify(result));
}

// --- the connection -------------------------------------------------------------
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
      log('discovery', { appId: discovery?.appId, origin: discovery?.origin, chain: discovery?.chainInfo });
      background.approveDiscovery(discovery.requestId); // a real Casberi asks first, naming the origin
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
        result = await callWallet(type, args);
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
};

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
