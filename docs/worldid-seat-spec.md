# The World ID seat — build spec

> **NOT BUILDABLE — MEASURED 2026-09-16 (prd §787).** §7's measurements were run before any code.
> `getPackedAccountData` is ZERO for a real World App wallet (a 1-of-1 Safe) and for its owner key:
> World App's authenticator is a hidden relayer-registered key, so no address a person can copy finds
> their World ID. Public World Chain RPCs cap `eth_getLogs` at 100 blocks, so §2.2's one-call history
> is thousands of calls. Every account's recovery agent is the same World contract. The rest of this
> document is kept as the record of what was planned; do not build it from here.

Written 2026-09-16 for a session with Xcode, a simulator and the icon file. It
is the ruling plus every registration point, derived by reading how the **Safe**
seat is wired (the user's own reference: *"a worldid seat like we have with safe
and others"*). Nothing here is built. §785 and §785a are shipped and untouched.

Numbers, addresses and event shapes below were read off `worldcoin/world-id-protocol`
at `9577f2f` and `contracts/deployments/core/production.json`. Everything marked
**UNMEASURED** has not been run against the live chain by anyone yet.

---

## 1. The ruling this reverses, and the line that survives

§785 refused a seat, citing **§515a**: *a protocol the wallet reads on its own
must never also ship as an offer* — the rule that keeps one capability from
appearing twice in the catalogue. That reasoning still holds for what §785
built, and that half does not change.

**The seat is a different subject.** Two facts, two surfaces:

| | subject | how it arrives | seat? |
|---|---|---|---|
| §785 (shipped) | is **any address** a verified human | the wallet reads it on its own, keylessly, when you open a card | **no** — §515a |
| this spec | **your own World ID account**: its keys, who can recover it, when its credential runs out, and every change to any of that | you name your World App address; it yields things | **yes** |

This is exactly Safe's split. The wallet reads addresses on its own; the Safe
seat reads *your* queue and *this phone's* signer standing. Same shape here.

**Write the ruling as §786** before the code, and state the §515a reasoning in
it — a later reader will otherwise see two World ID surfaces and assume drift.
(`prd-index-audit.py --next` said 922 sections written; confirm the number is
still free at commit time and say it out loud.)

---

## 2. What the seat reads, and how

All of it is **keyless `eth_call` / `eth_getLogs` on World Chain (480)** through
`WorldID.rpc`. No account, no key, no service, no World App. The seat adds **no
new host** — the one §785a moved to its own row already covers it.

`WorldIDRegistry` proxy: `0x0000000000aE079eB8a274cD51c0f44a9E4d67d4`

### 2.1 From an address to an account

```
getPackedAccountData(address authenticatorAddress) → uint256
```

Zero means *that address is not an admin authenticator on any World ID* — the
ordinary answer, and the seat must say so plainly rather than reading as broken.
Non-zero unpacks (`PackedAccountData.sol`, read directly):

- `leafIndex` = low 64 bits (`uint64(packed)`)
- `pubkeyId` = `packed >> 192`
- `recoveryCounter` = `packed >> 224`

**The `leafIndex` is a secret in this app's terms.** The World ID 4.0 spec names
authenticator-side knowledge of the raw leaf index as the tracking risk. Keychain,
never logged, never in a receipt, and it gets a row in `redaction-coverage-audit.py`.

### 2.2 The account's history — this is what the seat LANDS

Every account event carries `leafIndex` **indexed** (topic 1), so one
`eth_getLogs` filtered on it returns that account's whole history and nothing
else:

| event | what it means to a person |
|---|---|
| `AccountCreated` | your World ID was registered |
| `AuthenticatorInserted` | **a key was added to your World ID** |
| `AuthenticatorRemoved` | a key was removed |
| `AccountRecovered` | your account was recovered — every old key revoked |
| `RecoveryAgentUpdated` (+ initiate/execute/cancel/revert) | who can recover you changed |

`AuthenticatorInserted` is the one that matters most: **a key you did not add is
the compromise notice**, and the World ID spec itself lists user-visible account
auditability as a requirement nobody ships. It `standsAlone` in notifications
(`NotifyKind`), beside a dispute, a deadline, a liquidation and a Safe signature.

### 2.3 The two standing facts

- `getRecoveryAgent(uint64 leafIndex) → address` — set, or `address(0)`. "No
  recovery agent" is a real and useful fact: lose every key and the World ID is
  gone. State it; never nag.
- The Orb credential's expiry, which §785's `WorldIDSource` already reads for
  the same address. The seat does not re-read it — it draws what that store holds.

### 2.4 What it must never do

- Claim to hold your World ID, prove anything, or verify a person. It reads a
  public registry. The authenticator work (`docs/worldid-authenticator-spec.md`)
  is a different, larger thing and is not this.
- Say "not verified" about anybody. §785's four-case rule carries over whole.
- Read the leaf index of an address the person did not name.

---

## 3. The offer

```swift
Offer(name: "World ID",
      tagline: "Your World ID's keys, and what changes them",
      group: "Wallet", connectable: true, needsSetup: true,
      added: BridgeCatalog.day(2026, 9, 17))
```

- **Group `Wallet`**, with Safe, Altana, ENS and the rest.
- **Mode `.watchedWallets`** — it comes from `BridgeSetupMode.walletRidingSeats`
  containing the name, not from a literal on the screen. Add `"World ID"` to that
  set (`BridgeCatalog.swift:1141`) and `catalog-mode-audit.py` resolves it.
- The tagline follows §780c: it names what this seat brings, in its own nouns.

---

## 4. Every registration point

Derived by tracing `"Safe"` through the tree. Miss one and the seat is
half-present in a way no compiler catches.

| # | file | what to add |
|---|---|---|
| 1 | `Model/BridgeCatalog.swift` | the `Offer` in `allOffers`; `"World ID"` into `walletRidingSeats` (~:1141) |
| 2 | `Model/BridgeRouting.swift` | a `Destination` case (`case worldID`, beside `case safe` :25); `Row(offer: "World ID", id: "worldid", destination: .worldID)` (~:395); the wallet-riding name test (~:520); the destination switch (~:634) |
| 3 | `Model/BridgeStore.swift` | `WalletSeat(id: "worldid", name: "World ID", count:, noun: "World ID", can: [...])` (~:202); the `"Watching \(n) …"` localized arm (~:269) |
| 4 | `Model/WalletSeatStanding.swift` | `Seat(id: "worldid", thing: "World ID")` (~:52) — the seat is FOUND, not connected, so it takes the standing treatment |
| 5 | `Screens/WorldIDScreen.swift` | new — `AccountPage(name: "World ID", seatID: "worldid", source:, state: AccountPageState.of(...))`, modelled on `SafeScreen` |
| 6 | `Model/WorldIDAccount.swift` (+ `…Source.swift`) | the reads in §2, split pure/impure so the harness compiles the pure half whole |
| 7 | `Assets.xcassets/brand-worldid.imageset/` | the icon — see §6 |
| 8 | `website/` | shelf cell, hero marquee tile, `.ai-worldid` background — see §5 |
| 9 | `Model/NetworkReach.swift` | no new host; widen the World ID entry's purpose to name the seat's reads |
| 10 | `Model/NotifyPlan.swift` / `NotifySweep.swift` | the key-change notice; `standsAlone` |
| 11 | `docs/prd.md`, `CLAUDE.md`, `docs/hooks/wallet.md` | §786, one index line, the long entry |
| 12 | `scripts/worldid-seat-selftest.sh` (or extend `worldid-selftest.sh`) | the pure half + drift guards |
| 13 | `Shell/ProbeHooks.swift` | `-worldIDAccountProbe <0x…>` — packed data, leaf index presence, recovery agent, event count |

---

## 5. The website is a ship gate, not a follow-up

`catalog-sync.sh` fails the pass if a connectable offer is missing from the
website shelf, and CLAUDE.md's rule is that the app and website land **in the
same session**. Three edits, then bump the `?v=` cache-busters:

1. a `#catalog` shelf cell named exactly `World ID` (the name is the join key)
2. a hero marquee tile
3. an `.ai-worldid` background — **base64 data URI, never a hot link**

Watch the row placement: `catalog-sync.sh` compares name *sets* and is blind to
which category row a cell sits in (§780c). Put it on the Wallet row by eye.

---

## 6. The icon

`~/Downloads` has the real file. It now has a home, which it did not under §785:

- **App**: `Casberi/Casberi/Assets.xcassets/brand-worldid.imageset/` with a
  `Contents.json` beside the file — copy the shape of any existing
  `brand-*.imageset` (303 of them; `brand-safe` is the nearest sibling).
- **Website**: inline it as a base64 data URI on the `.ai-worldid` rule.

The mark is a dark glyph on transparent/white; check it reads on the dark theme
before shipping — several marks in this tree needed a light variant.

---

## 7. Measure before you build

The seat's entire content rests on a contract read **nobody has run**. Do these
first; if the first one fails, the seat has nothing to draw and the spec is wrong,
not the code.

1. `-worldIDProbe <0x…>` on the simulator — does `worldchain.drpc.org` answer,
   and does `addressVerifiedUntil` return a word rather than a revert? A zero
   word is a PASS (the selector is right; that address is simply absent).
2. `getPackedAccountData` against a World App address you control — non-zero?
   That is the seat's front door, and if World App's wallet address is not an
   *admin* authenticator (WIP-104 allows proving-only keys with no address at
   all), this seat cannot find an account from an address and needs a different
   door. **This is the single largest unknown in the document.**
3. `eth_getLogs` on the registry filtered by your `leafIndex` — how many events,
   and does a public RPC serve the range without a block-range cap that needs
   paging (`WalletApprovals.maxRange`'s problem).

---

## 8. Honesty lines to write into the screen

- Not connected, no address named: what the seat would show, empty
  (`DSEmptyState`), and the door — not a sentence telling you to act.
- Address named, `getPackedAccountData` zero: **"No World ID found for this
  address"** — a fact, not a failure, and not a claim about the person.
- Read unreachable: say the chain did not answer. Never render zero as absent.
- One `DSFootnote` at most (§748), and it should be the one honest thing the
  controls cannot say: this reads a public registry and holds nothing.
