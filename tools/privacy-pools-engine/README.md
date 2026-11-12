# Privacy Pools engine

0xBow's Privacy Pools v2 SDK, with snarkjs and viem, bundled into one script the app runs in a hidden web view (prd §1540).

| Output | Committed at |
| --- | --- |
| The engine | `Casberi/Casberi/Resources/privacy-engine.js` |
| Circuit pins | `Casberi/Casberi/Model/PrivacyArtifactPins.swift` |

## Reproducing the committed bundle

Every dependency is pinned exactly in `package.json` and `package-lock.json`, and esbuild's output is a function of its input, so the same tree builds the same bytes.

```sh
npm ci
```

```sh
node build.mjs --check
```

`--check` rebuilds in memory and fails if the committed file differs. `node build.mjs` writes the file and prints its size and SHA-256.

## What to read

| File | What it is |
| --- | --- |
| `src/engine.js` | The engine: the only code here that is Casberi's own. |
| `src/net.js` | The engine's one network door. |
| `src/shims.js`, `src/pino.js` | Node modules stubbed out for the browser build. |
| `pins.mjs` | Writes the SHA-256 of every circuit file the engine may run. The app refuses any byte that does not hash to its pin. |
| `mainnet-sim.mjs`, `run-mainnet-sim.sh` | Every mainnet move simulated, then each mutation, which must be caught. Nothing is signed or sent. `mainnet-sim.json` is the record. |
| `upstream.json` | The reviewed upstream state, compared by `scripts/ppv2-upstream.py`. |

The Swift side is checked by `scripts/privacy-engine-selftest.sh` and `scripts/private-money-selftest.sh`. Licences of everything bundled stay in the output file and are named in `Casberi/Casberi/Resources/Licenses.md`.
