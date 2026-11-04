// The WALLET half: Aztec's own background handler (key exchange, the session
// keys, every decrypt and encrypt) and the wallet that answers, in Casberi's
// own hidden web view. No app's page can reach it: the native shell passes it
// relay messages and tells it which page (tab) and origin each came from.
//
// READ-ONLY spike: answers with a throwaway address until the real engine
// (Aztec's EmbeddedWallet over a PXE) replaces `answer`.
import { BackgroundConnectionHandler } from '@aztec-labs/wallet-sdk/extension/handlers';
import { hashToEmoji } from '@aztec-labs/wallet-sdk/crypto';

const ADDRESS = '0x11b75d43a02d65dc912d0315aa976fc79f54b46eb4592996ec644982c8fd4e64';
const WALLET = { walletId: 'casberi', walletName: 'Casberi', walletVersion: '0.0.2-spike' };

const native = (name, value) => window.webkit?.messageHandlers?.[name]?.postMessage(JSON.stringify(value));
function log(event, detail) {
  native('engineLog', { event, detail, at: new Date().toISOString() });
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
      log('discovery', { appId: discovery?.appId, chain: discovery?.chainInfo, origin: discovery?.origin });
      // The real wallet asks the person, natively, naming the origin. The spike approves.
      background.approveDiscovery(discovery.requestId);
    },
    onSessionEstablished: session => {
      const emoji = hashToEmoji(session.verificationHash);
      log('session', { emoji, appId: session.appId, origin: session.origin });
      native('engineEmoji', { emoji, origin: session.origin });
    },
    onSessionTerminated: requestId => log('terminated', requestId),
    onWalletMessage: (session, message) => answer(session, message),
  },
);
background.initialize();

// The native shell calls this for every relay message, with the tab it came from.
window.casberiEngine = {
  fromContent(json, tabId, url) {
    contentListener?.(JSON.parse(json), { tab: { id: tabId, url } });
  },
};

async function answer(session, message) {
  const { messageId, type, args, chainInfo } = message;
  log('call', { type, origin: session.origin });
  let result;
  let error;
  switch (type) {
    case 'getChainInfo':
      result = chainInfo;
      break;
    case 'getAccounts':
      result = [{ alias: 'Casberi', item: ADDRESS }];
      break;
    case 'getAddressBook':
      result = [];
      break;
    case 'requestCapabilities': {
      const manifest = args?.[0] ?? {};
      result = {
        version: '1.0',
        granted: (manifest.capabilities ?? []).map(c =>
          c.type === 'accounts' ? { ...c, accounts: [{ alias: 'Casberi', item: ADDRESS }] } : c,
        ),
        wallet: { name: WALLET.walletName, version: WALLET.walletVersion },
      };
      break;
    }
    default:
      error = { message: `Casberi spike is read-only: ${type} is not answered` };
  }
  log(error ? 'refused' : 'answered', { type });
  await background.sendResponse(session.sessionId ?? session.requestId, {
    messageId,
    result,
    error,
    walletId: WALLET.walletId,
  });
}

log('engineReady', { origin: location.origin });
