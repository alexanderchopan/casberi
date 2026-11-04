// Casberi as an Aztec wallet inside a page: a THROWAWAY spike (never shipped).
//
// Aztec apps find a wallet only through @aztec-labs/wallet-sdk: the page
// broadcasts `aztec-wallet-discovery` with window.postMessage and an extension's
// content script answers with a MessagePort. Here both halves of an extension
// (content script + background) run in the page itself, wired by an in-memory
// transport, so a WKWebView user script (or a script pasted into any browser)
// answers as a wallet named "Casberi".
//
// READ-ONLY: it reports one throwaway address and refuses every call that
// would simulate, prove, sign or send. It logs every method the app asks for,
// which is the point: that list is what a real Casberi wallet must answer.

import {
  BackgroundConnectionHandler,
  ContentScriptConnectionHandler,
} from '@aztec-labs/wallet-sdk/extension/handlers';
import { hashToEmoji } from '@aztec-labs/wallet-sdk/crypto';

// A Schnorr account address computed offline from a random key that was thrown
// away (tools/aztec-account, getSchnorrAccountContractAddress, salt 0). It holds
// nothing and can never sign.
const ADDRESS = '0x11b75d43a02d65dc912d0315aa976fc79f54b46eb4592996ec644982c8fd4e64';
const WALLET = { walletId: 'casberi', walletName: 'Casberi', walletVersion: '0.0.1-spike' };

function log(event, detail) {
  const line = { event, detail, at: new Date().toISOString() };
  try {
    window.webkit?.messageHandlers?.casberi?.postMessage(JSON.stringify(line));
  } catch {}
  (window.__casberiLog ||= []).push(line);
  console.log('[casberi]', event, detail ?? '');
}

function overlay(text) {
  let el = document.getElementById('casberi-spike');
  if (!el) {
    el = document.createElement('div');
    el.id = 'casberi-spike';
    el.style.cssText =
      'position:fixed;left:12px;bottom:12px;z-index:2147483647;padding:10px 14px;border-radius:14px;' +
      'background:#111;color:#fff;font:15px/1.35 -apple-system,system-ui;max-width:320px;white-space:pre-wrap;' +
      'box-shadow:0 6px 24px rgba(0,0,0,.35)';
    (document.body || document.documentElement).appendChild(el);
  }
  el.textContent = text;
}

if (!window.__casberiWallet) {
  window.__casberiWallet = true;

  let contentListener = null;
  let backgroundListener = null;
  const tab = { id: 1, url: location.href };

  const background = new BackgroundConnectionHandler(
    { ...WALLET, walletIcon: 'https://casberi.app/favicon.ico' },
    {
      sendToTab: (_tabId, message) => queueMicrotask(() => contentListener?.(message)),
      addContentListener: handler => {
        backgroundListener = handler;
      },
    },
    {
      onPendingDiscovery: discovery => {
        const chain = discovery?.chainInfo ?? discovery?.request?.chainInfo;
        log('discovery', { appId: discovery?.appId ?? discovery?.request?.appId, chain, origin: discovery?.origin });
        // A real wallet asks the person here. The spike approves, read-only.
        background.approveDiscovery(discovery.requestId);
      },
      onSessionEstablished: session => {
        const emoji = hashToEmoji(session.verificationHash);
        log('session', { emoji, appId: session.appId });
        overlay(`Casberi · connected (read-only)\nCheck these match the app:\n${emoji}`);
      },
      onSessionTerminated: requestId => log('terminated', requestId),
      onWalletMessage: (session, message) => answer(session, message),
    },
  );
  background.initialize();

  const content = new ContentScriptConnectionHandler({
    sendToBackground: message => queueMicrotask(() => backgroundListener?.(message, { tab })),
    addBackgroundListener: handler => {
      contentListener = handler;
    },
  });
  content.start();

  async function answer(session, message) {
    const { messageId, type, args, chainInfo } = message;
    log('call', { type, args: summarise(args) });
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
        log('capabilities', manifest);
        result = {
          version: '1.0',
          // A granted `accounts` capability names the accounts it grants.
          granted: (manifest.capabilities ?? []).map(c =>
            c.type === 'accounts' ? { ...c, accounts: [{ alias: 'Casberi', item: ADDRESS }] } : c,
          ),
          wallet: { name: WALLET.walletName, version: WALLET.walletVersion },
        };
        break;
      }
      case 'registerSender':
        result = args?.[0];
        break;
      case 'registerContract':
        result = undefined;
        break;
      default:
        error = { message: `Casberi spike is read-only: ${type} is not answered` };
    }
    log(error ? 'refused' : 'answered', { type, result: summarise(result), error });
    await background.sendResponse(session.sessionId ?? session.requestId, {
      messageId,
      result,
      error,
      walletId: WALLET.walletId,
    });
  }

  function summarise(value) {
    try {
      const s = JSON.stringify(value);
      return s && s.length > 600 ? s.slice(0, 600) + '…' : value;
    } catch {
      return String(value);
    }
  }

  log('ready', { origin: location.origin });
}
