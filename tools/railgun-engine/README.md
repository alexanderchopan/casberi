# Railgun engine

Railgun's wallet SDK, with ethers and snarkjs, bundled into one module script the app runs in a hidden web view (prd §1713).

| Output | Committed at |
| --- | --- |
| The engine | `Casberi/Casberi/Resources/railgun-engine.js` |
| The SDK's wasm | `Casberi/Casberi/Resources/poseidon_hash_wasm_bg.wasm`, `curve25519_scalarmult_wasm_bg.wasm` |

## Reproducing the committed bundle

Every dependency is pinned exactly in `package.json` and `package-lock.json`, and esbuild's output is a function of its input, so the same tree builds the same bytes.

```sh
npm ci
```

```sh
node build.mjs --check
```

`--check` rebuilds in memory and fails if the committed files differ. `node build.mjs` writes them and prints size and SHA-256.

## What to read

| File | What it is |
| --- | --- |
| `src/engine.js` | The engine the app ships. |
| `src/net.js` | The page's one door to the network: every request goes to Swift. The page's Content-Security-Policy allows no host. |
| `src/socket.js` | The page's WebSocket, also Swift's, for reaching Railgun's broadcasters over Waku. |
| `src/inject.js` | Node globals the SDK's dependencies expect. |
| `src/core.js`, `src/page.js`, `src/app-page.js`, `src/broadcast-spike.js` | Spikes, Sepolia only. `node build.mjs src/<name>.js` bundles one into `dist/`; none ship. |
| `mainnet-test.mjs`, `safe-test.mjs`, `node-run.mjs` | Node-side runs used to measure the SDK. |

The Swift side is checked by `scripts/railgun-selftest.sh`. Licences of everything bundled stay in the output file and are named in `Casberi/Casberi/Resources/Licenses.md`.
