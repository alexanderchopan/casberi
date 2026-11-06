// An Aztec app finds Casberi, and gets nothing before the person says yes
// (prd §1700j). Runs Aztec's own wallet-sdk on both sides — the app's
// WalletManager, the relay's ContentScriptConnectionHandler and the engine's
// BackgroundConnectionHandler — over a JSON hop like the native one, with the
// engine's gate (src/connect-gate.js) between them.
//
//   node test/connect-gate.test.mjs            the checks
//   MUTATION=ask-first node test/...           the old order: discovery waits on Connect
//   MUTATION=no-hold node test/...             the app's calls skip the gate
//   GATE=<path> node test/...                  a mutated gate
//
// Exit 0 when every check holds, 1 otherwise.
import { WalletManager } from '@aztec-labs/wallet-sdk/manager';
import { BackgroundConnectionHandler, ContentScriptConnectionHandler } from '@aztec-labs/wallet-sdk/extension/handlers';
import { hashToEmoji } from '@aztec-labs/wallet-sdk/crypto';
// GATE: a mutated copy of the gate, for the self-test's mutations.
const { connectGate } = await import(process.env.GATE ?? '../src/connect-gate.js');

// --- a page: one window, postMessage delivered async with source and ports.
// Each rig opens a fresh page, so an earlier rig's relay hears nothing of it.
let target = new EventTarget();
globalThis.window = {
  addEventListener: (t, h) => target.addEventListener(t, h),
  removeEventListener: (t, h) => target.removeEventListener(t, h),
  postMessage(data, _origin, transfer = []) {
    const page = target;
    setTimeout(() => {
      const e = new Event('message');
      Object.assign(e, { data, source: globalThis.window, ports: transfer });
      page.dispatchEvent(e);
    }, 0);
  },
};

const MUTATION = process.env.MUTATION ?? '';
const APP_WINDOW_MS = 5_000; // Dark Forest Aztec's discovery window
const PERSON_MS = 1_500; // how long a person takes to read a sheet and answer
const ORIGIN = 'https://dfaztec-s1.dfarchon.xyz';
const chainInfo = { chainId: { toString: () => '1' }, version: { toString: () => '1' } };

function rig({ connectYes = true, emojiYes = true } = {}) {
  target = new EventTarget();
  const asked = [];
  let toBackground = null;
  let toContent = null;
  const hop = (fn, msg) => setTimeout(() => fn?.(JSON.parse(JSON.stringify(msg)), { tab: { id: 1, url: ORIGIN + '/' } }), 0);
  const relay = new ContentScriptConnectionHandler({
    sendToBackground: m => hop(toBackground, m),
    addBackgroundListener: h => (toContent = h),
  });
  let gate;
  const background = new BackgroundConnectionHandler(
    { walletId: 'casberi', walletName: 'Casberi', walletVersion: '1.0', logger: { debug() {}, info() {}, warn() {}, error() {} } },
    { sendToTab: (_t, m) => hop(toContent, m), addContentListener: h => (toBackground = h) },
    {
      onPendingDiscovery: d => {
        asked.push('discovery');
        if (MUTATION === 'ask-first') {
          // The old order: the wallet stays hidden until the person answers Connect.
          setTimeout(() => (connectYes ? background.approveDiscovery(d.requestId) : background.rejectDiscovery(d.requestId)), PERSON_MS * 4);
          return;
        }
        gate.discovered(d.requestId);
      },
      onSessionEstablished: s => gate.established(s.sessionId, s.origin, hashToEmoji(s.verificationHash)),
      onSessionTerminated: id => gate.terminated(id),
      onWalletMessage: async (s, m) => {
        const run = () => background.sendResponse(s.sessionId, { messageId: m.messageId, result: { version: '1.0', granted: [], wallet: { name: 'Casberi', version: '1.0' } }, walletId: 'casberi' });
        if (MUTATION === 'no-hold') return run();
        if (!gate.message(s.sessionId, run)) {
          await background.sendResponse(s.sessionId, { messageId: m.messageId, error: { message: 'Not connected to Casberi' }, walletId: 'casberi' });
        }
      },
    },
  );
  gate = connectGate({
    approveDiscovery: id => background.approveDiscovery(id),
    terminateSession: id => background.terminateSession(id),
    askConnect: id => {
      asked.push('connect');
      setTimeout(() => gate.answerConnect(id, connectYes), PERSON_MS);
    },
    askEmoji: id => {
      asked.push('emoji');
      setTimeout(() => gate.confirmEmoji(id, emojiYes), PERSON_MS * 2);
    },
  });
  background.initialize();
  relay.start();
  return { asked, gate, relay };
}

async function findWallets() {
  const started = Date.now();
  const discovery = WalletManager.configure({ extensions: { enabled: true } })
    .getAvailableWallets({ chainInfo, appId: 'dfpunk', timeout: APP_WINDOW_MS });
  // Stops at Casberi, as Dark Forest's discoverExtensionWalletById does; a
  // wallet that never answers costs the whole window.
  const found = [];
  for await (const p of discovery.wallets) {
    found.push(p);
    if (p.id === 'casberi') break;
  }
  discovery.cancel();
  return { found, took: Date.now() - started };
}

let failures = 0;
function check(ok, words) {
  console.log(`${ok ? '✓' : '✗'} ${words}`);
  if (!ok) failures++;
}

// 1. The app finds Casberi inside its 5 s window, with nobody touching a sheet.
const a = rig();
const { found, took } = await findWallets();
const casberi = found.find(p => p.id === 'casberi');
check(!!casberi && casberi.name === 'Casberi', `a 5 s app finds Casberi (found ${found.map(p => p.name).join(', ') || 'nothing'} in ${took} ms)`);
check(!a.asked.includes('connect'), 'nothing is asked while the app is only looking');

if (casberi) {
  // 2. Picking Casberi opens the channel; the asks come now, and the app's
  //    first call waits on both.
  const pending = await casberi.establishSecureChannel('dfpunk');
  check(typeof pending.verificationHash === 'string', 'the secure channel opens (key exchange inside the SDK\'s 2 s)');
  const wallet = await pending.confirm();
  const t0 = Date.now();
  const caps = await wallet.requestCapabilities({ version: '1.0', capabilities: [] }).then(r => r, e => ({ error: String(e?.message ?? e) }));
  const waited = Date.now() - t0;
  check(a.asked.join(',') === 'discovery,connect,emoji', `Connect then the emoji check are asked when Casberi is picked (${a.asked.join(', ')})`);
  if (caps?.error) console.log("  call error:", caps.error);
  check(!caps?.error && waited >= PERSON_MS * 2 - 50, `the app's first call waits for both yeses (${waited} ms) and then runs`);
}

// 3. A no to Connect: the app's call never runs.
rig({ connectYes: false });
const second = (await findWallets()).found.find(p => p.id === 'casberi');
if (second) {
  const pending = await second.establishSecureChannel('dfpunk');
  const wallet = await pending.confirm();
  const outcome = await Promise.race([
    wallet.requestCapabilities({ version: '1.0', capabilities: [] }).then(() => 'ran', () => 'refused'),
    new Promise(r => setTimeout(() => r('held'), PERSON_MS * 4)),
  ]);
  check(outcome !== 'ran', `a declined Connect gives the app nothing (${outcome})`);
} else {
  check(false, 'the second app finds Casberi');
}

console.log(failures ? `aztec connect self-test: ${failures} failed` : 'aztec connect self-test: ok');
process.exit(failures ? 1 : 0);
