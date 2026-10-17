# Aztec on an iPhone: the spike

One question: can an iPhone, **alone**, run a private Aztec account? Aztec's own
PXE (aztec.js 5.2.0) runs in a web view; every proof it makes is computed by
**Aztec's native iOS prover** (barretenberg, `libbb-external.a`) inside the app;
the account's only key is the phone's **Secure Enclave** P-256 key. Testnet v5
only, never shipped, not part of Casberi.

```sh
scripts/run-on-phone.sh --all          # build, install, run every step, print timings
scripts/run-on-phone.sh --all --wasm   # the same with bb.js's WebAssembly prover, to compare
```

The page's steps, each timed with the app's peak memory: check the prover
(one hash, native must equal WebAssembly), open the wallet, create the account
(the testnet's sponsor pays), deploy a token, mint 100, move 25 into private,
send 5 privately, read the balances. The console also prints every prover
command over 50 ms and the total time per command.

How it fits together:

- `web/src/native-backend.js` replaces bb.js's browser backend picker
  (`vite.config.js` swaps the module): the async prover posts each msgpack
  command to `/bb`; `App/AztecSpike/Prover.swift` hands the same bytes to the
  native `bbapi` on a 64 MB-stack thread.
- `App/AztecSpike/LocalServer.swift` serves the page from `http://127.0.0.1:8487`
  (a secure context, so the PXE's OPFS storage works) and answers `/bb`, `/key`,
  `/sign`, `/mem`, `/log`, `/result`.
- `App/AztecSpike/EnclaveKey.swift` signs with low-S, as Aztec's P-256 account
  requires (prd §1276); in a simulator without an Enclave it falls back to a
  software key. `deflate_shim.c` gives the prover libdeflate's gzip calls over
  the system zlib.
- Not committed: `web/node_modules`, `App/vendor/` (`scripts/fetch-prover.sh`),
  `App/Web/` (`npm run build`).

What the memory line counts: the app's own footprint, where the native prover
runs. The PXE's JavaScript runs in WebKit's separate web-content process,
which iOS limits on its own; Instruments shows both.

A simulator run proves the parts fit; its timings are the Mac's processor, not
a phone's.

## Measured (2026-10-17, iPhone 17 Pro Max, iOS 27, testnet v5, native prover)

| Step | Seconds | App peak |
|---|---|---|
| Each proof (`ChonkProve`) | 2.1 | |
| Create the account | 12.0 | 204 MB |
| Deploy a token | 10.0 | 286 MB |
| Mint 100 | 9.1 | 309 MB |
| Move 25 into private | 17.6 | 228 MB |
| Send 5 privately | 10.5 | 156 MB |

The rest of each step is the network: sending and waiting for the block. The
first iPhone run lost its token when the testnet discarded an unsettled block
(122389; "Tx dropped by P2P node", then "not deployed") — the network, not the
phone; the rerun passed every step. Simulator (Mac) proofs took the same ~2.2 s.
