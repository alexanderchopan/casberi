# Address Book, iteration 2 — filters, the tray door, and honest entry

Status: SPEC (2026-08-27). Follows the unification pass (prd §496) and the spine
removal (§497). User direction captured verbatim this session: *"we need filter
chips somehow"*, *"onchain as a filter"*, *"maybe even 'keys' as a filter"*,
*"right now it is a mix of wallet address and non wallet address but user can
only enter wallet here"*, *"we could put it next to the user avatar, apps, and
all feed buttons in the source tray 🙂"*, *"not like apple b/c theirs is kinda
wonky, and no cards"*.

## 1. Filter chips on the book (the core)

**One quiet capsule row between the input section and the A–Z list.** NO cards,
no slabs, no segmented control (user ruling — "no cards"; Apple Contacts' filter
UI named as the anti-pattern). The screen already owns the right component:
`AddressBookScreen.chipLabel(_:tinted:)` — a `label12` capsule on `fillFaint`,
tint = selected. Reuse it verbatim; do not invent a second capsule.

**The chip set is DERIVED from the book, never enumerated.** A chip appears only
when the book holds ≥1 member (§83 — a filter that can only produce an empty
list is a dead control). Candidate set, in fixed order:

| Chip | Membership test |
|---|---|
| All | always (leads; selected by default; no filter) |
| Wallets | `kind == .wallet \|\| .smartAccount \|\| .unknown` — the unmarked "who" population |
| Keys | `kind == .key` |
| Contracts | `kind == .contract \|\| .safe` |
| Vibenet | `entry.networks` contains `AddressBook.Network.vibenet` |

- **"Onchain" is deliberately NOT a chip today**: the book's membership rule is
  crypto-only (the copy test), so every entry is on-chain and the chip would
  select everything — a second All. It becomes real the day an off-chain
  population (imported contacts, §3 below) enters the book; the enum below is
  shaped so adding it then is one case. State this in the code comment so the
  next session doesn't "fix" its absence.
- Kind chips and the network chip are the SAME axis (one selection, not two
  rows) — "we cannot have four rows of chips" (§482's ruling, one room over).
  Single-select; tapping the active chip returns to All (the chip strip's own
  re-tap grammar).
- The filter COMPOSES with search and sort: it narrows `visibleEntries()`
  BEFORE `bookSections`, so the letter headings and the scrubber derive from
  the filtered list (the existing `AddressBookShape.index(of: sections)` guard
  then keeps the scrubber honest for free). While searching, the chip row folds
  with the rest of the chrome (`if !searching` — the existing fold).
- **Empty-after-filter never happens by construction** (a chip only exists with
  members), except mid-session when the last member is removed while its chip
  is selected — the selection then RESETS to All rather than showing an empty
  book (test this; it's the one transition that can strand the screen).

**Model half in `AddressBookShape`** (Foundation-only, so the harness covers
it): `enum BookFilter { case all, wallets, keys, contracts, vibenet }` with
`matches(_ entry:)` and `available(in entries:)` — the membership tests live
there once, and `address-book-selftest.sh` gains assertions + a mutation
(e.g. dropping `.smartAccount` from the wallets test must be caught: a smart
account filtered out of Wallets files somebody's own account with machinery).

**Vibenet's book screen does NOT grow chips** — its roster is one population
by construction. The chips are the shared book's answer to holding both.

## 2. The tray door ("Your feeds" header)

A third circle in `SourcesOverlay.headDoors`, between the avatar and Apps:
glyph `person.text.rectangle` (the rail's own address-book reading, §461 —
one glyph, both surfaces), same `DS.Hit.min` circle on `fillStrong`, same
`contentShape(Circle())` (the catalogue door's three bug reports). Wiring
mirrors `onSettings` exactly: close the panel first, then push, or the screen
arrives behind a raised panel and the tap reads as a no-op:

```swift
onOpenAddressBook: {
    closeSources()
    withAnimation(DS.Motion.standard) { sceneState.route.push(.addressBook) }
}
```

Accessibility label "Address Book". The doors stay a pair of… now a trio of
fused circles; `allChip` stays outside them. This honours the §461/§465 rail
doors too — three ways in (wallet rail, vibenet rail, tray), one screen.

## 3. Entry stops being wallet-only

The omnibox already ACCEPTS any hex/base58/name (`looksLikeAddress`), so entry
isn't structurally blocked — what's missing is that a hand-entered key can only
ever be detected `.wallet` (a key IS an EOA on-chain; `AddressKind` is blind to
keyness by design). Two additions:

1. **"Mark as key" in `AddressCard`'s overflow menu** (with "Unmark" when
   `.key`). A person asserting a fact about their own entry — the same grade of
   assertion the vibenet key-sheet door makes, now available for a key met
   anywhere (a Safe owner key, a session key pasted from a dapp). Sets
   `kind = .key` (detection already skips `.key`, so nothing overwrites it);
   Unmark sets `.unknown` and lets detection re-answer. This is NOT a kind
   picker in the add sheet — §169's "detected, never asked" stands for the
   populations the chain CAN answer; a key is the one kind it can't.
2. **Contacts and other saved-name sources: a PICKER, never a mirror**
   (user: "someone can also import their contacts… and saved contact names
   from other sources"). Phase 2, separate pass. The standing rule, written
   here so it survives: bulk graphs (a Farcaster starter pack, the Contacts
   database) are CANDIDATE sources feeding a picker with nothing preselected
   (`SocialFollows`' §87 ruling); only a deliberate per-address act writes the
   book. A contact chosen from the picker lands with
   `provenance: "Contacts · <name>"` — the same fill-in door Farcaster uses.
   Contacts stay a separate corpus source (the phone's book holds emails and
   phone numbers, which fail the copy test); what crosses over is a NAME for
   an address the person explicitly pairs.

## 4. Small honesty riders

- A row whose entry carries a note gets a `note.text` glyph at 11pt tertiary
  on the trailing edge, before the WHEN phrase — the note stays off the row
  (§496), but a fact the person wrote down shouldn't be undiscoverable until
  they happen to open the card. Cheap, and reversible if it reads as clutter.
- `-addressBookProbe` prints the ACTIVE filter and per-chip counts, so a chip
  that filters to the wrong population is visible in one launch.

## Guards / prd

- `address-book-selftest.sh`: `BookFilter` assertions + ≥2 mutations; a drift
  guard that the screen filters through `BookFilter.matches` (not an inline
  predicate — two spellings of membership is two books); the §497 negative
  already added stays.
- prd: new § entry (filters + tray door + mark-as-key), noting the "no cards /
  not like Apple" ruling and the deliberate absence of an Onchain chip.
- Demo: the demo book already holds wallets, contracts, a safe, a key and
  vibenet entries after §496 — every chip has members in demo mode. Verify
  via the probe, don't assume.

## Order

1. `BookFilter` in `AddressBookShape` + harness (pure).
2. Chip row + composition with search/sort/scrubber + reset-to-All edge.
3. Tray door.
4. Mark-as-key.
5. Probe + prd + note glyph.
6. Contacts picker is explicitly OUT of this pass (Phase 2).
