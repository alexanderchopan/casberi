# One Address Book — Wallet + Vibenet unification spec

Status: SPEC, not yet built. Written 2026-08-27 for implementation by a separate session.
Owner ruling to record in prd as a new § entry (see "PRD + docs" below): this AMENDS §465's
"the structure is copied, never the type" — the **data layer** is now shared; the screens
stay separate types. It also amends §472's last-account confirm copy (names no longer die
with the seat).

## What the user asked for (verbatim intent)

1. **One address book** backing both the Wallet room and the Vibenet room — the same
   entries visible from both, even though each room keeps its own screen.
2. **"Key" as an address type** — a vibenet authorized key (and, structurally, any future
   signer key) can be filed in the book as its own kind.
3. **A `note` field on every entry** — free text the person writes.
4. **Provenance/network denotation** — a row must say where it's from ("Vibenet" vs
   mainnet), so the two populations can share one list without ambiguity.

This is a data-model + migration change with UI riders. **No `Thing` changes, no SwiftData,
no CloudKit schema deploy** — the book is UserDefaults + the `KeyValueMirror` iCloud
mirror, and stays that way.

## Current state (read these files first)

| Concern | Wallet side | Vibenet side |
|---|---|---|
| Names ledger | `Model/AddressBook.swift` (`AddressBook`, singleton, UserDefaults `wallet.addressBook.v1`, iCloud-mirrored via `Model/AddressBookSync.swift` → `KeyValueMirror`) | `VibenetWatch.names` dictionary (`Model/VibenetBridge.swift`, UserDefaults `vibenet.watch.names.v1`, device-local, **not synced**) |
| Watch list | `WalletStore` (cap 5) | `VibenetWatch.addresses` (`vibenet.watch.addresses.v1`, uncapped — devnet reads are free) |
| Book screen | `Screens/AddressBookScreen.swift` (+ `AddressBookViews`, `AddressGroupViews`, `AddressIndexBar`, `AddressFlight`, `NameAddressPrompt`) | `Screens/VibenetAddressBookScreen.swift` (roster + rename alert writing `VibenetWatch.setName`) |
| Kind detection | `Model/AddressKind.swift` — Safe service + `eth_getCode` across five **mainnet** chains | none |
| Keys | n/a | `VibenetActor` in `Model/VibenetRoom.swift` (`actorId`, `authenticator`, `kind: VibenetAuthenticatorKind`, `scope`, `expiry`); sheets `VibenetKeySheet` / `VibenetKeyTraySheet` |
| Harness | `scripts/address-book-selftest.sh` (compiles `AddressBookShape.swift` whole; drift guards grep `AddressBook.swift`/`AddressActivity.swift`) | `scripts/vibenet-selftest.sh` |

Key doctrine that MUST survive (from `AddressBook`'s own header): **naming is free and
outlives every watch; watching is a separate act.** The unification applies that doctrine
to vibenet — today vibenet names are destroyed on disconnect, which the book's own header
calls the original sin this store was built to end.

---

## Architecture decisions (settled — don't re-litigate during implementation)

### D1. One store. `VibenetWatch` keeps the watch list, loses the names.
`AddressBook` stays the single ledger. `VibenetWatch.addresses` (which accounts are
watched on the devnet) stays exactly where it is — a watch is not a name, same split as
`WalletStore` vs `AddressBook`. `VibenetWatch.name(for:)` / `setName(_:for:)` become
thin delegates to `AddressBook.shared` (kept as call sites so `VibenetRoomCard`,
`VibenetAccountSheet`, etc. don't all need rewiring; their doc comments must say they
delegate). The `vibenet.watch.names.v1` storage key is migrated once and **left on disk**
(downgrade safety — the same rule `AddressBook.migrateIfNeeded` follows).

### D2. Identity stays the address. Network is a TAG, not part of the key.
`AddressBook.key(for:)` is unchanged. The same hex on vibenet and mainnet is the same
keyholder and folds into one entry — that is correct, not a collision to prevent (an EVM
address is a keypair, not a chain-scoped account). A composite network+address key would
break `KeyValueMirror`'s stored keys, the alias reconcile, and every existing book in
iCloud; refused.

New field:

```swift
/// Where this address has been MET — "vibenet" for Base's devnet; absent
/// means the mainnet family (every pre-existing entry). A fill-in UNION like
/// `groups`, never an overwrite: an address watched on vibenet and later met
/// on mainnet carries both tags. Optional for the Codable reason `groups`
/// documents.
var networks: [String]? = nil
```

- Constants: add `enum AddressNetwork { static let vibenet = "vibenet" }` (in
  `AddressBook.swift` or a small sibling) — one spelling, greppable.
- Helper: `Entry.isDevnetOnly: Bool` — true when `networks` is non-empty and every tag is
  a devnet (today: `== ["vibenet"]`). This is the gate D4 uses.
- Merge rules: alias merge (`AddressBook.merging`) UNIONs networks (same code shape as
  groups); `newer(_:than:)` unchanged (whole-entry newest-stamp wins — acceptable, the
  winner was written after the loser learned its tags on the same device path).
- Writers: `setName` gains `networks: [String]? = nil` fill-in parameter (union, never
  erase — same rule as provenance). Add `func addNetwork(_ tag: String, for address: String)`
  for the migration and the vibenet watch door.

### D3. `Kind.key` is a new case, asserted by context, never detected.
```swift
case key   // an address that signs FOR an account — a vibenet authorized
           // key (secp256k1 / delegate authenticator), and structurally any
           // future signer. Asserted by the door that filed it; eth_getCode
           // sees an ordinary EOA here, so detection can neither find nor
           // refute it and must never overwrite it.
```
- Glyph: `"key.fill"`, label `String(localized: "Key")`. A key wears the **square mark**
  (it is an instrument, not a who — same taxonomy the `Kind.glyph` doc states).
- `AddressKind.detect` / `detectPending`: skip `.key` entries entirely (both the unknown
  half — a `.key` is never `.unknown` — and the stale half: add `.key` beside `.safe` in
  the stale filter, with a comment saying why detection is blind to keyness).
- **Codable hardening (required, do first):** give `Kind` a custom `init(from:)` that
  falls back to `.unknown` on an unrecognized raw value. Today the synthesized decode
  THROWS on an unknown case, the book decodes under one `try?`, and `KeyValueMirror`
  decodes the whole remote dictionary the same way (`KeyValueMirror.swift:191`) — so
  without this, the first entry carrying `"key"` makes an **old build's iCloud pull decode
  to `[:]` and its next push clobber the remote blob**. The hardening only protects builds
  that carry it, so it cannot fully close the skew window for already-shipped builds;
  state that as an accepted risk in the prd entry (solo user, few devices), and land the
  tolerant decode in this same commit so the window never reopens for the NEXT case.

### D4. Detection is gated off for devnet-only entries.
`AddressKind.detect` asks five mainnet chains; for a vibenet account that answers "no code
anywhere" and files somebody's keystore account as `.wallet` — a confident wrong label.
Rule: `detect` returns early (no RPC, no stamp change) for `entry.isDevnetOnly`, and
`detectPending`'s two filters exclude them. Vibenet entries therefore rest at `.unknown`
(honest — the Vibenet badge already says what they are) unless a door asserted `.key`.
Do NOT build a vibenet-side detector in this pass (`isEstablishedCall` exists if a later
pass wants one; out of scope).

### D5. `note` is a per-entry field, searchable, edited on the entry's sheet.
```swift
/// The person's own free-text note on this address. Optional for the
/// Codable reason `groups` documents.
var note: String? = nil
```
- `AddressBook.search(_:)` matches it (lowercased contains), alongside name / address /
  provenance / groups — a field the person can read and cannot search reads as broken
  search (the file's own §440 rule for provenance).
- Setter: `func setNote(_ note: String?, for address: String)` — trims; empty → nil;
  stamps `updatedAt` (it IS the person's edit, unlike `setKind`); no-op when unchanged
  (don't push a whole book to iCloud for a keystroke-identical save).
- Alias merge: fill-in (`if out.note == nil { out.note = alias.note }`).
- Export: `exportPayload`/`importPayload` gain `"note"` (lossless round trip — the Data
  tray's "everything" claim). `exportText` is **deliberately unchanged**: notes contain
  commas and newlines and would corrupt the `Name, address, group…` format `addBulk`
  reads back; add a comment at `exportText` saying so, or the next reader "fixes" it.
- UI: a multiline note editor on the entry detail sheet on BOTH sides (the wallet book's
  `AddressBookSheetRoute` detail in `AddressBookScreen`/`AddressBookViews`, and
  `VibenetAccountSheet`/`VibenetAccountDetail`). Rows do NOT print the note (rows already
  carry provenance + groups; a note is long-form). Use the existing field components
  (`BridgeFieldRow`-family / whatever the sheet already uses) — no hand-rolled chrome, no
  hairlines, sentence case.

### D6. Two screens, one store, badges both ways.
Per §465's still-valid warning, the screens stay separate TYPES:

- **Wallet `AddressBookScreen` shows the whole book**, vibenet entries included. A
  vibenet-tagged row wears a small "Vibenet" tag in its subline (reuse the existing
  subline/provenance slot grammar in `AddressBookViews` — a word, not a new chip system;
  no hue invention: use the Base mark hue already defined for the seat, or plain
  `textSecondary`). `.key` rows sort/file exactly like any other entry (the shape logic in
  `AddressBookShape` is name-keyed and needs no change).
- **`VibenetAddressBookScreen` shows the vibenet slice of the same book**: its watched
  roster (unchanged, from `VibenetWatch` + `VibenetRoomCard`) plus a new section listing
  book entries tagged `vibenet` that are NOT watched (keys filed from the key sheets,
  counterparties) — rename/note/remove verbs writing `AddressBook`. Plus one quiet door
  ("Full address book") pushing the Wallet `AddressBookScreen`, so the "one book" claim
  is walkable from either room.
- Renaming a vibenet account ANYWHERE (roster context menu, account sheet, wallet book
  row) writes the one store; both rooms read it back on the next body pass.

### D7. Keys enter the book through a door on the key sheets.
- `VibenetKeySheet` (and the tray's key rows if cheap) gains an "Add to Address Book"
  verb, shown ONLY when the key's authenticator IS an address — `kind == .secp256k1 ||
  .delegate` and the `authenticator` parses as hex address. Passkey/P-256/custom keys
  have no address and get **no verb** (not a disabled one — §83; the copy test excludes
  them and the spec accepts that).
- The door files: `address = authenticator`, `kind: .key`, `networks: ["vibenet"]`,
  `provenance: "Vibenet key · <account short>"` (fill-in, same grammar as the existing
  Farcaster provenance), name = the key's existing display label if one exists, else the
  short form. If the address is already in the book, only fill-ins apply (never downgrade
  an existing `.wallet`/`.safe` kind to `.key` on an existing entry — fill-in means
  `kind` is passed only when the entry is new; an existing entry keeps its kind and just
  gains the network tag + provenance).

### D8. Migration + the behavior change it forces.
One-shot behind a new flag (`wallet.addressBook.migrated.vibenet.v1`), run in
`AddressBook.migrateIfNeeded()`'s shape (or a sibling called from init):

1. Every `(address, name)` in `vibenet.watch.names.v1` with a non-empty name → book
   entry if absent (`kind: .unknown`, `networks: ["vibenet"]`, `addedAt: .now`); if
   present, fill in the network tag only (never overwrite a wallet-side name).
2. Every address in `vibenet.watch.addresses.v1` (named or not) → ensure a book entry
   exists (short-form name if none) with the `vibenet` tag — watching implies the book
   holds it, the same invariant `addToGroup` enforces.
3. `VibenetWatch` reads/writes names through `AddressBook` from then on; its `names`
   dictionary and `persistNames()` become migration-era residue (keep the storage key on
   disk, delete the live read path).
4. **Watching a vibenet account from now on also files it** (short-form name, vibenet
   tag) — `VibenetWatch.add` calls the book, mirroring the invariant above.
5. **Disconnect no longer forgets names.** `VibenetWatch.removeAll()` / the last-unwatch
   teardown stop touching names — names are the person's ledger and outlive the watch
   (the book's founding doctrine). The confirm dialog copy in
   `VibenetAddressBookScreen` (currently "…the names you gave your accounts are
   forgotten") and any matching copy in `VibenetScreen` MUST be rewritten to what is now
   true: the chip leaves the strip; the names stay in the Address Book.
6. **Demo teardown**: `DemoSeedAll`/`DemoMode.exit` must forget demo-seeded book entries
   BY ADDRESS, never wholesale (a dev install carries a real book). Check what the vibenet
   demo currently seeds via `VibenetConfig.seedDemo` and whether demo watch names exist;
   seed the demo book with at least: one vibenet-tagged account entry, one `.key` entry,
   one entry carrying a note — so demo parity shows every new surface — and unwind all
   three symmetrically.

### D9. What is deliberately NOT in scope
- No merge of the two WATCH lists (mainnet's cap-5 economics vs the free devnet — §465's
  reasoning stands).
- No vibenet-side kind detector (D4).
- No book entries for address-less keys (passkeys) — no actorId-keyed entries; the book's
  identity is an address, full stop.
- No `exportText` change (D5).
- No new CloudKit/SwiftData anything.
- No parameterizing the two screens into one generic screen.

---

## Sync + compatibility hazards (read before coding)

1. **`Kind` decode brittleness** — see D3. Land the tolerant `init(from:)` in the same
   commit as the new case.
2. **Old-build iCloud skew** — an already-shipped build pulling a book that contains
   `kind: "key"` decodes the remote dict to `[:]` and its push can drop the new entries
   from the remote blob (local copies on the new device survive and re-push; the blob
   churns). Accepted risk; say so in the prd entry. Optional cheap mitigation to
   evaluate during implementation: keep `.key` out of the MIRRORED encoding is NOT
   possible cleanly (one Codable) — don't contort for it.
3. **New optional fields are safe by construction** (`groups` precedent: synthesized
   Codable + optional = decodes as nil on old data) — but ONLY if `note`/`networks` are
   optional with nil defaults. Never non-optional.
4. **`entries` didSet economics**: every mutation encodes the whole book and pushes to
   iCloud. Note editing must not write per keystroke — write on save/dismiss, and no-op
   when unchanged. Bulk migration runs inside `batched { }`.
5. **`VibenetWatch` and `AddressBook` are both singletons initialized early** — the
   migration reads `vibenet.watch.names.v1` straight from UserDefaults (not through
   `VibenetWatch.shared`), the same no-mutual-init rule `migrateIfNeeded` already
   documents for `WalletStore`.

## Guards, harnesses, checks (the part that keeps this shippable)

- `scripts/address-book-selftest.sh`: run its drift greps STANDALONE first (memory:
  fail-fast harness costs 15min per stale guard). Expect guards on `AddressBook.swift` to
  need amending, not deleting. ADD: assertions that `search` matches a note and a network
  tag; that `Kind(rawValue:)`-unknown decodes to `.unknown` (the tolerant decode, as a
  fixture — a JSON blob with `"kind":"flurb"` must decode with the entry surviving); that
  `merging` unions networks and fills note; that `exportPayload`/`importPayload` round-trip
  note + networks + `.key`. Remember the standing rule: **a fixture only tests the rule it
  names if it FAILS that rule and passes every other one** — the unknown-kind fixture must
  be an otherwise-valid entry.
- `scripts/vibenet-selftest.sh`: guards asserting `VibenetWatch.setName`/`name(for:)`
  delegate to `AddressBook` (grep the call), that disconnect no longer clears names
  (NEGATIVE grep on a comment-stripped copy — the source will document the old behavior
  by naming it; Obsidian/Cursor lesson), and that the key-sheet door only offers for
  secp256k1/delegate.
- `AddressKind`: mutation-worthy assertions that `.key` and devnet-only entries are
  excluded from both `detectPending` halves (whichever harness covers it — likely a new
  block in `address-book-selftest.sh` since `AddressKind.swift` does RPC; a drift grep is
  acceptable where compilation isn't).
- SwiftData liveness audit: untouched (no `Thing` involvement) — but new UI files go in
  audited dirs automatically; keep any new row structs in the shapes the lint sees.
- Demo parity (D8.6) + `demo-selftest.py` checks if any seed function is added (check A:
  reachable outside `#if DEBUG`).
- Design law: no hairlines, sentence case, `DSTray`/existing slab components, no
  letter-spacing; the Vibenet tag uses an existing hue, never an invented one.
- Localization: every new user-facing string via `String(localized:)`; String Catalog
  will drift at ship time (standing memory — pre-ship step, not this task).
- Run `scripts/verify.sh` (not just the audits you remember — the build-214 lesson).
  `SKIP_MAC=1 LAUNCH_CYCLES=0` acceptable during iteration; full pass before handoff.

## Probes (headless verification)

- Extend `-addressBookProbe YES` output: per entry print kind, networks, provenance,
  and note LENGTH (never the note text — it's the person's own words; the
  `-secretScanProbe` grade of caution costs nothing).
- New hook `-addressNote "<address>:<note>"` (split on FIRST colon after the address —
  addresses contain no colon; notes may) to seed a note headlessly.
- Extend the existing `-addressBook` seeder OR add `-addressKey "<address>"` to file a
  `.key` vibenet-tagged entry headlessly, so the badge + kind render can be screenshot
  without driving the key sheet.
- Vibenet side: `-vibenetProbe`/room probes unchanged; add one NSLog in the migration
  (`addressBookMigrate: vibenet moved N names`) so a device upgrade is observable once.

## PRD + docs

- New prd § entry (append-only; check `prd-index-audit` rules — next free number, record
  the amendment of §465 and §472 in the Superseded index if the wording rises to
  "amends"). Content: the four user asks, D1–D9 with their reasons, the accepted
  old-build skew risk, and the disconnect-copy change.
- Update `CLAUDE.md`'s vibenet/address-book bullets if any statement there becomes false
  (the §465 "deliberately does NOT copy" paragraph in `VibenetAddressBookScreen`'s header
  must be rewritten — it will otherwise document the opposite of the shipped truth).

## Suggested implementation order

1. `Kind` tolerant decode + `.key` case + `note`/`networks` fields + setters/merge/search/
   export (pure model; harness fixtures alongside).
2. Detection gating (D4) + `.key` exclusion.
3. Migration + `VibenetWatch` name delegation + watch-files-the-book invariant +
   disconnect behavior/copy change.
4. UI: wallet book badge + note editor; vibenet screen slice section + full-book door +
   note editor on the account sheet.
5. Key-sheet door (D7).
6. Probes, demo seeds/teardown, harness guards, prd entry, `verify.sh`.

## Acceptance checklist

- [ ] Rename a vibenet account in the vibenet roster → the same name shows on the wallet
      book row (badged "Vibenet"), and survives vibenet disconnect + reconnect.
- [ ] A key filed from `VibenetKeySheet` appears in both books as kind Key, square mark,
      key glyph, with provenance naming its account.
- [ ] A note saved on either side is searchable from the wallet book's field and round-trips
      through the Data tray export/import.
- [ ] `AddressKind.detectPending` never issues an RPC for a devnet-only or `.key` entry
      (assert via the harness, not by reading).
- [ ] An entry JSON with an unknown `kind` decodes to `.unknown` without losing the book.
- [ ] Demo mode shows a vibenet-tagged entry, a key, and a noted entry; demo exit removes
      exactly those.
- [ ] `scripts/address-book-selftest.sh`, `scripts/vibenet-selftest.sh`, and full
      `scripts/verify.sh` green.
