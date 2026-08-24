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

---
---

# Round 3 — kill the matrix, give accounts a real detail sheet

Rounds 1–2 shipped (`5c20ce0f`, `68344d32`, `61a9771a`). The user's verdict
on what remains: the permission matrix and the account detail experience
both suck. This round replaces them. **It explicitly SUPERSEDES Round 2's
R2.5 freeze** ("the matrix stays exactly as it is") — that rail protected
the matrix from incidental churn; this is its deliberate retirement.

Why they suck, named so the fixes aim at the right thing:
- The matrix demands AXIS LOOKUP: a solid block only means something after
  tracing up to a 9pt two-line column header. Six columns of 9pt text is
  spec-sheet density, the opposite of the Cash App grammar every other
  Round 2 element now speaks (number/word as hero, label whispering).
- The expand-in-place "detail view" crams every reading — matrix, expiry,
  history strip, chips, Explorer — into a card's width minus padding,
  which is exactly why the footer squeezed and the Explorer link wrapped.
  An account has earned a real surface.

## R3.1 Keys as worded chip rows (the matrix dies)

One component serves 1…N keys — the `singleKeyLine` / `scopeMatrix`
adaptive fork is DELETED, not extended.

- **New pure function** (`VibenetScope`, `VibenetRoom.swift`):
  ```swift
  /// The granted permissions as plain words, in `named` order — the chip
  /// row's whole content. A reserved bit this build can't name appends
  /// "+N unnamed" (never an invented permission, §83). Empty scope → [].
  var grantedPlainLabels: [String]
  ```
  Derive from the existing `named`/`plainLabels` tables — one source of
  truth, no second vocabulary. Harness: order matches `named`, unknown
  bits append the counted tail, empty scope yields empty. Mutation: drop
  the unknown tail — must go red.
- **The key row** (`VibenetRoomCard.swift`, new `keyRow(_ actor:)`):
  - Title line: `plainTitle` (`.label12` semibold) + `plainDetail`
    (`.label11` tertiary) beneath, exactly as `singleKeyLine` draws today.
  - Under it: the granted permissions as CHIPS — R2.3's exact capsule
    grammar (`Self.mark.opacity(0.12)` fill, `.label11`, `.lineLimit(1)
    .fixedSize()` per chip), laid out in the existing `FlowLayout`
    (`ThingSheetView.swift:2709`) so whole capsules wrap to the next line
    and text inside a capsule never does. "No scope" (empty grant) draws
    one plain-text line "Can't originate anything yet" in tertiary — a
    real state, not an empty chip row. The "+N unnamed" tail chip draws
    OUTLINED (stroke, no fill) — visibly a different claim.
  - Expiry: keep the existing conditional `expiryLabel` sub-line.
  - Rows in `byReach` order, unchanged.
- Reading one row now answers "what can this key do" with zero lookups,
  and cross-key comparison survives because every row uses the same words
  in the same order.
- `VibenetScope.plainLabels` and `shortLabel` stay (the harness pins
  them); `scopeMatrix`, `cell`, and `cellWidth` are deleted with their
  doc comments.

## R3.2 The account detail sheet (expand-in-place dies)

A row's tap stops toggling an inline disclosure and OPENS A SHEET — the
one-gesture rule holds (tap → sheet), the chevron flips from up/down to
`chevron.right`, and the card goes back to being a summary.

- **Presentation**: ONE `.sheet(item:)` on `VibenetScreen` (the house
  one-sheet rule), item = a small `Identifiable` wrapper on the address.
  The card gains `onOpen: (String) -> Void` beside `onRemove`/`onRename`;
  the row Button calls it. Detents `[.medium, .large]`,
  `dsSheetSurface` / the house sheet chrome (match `L2beatSheet`'s shape
  for a non-Thing sheet precedent).
- **The sheet resolves its item against `room.items`** (passed in, value
  types only — no Thing, no liveness class). Item vanished from a
  re-compose (unwatched elsewhere): dismiss, the `isLive`-sheet
  discipline without the SwiftData half.
- **Anatomy, top to bottom (Cash App: hero first, whisper labels)**:
  1. `WalletFace` at 56pt + nickname (or short address) as the hero title
     (`.heading22`); beneath it the FULL address, monospaced `.label11`
     tertiary, `.lineLimit(1)` middle-truncation is fine here (it's the
     one place the whole address appears; Copy handles precision).
  2. The state, as one sentence — reuse the row's own precedence verbatim:
     unlock countdown + full-width runway, else `urgentLine`, else
     `rowLine`. The Locked/Unlocking pill rides the hero row's trailing
     edge.
  3. "Keys" section: `keyRow` per actor (R3.1), `byReach` order.
  4. "History": the R2.1 summary line + dot strip + endpoint labels,
     moved here unchanged.
  5. The R2.3 sync chips — full width now, no ScrollView squeeze needed,
     but keep the ScrollView anyway (large Dynamic Type).
  6. Doors: "Explorer" `Link` (existing URL builder) and "Copy address"
     as visible buttons — a sheet earns visible verbs where a row only
     had a context menu. "Name this account…" and destructive "Stop
     watching" stay in an ellipsis menu on the hero row (stop-watching
     also dismisses).
- **The card's row after this**: face + title/subtitle + pill +
  `chevron.right`. The expanded-content block, `expanded: Set<String>`
  state, `keyHistoryStrip`, and `footer` all MOVE to the sheet file or
  delete. New file: `Casberi/Casberi/Screens/VibenetAccountSheet.swift`
  (synced folder — no pbxproj edit).
- **Context menu on the row stays** (name/copy/stop watching) — menu and
  sheet duplicating verbs is fine; the menu is the shortcut, the sheet is
  the surface.

## Round 3 rails

1. Pure logic (`grantedPlainLabels`) in `VibenetRoom.swift`, harness
   assertions + the mutation above. The DELETED matrix's harness lines
   (`plainLabels` pinning etc.) stay — the vocabulary survives, only the
   drawing dies.
2. No new `Thing` fields, no new hosts, no `NetworkReach` change. The
   sheet is value-types-only — none of the SwiftData liveness corollaries
   apply, and say so in its header doc.
3. Every text element: `.lineLimit(1)` + `.fixedSize()` for short labels,
   FlowLayout for chip collections — nothing wraps mid-word, nothing
   truncates silently except the hero address (deliberate, stated above).
4. Demo parity: the existing fixture already exercises every sheet
   section (multi-key roster incl. unknown scope, expiry, unlock runway,
   history, chips). No fixture change expected; verify by opening the
   sheet on each demo account in the sim.
5. Verify: build + `scripts/vibenet-selftest.sh` +
   `python3 scripts/demo-selftest.py` + `python3 scripts/setup-copy-audit.py`.
   Full `verify.sh` stays off unless asked. Shipping is ON HOLD until the
   user says go.

---
---

# Round 4 — the room itself

Rounds 1–3 shipped (409 iOS / 410 Mac). Every one of them improved the
SETUP SCREEN. Nobody had looked at what the room does when you tap the
chip, and the answer is: almost nothing. Alex found it in a minute of
use. Three findings, one root cause, plus a copy pass.

**The root cause: `Base Vibenet` appears NOWHERE in `FeedScreen.swift`.**
No `Shape` case, no `sourceHead` case. So the room falls to `.plain` and
draws generic `BandRow`s — one identical blue glyph per row, an 80-char
clamped title, a timestamp — with no head above them. This is the exact
defect this file's own neighbours document five times over (Files §283,
X §313, x402 §319, Instagram §395, Telegram §456); the comments beside
the switch literally describe it. Vibenet shipped straight into it.

## R4.1 The room gets its head

`VibenetRoomCard` — faces, headline, ranked accounts — exists and is
drawn on ONE screen: the setup screen, which you visit once. The room
you actually live in has no head at all.

- `FeedScreen.sourceHead` gains `case VibenetIdentity.source`, drawing
  the same card. It is already value-types-only and already composes
  from `VibenetRoomSource`, so this is a wiring change, not a new view.
- The card needs the room's composed `VibenetRoom`. Every other head
  here resolves its own state (`CursorRoomSource.compose()` etc.) — do
  the same: a small `@State` on the head's container, loaded in `.task`,
  never on every body pass.
- **`verify.sh`'s room-head coverage step is a hand-maintained map** —
  add the `case` name and its source string there in the SAME commit, or
  the check silently stops covering the room it was extended for.

## R4.2 Rows lead with WHO, not what

Alex: *"i can't see which accounts they are from… should it identify the
address first more like the others."* Yes — and every other identity
room in this app already does. A row today is one blue square for every
account, and the only identifying mark is a truncated `…f21f` at the END
of a sentence, in the same weight as the rest of it. Two accounts'
events are indistinguishable at a glance, which is the whole job of a
room you scan.

- **New `Shape` case `.vibenet`** (its own, not `.wallet` — that room's
  rows are money and its head is a balance; a key authorization is
  neither).
- The row: `WalletFace(address:)` leading, then the account's nickname
  or short address as the row's title, then the event as the line
  beneath. Same anatomy as every person/account row in the app.
- **The address must land somewhere the row can read.** It is currently
  recoverable only by parsing it back out of the title, which is the
  thing `MoneyReceipt`'s own doc forbids. Stamp it on `authorHandle` at
  landing (an existing deployed field — **no CloudKit deploy**), and
  `healEvents` it onto rows that predate this, the `XArchiveImport
  .healLinks` shape, since both facts are already on the row.
- **Two strings, not one renamed.** `title` stays whole and
  self-contained ("New passkey authorized for …f21f") because it is what
  the All feed, search, Spotlight and notifications show, where no face
  is present. The row uses a new `VibenetEventKind.phrase(keyLabel:)`
  — "New passkey authorized", no address — because in the room the face
  and name already said who. Printing both is §366's "read its first
  line twice" bug.
- Harness: `phrase` asserted for all three kinds and both keyLabel
  cases, plus a mutation proving `phrase` never carries the address.

## R4.3 The face question

Alex: *"i don't have a face for a vibenet account."*

- In the ROOM: fixed by R4.2 — every row gets its face.
- In the WALLET FACE RAIL: deliberately NOT. That rail is watched
  wallets (`WalletStore`), and a devnet test account is not one; putting
  it there would claim it holds your money, which is the same false
  claim the `.transaction` bug made in a different place. The chip
  belongs in the Wallet *category* (it is an address you watch); the
  face rail is about balances.

## R4.4 Copy: the product page and setup screen are verbose

Measured against their neighbours: the catalog summary is **41 words in
two paragraphs** where Linear's is 24 and one; the setup intro is **45
words** in a §315 budget of "one intro sentence". Both say the same
three things twice — no funds, read-only, contracts redeploy.

- Catalog summary → one paragraph, ≤25 words. The tagline already says
  "Watch an account on Base's devnet"; the summary should add what the
  devnet IS and stop.
  > "Base's experimental devnet for native account abstraction
  > (EIP-8130). No real funds, no account, no key — it only ever reads."
- Setup intro → ≤22 words, one sentence. Drop the redeploy clause: the
  card's own provenance line already names the exact commit under every
  read, which is that fact shown rather than promised.
  > "Watch any account on Base's EIP-8130 devnet — which keys can act
  > for it, and whether it's locked."
- `setup-copy-audit.py` must stay clean; run it, don't assume.

## Round 4 rails

1. Pure logic (`phrase`) in `VibenetRoom.swift`, harness-asserted and
   mutation-proven. No new `Thing` field, no new host, no CloudKit
   deploy.
2. `demo-selftest.py` check F reads the `Shape` switch to prove every
   shape has a seeded source — the demo seeds vibenet as a LANDLESS seat
   today, so adding `.vibenet` means seeding demo event rows too, or the
   check fails. Seed them; a room nobody can see in the demo is the gap
   that check exists to catch.
3. Verify: build + `vibenet-selftest.sh` + `demo-selftest.py` +
   `setup-copy-audit.py`. Ship only when Alex says.
