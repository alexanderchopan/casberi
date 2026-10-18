# Casberi's Aztec testnet account (no deployment, rotation, recovery)

A private-only Aztec account contract (`contract/src/main.nr`, prd §1419) whose signing key is a P-256 key, verified exactly like Aztec's `EcdsaRAccount` (P-256 over `sha256(outer_hash)`, low-S), so the phone's Secure Enclave key and the signer flow are unchanged. Unlike the stock account:

- the signing key **rotates**: the current key signs a tx calling `rotate_signing_key(new key)`;
- a separate **recovery** P-256 key can replace the signing key through `recover(new key, nonce)`, which anyone may submit but only the recovery key can authorise;
- nothing is **deployed**: no class publication, no instance publication, no initializer. The initial and recovery keys are bound into the address (`immutables_hash`); the account's first real tx creates its key note.

TESTNET ONLY. Measured on Aztec's v5 testnet (node 5.0.0, aztec.js 5.2.0) on 2026-10-18, account `0x0f536d9d…f7f0`:

| Step | Block |
|---|---|
| First tx (deploys a test token, creates the key note) | 123630 |
| Mint to private | 123631 |
| Rotate to key 2, signed by key 1 | 123632 |
| Key 1 refused | — |
| Transfer signed by key 2 | 123633 |
| Recovery to key 3, sent with no account (Sponsored FPC) | 123634 |
| Key 2 refused | — |
| Transfer signed by key 3 | 123635 |
| Authwit by key 2 refused, by key 3 accepted | 123636 |

The instance and class stayed unpublished throughout.

Known limits:
- Gas estimation swaps the account for a stub that lacks `rotate`/`recover`, so `run.mjs` sends with the network's maximum gas limits; a stub artifact for this class is the fix.
- An authwit proves the key was not nullified at the anchor block, so a rotated-away key can still authorise authwits for up to 10 minutes; the entrypoint path cuts it off at once.
- Recovery also needs the account's secret and salt (the PXE must nullify the note). The recovery key itself is fixed by the address.
- The compiled artifact in `contract/target/` is pinned: a recompile that changes the bytecode changes every address.

```sh
npm install
node run.mjs        # software P-256 keys stand in for the phone; state in ./state.json (test keys, never committed)
```

Compiled with nargo 1.0.0-beta.25 and `aztec compile` 5.2.0 against aztec-nr at the `v5.2.0` tag.
