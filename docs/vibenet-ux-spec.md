# Vibenet UX pass — spec

Goal: consumer-friendly, 100% technically accurate, stupid simple, visually rich.
Executor: implement in order; each item is independently shippable. Read the
"Rails" section before writing any code — every guard there is load-bearing.

Files in play:
- `Casberi/Casberi/Model/VibenetRoom.swift` — ALL new pure logic goes here (Foundation-only, compiled WHOLE by `scripts/vibenet-selftest.sh`; never import SwiftUI here)
- `Casberi/Casberi/Model/VibenetBridge.swift` — network + `VibenetWatch` store
- `Casberi/Casberi/Screens/VibenetRoomCard.swift` — the room card
- `Casberi/Casberi/Screens/VibenetScreen.swift` — setup/watch screen
- `scripts/vibenet-selftest.sh` — assertions + mutations for every new pure function
- `Casberi/Casberi/Design/WalletFace.swift` — REUSE, do not modify

---

## 0. Copy accuracy — "account-abstraction state" is the wrong noun (user ruling)

What this bridge reads is an address's KEYSTORE state — which keys can act
for it, and whether it's locked. "Account abstraction" is what vibenet the
DEVNET exists to test (EIP-8130, native AA), not a property an address has.
The catalog summary (`BridgeCatalog.swift:617`) already words this correctly
— use it as the model. Exact replacements, four sites:

1. `VibenetScreen.swift:42` — intro becomes (2 sentences, 42 words, inside
   the §315 budget):
   > "Base's experimental devnet for testing native account abstraction
   > (EIP-8130) — no real funds, and this only ever reads which keys can act
   > for a watched address and whether it's locked. Its contracts redeploy
   > often, so every read names the exact commit it saw."
2. `VibenetBridge.swift:239` — becomes:
   > "Reads which keys can act for a watched address — and whether it's
   > locked — on Base's vibenet devnet, where native account abstraction
   > (EIP-8130) is being tested."
3. `NetworkReach.swift:270` — `purpose` becomes:
   > "Reads a watched address's keystore state — is it established, which
   > keys can act for it, is it locked — from vibenet, Base's devnet for
   > testing native account abstraction (EIP-8130). Carries only the address
   > you watch; there is no account and no key, and nothing is ever signed
   > or sent."
4. Doc comments (`VibenetScreen.swift:4`, `VibenetRoom.swift:3`): replace
   "account-abstraction state" with "keystore state" in the same sentence
   shape. Nothing else in those comments changes.

Do NOT touch the catalog summary — it is already right.

## 1. Faces — accounts stop being bare hex

`WalletFace(address:size:circular:)` already draws a deterministic identicon
for any hex address (ENS-avatar overlay simply never resolves on devnet
addresses, which is the correct fallthrough — do not touch that file).

- Room card row: `WalletFace(address: item.address, size: 28, circular: true)`
  leading the row, before the address/subtitle VStack.
- Discovery rows on `VibenetScreen`: same face at `size: 24`.
- Card hero: a face-stack beside/above the headline — up to 5 watched faces,
  overlapped ~8pt (the house face-stack motif, see `StartFigureMark` /
  `AddressFlight` for the overlap idiom). Watched accounts ONLY — never the
  discovery strangers. Purely from `room.items`, no new data.

## 2. Names — optional local nicknames

`VibenetWatch` gains a names map:
- New persisted dictionary `[lowercased address: String]` under its own key
  `vibenet.watch.names.v1` — do NOT touch the existing address-list key
  (`vibenet.watch.addresses.v1`), so existing watch lists survive untouched.
- API: `name(for:)`, `setName(_:for:)` (empty string clears), pruned when an
  address is unwatched.
- Row title = nickname if set (in the current `.heading17`, NOT monospaced),
  with the short address dropping to a `label11` `textTertiary` monospaced
  line beneath. Unnamed rows unchanged.
- Context menu grows: "Name this account…" (alert with a text field),
  "Copy address" (`UIPasteboard.general.string = item.address` — a devnet
  address is not a secret; do NOT route through any scrubber), then the
  existing destructive "Stop watching".
- Names are display-only. They never leave the device, never land on a
  `Thing`, never appear in a log line.

## 3. Unlock runway — honest progress, or none

The one place a progress bar is HONEST here: both endpoints are known.
`VibenetAccountItem` already carries `unlocksAt: UInt64?` and
`unlockDelay: UInt16?` (seconds — the demo's 43_200 = 12h).

- New pure function on `VibenetAccountItem` in `VibenetRoom.swift`:

  ```swift
  /// 0…1 through the unlock timelock, or nil when EITHER endpoint is
  /// unknown — a bar with a guessed start is the fake status §83 bans.
  func unlockProgress(now: Date) -> Double?
  ```
  Rules: nil unless `hasInitiatedUnlock`, `unlocksAt` non-nil/non-zero, AND
  `unlockDelay` non-nil/non-zero. start = unlocksAt − unlockDelay. Clamp to
  0…1. Takes `now` as a parameter (house discipline — see `expiryLabel`).

- Draw: in the row, when `hasInitiatedUnlock`, under the existing countdown
  text — a thin capsule (height 4, full row width), track in
  `Self.mark.opacity(0.15)`, fill in `Self.mark`, corner radius 2. Drawn
  ONLY when `unlockProgress` returns non-nil; when nil the countdown text
  stands alone exactly as today. No animation on the fill (it moves on
  re-render; an appear animation would need the Reduce Motion check the
  design-motion audit enforces — skip it, static is fine).
- Harness: assert nil without delay, nil without initiation, 0.0 at start,
  1.0 at/after `unlocksAt`, ~0.5 midway. Mutation: break the clamp, break
  the delay-nil guard — both must go red.

## 4. Plain-words key identity

Flip the hierarchy from scheme-jargon to meaning — but ONLY where the claim
is certain. Add to `VibenetAuthenticatorKind` in `VibenetRoom.swift`:

```swift
var plainTitle: String   // what a person calls it
var plainDetail: String? // the technical name + one honest clause
```

Exact mapping (do not embellish — each line is the whole permissible claim):
- `.webAuthn`  → "Passkey" / "Face ID, Touch ID, or a security key — WebAuthn"
- `.delegate`  → "Another contract" / "a contract signs for this account"
- `.secp256k1` → "Wallet key" / "secp256k1 — the standard Ethereum key"
- `.p256`      → "P-256 key" / "the curve passkeys and secure enclaves use"
  (a claim about the CURVE, never about where this particular key lives)
- `.custom`    → "Custom authenticator" / nil (never guessed further)

Where drawn:
- `singleKeyLine`: title becomes `plainTitle` (semibold, as now), and
  `plainDetail` becomes a `label11` `textTertiary` line beneath it (above
  the scope sentence). Nil detail draws nothing.
- Matrix row name cells: keep `shortLabel` (width-constrained — do not
  change), EXCEPT `.secp256k1` may read "Wallet key" there if it measures
  ≤ the current "secp256k1" width; otherwise leave all as-is.
- Harness: pin all five `plainTitle`s and the `.custom` nil detail.
  Mutation: swap the webAuthn/delegate titles — must go red.

## 5. Discovery freshness

`VibenetDiscovery.recentAccounts` currently returns `[String]`. Change to:

```swift
struct VibenetDiscoveredAccount: Identifiable, Equatable {
    var id: String { address }
    let address: String
    let createdAt: Date?   // nil when the block-time lookup failed — omit, never guess
}
static func recentAccounts(keystore: String, limit: Int = 5) async -> [VibenetDiscoveredAccount]
```

- Resolve each row's `createdAt` via the existing `VibenetChain.blockTime`
  (≤5 lookups, already bounded by the cap; sequential is fine on a devnet).
- Screen row becomes: face (24) + short address + created-ago line
  ("Created 4m ago", `.relative(presentation: .named)`) in `label11`
  `textTertiary` — omitted entirely when `createdAt` is nil. "Watch" action
  unchanged.
- Update `VibenetScreen.discovered` state type + `loadDiscovery` to match.

## 6. Demo parity (required, not optional)

`VibenetRoom.demoFixture()` (~line 590) must exercise every visual above:
- at least one item with a non-nil `changeSequences` (currently none — the
  multichain footer line has never rendered in the demo),
- one actor with a future `expiry` (the expiry sub-label),
- the existing unlocking item keeps `unlockDelay` (runway shows),
- after item 2 ships: seed one nickname via `VibenetWatch` is NOT possible
  from the fixture (it's a live store) — instead the card takes names
  through a parameter or reads the store at draw time; demo naming is
  exercised by hand, note it in the fixture comment rather than faking it.

## 7. Deferred — do NOT build this round

- Per-account "last changed" line sourced from landed event `Thing`s: crosses
  SwiftData into a value-type card; wants its own pass.
- Any lifecycle stage-strip across all five states: the common state is
  "Active" and a five-segment strip on every row is chart junk; the pill +
  runway carry the story.
- Clipboard sniffing / paste chips on the watch field.

---

## Rails (violating any of these is a do-over)

1. Pure logic in `VibenetRoom.swift` only, Foundation-only, and EVERY new
   function gets harness assertions plus at least one mutation proving the
   harness can fail. Run `scripts/vibenet-selftest.sh` green before building.
2. Honesty (§83): no progress bar without both endpoints; no claim about
   where a P-256 key lives; discovery times omitted on a failed lookup;
   `.custom` never gets an invented name or icon.
3. Design law: `dsText` ramp only, sentence case, no `.kerning`, no hairline
   dividers, `DSHaptic` on taps, fixed-size matrix cells untouched.
4. §315 copy budget on `VibenetScreen`: no new slab notes, no new prose
   paragraphs — every new string sits ON a control or under a row.
5. No new hosts, no new `Thing` fields (so no CloudKit deploy), no changes
   to `NetworkReach`/`network-reach-audit.sh`.
6. All new user-facing strings via `String(localized:)`.
7. Verify: `xcodebuild` (iOS Simulator scheme Casberi) + `scripts/vibenet-selftest.sh`
   + `scripts/catalog-sync.sh` + `python3 scripts/demo-selftest.py` +
   `scripts/setup-copy-audit.py`. Do not run full `verify.sh` unless asked.
8. Commit style: one commit, imperative subject, body bullets per item.

---
---

# Round 2 — the visualization pass ("imagine Cash App")

Round 1 (items 0–6 above) SHIPPED in `5c20ce0f`. This round is the data
visualizations. The sensibility asked for is Cash App's: one bold color
doing all the work, numbers and moments as heroes with labels whispering
under them, chunky rounded shapes (fat dots, capsules, pills — never thin
ticks or hairlines), instantly legible before it is read. Playfulness lives
in SHAPE and WEIGHT only — never in the claim; every mark stays backed by a
real measurement (§83). The one color is `Self.mark` (Base blue) — no
second accent, no green/red, exactly as the card already does.

Same files as Round 1. Same rails (bottom of Round 1) — pure logic in
`VibenetRoom.swift`, every new function harness-asserted AND
mutation-proven, demo fixture exercises every new visual.

## R2.1 The key history strip (the big one)

The room already fetches every `ActorAuthorized`/`ActorRevoked` event to
compute the surviving roster — then throws the history away. Draw it: the
account's own story ("established in March, rotated keys twice, added a
passkey last week"), which no other surface can tell.

**A SEQUENCE STRIP, deliberately NOT a time-proportional axis.** Order is
EXACT (block, then logIndex — already how `survivors` sorts); positions
along a time axis would need every block's timestamp to be honest and a
degenerate span (several events in one block) has no honest layout. So:
chunky dots in chronological order, evenly spaced, oldest left — even
spacing claims ORDER, not elapsed time, and the two endpoint date labels
carry the actual clock.

- **Data plumbing** (`VibenetBridge.swift`): `VibenetRead.account` already
  holds the raw events; carry the newest `historyCap = 10` onto the item as
  `history: [VibenetKeyMoment]` (new trailing init param, `= []`, backward
  compatible). Resolve each DISTINCT block's time via the existing
  `VibenetChain.blockTime` (≤10 lookups, devnet-cheap; dedupe by block so
  several events in one block cost one read). A moment whose block-time
  lookup failed keeps `date: nil` — it still DRAWS (its order is exact
  regardless) but can never be an endpoint label.
- **New pure type** (`VibenetRoom.swift`):
  ```swift
  struct VibenetKeyMoment: Identifiable, Equatable {
      var id: String { "\(block):\(logIndex)" }
      let block: Int
      let logIndex: Int
      let authorized: Bool          // added vs revoked
      let kind: VibenetAuthenticatorKind?  // nil when unresolvable (a revoked key is not re-read)
      let date: Date?               // nil on a failed block-time lookup — never guessed
  }
  ```
  Plus `VibenetKeyHistory` (enum, pure):
  - `ordered(_:)` — by (block, logIndex), TOTAL (the card must never
    reshuffle between opens).
  - `summaryLine(_:)` — "3 keys added · 1 revoked" (each half omitted at
    zero; both zero → nil, and the strip doesn't draw at all).
  - `endpointLabels(_:now:)` — (oldest, newest) as short relative/absolute
    labels ("Mar 12", "2d ago" via `.relative(presentation: .named)` for
    anything inside ~30d, month-day beyond); nil for an endpoint whose
    date is nil. Newest label is OMITTED (not repeated) when it would
    equal the oldest.
- **Drawing** (`VibenetRoomCard.swift`, expanded view, between the
  matrix/single-key block and `footer`): the summary line in `.label12`
  semibold `textPrimary`, then the strip — 10pt dots, `Self.mark` filled
  for added, a 2.5pt `Self.mark` ring (clear center) for revoked, 8pt
  spacing, left-aligned with a `Spacer` (the matrix's own intrinsic-width
  rule). Endpoint labels in `.label11` `textTertiary` under the strip's
  first and last dots. More than `historyCap` events: a leading
  "+N earlier" in `.label11` `textTertiary` before the first dot.
  ≤1 moment total: don't draw the strip (one dot is not a story) — the
  summary line alone may still show.
- **Demo**: give `rich` a 4-moment history (two adds, a revoke, an add —
  dates computed RELATIVE to `Date.now` inside `demoFixture()`, e.g.
  −40d/−12d/−12d/−2d, so the labels never go stale; the fixture is
  composed live, not persisted, so a live clock is honest here) and
  `unlocking` a 1-moment history (exercises the no-strip floor).
- **Harness**: `ordered` totality; `summaryLine` singular/plural/zero
  halves; `endpointLabels` nil-date endpoint and same-label collapse;
  demo-fixture history coverage. **Mutations**: break `ordered`'s
  logIndex tiebreak; make `summaryLine` count revoked as added.

## R2.2 Urgency surfaces on the collapsed row

A key expiring in 3 hours is invisible until the row is expanded — the
collapsed subtitle says "3 keys". The time-critical fact must be the
visible one.

- **New pure function** (`VibenetAccountItem`):
  ```swift
  /// The row's own alarm clock — non-nil when a key's expiry is inside
  /// `urgencyWindow` (7 days) or already past. The soonest FUTURE expiry
  /// wins over already-expired (a ticking clock is actionable; a lapsed
  /// one is a standing fact): "Key expires in 3 hours" / "2 keys expired".
  func urgentLine(now: Date) -> String?
  ```
  Rules: `static let urgencyWindow: TimeInterval = 7 * 86_400`. Any actor
  with `0 < expiry` and `expiry` within the window and future → name the
  SOONEST, singular wording, relative format. None future-urgent but ≥1
  expired → count them ("1 key expired" / "N keys expired"). Else nil.
  `expiry == 0` never counts (Keystore's own "never expires").
- **Row precedence** (`VibenetRoomCard.row`): unlock countdown (existing,
  first — the pill beside it already says why) → `urgentLine` → `rowLine`.
  The urgent line draws `.label12` **semibold** in `Self.mark` — the one
  place the room's color carries urgency, honest because expiry is
  genuinely time-critical; never bold-white-on-blue (that's the pill's
  grammar, reserved for the lock alarm).
- **Demo**: one account's key gets `expiry = now + 3 days` (computed live
  in the fixture, same reasoning as R2.1's dates) — `lockedPlain`'s single
  key is the natural host; its far-future sibling on `rich` keeps the
  existing "future expiry" checks true.
- **Harness**: window boundary (8 days out → nil; 6 days → non-nil),
  soonest-future-wins over expired, expired-count plural, `expiry == 0`
  excluded. **Mutations**: flip the window comparison; make expired win
  over ticking.

## R2.3 Change-sequence chips, not a sentence

The single-chain footer sentence ("Only one EIP-8130 chain to compare —
nothing to sync yet") says nothing about THIS account. The counters are a
real reading of its config churn — show them as numbers.

- **New pure function** (`VibenetChangeSequences`):
  ```swift
  /// The footer chips: value + whisper label, Cash App grammar (number
  /// is the hero). Wording is the whole of the EIP's own meaning:
  /// `multichain` counts changes applied off the cross-chain channel,
  /// `localSequence` counts this chain's own changes this epoch.
  var chips: [(value: String, label: String)] {
      [("\(multichain)", "cross-chain changes"),
       ("\(localSequence)", "local, epoch \(localEpoch)")]
  }
  ```
- **Drawing** (`footer` in `VibenetRoomCard.swift`): replace the
  single-chain `VibenetMultichainSync.summary` text with the two chips —
  capsules, `Self.mark.opacity(0.12)` fill, `.padding(.horizontal, 8)
  .padding(.vertical, 3)`; inside each, the value `.label12` semibold
  `textPrimary` then the label `.label11` `textTertiary`, one line, no
  wrapping (`.fixedSize()`). Explorer link unchanged on the trailing edge.
  `changeSequences == nil` → no chips, exactly as the sentence today.
- **Ready-to-extend, NOT built**: when `VibenetChainStanding`s ≥ 2 exist
  (a second live 8130 chain), the chips yield to per-chain aligned bars —
  full track = the LEADING multichain count, each chain's fill
  proportional, lagging chains named via the existing `laggingChains`.
  `VibenetMultichainSync.summary`/`laggingChains` stay exactly as shipped
  for that day; do not delete them, do not build dormant bar UI now.
- **Harness**: pin both chip tuples exactly; zero values still render
  ("0" is a real reading, never hidden). **Mutation**: swap the two
  labels — must go red.

## R2.4 The lock badge on the hero faces

The face-stack says who's watched, not who's in trouble — the stack
should carry the alarm at a glance.

- `heroFaces` becomes `[(address: String, alarmed: Bool)]` off the same
  `room.items.prefix(5)`. An alarmed face wears a badge: 12pt circle,
  `Self.mark` fill, white `lock.fill` glyph at ~7pt, bottom-trailing
  offset, with the same 2pt `DS.surfaceSheet` stroke the faces already
  wear so it reads as part of the stack. One badge for both locked and
  unlocking (the alarm is the alarm; the row's pill already separates the
  two words). No badge for anything else — an unreached or unestablished
  account is not in trouble.
- No new pure logic (a direct read of `item.alarmed`), so no harness
  addition — but the DEMO already shows it for free (two alarmed
  fixtures) and `demo-selftest` needs nothing.

## R2.5 The matrix stays exactly as it is

Four iterations landed it. Its blank-denial/solid-grant design, fixed
42pt cells, plain-word columns and `byReach` rows are all measured
decisions — this round touches NOTHING inside `scopeMatrix` or `cell`.
Treat any diff there as a defect of this round.

## Round 2 rails (delta on Round 1's)

1. `VibenetKeyMoment`/`VibenetKeyHistory`/`urgentLine`/`chips` all live in
   `VibenetRoom.swift` (Foundation-only) — the strip/chips VIEWS read them
   dumbly.
2. The fixture may read `Date.now` ONLY inside `demoFixture()` (composed
   live, never persisted); everything else keeps taking `now` as a
   parameter.
3. The strip claims ORDER, never elapsed time — if a reviewer asks for
   time-proportional spacing, the answer is in R2.1's second paragraph.
4. Same verify list as Round 1 rail 7; same one-commit style.
