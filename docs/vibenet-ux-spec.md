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
