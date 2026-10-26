# Casberi's Aztec testnet account (no deployment, rotation, recovery, a private pocket)

A private-only Aztec account contract (`contract/src/main.nr`, prd §1419) whose signing key is a P-256 key, verified exactly like Aztec's `EcdsaRAccount` (P-256 over `sha256(outer_hash)`, low-S), so the phone's Secure Enclave key and the signer flow are unchanged. Unlike the stock account:

- the signing key **rotates**: the current key signs a tx calling `rotate_signing_key(new key)`;
- a separate **recovery** P-256 key can replace the signing key through `recover(new key, nonce)`, which anyone may submit but only the recovery key can authorise;
- nothing is **deployed**: no class publication, no instance publication, no initializer. The initial and recovery keys are bound into the address (`immutables_hash`); the account's first real tx creates its key note.

TESTNET ONLY. v5 was measured first (node 5.0.0, 2026-10-18: first tx, mint, rotate, refusal, recovery, authwit, all green). This file now records the **v6** trial.

## v6 trial, 2026-10-26

Aztec testnet v6 (node 6.0.0, rollup version 679261766, L1 Sepolia), `@aztec-labs/*` 6.0.0, nargo 1.0.0-rc.3. Client: Node 25 on an Apple M3 (8 cores), proving locally with `proverEnabled: true`. Account A `0x104aca52…515f`, account B `0x0195160c…2064` (a second undeployed CasberiKeyAccount), test token cUSD `0x24fb9768…94e5`, L2 bridge `0x206ec84a…98fb`.

"Wall" is from the call to an L2 receipt at status `proposed` (blocks every ~12 s); "prove" is the client proof (ClientIVC) alone, witness generation separate. Fees are in Fee Juice (FJ, 18 decimals); all L2 fees so far were paid by the canonical Sponsored FPC.

| Step | Wall | Prove (+witgen) | L2 fee | L1 gas | Third party |
|---|---|---|---|---|---|
| s1 A's first tx: deploy the test token, create the key note | 16 s | 2.6 s (+1.6 s) | 1.61 FJ | — | Sponsored FPC |
| s2 deploy the L2 token bridge (portal = the address L1 will deploy) | 12 s | 3.4 s (+0.9 s) | 1.25 FJ | — | Sponsored FPC |
| s3 bridge set as minter | 13 s | 2.3 s (+0.6 s) | 0.86 FJ | — | Sponsored FPC |
| s4 mint 1,000 cUSD to A, private | 12 s | 2.7 s (+0.7 s) | 0.93 FJ | — | Sponsored FPC |
| s5 private send A → B (100 cUSD; B's PXE reads 100) | 14 s | 2.4 s (+0.6 s) | 0.68 FJ | — | Sponsored FPC |
| s6 private send OUT: `exit_to_l1_private` 50 cUSD to a plain Sepolia address | 25 s | 3.9 s (+1.4 s) | 1.07 FJ | — | Sponsored FPC |
| s7 wait until the withdrawal is consumable on L1 | **23.8 min** | — | — | 0 (eth_call) | none |
| r1 rotate to key 2, signed by key 1 | 10 s | 2.2 s | 0.64 FJ | — | Sponsored FPC |
| r2 key 1 refused | 2 s | — | — | — | — |
| r3 transfer signed by key 2 | 9 s | 2.3 s | 0.68 FJ | — | Sponsored FPC |
| r5 recovery to key 3, sent with no account | 11 s | 2.3 s | 0.62 FJ | — | Sponsored FPC |
| r6 key 2 refused | 2 s | — | — | — | — |
| r7 transfer signed by key 3 | 9 s | 2.4 s | 0.68 FJ | — | Sponsored FPC |
| r8 authwit by key 2 refused | 3 s | — | — | — | — |
| r9 authwit by key 3 spent by a third party | 26 s | 2.8 s | 0.68 FJ | — | Sponsored FPC |

Every tx above reached `proven` (epoch 157). Account A stayed `UNINITIALIZED`, its instance and class unpublished, from first tx to last. Refusals are local: the simulation fails at the account's `assert(valid_fn(...))`, so nothing is sent.

**The withdrawal (s6 → s7).** The L2→L1 message is consumable only once its epoch is proven: epochs are 32 slots × 72 s = 38.4 min, and the proof landed about 8 min after epoch 157 closed. The s6 tx landed in slot 19 of 32 (about 23 min into the epoch, 15.6 min before it closed), so it took 23.8 min; expect roughly 8 min (sent at an epoch's end) to 47 min (sent at its start). The proof covered the whole epoch (`numCheckpointsInEpoch` 32); no partial-epoch proof arrived earlier. Claimability was checked without Sepolia ETH by an `eth_call` of `Outbox.consume` from the portal's predicted address (the Outbox only checks `msg.sender`), which succeeded against the real Sepolia Outbox.

**L1 legs, rehearsed on an anvil fork of Sepolia** (2026-10-26, block ≈11,999,245, after s7; the test address funded on the fork only). Everything below ran from our own test address, no relayer:

| L1 step | Gas |
|---|---|
| deploy test ERC20 (nonce 0) | 4.83 M |
| deploy TokenPortal (nonce 1, at the address the L2 bridge already names) | 5.05 M |
| `initialize` the portal | 0.81 M |
| Fee Juice in: FeeAssetHandler `mint` (1,000 FJ, public, no allowlist) + approve + `depositToAztecPublic` | 0.15 M + 0.13 M + 0.29 M |
| token in, private: ERC20 mint + approve + `depositToAztecPrivate` | 0.24 M + 0.13 M + 0.40 M |
| **claim the s6 withdrawal on L1** (`TokenPortal.withdraw`, against the real proven root) | **0.29 M**; the plain address received 50 cUSD |

Sepolia now prices state growth high (a 3 KB contract deploy estimates ~5 M gas on Sepolia itself), and anvil under-estimates it, so `run.mjs` declares every L1 tx's estimate + 50%. Sepolia's base fee was 19 wei, so L1 cost in ETH is negligible; gas is the meaningful figure.

**Sponsored fees.** The canonical Sponsored FPC (salt 0, `0x2d8fff82…69d3`) is deployed on the v6 testnet and paid every L2 fee above. **Paying from A's own Fee Juice is not yet measured**: Fee Juice exists only through the L1 portal, which needs Sepolia ETH (steps f1–f3 below). The FeeAssetHandler's `mint` is public (1,000 FJ per call, simulated OK from the unfunded test address), so once the address holds ETH no third party is needed.

## Not done yet (needs Sepolia ETH on the test address)

The Sepolia test address is `0xe8C5ED699a31FF4E7057dA6AE31e037533fD154E` (key only in `state.json`); the withdrawal recipient is `0x5ff9534D9a4A935ea4e9a8Da3c0B55953859d196`. It must still be at nonce 0: its first two txs deploy the ERC20 and the portal at the addresses the L2 bridge was built for. About 0.05 Sepolia ETH is plenty. Then `node run.mjs` runs, in order:

- `l1_deploy_erc20`, `l1_deploy_portal`, `l1_init_portal`;
- `f1_bridge_fee_juice` (mint 1,000 FJ, deposit to A), `f2_claim_and_pay_with_own_fee_juice` (A claims its Fee Juice in a tx that pays for itself: no FPC), `f3_tx_paid_from_own_fee_juice`;
- `d1_l1_deposit_private`, `d2_l2_claim_private` (the token bridged IN privately; amount public, recipient not; paid from A's own Fee Juice);
- `w1_l1_claim_withdrawal` (the s6 withdrawal, submitted by our own address).

## What v6 changed

- **Contract: no source change.** `main.nr` compiles unchanged against aztec-nr v6.0.0; only `Nargo.toml` moved. aztec-nr is no longer in `AztecProtocol/aztec-packages` at v6 (`AztecProtocol/aztec-nr` has nightlies only); its v6.0.0 source is tagged in `aztec-labs-eng/aztec-node` (`noir-projects/aztec-nr`, and `ecdsa_public_key_note` moved to `noir-projects/aztec-nr/ecdsa-public-key-note`). A recompile with local paths gives identical function bytecode. The v5 artifact fails to load on v6 (verification key 5,216 bytes, v6 expects 4,832), so v6 addresses differ from v5.
- **JS:** packages are `@aztec-labs/*` and `@aztec-foundation/*` 6.0.0; the module paths used here are otherwise the same. The embedded wallet now simulates through a stub account it looks up in its own DB; our account is not there, so `run.mjs` points `simulateViaEntrypoint` at the base wallet and estimates gas with the real account (the v5 "send with max gas" workaround is gone). `BaseAccount.createAuthWit` now needs the chain info; `run.mjs` signs through the provider directly.
- **RPC:** the public endpoint (`aztec-testnet.drpc.org`) refuses JSON-RPC batches of more than 3, so the node client is built with `maxBatchSize: 3` (`AZTEC_MAX_BATCH` overrides).

## Known limits

- An authwit proves the key was not nullified at the anchor block, so a rotated-away key can still authorise authwits for up to 10 minutes; the entrypoint path cuts it off at once.
- Recovery also needs the account's secret and salt (the PXE must nullify the note). The recovery key itself is fixed by the address.
- The compiled artifact in `contract/target/` is pinned: a recompile that changes the bytecode changes every address.
- `exit_to_l1_private` makes the recipient and amount public on L1, and `claim_private` makes the amount public on L2 (the recipient stays private).

## Rerun

```sh
npm install
node run.mjs info        # node, sponsored FPC, Sepolia test address balance and nonce, predicted portal
node run.mjs             # every step not yet done; L1 steps only once the test address holds Sepolia ETH
node run.mjs claimable   # poll until the s6 withdrawal can be consumed on L1, record how long it took
node run.mjs status      # state, public parts only
node receipts.mjs        # every recorded tx's status and fee now

# L1 rehearsal on a Sepolia fork (no real ETH; aztec-anvil from the Aztec 6.0.0 toolchain):
aztec-anvil --fork-url https://ethereum-sepolia-rpc.publicnode.com --port 8645 &
cast rpc anvil_setBalance 0xe8C5ED699a31FF4E7057dA6AE31e037533fD154E 0x8AC7230489E80000 --rpc-url http://127.0.0.1:8645
cp state.json state-fork.json
STATE_FILE=$PWD/state-fork.json L1_RPC=http://127.0.0.1:8645 node run.mjs l1only
```

State (P-256 test keys, account secrets and salts, the Sepolia test key) lives only in `state.json` and `state-*.json`, the PXE in `pxe/`; all gitignored. Nothing prints a private key.

Compile (Aztec 6.0.0 toolchain, `curl -fsSL https://install.aztec-labs.com/6.0.0/install`): `cd contract && aztec compile`.
