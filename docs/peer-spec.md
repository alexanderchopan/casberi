# Peer: cash out and add cash — a proposal for a Mac session to explore

**Status: PROPOSED, NOT RULED.** Nothing here is law yet. The Mac session
measures, mocks, and brings the user a ruling to approve; the ruling goes in
`docs/prd.md` first (then `python3 scripts/law-digest.py`), and only then is
anything built.

Written 2026-10-29 in a cloud session that could read the code and Peer's
published npm packages, but could not build, run a simulator, or reach
`docs.peer.xyz` (outside the session's network allowlist). Every Casberi file
and symbol below was read; nothing was compiled. Where this spec and the code
disagree, the code wins: say so, then follow it.

Read first: `CLAUDE.md`, `docs/law.md` (Wallet, Move, Signing), prd §113,
§207, §1048f (Peer today), §1473 (Buy, the nearest precedent: a third party's
door the account pays through), §1540/§1544 (an SDK in a hidden web view),
§1438 and §1501 (Move's sentence), §1547 (verb order), §1576 (Take it back),
§154 (what was declined and why).

## Why

A new account starts at $0, and since §1484 Receive has no exchange door. A
person with dollars in Venmo has no way in, and a person with USDC has no way
out to their bank. Peer (peer.xyz, formerly ZKP2P) is the one ramp that fits
§1538's rule (open, no gatekeeper, no custody): a person-to-person market on
Base whose escrow is a contract and whose proof of a fiat payment is checked
by an attestation service, not a company holding the money.

## How Peer works (from its SDK READMEs, read 2026-10-29)

- **Add cash (the taker / buyer).** You signal an intent against a seller's
  deposit (the contract reserves their USDC for you), pay the seller in
  Venmo, Cash App, Zelle, Revolut, Wise, PayPal, Monzo, Chime, …, then prove
  that payment. On a phone the proof is a sign-in to the payment app inside a
  web view; the SDK captures the session material, encrypts it to Peer's
  attestation service (a TEE, "buyer TEE"), and `fulfillIntent` puts the
  attestation on chain, which releases the USDC to you.
- **Cash out (the maker / seller).** You put USDC in Peer's escrow as a
  deposit naming your payment handle. A buyer pays you fiat and proves it;
  the contract releases your USDC to them. Your side is one deposit
  transaction (plus, for Venmo and PayPal, one access-policy transaction), and
  `withdraw` takes back whatever is unfilled.

Packages (npm, latest on 2026-10-29):

| Package | Version | What it is |
|---|---|---|
| `@zkp2p/cash` | 0.7.3 (2026-10-13) | Offramp only. Verbs: `estimate`, `capabilities`, `fillStats`, `prepare` / `finalizePreparedCashout` / `prepareAccessPolicy`, `order`, `orders`, `watch`, `withdraw`, `topUp`. No API key. Base USDC is the only destination. |
| `@zkp2p/sdk` | 0.14.11 (2026-10-26) | The whole protocol: quotes, `signalIntent`, `fulfillIntent`, deposits, referrals. "No external API key is required." New intents go through EscrowV2 / OrchestratorV3. |
| `@zkp2p/zkp2p-react-native-sdk` | 0.5.1 (2026-10-02) | The phone's proof flow: `initiate`, `authenticate`, `prepareBuyerTeeProof`, `fulfillIntent`, built on `react-native-webview` and a cookie manager. Provider templates come from `https://api.zkp2p.xyz/providers/`. |

Facts that shape the design:

- Venmo and PayPal cash-outs need a second transaction (the Peer Pay merchant
  access policy) that needs the deposit id from the first receipt. Never
  create a second cash-out if it fails: prepare the policy again.
- A NEW Wise or PayPal payee needs an identity attestation from Peer's
  browser extension, which a phone cannot run. On the phone: Venmo, Cash App,
  Zelle, Revolut, X Money, UPI.
- The cash-out rate is bound when a buyer signals (Base oracle, zero spread);
  any estimate before that is "≈".
- `fillStats()` gives 30-day fill counts and median time to first fill per
  `platform:currency`. Peer suggests offering a pair only at
  `fills >= 10 && medianFillSeconds <= 48h`.
- A referral code stamped on a deposit pays its owner 50 bps of what fills
  (ERC-8021 attribution, no key, no registration).
- **Trust gap:** `@zkp2p/cash` depends on `@zkp2p/sdk`, which its README
  says "currently ships from private source" (the npm tarball is published,
  the repository is not). This is the §1538 question; the user rules on it.

## What Casberi has today

- `Casberi/Casberi/Model/PeerBridge.swift` reads Peer fills for watched
  wallets off Base (Orchestrator, V2 and V3; payment-method and currency hash
  tables), lands buys ("Bought 25 USDC with Venmo on Peer") and sales, and a
  sale whose buyer fell through. Read-only by §113; automatic since §207.
- `PeerRoom.swift`, `PeerRoomSource.swift`: the room head, folded into the
  Wallet (§1048); settling sales are dated items in Coming up (§1048f).
- `NetworkReach` has one Peer endpoint (`service: "Peer"`, Base's chain).
- Move: `Screens/MoveSentence.swift` (`enum Verb { swap, send, receive, buy,
  sweep }`), `MoveScreen.swift`, `MoveDetails.swift`; checks in
  `Model/MoveChecks.swift` and `Model/MoveWarnings.swift`.
- The engine precedent: `Model/PrivacyEngine.swift` (+ `PrivacyEngineQueue`,
  `PrivacyEngineWire`) runs 0xBow's TypeScript SDK in a hidden `WKWebView`
  from `Resources/privacy-engine.js`, built reproducibly by
  `tools/privacy-pools-engine`; every request the page makes is handed to
  Swift and sent only to declared hosts, through Tor where it names a wallet.
- The Bitrefill precedent: `Model/BitrefillBuy.swift`, `BitrefillX402.swift`
  (§1473): a third party's door, the account signs, the seat stays read-only.

## The proposal, in phases

Each phase ends the repo's way: build through `scripts/xcb.sh`,
`scripts/verify.sh` green, simulator screenshots with the demo
(`-demoEnter YES`) and a real account where it can be had, `/code-review` on
the diff, a prd entry marked BUILT with how it was seen, then the user.
**UI is shown as a canvas before it is built** (`design/mockups/`).

### Phase 0 — measure (no UI)

Answer these before mocking anything, with the smallest real money possible
(the user does not want to spend more than a few dollars):

1. **Can our account deposit?** The account is a Safe with a Secure Enclave
   owner. `createDeposit` is a plain call from the Safe, so it should work,
   but confirm `cash.prepare()`'s `txs[]` simulate and execute as one Safe
   batch (approve + createDeposit) for $1 of USDC on Base, and that
   `order(depositId)` then reads it. Then `withdraw()` it back.
2. **The Venmo second transaction** from a Safe: `finalizePreparedCashout` on
   our receipt, then `prepareAccessPolicy`.
3. **Payee registration** for a Venmo handle: does the curator call need a
   signature from the depositor, and does it accept a Safe (ERC-1271)?
4. **Fill times for small orders:** `fillStats()` for `venmo:USD`,
   `cashapp:USD`, `zelle:USD`, `revolut:EUR+GBP+USD`. If $20–$100 orders sit
   for days, cash out is not worth a verb.
5. **Tor:** do `api.zkp2p.xyz` (curator, provider templates),
   `indexer.zkp2p.xyz` and `attestation.zkp2p.xyz` answer through Tor
   (§1495)? A host that refuses every exit goes in `refusesTor` and Move's
   foot says "not through Tor" (§1512's rule).
6. **The handoff link** for add cash: read `docs.peer.xyz`'s onramp page
   (blocked in the cloud) for the URL and its parameters (recipient address,
   amount, token, chain, return URL). Confirm it opens in the in-app Safari
   sheet (§653) and that the USDC lands in the account.
7. **The buyer side, on paper:** the intent's reservation window, whether a
   taker needs Peer's stake ("Taker staking" in the SDK), and what the
   proof needs from the phone (read the React Native SDK's source in its npm
   tarball: the provider template, what is intercepted, what is sent).

Hooks to add for the measurements, DEBUG only: `-peerCashProbe
estimate|caps|stats|prepare:<amount>|order:<id>|withdraw:<id>` logging
`peerCash|` lines, the `-bitrefillPayProbe` shape.

### Phase 1 — Cash out (Move's sixth verb)

**Verbs.** Move's verbs read A–Z (§1547): Buy · Cash out · Receive · Send ·
Swap · Sweep; Move still opens on Swap. Cash out is drawn only when the phone
holds an account (§83, as Buy).

**The sentence.**

> Cash out **$100** / to **Venmo** **handle** / from **USDC on Base**.

- **$100** — Send's slider and keypad. Under it, grey: "≈ $100.00 to you ·
  usually paid within 2 hours" (the "≈" because the rate is bound when a
  buyer signals; the time from `fillStats()`).
- **Venmo** — opens the choices glass (§1442b): Venmo, Cash App, Zelle,
  Revolut, X Money, UPI, each with its mark. A pair under Peer's bar is
  dimmed with its reason.
- **handle** — a search row for "@you". The curator checks the handle before
  anything moves; a wrong one is one line ("Venmo doesn't know @yuo") and no
  deposit is written. A handle used before comes back.
- **from** — your USDC networks. Ethereum or Robinhood Chain adds the Across
  crossing to Base (§1555) to the same move; Peer's own Relay source routing
  is not used.

**The foot.** "Through Peer · no fee to you · paid by a person, not a
company". Details, one line a row (§1510): "Approves · 100 USDC to Peer",
"Deposits · 100 USDC for Venmo @you". Simulated before Face ID, as every
move.

**Signing.** One Face ID for Cash App, Zelle, Revolut, X Money, UPI. Venmo
and PayPal: the tray holds after the first (§1586) and says "One more to
finish: limits buyers to Peer Pay", then a second Face ID. If the second is
refused, the tray offers Finish, never a second Cash out.

**The receipt.** "Waiting for a buyer · $100 to Venmo @you". The tray can
close.

**While it waits.** One Activity row, amber: "Cashing out $100 to Venmo".
- A buyer signals: "Matched · a buyer is paying you"; a notification,
  "Someone is sending you $100 on Venmo" (Wallet switch, §1237).
- The dollars arrive in Venmo from a stranger. The row's sheet says it once:
  "The payment comes from a person. Don't send it back."
- The buyer proves: "Cashed out $100 to Venmo · paid $100.00", the matched
  rate in Details.
- A partial fill: "$60 of $100 paid"; the rest keeps waiting.

**No buyer.** Past the pair's median fill time, a Needs you row: "$100 still
waiting for a buyer on Venmo". **Take it back** (`withdraw()`, one Face ID)
is on the row's sheet from the start, as §1576 ruled for Privacy Pools.

**Where it reads from.** `PeerBridge` already lands sales; the Mac session
decides whether the order's state (`order(depositId)`, `watch`) is read
through the engine or by extending `PeerBridge`'s own chain reads. Prefer one
reader for one fact (§837).

**Revenue.** Stamp Casberi's Peer referral code on every deposit (50 bps of
what fills). The user decides whether to, and the foot does not mention it
unless the user rules it should.

### Phase 2a — Add cash, by handoff

1. Receive gets one line under the address: "Add cash with Venmo, Cash App, …".
2. A tap opens Peer in the in-app Safari sheet (§653) with the account's
   address as the recipient (the link from Phase 0 item 6).
3. Back in Casberi, `PeerBridge` lands the fill: "Bought 100 USDC with Venmo
   on Peer", and money arriving says it (§1587).

This amends §1484 ("Receive has no exchange door"): Peer is not an exchange
and the line pays into the account, but the user rules it.

### Phase 2b — Add cash, in the app (only if 2a is not enough)

**The sentence.**

> Add **$100** / with **Venmo** / as **USDC on Base**.

Under it: "≈ 99.40 USDC · from one seller" (the best quote).

1. **Add** — one Face ID signs the intent; the seller's USDC is reserved.
2. **Pay** — "Pay **@seller** **$100** on Venmo." **Open Venmo** opens the
   payment filled in (the SDK's `initialAction`). A countdown shows the
   reservation's time left.
3. **Prove** — "Did you pay? Prove it". The first time, Venmo's sign-in in the
   tray; the session is kept (device-only Keychain, never synced: §277).
   Your recent Venmo payments are listed; tap the one to @seller. A progress
   line while the attestation runs: "Checking with Venmo…".
4. **Claim** — one Face ID puts the proof on chain: "Added 99.40 USDC with
   Venmo".

Failure paths:
- The reservation runs out before you pay: "Time ran out; nothing was taken."
- You paid and the proof failed: a Needs you row, "Your $100 Venmo payment
  isn't proven yet", with **Prove again**; the sheet keeps the payment, the
  seller and the time left.
- You paid after the reservation ran out: the sheet names the seller and the
  payment and says the dollars are with them. Casberi cannot undo it; say so.

Build cost: port the React Native SDK's proof flow to Swift (`WKWebView`
sign-in, template-driven capture, encryption to the attestation service), or
run it in the engine's web view. Weeks, and it must be seen on a phone with
real money. App Review: Peer's own iOS app signs into Venmo in a web view;
read its listing and Guideline 5.1.1 before building.

## Hosts (`Model/NetworkReach.swift`, a ship gate)

Candidates, to confirm in Phase 0: `api.zkp2p.xyz` (curator, quotes, payee
registration, provider templates), `indexer.zkp2p.xyz` (order history),
`attestation.zkp2p.xyz` (Phase 2b only), `app.peer.xyz` / `peer.xyz` (the
handoff page, opened in Safari, not fetched). Each names its service and
`.whenConnected` per §1163; a wallet-naming request goes through Tor
(§1495). Chain reads go through the account's own node (§1517) where set.

## Rulings this touches (the user rules each)

- **§113 / §207** — the Peer seat reads and never acts. Cash out and Add are
  the ACCOUNT's acts, the way §1473 amended §103 for Bitrefill; the seat stays
  read-only.
- **§154** — declined Venmo / Cash App split links (an identity problem, no
  API). Peer is a different mechanism; the new ruling says so.
- **§1484** — Receive has no exchange door (Phase 2a).
- **§1538** — open source, no gatekeeper: Peer's SDK core ships from private
  source, and the curator can refuse a handle or an intent.
- **§1495 / §1512** — Tor, and the foot's "not through Tor" if a host refuses.
- **§1402** — the Mac half: the Mac holds no account key, so neither verb is
  drawn there (as Buy, §1473 item 10). State it in the ruling.
- **§83** — the "≈", the fill-time wording ("usually", from data, never a
  promise), and no "Paid" until the chain says so.

## Questions for the user

1. Cash out first, or add cash first?
2. The verb's word: "Cash out", or Send with a payment app as a recipient?
3. Is a private-source SDK core acceptable under §1538, or is a Swift port of
   the deposit and withdraw calls (two contracts, no proof) the price?
4. Stamp Casberi's referral code?
5. Phase 2a's line on Receive: allowed, given §1484?

## Not in scope

Selling as a business (vaults, rate managers, delegation), Wise and PayPal
new payees (need the extension), Peer's staking, disputes, and any
non-Base destination.

## Sources

- `@zkp2p/cash` README (npm, 0.7.3) — https://www.npmjs.com/package/@zkp2p/cash
- `@zkp2p/sdk` README (npm, 0.14.11) — https://www.npmjs.com/package/@zkp2p/sdk
- `@zkp2p/zkp2p-react-native-sdk` README (npm, 0.5.1) — https://www.npmjs.com/package/@zkp2p/zkp2p-react-native-sdk
- Onramp integration (not read: blocked in the cloud) — https://docs.peer.xyz/developer/integrate-zkp2p/integrate-redirect-onramp
- Peer Cash — https://peer.xyz/cash-sdk
- The archived client SDK — https://github.com/zkp2p/zkp2p-client-sdk

## Prompt for the Mac session

> Read `docs/peer-spec.md` and the files it lists under "Read first". Do
> Phase 0 only: answer its seven questions with the smallest real money the
> user approves (ask before spending), add the `-peerCashProbe` hook, and
> record what you measured. Then draw a canvas in `design/mockups/` for
> Phase 1 (the sentence, the foot, Details, the receipt, the Activity row in
> each state, the Needs you sheet) and bring the user the five questions at
> the end of the spec with your measurements beside them. Do not write a prd
> ruling or build Move UI until the user has answered.
