# Privacy Pools v2 on Sepolia: a measured trial

TESTNET ONLY. This folder evaluates 0xBow's Privacy Pools v2 for Casberi. It is not app code, and nothing here touches mainnet. Measured on 2026-10-26 on an Apple M3 (8 cores, 16 GB) running Node 25.9 with `@0xbow/privacy-pools-v2-sdk@1.0.2`. Other sessions kept the machine busy throughout: the load average was 45–60, with spikes to 400. Treat every local timing as an upper bound.

**Status: unfunded.** The funding address is `0x0037862F20DC405e456ea88704436b498df1dF39` (key A). Everything that needs no funds has run. `node trial.mjs run` holds the funded path (register, deposit, wait for the ASP, private transfer, relayed withdrawal), but it has never run, so it is untested.

## Sepolia deployment (V9, pool 4), confirmed on chain

| | Address | How it was confirmed |
|---|---|---|
| Entrypoint | `0xEB3e3961008952348445513e418ad6F43C23ca9a` | ASP `/global/public/entrypoints` (pool 4), relayer `/v1/details`, and `relay.ENTRYPOINT()` agree |
| PoolVault | `0x09b94d3127019298757A6ceeB7911922085f7C01` | same, plus `relay.POOL()`. The vault holds about 119 test ETH and saw 5,678 note events since block 11.7M |
| Keystore | `0x6d264aCb9C3A7A3105c29470AfE2F5F1EC203C73` | ASP feed |
| ASPRegistry | `0x35D29EFDCf067599ab4A53cf40229477f0b1cA9c` | `latestASPRoot()` equals the ASP's `/association-set/root` |
| PrivacyPoolRelay (withdraw processor) | `0x7430cc030d7eb8C83E76cD983996982C8C054204` | relayer `/v1/details`; `MAX_BATCH()` = 10 |
| Relayer signer (transfer processor) | `0x4Ba5fF376865b370790A56276C63e7984DCFf1f7` | relayer `/v1/details` |
| Assets | ETH, USDC `0x1c7D…7238`, USDT `0xaA8E…33D0` | relayer: ETH carries a 10 bps fee plus gas; tokens pay gas only |
| ASP | `https://api-dev.0xbow.io` | `api-v2.0xbow.io` serves production only and lists no Sepolia pool |
| Relayer (v2 staging) | `https://relayer-v2-staging-149184580131.us-east1.run.app` | `testnet-relayer.privacypools.com` is the **v1** relayer and has no `/v1/*` routes. The website's source redacts this URL as `relayer-staging.example` |

## Results

| Step | Wall time | Proving (this Mac) | Gas | Relayer fee | Notes |
|---|---|---|---|---|---|
| Session build (SDK) | 0.2–1.3 s | — | — | — | |
| Note discovery, empty account | 18–58 s | — | — | — | Scans the logs of about 1M blocks over a public RPC. A phone pays this on every cold start unless leaf caches are seeded |
| Keystore registration | 22–26 s for two txs | — | 645,138 + 135,292 estimated (auth policy, then viewing key) | — | Measured on chain for A and B. A gasless relayed variant exists (EIP-712 `SetAuthPolicy`) |
| Deposit 0.0002 ETH | ~15 s | prepare + proof 1.4 s | **904,263** | none | Measured. The depositor does not need to be registered first |
| ASP approval | **3.2 min** | — | — | — | Measured: deposit mined 17:07:48 UTC, approved 17:11:00. Ask by label HASH (`Poseidon(label)`); the raw label always reads `unknown`. Over 14 days the next root followed a deposit after p50 1.4 min, p90 2.6 min, max 62 min |
| Private transfer (1 in → 2 out) | 124 s | 101 s prepare, almost all the keystore-tree sync over rate-limited RPCs; transact_1x2 alone 3.0 s | **1,538,548** (relayer budgets 850,000) | 16,171,000 wei at 19 wei gas | Measured. The relayer paid the gas; B found the note in 14 s |
| Relayed withdrawal (0.00005 ETH) | 27 s | transact_1x1: 3.1 s | **1,450,486** (relayer budgets 1,050,000) | 0.00000005 ETH (10 bps) + gas | Measured. The plain address C received exactly 0.00005 ETH |
| Ragequit | not run | 1.2 s | — | — | |
| Payment request | 6 ms | — | — | — | Generated locally; no registration needed |
| Stealth withdrawal | not run | — | — | — | `@0xbow/privacy-pools-v2-sdk/stealth` (ERC-5564, canonical and FluidKey schemes) |

**Proving.** These times use the real ceremony zkeys on synthetic inputs that satisfy the circuit; every proof verified against the ceremony vkey (`prove-bench.mjs`). These are medians of 3 runs. 0xBow's own benchmark, on an unloaded machine, gives 1.54 s for transact_1x1 and 1.99 s for transact_2x2.

**Mainnet cost.** On Sepolia, gas costs about 20 wei, so fees round to zero. At 1 gwei on mainnet:

| Step | Cost |
|---|---|
| Registration | ≈ 0.00078 ETH |
| Deposit | ≈ 0.00093 ETH |
| Transfer | ≈ 0.0015 ETH (measured gas) |
| Withdrawal | ≈ 0.0015 ETH (measured gas), plus 0.1% |

## Surprises

1. **The SDK's proofs do not verify on Sepolia.** SDK 1.0.1 and later pin the trusted-setup ceremony keys. The Sepolia V9 verifiers were built from the single-contributor dev keys of SDK 1.0.0. I checked this by finding the deposit vkey's alpha, delta and IC constants in the verifier bytecode: the 1.0.0 keys are there, and the ceremony keys are not. Mainnet's verifier holds the ceremony keys.
   - With the published SDK, `prepareDeposit` produces a proof that reverts with `PoolVault_InvalidDepositProof()` (`0x08bf478d`).
   - The live website ships the ceremony keys too, so its Sepolia flow should fail the same way. I inferred this and did not test it.
   - Workaround here: `manifest-sepolia-dev.json` (the 1.0.0 manifest) and `circuits-cache-sepolia-dev/`. With them, the same deposit estimates at 928k gas.
2. **The SDK's only default IPFS gateway, `ipfs.io`, is unreliable.** It (and `dweb.link`) now answers some CIDs with a "switching to a service worker gateway" page or a 429. The SDK's sha256 check rejects that page, so only a second gateway saves the fetch (Pinata worked). An app must self-host the circuits, as privacypools.com does under `/artifacts`.
3. **Registration is about 780k gas**, because the keystore tree is a Poseidon Merkle tree updated on chain. A deposit is about 930k gas.
4. **The ASP's status endpoint takes the label's hash.** `GET /labels/{id}/status` wants `Poseidon(label)`, which the SDK's types say (`labelHash`), but its own `getLabelStatus` passes whatever it is given. Asked with the raw label, an approved deposit reads `unknown` forever; the first funded run gave up after 60 min for this reason alone.
5. **The keystore is older than pool 4.** Its first event is block 10,932,354; pool 4 starts at 10,994,884. Scanning from the pool leaves holes at the start of the keystore tree, and the transfer witness fails with `keystoreLeaves.0 … undefined`. The SDK takes one `deploymentBlock` for every contract, so it must be the oldest.
6. **Real gas runs past the relayer's budget.** The transfer used 1.54M against an 850k budget, the withdrawal 1.45M against 1.05M. The relayer still posted both.
7. **Licensing.** The SDK is MIT, but its runtime dependencies `snarkjs` and `circomlibjs` are GPL-3.0. The monorepo, including the circuits, is GPL-3.0 as well.

## Phone feasibility

- **SDK.** TypeScript only. Bundled for the browser (SDK + snarkjs + viem + LiFi, minified), it is 4.6 MB, or 1.9 MB gzipped.
- **Circuit downloads.** Each operation's circuit downloads on first use:

  | Circuit | Download (wasm + zkey) |
  |---|---|
  | deposit | 3.2 MB |
  | ragequit | 8.6 MB |
  | transact_1x1 | 20.4 MB |
  | transact_1x2 | 21.0 MB |
  | transact_2x2 | 29.6 MB |
  | transact_5x5 | 65.8 MB zkey |

  27 circuits in all; 0xBow publishes the sizes.
- **Proving cost.** One private transfer or withdrawal is one Groth16 proof of 38k–64k constraints, about 3 s on this Mac with threads. A phone would plausibly take 5–10 s in a WKWebView. That is an estimate; it was not measured on a phone.
- **WKWebView.** It has WebAssembly, Web Workers and JIT, so snarkjs runs there as it does in Safari. This is the realistic near-term host.
- **JavaScriptCore (`JSContext`).** iOS gives a third-party JSContext no JIT, and in practice no WebAssembly, which snarkjs needs for both the witness and the curve arithmetic. Not viable.
- **Hermes (React Native).** It has no WebAssembly at all. 0xBow's own Expo app (`privacy-pools-website-v2`, bundle `com.privacypools.v2`) replaces circomlibjs's Poseidon with a Rust uniffi module (`modules/native-poseidon`, MIT, with an iOS xcframework build script). I found no native proving path in its public code, and its native build still carries a mock-data mode.
- **Native proving.** The same `.zkey` files would work with rapidsnark or mopro, plus a native witness generator. 0xBow ships none of this publicly.
- **Rust SDK.** It is not public. There is nothing on crates.io (searched `privacy-pools`, `privacy_pools`, `0xbow`, `privacypools`, `ppv2`). The `0xbow-io` GitHub org has 10 public repos, and every SDK among them is TypeScript. The only public Rust is:
  - `native-poseidon` (a hash only);
  - the relayer's `funder` crate;
  - `anon-rpc-rs`, which ships only as vendored tarballs in the website repo and is not on npm.

  **Ask 0xBow for access** (version, licence, uniffi/Swift bindings, native prover) before planning a native integration.

## The key model for Casberi

Casberi's account is a Safe owned by a Secure Enclave P-256 key behind Face ID.

v2 implements only `authType = 0`: a direct software key, where the circuit proves the Poseidon preimage of `privateNullifyingKey` and `privateRevocableKey`.

- **Designed but not implemented:** `authType = 1` (BabyJubJub EdDSA, aimed at hardware wallets) and `authType = 2` (intent-based, for contract accounts such as a Safe).
- **Multisig direction:** per 0xBow's notes in the website repo (`docs/multisig-and-intents.md`), the team is going with in-circuit FROST on BabyJubJub instead of intents.
- **P-256 / passkeys:** no P-256 or passkey auth type is implemented or designed at the circuit level. Passkeys appear only as a seed source: the website derives the same key tree from a WebAuthn PRF output for smart-contract wallets.

The gap, concretely:

- **The Safe can own the account.**
  - On chain, the keystore entry is keyed by the owner address.
  - `Keystore` accepts `setAuthPolicy` from `msg.sender`, which a Safe transaction can do.
  - It also accepts a relayed EIP-712 `SetAuthPolicy` checked with OpenZeppelin `SignatureChecker`, which supports ERC-1271.
  - So registration and key rotation can be authorised by the Secure Enclave through the Safe.
- **Spending cannot sit in the Secure Enclave.**
  - Every proof takes the two private keys as circuit inputs, so they must be in app memory. The Secure Enclave cannot do BN254 or Poseidon.
  - The SDK's standard derivation is a deterministic secp256k1 EIP-712 signature from the owner. Neither a Safe nor a P-256 key can produce it, so Casberi would generate a random seed instead.
  - The SDK accepts pre-derived `ProtocolKeys`, or the website's PRF-style derivation.
  - The seed would be stored in the Keychain with a biometry access control, so Face ID gates use, but the key itself is software.
- **How big the gap is.** Moderate and workable today, but the Secure Enclave guarantees custody of the Safe, not of the shielded notes. A stolen seed spends the private balance. Rotating `privateRevocableKey` (Safe-authorised) cuts that off, but the nullifying key is write-once.

## Rerun

```sh
npm ci
node discover.mjs                          # deployment, on chain + ASP + relayer
node keys.mjs                              # creates state/keys.json (gitignored, 0600), prints addresses and balances
node fetch-circuits.mjs                    # ceremony keys -> circuits-cache/ (what mainnet verifies)
KEYS=sepolia-dev node fetch-circuits.mjs   # SDK 1.0.0 dev keys -> circuits-cache-sepolia-dev/ (what Sepolia verifies)
node prove-bench.mjs 3                     # proving times; SINGLE_THREAD=1 for no workers
node asp-cadence.mjs 100000                # ASP root cadence vs deposits, last 100k blocks
node trial.mjs prep                        # no-funds SDK path; results -> state/results.jsonl
# fund key A (address printed by keys.mjs) with ~0.02 Sepolia ETH, then:
node rpc-router.mjs &                      # old logs from Tenderly, the rest from PublicNode, 429s retried
SEPOLIA_RPC=http://127.0.0.1:8547 node trial.mjs run   # caps spend at 0.02 ETH
SEPOLIA_RPC=http://127.0.0.1:8547 RESUME=1 DEPOSIT_ETH=0 GAS_BUFFER_ETH=0 B_GAS_ETH=0 node trial.mjs run   # transfer + withdraw an earlier deposit
```

## Blockers

- **Sepolia uses dev keys.** The SDK's default circuits do not match the Sepolia verifiers; use the dev-key cache (the default in `trial.mjs`; set `CEREMONY=1` to use the ceremony set).
- **Archive history.** PublicNode answers `pruned history unavailable` for old logs, and every other free Sepolia RPC tried caps the range or rate-limits; Tenderly's gateway serves the whole range. `rpc-router.mjs` routes `eth_getLogs` there and falls back at the chain head, where Tenderly lags a block. A phone needs the same: an archive-capable RPC or seeded leaf caches.
