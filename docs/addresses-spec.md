# Addresses — the unified contacts list, rebuilt as a room that learns

> **JOINT SPEC, half B.** One feature in two files, one session each: **A** `docs/social-spec.md`
> (share and act — the card, the Text/Email/Call doors, later acts by seat; its section 0 rules bind
> both halves) and **B** this file (the person — the book, the join, the room, the sheet; was `docs/people-spec.md`). The
> seam is one call, `ContactIndex.contact(for:)` (section 2.5 here, section 5 there). Read A section 0, then B section 0, then
> whichever half you are building. Neither session edits the other's file; disagreements go in
> the seam sections, not in a third copy.

Status: SPEC, not built. Written 2026-09-24 from the user's ask: *"i think we need to have
unified contacts list again … we have a contacts app, and it's already in life, and i think we
can create a contacts list that starts building and gets smarter. especially if apple gives us
access to private compute."* Record the ruling as **§916** before the code (confirm with
`prd-index-audit.py --next`).

Rulings this stands on, unchanged: §169 (naming is free, the mirror carries addresses), §632
(nothing under a thing is a guess), §690 (follow lives on each seat's page; the address-book
screen stays deleted), §818 (Contacts is a room of its own and never in All), §744/§764/§902
(one row anatomy), §782 (no plates), §815 (kind tiles), §833 (`AskModel.session` is the one
switch to Apple's cloud model). Rulings this **amends**: §498 (the book as the people surface —
the surface moves to the room; the ephemeral-row code is dead and is deleted), §818's title
(the room is *Addresses*, and Contacts is one seat feeding it).

**The word is Addresses** (user, 2026-09-24: *"we should name it addresses not people"*). The room's
`heading34` says Addresses, the verb is `Add to Addresses`, and the noun matches the wallet family's
(§747/§774: *Follow address*, and `address` wherever a list is counted). The code's type stays
`Person` — a row IS a person; Addresses is what the book holds about them: a card, an email, a
wallet, a handle — **and a row need not be a person at all** (user, same day: *"someone may have
addresses that aren't people"*). A contract, a Safe, an exchange deposit address, a company, a
newsletter, a podcast: each is an address you deal with, and each is a row. So the record is a
`Contact` with a `kind`, never a `Person`: `kind: person | organization | contract | safe |
smartAccount | key | publication`, the wallet book's kinds (§169/§294) plus the three the seats
add. `AddressBook` (the wallet ledger, §169) keeps its name; the unified record's index is
`ContactIndex`, the saved store `ContactBook`.

Everything marked **UNMEASURED** has not been run.

**Consumer:** `docs/social-spec.md` section 5 (the share tray's Text/Email doors) reads
`ContactIndex.contact(for:)` (section 2.5 below) and takes a phone or email from the person's `.contact`
identity's facts, falling back to `detectedTel`/`detectedMailto` until this lands. Its section 0 sets
the key order this spec's section 2.1 follows: the person is keyed on what Mail, Contacts and GitHub
carry, and a Farcaster or Bluesky handle is one more alias, not the key.

---

## 0. The rule

> One person, one row, everywhere the app names them.

The app already holds people in five piles that never meet: Apple contacts (`Thing`s, kind
`.contact`), the wallet book (`AddressBook.Entry`), the social watch lists (Farcaster, Bluesky,
Nostr stores), GitHub people (`.link` things from `GitHubPersonWatch`), and World App usernames
(`WorldAppDeFi`). A person you know as a contact, follow on Farcaster and receive ETH from is
three strangers to the app. §498 tried to fix this by listing the piles side by side; that is
not unification, and §690 deleted it for a structural reason that still holds.

What is new: a **join** the app never had. Farcaster verifications and web3.bio give
address ↔ ENS ↔ Basename ↔ Farcaster ↔ Lens edges keylessly, and the person's own corpus gives
contact ↔ email ↔ handle edges. So the list can be one list of *people*, not of identifiers.

**And the book is yours to build** (user, 2026-09-24: *"make it easy for a person to save a
contact and 'add to contact lists' kind of thing. anywhere in the app there is a person even if
not social like an rss writer or whatever. a smart book."*). Wherever a thing names a person —
an RSS writer, a mail sender, a GitHub actor, a poster, a wallet counterparty, a meeting's
organizer — the dial offers **Add to Addresses**, and a saved contact is a row in the room like any
other. The seats fill the book by themselves; the person fills it by hand from anywhere; the join
makes both smarter over time. That is the whole "smart book".

**Not every row is a person, and the room says which** (user, 2026-09-24). A wallet entry the
kind check found to be a contract or a Safe keeps its kind and its mark (`Kind.isMonogram` is
false there — the machinery mark, the Safe mark), a followed feed is a `publication` wearing the
feed's own mark, and an Apple contact with an organization name and no person name is an
`organization`. The tiers in section 3 apply unchanged: a contract's Etherscan label is a stated name,
a Safe's owners are verified links to the wallets that own it (§652's head already reads them).

Three things this is NOT: not a place to follow from (§690 — the seat pages keep every follow
verb), not a balance surface (user, 2026-08-21: money lives on the wallet crown only), and not a
name-matcher (§632 — two accounts called "Alex" are two people until something verifies
otherwise).

## 1. What you see

**RULED 2026-09-24 (user, after section 1 was first written as a room): Addresses lives UNDER THE
FACE, not on the dock.** The Accounts screen's switcher becomes `Connect · Manage · Settings ·
Addresses` (§796's one switcher, one word wider). Addresses is a DIRECTORY, not a feed: it has no
time, so the room chassis (a cover, day dividers, a lead) fights it, and §818 already fenced
contacts out of All for that reason. Beside Accounts it takes the same anatomy that screen
already has — the search field, the dock's category chips as filters, rows — so the filter the
user asked for ("the categories that are on the dock to filter by") is reuse, not a second
strip. **No Contacts room in the dock** (user: "i don't think contacts should live in the dock;
if a user adds their contacts it goes in the contact or address book"): §818's room is retired,
`Corpus.roomOnlySources` keeps Apple's cards out of All, Home, the widgets and notifications, and
a Contacts connect lands in Addresses with the toast saying so ("Your contacts land under
Addresses") — which is the answer to the beta tester who could not find a tab. The seat in the
catalogue stays "Contacts" (Apple's book); the name of the list is **Addresses** (user: a
contract, a Safe, a newsletter and an email are not contacts, and "Contacts" is Apple's word for
the seat).

The paragraphs below were written for the room and are kept where they still hold; where they
say "the room", read "the Addresses list". The lead box and the kind tiles are DELETED by this
ruling — a directory opens on its search field and its category chips, like Accounts. The
category chips filter by "has an identity in that category": Wallet (wallet, contract, Safe, key,
name services), Social (Farcaster, Bluesky, Nostr, X), Work (GitHub, email at a work seat), Life
(Apple contacts, email), Reading (publications). A contact can stand in several.

- ~~**Lead (the box, §904)**~~ DELETED by the ruling above (a directory has no lead). Was: the person who most recently *acted toward you* — a transfer, a
  reply, a mention, a mail — with their face, name, and the sentence: "Sent you 0.2 ETH · Tuesday".
  `FeedLedeFace.kind` for the room is a face (the cast face, §907), never a picture grid. A room
  with nobody who acted leads with the newest person added.
- ~~**Kind tiles (§815)**~~ DELETED by the ruling above — the dock's category chips filter instead
  (Accounts' own strip). Was: `All · Contacts · Wallets · Social · Work · Feeds`. All is first and where
  the room opens; fewer than two kinds draws no tiles. Work is GitHub people (and any later work
  seat that watches a person); Feeds is every `publication` row. A wallet row that is a contract
  or a Safe stays under Wallets with its own mark. Each tile needs its `ScopeTileGlyph` constant named for its own case.
- **Rows:** `DSFeedRow`. Lead: the person's face (contact photo, then a social avatar, then an
  ENS avatar, then the monogram — `Kind.isMonogram`'s rule). Title: the display name, one line.
  Line (`subhead12`): their identities in a fixed order, e.g. `@jesse · jesse.base.eth · Farcaster, Base`.
  Trailing slot: **empty**. No money, no counts (§345: a per-face number was a fake status).
- **Sections:** not by day. Two groups, `dated: false`: **Recent** (people with any thing in the
  last 30 days, newest act first) then **Everyone** (alphabetical by display name). The day
  divider's pink is only for time (§740).
- **Search (RULED, user 2026-09-24: "the address book also will need a search field"):** one
  entry field under the tiles and above Recent — the Accounts screen's own search field, same
  `dsWell` (the one thing §782 lets a well hold), never pinned to the top edge (§752). It filters
  the rows live over every identity a row carries: name, handle, ENS/Base name, hex address,
  email, company. Typing folds case and diacritics (`address-book-selftest.sh`'s heading fold);
  a pasted full address matches its row exactly. Empty query draws the room as it was. It is a
  filter, not a resolver: an unknown name typed here lands nothing and offers nothing — the
  follow field on the seat pages is where a new address is asked for (§690).
- **Suggestions:** at most ONE row in Recent, above the rest, reading "Same person? jesse.eth
  and @jesse" — a `DSDoorRow` that opens the pair on a sheet with `Yes, same person` / `No`. It
  is drawn only when the app holds a tier-2 edge (section 3) and never more than one at a time.
  Declining is remembered forever for that pair.

**The sheet.** `PersonCard` (already the contact sheet) grows into the person sheet:

1. Face, name, the Role · Company line where a contact carries one.
2. **Identities**, one row each, every one a door: a contact row opens Apple Contacts
   (`contacts://` UNMEASURED — else the reachable facts stay inline as today); a wallet row
   opens `AddressCard`; a social row opens `PersonRoomScreen`; a GitHub row opens the profile.
   Each row's line says how the app knows it (section 3's tier word): *verified*, *you confirmed*,
   *from their contact card*.
3. The reachable and standing facts a contact already draws (call, mail, address, birthday).
4. **With you** — the person's things across the whole corpus, newest first, capped at 20 with
   a `Show older` door: transfers whose `counterpartyAddress` is one of their addresses, posts
   and notices whose `authorHandle` is one of their handles, mail whose sender is one of their
   emails, events whose attendees carry one. This is `PersonRoomScreen.load()`'s query widened
   from one handle to a person, and it is the whole "smarter" of the sheet: one place that
   answers "what has this person and I done".

**Add to Addresses — the one new verb, everywhere.** `Verb.Action.addToPeople(Identity)` in
`Model/Verbs.swift`, offered on any thing where `contact(for:)` is nil but an identity is
readable (section 2.5's resolution, run the other way): an RSS item's `authorHandle` (the feed's name,
or `FeedParser.author` where the item carries a writer), a mail sender, a GitHub actor, a social
poster, a transfer's counterparty, a calendar organizer. Tapping it raises the existing naming
prompt (`NameAddressPrompt`, §169's shape) prefilled with the best display name, and writes one
`SavedContact` (section 2.6). Where `contact(for:)` already answers, the same disc reads `Open`
and opens the sheet — one disc, two words, never both (§83). A saved contact's sheet carries
`Remove from Addresses`; a seat-fed person's does not (its removal is the seat's — §690). Call and
Mail ride the facts; Follow/Watch/Unfollow stay on the identity's own door. The dial on a person
row: `Open`, `Copy address` where they have exactly one.

The verb lands through `Verbs.swift`, which `social-spec.md` section 5 leaves to this half; it does
not touch `VerbDial` in `ThingStage.swift`, where half A's Share disc lives.

**Naming on transactions.** `WalletIngest.counterpartyNames(for:)` gains one step at the top:
a linked person's display name beats everything below it, so a transfer from a wallet you
confirmed is "Alex" reads *from Alex*, with Alex's face (`MovedStage` draws the person's face
instead of the identicon when the address resolves to a person). Step 5 (ENS reverse) gains
web3.bio's `/ns/{address}` beside ensideas, forward-verified as §599 requires. Nothing else in
the chain moves.

## 2. The data: a derived index over a link ledger

**No new `Thing`, no SwiftData, no CloudKit schema.** Contacts are already things; wallet
entries and social accounts already have stores. A `Person` is a **value built at read time**
from those stores plus one new persisted ledger of edges. This is §498's ephemeral-row insight
kept and the rest of §498 dropped: rows built from sources that hold them need no reconcile pass,
and disconnecting a seat removes its rows by itself.

```swift
/// Model/ContactIndex.swift
struct Contact: Identifiable, Equatable {
    let id: String                       // the lead identity's key (see section 2.1)
    let name: String                     // display name, section 2.2
    let identities: [Identity]           // ordered: contact, wallets, social, work
    let face: Face                       // .photo(Data) | .url(String) | .monogram(String)
    let kind: Kind                       // person | organization | contract | safe | smartAccount | key | publication
    let lastActedAt: Date?               // for the Recent section and the lead
}
struct Identity: Equatable, Hashable {
    enum Kind: String { case contact, email, github, wallet, ens, basename, farcaster, lens, bluesky, nostr, worldApp, feed }
    let kind: Kind
    let key: String                      // lowercased address, "@handle", "contact:<id>", "name.eth"
    let label: String                    // what the row's line draws
    let tier: LinkTier                   // how it joined this person, section 3
}
```

### 2.1 Keys

Every identity has one canonical key, lowercased: Apple contacts `contact:<CNContact.identifier>`,
an email `mail:<mailbox@host>`, GitHub `gh:<login>`, hex addresses as `0x…`, ENS/Basename/Linea
names as the name, Farcaster `fc:@name` (fid kept beside it — a username can be sold, a fid
cannot), Bluesky `bsky:@handle`, Nostr `nostr:<pubkeyHex>`, World App `world:<username>`, a publication `feed:<feedURL>`
(the `FeedFollowEntry.feedURL` the five feed-follow stores and RSS already key on).

**An email is an identity in its own right.** More people use Gmail, Calendar and GitHub than
Farcaster (user, 2026-09-24, recorded in `social-spec.md` section 0), so a sender who mails you is a
person with one identity even when no contact card and no handle exist — the list must start
from the inbox, not from crypto. A mail thing's `authorHandle` is the display name when the
sender set one and `mailbox@host` otherwise (`IMAPClient.swift:541–550`), so the address is
NOT recoverable from every mail row today; section 2.5 names the gap.

A person's `id` is the key of its **lead identity** in this order: contact, email, GitHub login,
the oldest wallet entry, the oldest social account — so the id is stable while links are added
and only moves if the lead is deleted.

### 2.2 Name

Fixed precedence, never ranked: the name **you** typed (book entry `name`, or a contact's
name), then a verified primary name (`NameResolve.primaryNames`' first, itself forward-verified),
then a social `displayName`, then the handle. A name you typed always wins — §169's "naming is
free" is the person's own authority over their book.

### 2.3 The ledger

```swift
/// Model/ContactLinks.swift — the only thing this feature persists.
struct ContactLink: Codable, Equatable {
    let a: String, b: String             // two identity keys, sorted, so a pair has one row
    let tier: LinkTier
    let source: String                   // "farcaster.verifications" | "web3.bio" | "contact.card" | "you" | "corpus.email"
    let at: Date
    var declined: Bool = false           // "No" on a suggestion; sticks forever
}
```

Stored in UserDefaults `addresses.links.v1` through `DefaultsWrite` (§721). **Mirrored** through
`KeyValueMirror` (`addresses.links.v1`, tombstones `addresses.links.tombstones.v1`) **only for edges
whose both keys are public identities** — addresses, names, handles. An edge touching a
`contact:` key never leaves the device: `CNContact.identifier` is not stable across devices
(UNMEASURED for iCloud contacts; assume not), and §169's mirror carries addresses, not people's
phone books. Contact-side edges are cheap to rebuild from the card itself (section 3 tier 3), so nothing
is lost.

The union-find over edges is computed at read time; a person is a connected component whose
`declined` edges are cut. A declined edge also blocks the two components from being *suggested*
again, but never blocks a **verified** edge (section 3 tier 1) — if Farcaster later verifies the
address, the app says so, because that is a fact and the earlier "No" was an opinion about a guess.

### 2.4 Refresh

`ContactIndex.rebuild()` runs on foreground after the seats' sweeps, behind `GestureGate.idle()`,
and is bounded: at most 12 web3.bio lookups per pass (`AddressNames`' own cap), 14-day freshness
for an answer, misses recorded so an address that links to nothing is not re-asked every
foreground. Web3.bio is asked only for addresses and names the person already holds — watched
wallets, book entries, counterparties in the last 30 days — never for a contact's fields.

### 2.5 `contact(for:)` — the seam other features read

```swift
/// The person a thing is from or about, or nil when the app holds none.
static func contact(for thing: Thing) -> Contact?
```

Resolution, first hit wins, every key lowercased: `counterpartyAddress` and `walletAddress` (a
transfer, a card spend) → a wallet identity; `authorHandle` + `source` → the seat's identity kind
(Farcaster/Bluesky/Nostr/X handle, GitHub login, a mail sender); a `.contact` thing → itself; a
mail row whose sender address is held → the email identity; a calendar event's `Organizer` fact
→ the email identity. **Two traps read off the tree:** a GitHub *notification's* `authorHandle`
is the repo OWNER, not the actor (`GitHubRowTag.swift:36–47`), so notifications resolve through
the actor `GitHubEventShape` carries or not at all; and a mail row whose sender set a display
name holds no address in any field (`detectedMailto` is nil there too), so `contact(for:)` can
name that sender only through a contact card carrying the same display name — which section 3 forbids
as a merge key. **RULED yes (user, 2026-09-24):** add `authorEmail: String?` to `Thing`
(additive, optional — no schema version, but a CloudKit Production deploy per
`docs/cloudkit-deploy.md` before the build that writes it ships) and have `MailBridge` stamp it
from the sender's mailbox; calendar's `Organizer` fact can ride the same field. Until it lands
the Email door stays missing on those rows, as it is today.
`Shared/Thing.swift` is on this spec's path list (`social-spec.md` section 5).

### 2.6 The saved half: `SavedContact`

The seats feed the index; this is what the person adds by hand, and it is the only population
that is neither a `Thing` nor a seat's store:

```swift
/// Model/ContactBook.swift — persisted, `addresses.saved.v1`, mirrored (public keys only, section 2.3).
struct SavedContact: Codable, Identifiable, Equatable {
    let id: String                       // the identity key it was saved from (section 2.1)
    var name: String                     // what you typed
    var identities: [String]             // keys added later through links or the sheet
    var note: String?                    // the book entry's note (§169's `note`), same field
    let addedAt: Date
    var updatedAt: Date?
}
```

A saved contact with a wallet identity is ALSO an `AddressBook.Entry` — the book stays the one
ledger for addresses (§169), and `ContactBook` holds the non-address half (an RSS writer has no
address). Saving from a counterparty writes both, in one statement, so a name typed on a
transfer is the book's name the wallet room already draws. Merging is newest-stamp-wins, as the
book's is. A saved contact joins the index as a component like any seat-fed one, and links grow
onto it by the same three tiers.

The "With you" block on the sheet is the inverse: every thing whose `contact(for:)` is this
person, which is one predicate per identity kind, never a name match.

## 3. How it gets smarter: three tiers of link, and what each may do

| tier | name | how it arrives | may merge rows? | drawn as |
|---|---|---|---|---|
| 1 | **verified** | Farcaster `verificationsByFid` (address ↔ fid); web3.bio `/ns` forward-verified (name ↔ address, and the platforms the record carries); World App username ↔ address (§795, forward-verified) | **yes, silently** | *verified* |
| 2 | **suggested** | the corpus: a contact card's `socialProfiles`/`instantMessageAddresses` naming a handle you follow; a contact's email matching a mail sender you also know as a social account (`from` ↔ card); a book entry's `provenance` ("Farcaster · @jesse") pointing at an account you watch; web3.bio `links` naming an X/GitHub handle you watch | **no** — one "Same person?" row | *you confirmed* once tapped |
| 3 | **stated** | the contact card's own fields (an ENS name or `0x` address in a URL/note field, a handle in a social profile) | yes, into the contact, never outward | *from their contact card* |

Two rules keep §632: **a display name is never a key** — `AddressBookPeople.merged`'s
name-match merge is deleted with the rest of that file, and the self-test mutates a name-only
merge back in and must catch it. And **a suggestion is one row, once** — the room never fills
with "Same person?" rows; the next one is drawn after the first is answered.

**On-device model, then Private Cloud Compute.** Tier 2 has one case a rule cannot write: a
bio, a contact note, a screenshot's OCR text that *reads like* the same person ("Jesse Pollak ·
Base" beside a card for Jesse Pollak at Coinbase). That is a language judgement over private
text, and it is the one place a model belongs here:

- `@Generable struct ContactLinkVerdict { let samePerson: Bool; let because: String }` — file
  scope, never nested (the heap-corruption gotcha). Input: the two identities' public words
  (display name, bio, org, handle list), never a phone number or email. Output: a tier-2
  suggestion, never a merge. Available on iOS 26+ through `AskModel.session(forceDevice: true)`.
- When Apple grants the managed entitlement (§833: `AskModel.entitled` is false today, and
  calling the cloud model without it crashes — §838), the same call goes through
  `AskModel.session` unchanged and the bigger model reads the same inputs. Nothing about the
  feature waits on that grant; it gets better on the day the switch flips. The librarian rule
  from §833 holds — background work stays on the phone — so the cloud model judges a pair only
  when you open the suggestion sheet, never in the foreground sweep.

## 4. Privacy, and what leaves the device

- **web3.bio** receives only an address or a name the app already holds publicly (the same
  contract `api.ensideas.com` has). Host `api.web3.bio` joins the "Names & avatars" endpoint in
  `NetworkReach` with the purpose sentence extended by one clause ("and the Farcaster, Lens and
  Base names an address has linked to itself"). Avatar URLs it returns are third-party hosts:
  read through the existing avatar path, which already names a declared family.
- **Apple Contacts** never leave the device and never reach a model in the cloud unless the
  person opens a suggestion sheet while the §833 entitlement is live; even then only the public
  words in section 3 go. The mirror never carries a `contact:` edge (section 2.3).
- The demo reaches nothing: web3.bio is gated on `DemoMode.isActive` in the function that
  reads, `ENS.resolve`'s pattern.
- Settings' privacy sentence for Contacts gains the one line: "Links a contact to a wallet or
  a social account only from their own card or when you confirm it."

## 5. Files

| file | change |
|---|---|
| `Model/ContactIndex.swift` | NEW — `Person`, `Identity`, `rebuild()`, the component walk, name precedence |
| `Model/ContactLinks.swift` | NEW — the ledger, tiers, mirror rules, decline |
| `Model/ContactBook.swift` | NEW — `SavedContact`, the mirror, `Remove from Addresses` |
| `Model/Verbs.swift`, `Screens/NameAddressPrompt.swift` | `addToPeople` / `Open`; the prompt takes a non-address identity |
| `Model/ContactSuggest.swift` | NEW — tier-2 candidates from the corpus; the `@Generable` verdict |
| `Model/Web3Bio.swift` | NEW — `/ns` and `/profile/batch`, forward-verify, miss cache; called by `ENS`'s three functions and `ContactIndex` |
| `Model/ENS.swift` | web3.bio first, ensideas fallback, in `resolve`/`reverseName`/`avatar` |
| `Model/NameResolve.swift` | `primaryNames` gains Farcaster/Lens/Basename rows from web3.bio; labels "Farcaster", "Lens", "Base" |
| `Model/WalletIngest.swift` | `counterpartyNames`: person's name first; `knownLabel` reads the index |
| `Model/AddressBookPeople.swift` | DELETE all but `unfollowable` and `addressLabel` (move those to `AddressBook.swift`); fix `address-book-selftest.sh`'s path pin |
| `Screens/FeedScreen.swift` | `Shape.people` (was `.plain` for Contacts): lead, tiles, two sections; the room's source filter unions Contacts + the index |
| `Screens/ThingContent.swift` | `PersonCard` takes a `Contact`; Identities and With-you blocks |
| `Screens/ThingStage.swift` | `MovedStage` draws the person's face when linked |
| `Screens/ScopeTileGlyphs.swift`, `Model/RoomKindTiles.swift` | the four tile cases and their glyph constants |
| `Model/NetworkReach.swift` | `api.web3.bio` |
| `Shared/Thing.swift`, `Model/MailBridge.swift` | `authorEmail` (section 2.5, RULED) + `cktool import-schema` |
| `Model/BridgeCatalog.swift` | the Contacts offer's tagline says the room: "The people you know, everywhere you know them" |
| `Shell/RootShell.swift` | probes below; `casberi://person/…` resolves through the index so either handle lands on the same person |
| `Model/DemoSeedAll.swift` | six demo people spanning three tiers, so the census sees every row shape |

## 6. Guards

- **`scripts/addresses-selftest.sh`** (zsh, Foundation-only stubs) over `ContactIndex`/`ContactLinks`:
  1. two identities with the same display name and no edge are two people (mutation: name-only merge);
  2. a tier-1 edge merges, a tier-2 edge does not (mutation: tier check dropped);
  3. `declined` cuts a component and blocks re-suggestion, and a later tier-1 edge still merges;
  4. the lead identity's precedence, and `id` stability when a later identity is added;
  5. name precedence: typed > verified > displayName > handle;
  6. keys are lowercased and a mixed-case address matches (the §857 trap);
  7. the mirror payload never contains a `contact:` key (mutation: filter removed);
  8. at most one suggestion row per rebuild;
  9. a web3.bio reverse answer that does not forward-resolve is dropped (mutation: verify removed);
  10. `addToPeople` is offered exactly when `contact(for:)` is nil and an identity is readable, and
      `Open` exactly when it is not (mutation: both offered — a dead second disc, §83);
  11. saving from a counterparty writes the `AddressBook` entry and the `SavedContact` together
      (mutation: one write dropped), and a saved RSS writer writes no book entry.
- **`scripts/web3bio-selftest.sh`**: the `/ns` array shape, an unknown-platform record ignored, a
  `basenames` record filed as `.basename`, a 429 read as throttled, a 200 that is not an array
  read as "shape not readable" (§780b's honesty rule), never a value logged.
- Existing audits that must stay green and will bite: `network-reach-audit.sh` (the new host),
  `room-kind-tiles-selftest.sh` (four glyph constants), `feed-row-skeleton-audit.py` (the row draws
  no age), `plate-audit.py`, `footnote-audit.py` (one sentence in the room, none), `day-divider-audit.py`
  (`dated: false`), `swiftdata-liveness-audit.py` (the With-you list is a `ForEach` over a derived
  `[Thing]` — hold IDs, refetch), `defaults-lock-audit.py`, `feed-walk-selftest.sh` (a people row
  walks only inside its room), `demo-marking-audit.py` and the demo census (the Addresses room is a row).
- `live-integrations.sh` gains a warn-only web3.bio row.

## 7. Probes

- `-addressesProbe YES` — rebuild and NSLog `addresses| N contacts | links: v=… s=… c=…` then one line
  per person: `contact| <name> | <identities…> | tier words`. Never a phone or email.
- `-addressLinkProbe "<address|handle>"` — what web3.bio and the corpus say about one identity,
  every candidate edge with its tier and source, and whether it forward-verified.
- `-addressesDecline "<a>|<b>"` / `-addressesConfirm "<a>|<b>"` — write one ledger row headlessly, so the
  census can draw the confirmed and the suggested row.
- `-addressesSave "<identity key>|<name>"` — write one `SavedContact` headlessly (and the book entry
  when the key is an address); `-addressesProbe` then shows it with the tier word *saved*.
- `-openRoom "Contacts"` already lands in the room; `-openThing "<name>"` opens a contact's sheet.

## 8. Order

1. `Web3Bio.swift` + the `ENS` swap + `primaryNames` rows + reach + selftest. Ships alone:
   better names on transactions and Basenames resolve, no UI.
2. `ContactLinks` + `ContactIndex` over tier 1 only, `-addressesProbe`, the selftest. No UI. Measure
   on the user's own book: how many of their entries link at all. **This number decides section 8.3's
   priority** — a list of one-identity people is the Contacts room we have.
3. The room: `Shape.people`, tiles, sections, the sheet's Identities and With-you.
3b. `ContactBook` + `Add to Addresses` / `Open` on the dial, the saved tier word, `Remove from Addresses`.
4. Tier 2 suggestions from rules; the one row; decline.
5. The model verdict on-device; the cloud path is the same call and needs no work when granted.
6. Delete `AddressBookPeople`'s dead half.

## 9. Open questions (assumptions taken, say if wrong)

- **Name and place.** RULED: *Addresses* (user, 2026-09-24, twice — the second time against
  "Contacts", because "someone may have addresses that aren't people"), under the face as the
  Accounts screen's fourth segment, with the seat still *Contacts*. Not on the dock.
- **Order.** RULED (user, 2026-09-24): Recent, then Everyone alphabetical. No index bar (§752:
  nothing pinned at the top; the deleted book's `AddressIndexBar` stays deleted).
- **Who counts.** RULED by the name: everything you hold an address for. Apple contacts, wallet
  book entries (contracts and Safes included, with their kind), social accounts you watch, GitHub
  people, World App usernames, AND publications — Substack, RSS, YouTube, podcasts, Pinterest
  boards, Telegram channels — as `publication` rows keyed on the feed. A board is not a person,
  and it no longer has to be.
- **The "starts building" half.** RULED yes (user, 2026-09-24: *"yes, and any address or
  whatever a person should be able to save easily"*), and **RULED AGAIN: the naming prompt is
  offered ANY time, never gated on three dealings** (user: *"naming prompt for counterparty
  should be anytime, not just three times"*). Every unnamed counterparty — a wallet you
  received from, a sender who mailed once, a login that acted on your repo once — can be named
  the moment it appears: `Add to Addresses` on its row's dial and on the sheet (section 1), and
  the address card's own name field (§169). The nudge ROW in the Addresses list names the NEWEST
  unnamed counterparty ("0xab…12 sent you 0.2 ETH. Name them?"), one row at a time (section 1's
  one-row rule), and a dismissed nudge moves on to the next; no count is kept and no threshold
  exists. The three-times rule is DELETED.
