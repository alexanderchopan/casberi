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
