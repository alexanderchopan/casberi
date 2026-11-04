// The PAGE half, and the only part of Casberi that runs inside an app's page:
// Aztec's own content-script relay. It is added in an isolated script world
// ("casberi"), so the app's JavaScript can neither read nor replace it, and it
// holds nothing secret — discovery requests, public keys and ciphertext pass
// through it to the native shell, which hands them to the engine web view
// (web/engine.js), where the session keys and the wallet live.
import { ContentScriptConnectionHandler } from '@aztec-labs/wallet-sdk/extension/handlers';

if (!window.__casberiRelay) {
  window.__casberiRelay = true;
  let deliver = null;
  const relay = new ContentScriptConnectionHandler({
    sendToBackground: message => window.webkit.messageHandlers.casberiRelay.postMessage(JSON.stringify(message)),
    addBackgroundListener: handler => {
      deliver = handler;
    },
  });
  // The native shell calls this with what the engine sent back.
  window.__casberiDeliver = json => deliver?.(JSON.parse(json));
  relay.start();
}
