# Casberi as an Aztec wallet in its own browser: the spike

One question: can an Aztec app, running in Casberi's in-app browser, find and
talk to Casberi as its wallet? Aztec apps reach a wallet only through Aztec's
`@aztec-labs/wallet-sdk` (6.0.0): a `window.postMessage` discovery answered by
a browser extension, then a P-256 ECDH channel, a nine-emoji check, capability
grants and encrypted calls. No WalletConnect, no deep link.

`web/inject.js` runs BOTH halves of an extension (the SDK's own
`ContentScriptConnectionHandler` and `BackgroundConnectionHandler`) inside the
page over an in-memory transport, so a WKUserScript makes the page see a wallet
named "Casberi". READ-ONLY: it reports one throwaway address (its key was never
kept) and refuses everything that would simulate, prove, sign or send, logging
every method the app asks for.

```sh
npm i && node build.mjs                          # dist/inject.js (30 KB) + dist/dapp.js (the SDK's app side)
node cdp.mjs <url> [eval:<expr>|click:<text>|xy:x,y|wait:ms|shot:name|log|dom]   # headless Chrome, script injected at document start
App/build.sh                                     # AztecDapp.app for the simulator, swiftc only
```

`dist/index.html` / `dist/ios.html` are the app side, built from Aztec's
`WalletManager` (what Shield ships). Serve `dist/` on :8779 (`.claude/launch.json`
"aztec-dapp-spike"). Never shipped, not part of Casberi.

## Round two: the real engine, split like an extension

- `web/relay.js` (7.6 KB) is the ONLY thing in the app's page: Aztec's content-script
  relay, added in an isolated `WKContentWorld` ("casberi") the page cannot reach.
- `engine-web/` (Vite) builds Casberi's engine page into `dist/engine/`: Aztec's
  background handler (key exchange, session keys) in front of Aztec's
  `BrowserEmbeddedWallet` (a PXE on the device) on the **V6 testnet**, with a stock
  Schnorr account. Reads only; anything that sends refuses until a native sheet asks.
- `App/` runs it: the engine in a hidden web view served from the app on
  `127.0.0.1:8488` (`EngineServer.swift`, isolation headers, OPFS), the shell
  passing relay messages and naming the page's origin itself.
- `serve.mjs` serves `dist/` with the same headers on :8780 for headless Chrome
  (`NO_INJECT=1 node cdp.mjs http://localhost:8780/engine/ ...`).

Measured on the iPhone 17 Pro simulator, 2026-11-04: PXE ready 1.9 s, account
2.1 s, handshake to the app ~50 ms after that, `getContractMetadata` from the
testnet node 417 ms. Not yet: proving (prover off), fees, sending, an approval
sheet, keys from iCloud Keychain.

## Round three: the first private send, through Casberi, on a phone web view

`dist/ios.html?auto=send` (the app side, Aztec's own `WalletManager` and
`TokenContract`) deploys a token, mints to the person's PRIVATE balance, sends
250,000 PRIVATELY to a random address and reads the balance back. Every
`sendTx` stops at the engine's approval (`engineApprove` → the shell; the spike
says yes and logs what it was asked), is simulated, PROVED on the device
(ClientIVC, Aztec's WebAssembly prover with threads) and sent; fees come from the
testnet's Sponsored FPC; the account is Aztec's stock `SchnorrInitializerlessAccount`
(no deployment transaction).

iPhone 17 Pro simulator, V6 testnet, 2026-11-04 (each to PROPOSED):

| step | through Casberi | of which the proof |
|---|---|---|
| deploy token | 26.4 s | 16.3 s |
| mint privately | 20.0 s | 11.4 s |
| send privately | 26.4 s | 14.2 s |
| read private balance | 1.6 s (750,000, correct) | — |

Desktop Chrome, same engine (`?local=1` runs the relay and test app in the
engine page): 20.6 / 13.8 / 16.9 / 1.5 s. The proof is the Mac's cores through
WebAssembly; the phone spike's native prover made one in 2.1 s on an iPhone.

Traps: never log an aztec.js `Contract` (it holds the wallet proxy); Aztec's
loggers bind `console` at import, so the bridge that forwards them
(`engine-web/src/console-bridge.js`) is imported first.

## Round four: Aztec's native prover

`engine-web/src/native-backend.js` replaces bb.js 6's `bb_backends/browser/index.js`
(`vite.config.js`): in the app, every prover command goes to `POST /bb` on the
engine's own origin, where `App/Prover.swift` hands it to Aztec's official v6 iOS
library (`App/vendor/`, `gh release download v6.0.0 -R AztecProtocol/aztec-packages
-p 'barretenberg-static-arm64-ios*'`, not committed) on a 64 MB-stack thread.
`App/deflate_shim.c` gives it libdeflate's gzip calls over zlib. Outside the app,
or with `?prover=wasm`, bb.js's WebAssembly prover runs.

Same simulator, same flow:

| step | WebAssembly | native |
|---|---|---|
| deploy token: proof / total | 16.3 / 26.4 s | 11.2 / 21.9 s |
| mint privately | 11.4 / 20.0 s | 9.2 / 18.5 s |
| send privately | 14.2 / 26.4 s | 7.3 / 20.0 s |

Inside a native proof, `bbapi` itself spends ~6–7 s (ChonkProve 2.9–4.1 s); the
rest is the commands' round trips between the web view and the app. The rest of
each total is simulation, witness generation and waiting for the block.

## Round five: the person is asked

The engine no longer says yes on its own. A site's connect asks the shell
(`engineConnect`); every `sendTx` asks too (`engineApprove`), described from the
request itself: each call's function, its contract's last four characters, and
whether it runs PRIVATELY (lock) or in PUBLIC (eye), plus who pays the fee. The
shell raises one native sheet at a time (`Ask`, `AskSheet`, a queue so a second
ask waits for the first sheet to go) and shows the session's nine emoji in a
banner to compare with the site's. `-autoApprove YES` says yes 2.5 s after a
sheet appears, for unattended runs. Not yet read: public steps a private call
starts on its own (the sheet does not claim to know them).
