# World ID beyond §785 — this phone as an authenticator

> **BLOCKED IN WORLD'S APP — MEASURED 2026-09-16 (prd §787).** §6 measurement 1 is a NO: the user
> checked World's app and found no way to add keys or guardians and no recovery choice. A new
> authenticator joins only when one already on the account calls `insert_authenticator` (WalletKit's
> pubkey validator names "a key scanned during pairing"), so without a pairing screen Stage 1 has no
> door. Measurement 5 reads the same way: the recovery agent on every sampled account is World's PoH
> Recovery Agent `0x00000000CBBA8Cb46C8CD414B62213F1B334fC59`. WalletKit is `worldcoin/walletkit`
> (Swift: `walletkit-swift`, 127 MB compressed xcframework). Re-open when World's app ships pairing.

Spec, 2026-09-16. Read against `worldcoin/world-id-protocol` at `9577f2f` (2026-09-16), the World ID 4.0
product/technical spec, WIP-103 and WIP-104, and the deployed `WorldIDRegistry` on World Chain.
Everything below marked **MEASURED** was read off that tree or the chain; everything marked
**UNMEASURED** was not, and each one names the check that settles it. §785 stands as stage 0 and
this does not reopen it.

## 0. The one-paragraph version

World ID 4.0 turned a World ID from a secret into an **account** in an on-chain registry with up to
48 authorized keys. Their definition of an Authenticator names "app, device, web client, or
service", their stated motivation is "no reliance on a single actor (such as a single Authenticator
provider, e.g. World App)", and `insertAuthenticator` has no whitelist — it takes a signature from
an authenticator already on the account. The registry is in production on World Chain (480). A
second authenticator gets the person's Orb credential by proving ownership of its `sub` to the
issuer and asking for re-issuance (WIP-103, "Re-issuance. Allowing the user to get a new copy").
So **Casberi can hold a key on somebody's World ID, and nobody at World has to say yes.** What is
still unknown is product, not protocol: whether World App exposes "add another authenticator"
today, and how a proof request travels from a relying party to a phone that is not World App.

## 1. What the protocol allows — MEASURED

| Fact | Where |
|---|---|
| A World ID is a leaf in `WorldIDRegistry`; the leaf commits to up to `NUM_KEYS = 7` BabyJubJub signing keys (WIP-103 §3.1); the bitmap allows 48 authenticators (WIP-104 §3.3) | `contracts/src/core/WorldIDRegistry.sol`, `docs/WIPs/wip-104.md` |
| `insertAuthenticator(leafIndex, newAddress, pubkeyId, newPubkey, oldCommitment, newCommitment, signature, nonce)` — no `onlyOwner`, no allowlist; the signature must recover to an address whose packed account data names this `leafIndex`; nonce is per-leaf | `WorldIDRegistry.sol:585–651` |
| `createAccount` is permissionless, fee-gated (ERC-20 registration fee) | `WorldIDRegistry.sol:450` |
| Production: registry proxy `0x0000000000aE079eB8a274cD51c0f44a9E4d67d4`, RP registry `0xD9A2…5BbC`, issuer-schema registry `0x9412…5d2c`, verifier `0x0000…8A25`; chain 480 | `contracts/deployments/core/production.json` |
| Two authenticator classes (WIP-104, **Final**): **Proving** — signing key only, cannot change account state, inserted with `address(0)`; **Admin** — signing key + secp256k1 management key. Insertion of either is authorized by an existing Admin | `docs/WIPs/wip-104.md` |
| Credentials are bound to the account (`sub = H(leafIndex, blindingFactor)`), not to an authenticator; "credentials could be authenticator-specific" is listed as a *future* change | spec §Technical Details; `crates/primitives/src/credential.rs:133` |
| Any authorized authenticator re-derives the blinding factor through the OPRF nodes: `generate_credential_blinding_factor(issuer_schema_id)` | `crates/authenticator/src/prove.rs:162` |
| WIP-103 Ownership Proof (**Last Call**): an authenticator proves to an issuer it owns a `sub` without revealing `leafIndex` or the blinder; use case 001 is issuer authentication for **re-issuance, renewal, deletion**; must be user-initiated | `docs/WIPs/wip-103.md`; `prove_credential_sub` in `prove.rs:481` |
| Reference client is a Rust crate: `Authenticator::init / register / init_or_register`, `insert_authenticator`, `prove`, `prove_credential_sub`; management ops go through a **gateway** that relays them on-chain (`POST /insert-authenticator`, `/create-account`, `/status/{id}` …) — the phone signs, the gateway pays | `crates/authenticator/src/*`, `services/gateway/src` |
| Services in production: indexer `indexer.{us,eu,ap}.id-infra.world.org` (inclusion proofs, `/packed-account`), gateway `gateway.id-infra.world.org`; requests can ride an **OHTTP relay** so the service never sees the phone | `README.md`, `crates/authenticator/src/ohttp.rs` |
| Proving: two Groth16 proofs per uniqueness proof (query → OPRF nodes, then nullifier), circom/arkworks; the ownership proof is Noir/ProveKit. Artifacts: `OPRFQuery.arks.zkey` 10.9 MB, `OPRFNullifier.arks.zkey` 25.4 MB, graphs 1.8 MB — ~38 MB embedded or fetched (`ZkArtifactSource`) | `circom/`, `crates/proof/src/artifacts/` |
| Mobile is in their own plan: `crates/zk-mobile-bench` builds a **uniffi** library for iOS (device matrix iPhone 14 / 16 Pro). **No results are committed** — `results/LATEST.md` is a placeholder | `crates/zk-mobile-bench/` |
| Authenticator attestation (WIP-106, code only, no doc yet): a P-256 "assertion key" attested with `SecLevel` (Secure Element / platform non-extractable / software), `Platform` (iOS), `UserPresence` (biometric, ≤7d, ≤30d) | `crates/proof/src/authenticator_attestation/mod.rs` |
| The reference `web-authenticator` repo holds a README and a `package.json` | github.com/worldcoin/web-authenticator |

Two protocol facts that shape the design:

- **The signing key is BabyJubJub EdDSA.** It cannot live in the Secure Enclave (P-256 only) —
  the same wall `FramesKey` documents for secp256k1. World's own spec says so: "Initial keys will
  have the same characteristics as the previous protocol version due to ZK proving limitations."
  So the signing key is a software key in the Keychain, device-only, `.biometryCurrentSet`, the
  `FramesKey` body — and the attestation says `SecLevel.software` about it, because that is true.
  The P-256 **assertion** key WIP-106 attests can be `FramesPasskey`'s Enclave key.
- **An authenticator learns the raw `leafIndex`** and the spec names that as the authenticator risk
  ("a malicious Authenticator can misuse this to track the user"). It is a secret in this app's
  terms: Keychain, never logged (`crates/authenticator` redacts it from `Debug`), never in a
  receipt, and the redaction audit gets a row.

## 2. What to build, in the order the dependencies run

### Stage 1 — this phone becomes an authenticator on the person's World ID

**What the person does.** In Casberi: *World ID → Add this phone*. Casberi mints a signing key,
shows what it is about to become (proving-only: "can prove you are human, cannot change your World
ID"), and hands the request to World App. In World App: approve. Back in Casberi: the row reads
*This phone · proving key · since today*.

**What actually happens.** Casberi generates the BabyJubJub key; builds the EIP-712
`INSERT_AUTHENTICATOR` message for the person's leaf (`pubkeyId`, new pubkey, old/new leaf
commitment — the commitment needs the current key set, from the indexer); the person's **Admin**
authenticator (World App) signs it; the signed operation goes to the gateway, which relays it
on-chain; Casberi polls `/status/{id}` and then `init`s.

**Then the credential.** Casberi derives the Orb credential's blinding factor via the OPRF nodes for
Tools for Humanity's `issuerSchemaId`, generates a WIP-103 ownership proof for the `sub`, and asks
the issuer for re-issuance. The credential lands on the phone: Keychain, device-only.

**Tier: Proving first (WIP-104), Admin later.** Smallest attack surface, no Ethereum key to hold,
and the honesty line writes itself. The spec is Final; **the reference crate has not implemented
the proving tier yet** (`Authenticator::init` requires an on-chain address, and nothing in
`crates/authenticator` mentions WIP-104) — UNMEASURED whether the deployed registry has the V2
bitmap. If it has not landed by build time, Stage 1 ships as Admin with the management key held
the `FramesKey` way, and the row says so.

**UNMEASURED, and these gate the stage:**

1. **Does World App expose "add an authenticator"?** Protocol yes; product unknown. Check in World
   App settings on a verified phone. If not, Stage 1 has no door and waits.
2. **How does the signed insertion get from World App to Casberi?** The management signature is
   made in World App; the operation is submitted by whoever holds it. Either World App submits to
   the gateway itself (then Casberi only needs to hand over its pubkey — a QR or a universal link)
   or it hands the signature back (a callback URL). Read World App's flow when (1) is answered.
3. **Tools for Humanity's re-issuance policy.** WIP-103 defines the proof; the issuer defines when
   it re-issues. The `faux-issuer` service (`POST /issue`) shows the shape, not the policy. If the
   Orb issuer will not re-issue to a second authenticator, Stage 1 yields a key with nothing to
   prove — the row must say "no credential on this phone" rather than imply one.
4. **How a proving-only authenticator learns its `leafIndex`.** `/packed-account` is keyed by
   address; a proving key has none. The indexer or gateway must answer by pubkey. Find the route
   or wait for the crate.

### Stage 2 — your World ID as things in the corpus

The cheapest stage and the most Casberi-shaped; it needs only Stage 1's leaf index.

- **Management events are things.** `AuthenticatorInserted`, `AuthenticatorRemoved`,
  `AccountRecovered`, `RecoveryAgentUpdate*` on the person's leaf land as `.event` rows in a
  **World ID** room: "A key was added to your World ID · 3 Sep". The spec makes this a
  requirement ("each user needs to be able to see account management events") and nobody ships
  it. It is also the one safety feature that matters: a key you did not add is the compromise
  notice, and it `standsAlone` in notifications (`NotifyKind`).
  Read through the OHTTP relay or the indexer, never a bare `eth_getLogs` with the leaf index in
  the topic to a public RPC (that is the tracking risk the spec names).
- **The credential's expiry is a deadline row.** `Credential` carries `genesis_issued_at` and an
  expiry; the row wears `dueAt` and rides the generic deadline path (`ENSName`'s ladder shape) —
  "Your Orb verification runs out in 40 days · renew in World App".
- **The room head** is `DSRoomChassis.Head`: the tier this phone holds, since when, the credential's
  state, the recovery agent's presence. No plate (§758), one footnote (§748).

### Stage 3 — this phone proves you are human to somebody else

The heavy stage, and the one with the open transport question.

- **Proving.** `world-id-core` (`authenticator`, `embed-zkeys` or fetched artifacts) built as an
  XCFramework through uniffi — the path their own bench already takes for iPhone. Two Groth16
  proofs plus an OPRF round trip per uniqueness proof. **Cost UNMEASURED**: their bench has no
  committed numbers. Run `cargo-mobench` on the user's iPhone before designing the wait; a proof
  that takes eight seconds is a sheet with a progress line, one that takes forty is a different
  product.
- **Request transport — SUPERSEDED 2026-09-16 (prd §787): IDKit 4.x now ships a 4.0 transport with a Swift SDK (`idkit-swift`), so the paragraph below is stale; proving still needs a key on the account first.** The earlier reading, kept for the record — **MEASURED 2026-09-16, and it said wait.** Today's IDKit is `@worldcoin/idkit-core`
  2.1.0 (`packages/core/src/bridge.ts`): the RP posts an AES-encrypted request to
  `https://bridge.worldcoin.org/request`, gets a `request_id`, and shows
  `https://world.org/verify?t=wld&i=<request_id>&k=<key>[&b=<bridge>]` — a universal link on World's
  domain, so it opens World App and nothing else can claim it on iOS. The URI does carry everything
  an authenticator needs (bridge, id, key), so a QR scanned by Casberi could serve the request
  through the bridge's app-side endpoints — but that half is unpublished (no `world-id-bridge` repo)
  and, more to the point, **the request is the 3.0 protocol**: `credential_types`,
  `verification_level`, a Semaphore `nullifier_hash`. A 4.0 authenticator holds no Semaphore secret
  and cannot answer it. The 4.0 `ProofRequest` (`crates/primitives/src/request`) is a schema with no
  published transport, and `idkit-js` has no 4.0 branch under any obvious name. Stage 3 waits for
  World to ship the 4.0 RP side; until then a proving key on this phone has nobody to prove to.
- **Attestation.** Every proof carries a WIP-106 token: `Platform.iOS`, `SecLevel` as it is (the
  signing key is software; the assertion key is Enclave), `UserPresence.biometric` when Face ID was
  asked for the signature. Casberi says what it is; it never claims a Secure Element it does not
  have.
- **Trusted RPs.** The RP registry lets an authenticator refuse a request from an unregistered
  party. Casberi verifies the RP's signature against `rpRegistry` before it draws anything.
- **The nullifier pool** for long-running actions: query before presenting (the crate does this).

### Stage 4 — the Safe is the Recovery Agent, and this phone is one of its signers

**MEASURED, and it reorders the plan.** The registry checks a recovery signature with
`SignatureChecker.isValidSignatureNow` — ERC-1271 — while every management op (insert, remove,
recovery-agent update) goes through `ECDSA.recover` and must come from an EOA
(`WorldIDRegistry.sol:275` vs `:760`). So:

- **A Safe cannot be an Admin Authenticator.** Only a key can add or remove keys.
- **A Safe can be the Recovery Agent.** Safe v1.4.1 has a canonical deployment on chain 480
  (`safe-deployments`, `networkAddresses["480"]`). A recovery is a `RecoverAccount(leafIndex,
  newAuthenticatorAddress, newPubkey, newCommitment, nonce)` signed by the Safe — N-of-M owners,
  collected asynchronously, submitted by anyone, no deadline in the message.
- **A management signature is a voucher.** `InsertAuthenticator(...)` carries a nonce and no
  expiry, so World App can sign an insertion once and Casberi can execute it later, as long as no
  other management op moved the nonce first. "Be there at the time" is the moment of signing, not
  the moment of execution.

**The product this makes.** Casberi already renders a Safe's queue, says who a transaction waits
on, and holds a co-signer key that can sign and never spend (§425, §652, `SafeRoomSource`,
`SafeSigner`, `SafeTransaction`). Point that at a Safe whose job is *recover my World ID* — owners:
the person's World App wallet, this phone's co-signer, a friend, a hardware key; threshold 2 — and
the existing Safe room becomes the World ID recovery console with no new signing machinery. The
sentence is **"Your World ID can be recovered by 2 of these 4, and this phone is one of them."**
No other app can say it, because no other app already holds a Safe co-signer and a Safe queue.

**What recovery does, stated plainly.** It installs ONE new authenticator and revokes every old one
(`recoverAccount`, spec §Recovery). It is not a way to add a key beside World App; it is what the
person reaches for when the phone with World App is gone. After it, World App is re-inserted by the
new admin (this phone), and credentials are re-requested through WIP-103 — the `sub` is unchanged
because the leaf is unchanged, so the ownership proof still works; the issuer's policy decides.

**Two ways in, and which one is permissionless.**

- *Path A — the World ID exists in World App first.* Designating a Recovery Agent is a management
  op: World App must sign `InitiateRecoveryAgentUpdate(leafIndex, newRecoveryAgent, nonce)`, then a
  delay runs (today initiate → cooldown → execute; WIP-102, Last Call, makes it immediate with a
  revert window). **UNMEASURED and likely the wall:** the spec says "Users may designate the PoH
  AMPC system as their Recovery Agent … In the future, other Recovery Agents are expected", which
  reads as World App offering one choice today. The contract takes any address; the UI may not.
- *Path B — Casberi creates the World ID.* `createAccount(recoveryAddress, authenticators, …)` is
  permissionless and takes the Recovery Agent **at creation, with no cooldown**. This phone is the
  first Admin key, the Safe is the Recovery Agent from block one, and World App is inserted later
  with a voucher this phone signs. Nothing here asks World for anything. **UNMEASURED and decisive:**
  whether the Orb issues a credential to an account World App did not create. Enrollment is out of
  scope for their own web authenticator, so assume no until an Orb visit with a Casberi-made leaf
  says otherwise.

**Build order inside the stage.** (1) `SafeBridge` learns World Chain — one row beside eth/base,
and the Safe Transaction Service host for 480, UNMEASURED; (2) the Safe room recognises a queued
`recoverAccount` to the registry and draws it as what it is — "recover a World ID, replacing every
key" — never as an opaque call; (3) the World ID row states the recovery agent, the threshold, and
whether this phone is an owner; (4) Path B's create flow, gated on the Orb question.

## 3. The keys, stated once

| Key | Curve | Where | Attested as |
|---|---|---|---|
| Signing (proofs, WIP-103) | BabyJubJub EdDSA | Keychain, device-only, `.biometryCurrentSet` (software — the Enclave cannot hold it) | `SecLevel.software` |
| Assertion (WIP-106 attestation) | P-256 | Secure Enclave (`FramesPasskey`'s key, or a sibling under its own service) | `SecLevel.secureElement` |
| Management (Stage 4) | secp256k1 | Keychain, device-only, `.biometryCurrentSet` (`FramesKey` body) | n/a |
| `leafIndex` | — | Keychain; never logged, never in a receipt, redaction-audit row | — |

## 4. Ship gates this trips (existing law)

- `NetworkReach`: indexer and gateway hosts, the OPRF node hosts (URLs UNMEASURED — the crate takes
  them from a config JSON; read production's), the OHTTP relay, the issuer. Each with one honest
  sentence. `network-reach-audit.sh` fails the build until they are there.
- `keychain-audit.py` / `secret-scan` / `redaction-coverage-audit.py`: three new secrets.
- A Foundation-only Swift wrapper over the uniffi types so `worldid-authenticator-selftest.sh` can
  compile the pure half; the Rust crate's own tests cover the proofs.
- `catalog-sync.sh`: **no new offer.** World ID stays off the catalogue (§515a) — the door is a row
  on the Wallet shelf's account page, not a seat.
- App size: +~40 MB of proving artifacts if embedded. Fetch on first use through
  `ZkArtifactSource` unless measured otherwise, and say so in Receipts.
- verify.sh: every stage lands with its probe (`-worldIDAuthProbe`) and its harness, per CLAUDE.md.

## 5. What is deliberately not built

- **Sign in with World ID** (OIDC) — declined in §785; nothing here changes the reason.
- **Being a relying party.** Casberi has nothing to gate. Session proofs for its own doors would be
  a proof shown to itself.
- **Hosting mini apps.** A different product; §785's reply stands.
- **Running an OPRF node, or being an Issuer.** Issuing PoH takes an Orb.

## 6. The first four measurements, in order

1. ~~World App on a verified phone: is there an *add authenticator* flow~~ — MEASURED NO (prd §787):
   no way to add keys or guardians, no recovery choice.
2. ~~`worldcoin/idkit` at v4~~ — MEASURED twice: IDKit 2.1.0 spoke the 3.0 bridge; by the evening of
   2026-09-16 IDKit 4.x ships a 4.0 transport (JS, Swift, Kotlin). Stage 3's transport gate is open.
3. `cargo-mobench` on an iPhone 17 Pro: query + nullifier proving time and peak memory.
4. Tools for Humanity's issuer: will it re-issue the Orb credential to a second authenticator on
   the same account, and through which endpoint.
5. World App's recovery-agent picker: an arbitrary address, or the AMPC only. If arbitrary, Stage 4
   Path A is open today and is the cheapest thing in this document.
6. An Orb visit with a leaf Casberi created (`createAccount`): does the credential issue. If yes,
   Path B needs nothing from World App at all.

Until (1) is a yes, nothing in Stage 1 draws in the app — §83 forbids a door that opens on nothing.
