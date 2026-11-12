# Aztec engine

Aztec's `EmbeddedWallet` behind the wallet-sdk background handler, built as a page the app runs in a hidden web view (prd §1700). Proofs are made by Aztec's native iOS prover, not in JavaScript.

Neither output is committed (72 MB and 57 MB). `scripts/xcb.sh` runs the build before every app build.

| Output | Where it lands | Source |
| --- | --- | --- |
| The engine page | `Casberi/AztecEngine/` | This folder, built with Vite. |
| The prover | `Casberi/vendor/aztec/{ios,sim}/libbb-external.a` | Aztec's official v6.0.0 static libraries, downloaded from the `AztecProtocol/aztec-packages` GitHub release. |

## Building

```sh
scripts/aztec-engine.sh ensure
```

It installs the packages `package-lock.json` names, fetches and pins Shield's contract interfaces (`fetch-shield.mjs`), builds the page, and stamps the result with a hash of its inputs so an unchanged tree is not rebuilt.

## What to read

| File | What it is |
| --- | --- |
| `src/main.js` | The engine's entry point. |
| `src/connect-gate.js` | What an Aztec app may do before and after you pick Casberi as its wallet. Checked by `scripts/aztec-connect-selftest.sh`. |
| `src/native-backend.js` | The bridge to the native prover. |
| `src/net-shim.js` | The page reaches no host itself: its Content-Security-Policy allows only its own origin, and every outside request is rewritten to the app's loopback server. |
| `src/relay.js` | The only part of Casberi that runs inside an Aztec app's page: Aztec's content-script relay, in an isolated script world. |
| `src/private-fees.js`, `src/zk-link.js`, `src/steps.js` | Fee payment, zk.money links and progress reporting. |
| `test/` | The engine's own tests. |

The security model is in `docs/specs/aztec-security-model.md`.
