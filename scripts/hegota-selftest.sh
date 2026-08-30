#!/bin/zsh
# The Ethrex Hegotá room's SCOPE rules and its UTXO arithmetic, compiled AS SHIPPED.
#
# `Model/HegotaSection.swift` and `Model/HegotaCoins.swift` are Foundation-only
# by design, so this compiles them WHOLE and unmodified — no stubs, no copied
# logic. Nothing on this host can make a coin get spent or a nonce key get used,
# so this harness is not the best proof these numbers are right, it is the ONLY
# one — the grade `journal-room-selftest.sh` describes.
#
# Every failure it catches renders as a perfectly ordinary room:
#   • a scope that never appears, indistinguishable from an address that
#     genuinely owns no coins
#   • a remembered scope resolving to the WRONG one, so the room opens somewhere
#     nobody picked and nothing on screen can explain why
#   • the spent bitmap read one storage region over, so EVERY coin reads unspent
#     and the card shows money that is already gone
#   • a missing bit treated as "not spent", which is the same wrong answer
#     arriving one coin at a time
#   • a fee computed from a bad parse, rendering as confidently as a real one
#
# None of that fails a build, a screen sweep or a probe.
set -euo pipefail
cd "$(dirname "$0")/.."

SECTION="Casberi/Casberi/Model/HegotaSection.swift"
COINS="Casberi/Casberi/Model/HegotaCoins.swift"
ACCOUNT="Casberi/Casberi/Model/HegotaAccount.swift"
ROOM="Casberi/Casberi/Model/HegotaRoom.swift"
# Foundation-only, and the nonce-slot derivation is real keccak — so the harness
# compiles the SHIPPED hash rather than asserting against a copied digest.
KECCAK="Casberi/Casberi/Model/Keccak256.swift"
VERIFY="scripts/verify.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail() { print -u2 "✗ $1"; exit 1; }

# ── the assertions, run against the shipped source ───────────────────────────
# Every fixture below is REAL: the logs, topics, values and slots are what
# rpc1.hegota.ethrex.xyz served on 2026-08-27, not numbers invented to pass.
cat > "$work/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { print("  ✗ \(what)"); failures += 1 }
}

// ─────────────────────────── scopes ───────────────────────────

check(HegotaSection.order == [.home, .activity, .accounts, .frames, .coins, .nonces, .sponsors],
      "order is home → activity → accounts → frames → coins → nonces → sponsors")
// **`frames` LEADS the conditional tail, ahead of `coins` (§504).** Pinned as
// its own assertion rather than left implicit in the list above, because it is
// a RULING — frame transactions are what the chain is for, and the scope reads
// directly off `activity`, which precedes it.
check(HegotaSection.order.firstIndex(of: .frames)! < HegotaSection.order.firstIndex(of: .coins)!,
      "frames leads the conditional tail, ahead of coins")
check(HegotaSection.order.firstIndex(of: .activity)! + 2 == HegotaSection.order.firstIndex(of: .frames)!,
      "frames sits as close behind activity as the tail rule permits")
check(HegotaSection.order.count == HegotaSection.allCases.count,
      "order lists every case — a new scope cannot be silently unlisted")
check(HegotaSection.order.first == .home, "home leads")
check(HegotaSection.order.last == .sponsors, "sponsors is last — the rarest scope")

// THE STRUCTURAL RULE, inherited from WalletSection: no unconditional scope may
// sit after a conditional one, so the strip's stable head never reflows. Frames
// opening the tail satisfies this — home, activity and accounts are the only
// unconditional scopes and all three precede it.
let firstConditional = HegotaSection.order.firstIndex { $0.isConditional }!
let lastUnconditional = HegotaSection.order.lastIndex { !$0.isConditional }!
check(lastUnconditional < firstConditional,
      "no unconditional scope sits after a conditional one")
check(HegotaSection.order[3] == .frames,
      "frames leads the conditional tail — the reading this chain exists for")
check(HegotaSection.order[2] == .accounts,
      "accounts closes the unconditional head — every watched address always has one")

check(HegotaSection.home.isAlwaysPresent, "home is always present")
check(HegotaSection.activity.isAlwaysPresent, "activity is always present")
check(HegotaSection.accounts.isAlwaysPresent, "accounts is always present")
for s in [HegotaSection.frames, .coins, .nonces, .sponsors] {
    check(s.isConditional, "\(s.rawValue) is conditional")
    check(!s.isAlwaysPresent, "\(s.rawValue) is not always present")
}
check(!HegotaSection.home.isConditional, "home is not conditional")
check(!HegotaSection.activity.isConditional, "activity is not conditional")
check(!HegotaSection.accounts.isConditional, "accounts is not conditional")

// present(): a false flag must not produce a scope, and the two constants must
// appear even when every flag is false — which is the state of MOST addresses
// on this chain, so it is the common path rather than an edge one.
check(HegotaSection.present(frames: false, coins: false, nonces: false, sponsors: false)
        == [.home, .activity, .accounts],
      "all flags false yields the three unconditional scopes alone")
check(HegotaSection.present(frames: true, coins: true, nonces: true, sponsors: true) == HegotaSection.order,
      "all flags true yields the full order")

// Each flag governs its OWN scope and no other — the mapping a careless edit
// gets wrong in a way nothing else can see.
check(HegotaSection.present(frames: true, coins: false, nonces: false, sponsors: false)
        == [.home, .activity, .accounts, .frames],
      "frames' flag yields frames alone beside the constants")
check(HegotaSection.present(frames: false, coins: true, nonces: false, sponsors: false)
        == [.home, .activity, .accounts, .coins],
      "coins' flag yields coins alone beside the constants")
check(HegotaSection.present(frames: false, coins: false, nonces: true, sponsors: false)
        == [.home, .activity, .accounts, .nonces],
      "nonces' flag yields nonces alone beside the constants")
check(HegotaSection.present(frames: false, coins: false, nonces: false, sponsors: true)
        == [.home, .activity, .accounts, .sponsors],
      "sponsors' flag yields sponsors alone beside the constants")

// present() returns DECLARATION order, not argument order.
let mixed = HegotaSection.present(frames: false, coins: true, nonces: false, sponsors: true)
check(mixed == [.home, .activity, .accounts, .coins, .sponsors], "present() preserves declaration order")
// **The tail's own order, proven by a mix rather than by the full list.** An
// address with frames and a sponsor but no coins is the shape that would expose
// a tail reordered by argument position rather than by declaration.
let tailMix = HegotaSection.present(frames: true, coins: false, nonces: false, sponsors: true)
check(tailMix == [.home, .activity, .accounts, .frames, .sponsors],
      "frames precedes sponsors when both are present and coins is not")

// resolve(): the fallback is home, NEVER "the first present scope". The two
// differ only when home is absent, which cannot happen — and that is the point,
// since the wrong fallback silently opens somewhere nobody chose.
check(HegotaSection.resolve(nil, present: HegotaSection.order) == .home,
      "nil resolves to home — the room's front door")
check(HegotaSection.resolve(.coins, present: HegotaSection.order) == .coins,
      "a present scope resolves to itself")
check(HegotaSection.resolve(.sponsors, present: [.home, .activity]) == .home,
      "a scope whose content has gone falls back to home")
// The fixture that separates "falls back to home" from "falls back to the first
// present entry" — without it both implementations pass every case above.
check(HegotaSection.resolve(.sponsors, present: [.coins, .home]) == .home,
      "falls back to HOME, not to the first entry of `present`")

// shows(): one scope is a label, not a control (§83).
check(!HegotaSection.shows(present: [.home]), "one scope draws no strip")
check(!HegotaSection.shows(present: []), "no scopes draw no strip")
check(HegotaSection.shows(present: [.home, .activity]), "two scopes draw a strip")

// THE NAMING RULING (2026-08-27): the literal term, not a metaphor.
check(HegotaSection.nonces.label == "Nonces", "the keyed-nonce scope reads Nonces")
check(HegotaSection.home.label == "Home", "home reads Home")
check(HegotaSection.activity.label == "Activity", "activity reads Activity")
check(HegotaSection.coins.label == "UTXOs", "the unspent-output scope reads UTXOs, the chain's own word")
check(HegotaSection.sponsors.label == "Sponsors", "sponsors reads Sponsors")
for s in HegotaSection.allCases {
    check(!s.label.contains(" "), "\(s.rawValue)'s label is ONE word — the strip must not wrap")
    check(s.label.count <= 11, "\(s.rawValue)'s label is short enough for a chip")
    check(!s.summary.isEmpty, "\(s.rawValue) carries an accessibility summary")
    check(s.summary != s.label, "\(s.rawValue)'s summary says more than its label")
    check(s.id == s.rawValue, "\(s.rawValue)'s id is its raw value — a computed id re-centres the strip on nothing")
}

// NO DOTS, EVER. Nothing in this room is urgent: no deadline, no liquidation,
// no expiry, no grant to revoke, and the asset has no price.
check(HegotaSection.attention().isEmpty, "no scope ever wears an attention dot")

// ─────────────────────────── words off the wire ───────────────────────────

check(HegotaWord.normalized("0x" + String(repeating: "a", count: 64)) != nil,
      "a 64-nibble word with 0x normalizes")
check(HegotaWord.normalized(String(repeating: "a", count: 64)) != nil,
      "a 64-nibble word without 0x normalizes")
check(HegotaWord.normalized(String(repeating: "a", count: 63)) == nil,
      "a short word is refused — a shape we did not expect is not one to guess at")
check(HegotaWord.normalized(String(repeating: "a", count: 65)) == nil, "a long word is refused")
check(HegotaWord.normalized(String(repeating: "z", count: 64)) == nil, "a non-hex word is refused")

// The real value word off the chain's first UTXO: exactly 1 ETH.
let oneETH = "0x0000000000000000000000000000000000000000000000000de0b6b3a7640000"
check(HegotaWord.integer(oneETH) == Decimal(1_000_000_000_000_000_000),
      "1 ETH parses exactly from its real log word")
check(HegotaWord.integer("0x" + String(repeating: "f", count: 64)) == nil,
      "a word too large to hold exactly is REFUSED, never rounded")
check(HegotaWord.integer("0x" + String(repeating: "0", count: 64)) == Decimal(0),
      "a zero word is zero, not nil")

check(HegotaWord.index("0x" + String(repeating: "0", count: 62) + "2f") == 47,
      "a coin index parses from its word")
check(HegotaWord.index("0x" + String(repeating: "f", count: 64)) == nil,
      "an index too large for the vault's own layout is refused, never truncated")

// The real source topic off that same log.
let realTopic = "0x00000000000000000000000056acbd6ef7bb3748fb9cab82f2bbdc4af3d74bfd"
check(HegotaWord.address(topic: realTopic) == "0x56acbd6ef7bb3748fb9cab82f2bbdc4af3d74bfd",
      "an address parses out of a real 32-byte topic, lowercased")
// THE DISCRIMINATING FIXTURE: a topic whose upper bytes are NOT zero is not an
// address we failed to read, it is a log we have misunderstood — and taking its
// low 20 bytes anyway invents a counterparty.
check(HegotaWord.address(topic: "0x00000000000000000000000156acbd6ef7bb3748fb9cab82f2bbdc4af3d74bfd") == nil,
      "a topic with a non-zero upper byte yields NO address")

// ─────────────────────────── the spent bitmap ───────────────────────────

check(HegotaVaultStorage.word(index: 0) == 0, "coin 0 lives in word 0")
check(HegotaVaultStorage.word(index: 255) == 0, "one word covers 256 coins")
check(HegotaVaultStorage.word(index: 256) == 1, "coin 256 starts the next word")

// The real slots, as queried against the live chain.
check(HegotaVaultStorage.spentSlot(index: 0)
        == "0x0000000000000000000000000000000200000000000000000000000000000000",
      "the spent region begins at 2^129")
check(HegotaVaultStorage.spentSlot(index: 300)
        == "0x0000000000000000000000000000000200000000000000000000000000000001",
      "the word index adds into the LOW nibbles, never carrying into the marker bit")

// Bit 0 set, nothing else.
let bit0 = "0x" + String(repeating: "0", count: 63) + "1"
check(HegotaVaultStorage.isSpent(index: 0, word: bit0) == true, "bit 0 reads as spent")
check(HegotaVaultStorage.isSpent(index: 1, word: bit0) == false, "bit 1 reads as unspent")
// Bit 4 lives in the SECOND nibble from the right — the check that pins which
// end of the word the bits are counted from.
let bit4 = "0x" + String(repeating: "0", count: 62) + "10"
check(HegotaVaultStorage.isSpent(index: 4, word: bit4) == true, "bit 4 reads out of the second nibble")
check(HegotaVaultStorage.isSpent(index: 0, word: bit4) == false, "bit 0 is clear in that word")
check(HegotaVaultStorage.isSpent(index: 255, word: "0x8" + String(repeating: "0", count: 63)) == true,
      "bit 255 reads out of the leading nibble")
check(HegotaVaultStorage.isSpent(index: 0, word: "nonsense") == nil,
      "an unreadable word yields nil — never a confident 'not spent'")

// ─────────────────────────── coins ───────────────────────────

let sig = HegotaChain.utxoCreatedTopic
let alice = "0x00000000000000000000000056acbd6ef7bb3748fb9cab82f2bbdc4af3d74bfd"
let bob   = "0x00000000000000000000000056ae0bf9c161b74f902c34fc75d9ff17979b2fa9"
// The real first log: index 0, 1 ETH, alice → bob, block 0x1578d.
let realData = "0x0000000000000000000000000000000000000000000000000000000000000000"
             + "0000000000000000000000000000000000000000000000000de0b6b3a7640000"
let first = HegotaCoins.coin(topics: [sig, alice, bob], data: realData, block: 87949)
check(first?.index == 0, "the real log's index parses")
check(first?.wei == Decimal(1_000_000_000_000_000_000), "the real log's value parses")
check(first?.owner == "0x56ae0bf9c161b74f902c34fc75d9ff17979b2fa9", "the recipient is topic 2")
check(first?.source == "0x56acbd6ef7bb3748fb9cab82f2bbdc4af3d74bfd", "the creator is topic 1")
check(first?.isChange == false, "a coin paid to somebody else is not change")

let selfPaid = HegotaCoins.coin(topics: [sig, bob, bob], data: realData, block: 87949)
check(selfPaid?.isChange == true, "a coin whose source is its owner IS change")

check(HegotaCoins.coin(topics: [HegotaChain.transferTopic, alice, bob], data: realData, block: 1) == nil,
      "a log wearing the TRANSFER signature is not a coin")
check(HegotaCoins.coin(topics: [sig, alice], data: realData, block: 1) == nil,
      "a log missing a topic yields no coin")
check(HegotaCoins.coin(topics: [sig, alice, bob], data: "0x00", block: 1) == nil,
      "a truncated data field yields no coin — never a coin of unknown value")

// unspent(): the ordering, and THE refusal.
func made(_ i: UInt64, _ wei: Int) -> HegotaCoin {
    HegotaCoin(index: i, wei: Decimal(wei), source: "0xa", owner: "0xb", block: 1)
}
let three = [made(2, 500), made(0, 100), made(1, 400)]
let allClear: [UInt64: String] = [0: "0x" + String(repeating: "0", count: 64)]
check(HegotaCoins.unspent(three, words: allClear)?.map(\.index) == [0, 1, 2],
      "unspent coins come back oldest first, by the vault's own counter")

// coin 1 spent (bit 1), coins 0 and 2 clear
let bit1 = "0x" + String(repeating: "0", count: 63) + "2"
check(HegotaCoins.unspent(three, words: [0: bit1])?.map(\.index) == [0, 2],
      "a spent coin is dropped and the rest survive")

// THE LOAD-BEARING REFUSAL: a coin whose word is missing is not "unspent".
check(HegotaCoins.unspent([made(0, 1), made(300, 1)], words: allClear) == nil,
      "a coin whose spent bit could not be read refuses the WHOLE set")
check(HegotaCoins.unspent([], words: [:])?.isEmpty == true,
      "no coins is an empty set, not a refusal")

// reconciles(): exact, because these are integers off the same chain.
let two = [made(0, 400), made(1, 600)]
check(HegotaCoins.reconciles(unspent: two, vaultWei: Decimal(1000)), "an exact sum reconciles")
check(!HegotaCoins.reconciles(unspent: two, vaultWei: Decimal(1001)),
      "one wei out does NOT reconcile — a tolerance here would only hide a bug")
check(!HegotaCoins.reconciles(unspent: two, vaultWei: Decimal(999)), "short by one wei does not reconcile")

// fee(): the REAL split on chain — 1 ETH in, 0.4 + 0.5 out, change back.
let inputs = [Decimal(1_000_000_000_000_000_000)]
let outputs = [Decimal(400_000_000_000_000_000),
               Decimal(500_000_000_000_000_000),
               Decimal(99_941_393_999_589_758)]
check(HegotaCoins.fee(inputs: inputs, outputs: outputs) == Decimal(58_606_000_410_242),
      "the real spend's fee is derived exactly from inputs minus outputs")
check(HegotaCoins.fee(inputs: inputs, outputs: [Decimal(2_000_000_000_000_000_000)]) == nil,
      "outputs exceeding inputs yield NO fee — a negative fee is a parse bug wearing a number")
check(HegotaCoins.fee(inputs: [], outputs: outputs) == nil, "no inputs yields no fee")
check(HegotaCoins.fee(inputs: inputs, outputs: inputs) == Decimal(0), "a zero fee is zero, not nil")

check(HegotaCoins.total([]) == Decimal(0), "an empty set totals zero")
check(HegotaCoins.eth(Decimal(1_000_000_000_000_000_000)) == Decimal(1), "1e18 wei is 1 ETH")
check(HegotaCoins.eth(Decimal(0)) == Decimal(0), "zero wei is zero ETH")

// The predeploys are fixed by spec — verified on chain to carry code.
check(HegotaChain.vault == "0x0000000000000000000000000000000000008312", "the vault predeploy address")
check(HegotaChain.nonceManager == "0x0000000000000000000000000000000000008250", "the nonce manager address")
check(HegotaChain.chainID == 3151908, "the chain id")

// ─────────────────────────── the room head ───────────────────────────

func acct(_ a: String, reached: Bool = true, wei: Int? = 1000,
          coins: [HegotaCoin] = [], reconciled: Bool = true,
          lanes: [HegotaNonceLane] = [], moves: [HegotaMove] = []) -> HegotaAccount {
    var x = HegotaAccount(address: a)
    x.reached = reached
    x.balanceWei = wei.map { Decimal($0) }
    x.coins = coins
    x.unspent = coins.isEmpty ? [] : coins
    x.reconciled = reconciled
    x.lanes = lanes
    x.moves = moves
    return x
}
func coin(_ i: UInt64, _ wei: Int, change: Bool = false) -> HegotaCoin {
    HegotaCoin(index: i, wei: Decimal(wei), source: change ? "0xme" : "0xthem",
               owner: "0xme", block: 1)
}
func mv(_ payer: String?, sender: String?) -> HegotaMove {
    var m = HegotaMove(hash: "0xh", counterparty: "0xc", wei: Decimal(1),
                       incoming: false, block: 1)
    m.payer = payer; m.sender = sender
    return m
}

check(HegotaRoom.head([]) == nil, "nothing watched is NO room, not an empty one")

// A WATCH LIST WITH NO SWEEP YET IS STILL A ROOM. Reported from a device as an
// address that "has nothing": it was neither a failure nor an empty account,
// it was a read that had not run, and returning nil drew a blank room.
let pending = HegotaRoom.head([], hasRead: false, watching: 2)
check(pending != nil, "a watched address with no sweep yet is still a room")
check(pending?.hasRead == false, "…and it says no read has happened")
check(pending?.watched == 2, "…and how many it is waiting on")
check(pending?.balanceWei == nil, "…with no total, since nothing has been read")
// hasRead and everythingUnreached are DIFFERENT facts: not tried yet vs tried
// and failed. Collapsing them makes a room you just opened claim the chain is
// unreachable.
check(HegotaRoom.head([acct("0xa", reached: false, wei: nil)])?.hasRead == true,
      "a completed sweep that reached nothing still counts as read")
check(pending?.everythingUnreached == true,
      "an unread room reports nothing reached — the card must branch on hasRead FIRST")

// THE RANK. Coins leads because it is the reading no other room can draw.
check(HegotaRoom.head([acct("0xa", coins: [coin(1, 5)])])?.lead == .coins, "coins leads")
check(HegotaRoom.head([acct("0xa")])?.hasRead == true, "a normal compose reports a read")
check(HegotaRoom.head([acct("0xa", moves: [mv("0xp", sender: "0xs")])])?.lead == .sponsored,
      "sponsorship leads when there are no coins")
check(HegotaRoom.head([acct("0xa", lanes: [HegotaNonceLane(key: "0x1", seq: "0x0", lastBlock: 1, sends: 1)])])?.lead == .nonces,
      "nonces lead when there are no coins and no sponsor")
check(HegotaRoom.head([acct("0xa", moves: [mv("0xs", sender: "0xs")])])?.lead == .moves,
      "a self-paid move leads with moves, never with sponsorship")
check(HegotaRoom.head([acct("0xa")])?.lead == .nothing, "an account with nothing leads with nothing")

// THE DISCRIMINATING FIXTURES. Each of the five cases above holds exactly ONE
// candidate, so every one of them passes whatever order the ladder is written
// in — measured, not assumed: swapping coins and sponsorship left all five
// green and the mutation survived. A rank is only tested by a fixture that
// holds BOTH candidates and can therefore fail one ordering.
let coinsAndSponsor = acct("0xa", coins: [coin(1, 5)], moves: [mv("0xp", sender: "0xs")])
check(HegotaRoom.head([coinsAndSponsor])?.lead == .coins,
      "coins beat sponsorship when an account has both")
check(HegotaRoom.head([coinsAndSponsor])?.sponsoredCount == 1,
      "…and the sponsorship it did not lead with is still counted")
let sponsorAndLanes = acct("0xa", lanes: [HegotaNonceLane(key: "0x1", seq: "0x0", lastBlock: 1, sends: 1)],
                           moves: [mv("0xp", sender: "0xs")])
check(HegotaRoom.head([sponsorAndLanes])?.lead == .sponsored,
      "sponsorship beats nonces when an account has both")
let lanesAndMoves = acct("0xa", lanes: [HegotaNonceLane(key: "0x1", seq: "0x0", lastBlock: 1, sends: 1)],
                         moves: [mv("0xs", sender: "0xs")])
check(HegotaRoom.head([lanesAndMoves])?.lead == .nonces,
      "nonces beat plain moves when an account has both")
// And the whole ladder at once, which no pair can pin on its own.
let everything = acct("0xa", coins: [coin(1, 5)],
                      lanes: [HegotaNonceLane(key: "0x1", seq: "0x0", lastBlock: 1, sends: 1)],
                      moves: [mv("0xp", sender: "0xs")])
check(HegotaRoom.head([everything])?.lead == .coins, "coins lead an account that has all four")

// AN UNREACHED ACCOUNT IS NAMED, NEVER FOLDED IN AS ZERO. This is the silent
// wrong answer the whole seat is built to avoid: a total quietly missing an
// account reads exactly like money leaving.
let partialHead = HegotaRoom.head([acct("0xa", wei: 500), acct("0xb", reached: false, wei: nil)])
check(partialHead?.balanceWei == Decimal(500), "the total sums REACHED accounts only")
check(partialHead?.reached == 1 && partialHead?.watched == 2, "the head reports how many answered")
check(partialHead?.partial == true, "a head missing an account says it is partial")
check(HegotaRoom.head([acct("0xa", reached: false, wei: nil)])?.balanceWei == nil,
      "nothing reached has NO total — zero would be a claim")
check(HegotaRoom.head([acct("0xa", reached: false, wei: nil)])?.everythingUnreached == true,
      "nothing reached says so")
check(HegotaRoom.head([acct("0xa", wei: 500)])?.partial == false, "a complete head is not partial")

// A SET THAT DID NOT RECONCILE CONTRIBUTES NO COINS — the gate, at the head.
check(HegotaRoom.head([acct("0xa", coins: [coin(1, 5)], reconciled: false)])?.coinCount == 0,
      "coins from an unreconciled set are not counted")
check(HegotaRoom.head([acct("0xa", coins: [coin(1, 5)], reconciled: false)])?.lead != .coins,
      "an unreconciled set never leads with coins")
check(acct("0xa", coins: [coin(1, 5)], reconciled: false).coinsWei == nil,
      "an unreconciled account states no coin total")

// sections() is derived from the ROOM, never the watch list.
check(HegotaRoom.sections([]) == [], "no accounts offers no scopes")
check(HegotaRoom.sections([acct("0xa", reached: false, wei: nil)]) == [],
      "an unreached account offers no scopes — a chip that opens nothing is a dead control")
check(HegotaRoom.sections([acct("0xa")]) == [.home, .activity, .accounts],
      "a reached but empty account offers the three constants")
check(HegotaRoom.sections([acct("0xa", coins: [coin(1, 5)])]) == [.home, .activity, .accounts, .coins],
      "coins earn their chip")

// split(): derived, and refused when it cannot be derived.
check(HegotaRoom.split(inputs: [Decimal(1000)], outputs: [coin(1, 400), coin(2, 500)])?.fee == Decimal(100),
      "a split's fee is inputs minus outputs")
check(HegotaRoom.split(inputs: [], outputs: [coin(1, 400)]) == nil, "no inputs is no split")
check(HegotaRoom.split(inputs: [Decimal(1000)], outputs: []) == nil, "no outputs is no split")
check(HegotaRoom.split(inputs: [Decimal(100)], outputs: [coin(1, 400)]) == nil,
      "outputs exceeding inputs yield no split")
check(HegotaRoom.split(inputs: [Decimal(1000)],
                       outputs: [coin(2, 500), coin(1, 400, change: true)])?.outputs.map(\.index) == [1, 2],
      "a split's outputs come back in creation order")
check(HegotaRoom.split(inputs: [Decimal(1000)],
                       outputs: [coin(1, 400, change: true), coin(2, 500)])?.changeCount == 1,
      "the change output is counted")

// ───────────────── the bar scale (prd §503) ─────────────────
// The failure this prevents is specific and severe: a devnet prefunds
// addresses, so one watched account really holds nine hundred million times
// another's, and plain bars draw the account somebody USES as nothing.
check(HegotaScale.of([Decimal(10), Decimal(50)]) == .linear,
      "a comparable set stays linear — the ordinary case is a plain bar chart")
check(HegotaScale.of([Decimal(1), Decimal(1_000_000)]) == .logarithmic,
      "a set spanning six orders takes the log scale")
check(HegotaScale.of([Decimal(1), Decimal(100)]) == .linear,
      "exactly at the ceiling is still linear — the smallest bar is 1%, a visible sliver")
check(HegotaScale.of([Decimal(1), Decimal(101)]) == .logarithmic,
      "one past the ceiling flips")
check(HegotaScale.of([]) == .linear, "an empty set has no spread to answer for")
check(HegotaScale.of([Decimal(0), Decimal(5)]) == .linear,
      "zeros are excluded from the spread rather than making it infinite")
let linShare = HegotaScale.share(Decimal(50), in: [Decimal(50), Decimal(100)], scale: .linear)
check(abs(linShare - 0.5) < 0.001, "a linear share is the plain ratio to the largest")
check(HegotaScale.share(Decimal(0), in: [Decimal(50)], scale: .linear) == 0,
      "a true zero draws NOTHING — distinct from a small value's floor")
check(HegotaScale.share(Decimal(1), in: [Decimal(1), Decimal(1_000_000)], scale: .linear) >= 0.02,
      "a real value keeps a visible stub — a bar of no length reads as an absent account")
check(HegotaScale.share(Decimal(1_000_000), in: [Decimal(1), Decimal(1_000_000)], scale: .logarithmic) == 1,
      "the largest fills the bar on either scale")
check(HegotaScale.share(Decimal(1), in: [Decimal(1), Decimal(1_000_000)], scale: .logarithmic) >= 0.06,
      "the log floor keeps the smallest readable")

// ───────────────── the flow band ─────────────────
func fmv(_ other: String, _ wei: Int, incoming: Bool, modes: [HegotaFrame.Mode] = []) -> HegotaMove {
    var m = HegotaMove(hash: "0x\(other)\(wei)", counterparty: other, wei: Decimal(wei),
                       incoming: incoming, block: 1)
    if !modes.isEmpty {
        m.frames = modes.map { HegotaFrame(mode: $0, target: nil, wei: 0,
                                           succeeded: true, gasUsed: 1, stateGasUsed: 0) }
    }
    return m
}
let band = HegotaFlow.band([fmv("0xa", 100, incoming: true), fmv("0xb", 30, incoming: true),
                            fmv("0xa", 10, incoming: false)])
check(band?.inWei == Decimal(130), "the in side sums its own lanes")
check(band?.outWei == Decimal(10), "the out side sums its own")
check(band?.scaleWei == Decimal(130), "ONE scale across both sides — the larger of the two")
check(band?.inLanes.first?.address == "0xa", "lanes rank by AMOUNT, not by count")
check(HegotaFlow.band([]) == nil, "no moves is no band")
check(HegotaFlow.band([fmv("0xa", 0, incoming: true)]) == nil,
      "a zero-value move builds no lane — a bar for money that did not move")
// The same counterparty on BOTH sides must not net out.
let twoSided = HegotaFlow.band([fmv("0xv", 50, incoming: true), fmv("0xv", 20, incoming: false)])
check(twoSided?.inLanes.count == 1 && twoSided?.outLanes.count == 1,
      "one counterparty on both sides is TWO lanes — netting them draws neither")
check(twoSided?.inLanes.first?.id != twoSided?.outLanes.first?.id,
      "the side is part of a lane's identity")
// Folding: the tail is NAMED, never dropped.
let many = (1...8).map { fmv("0x\($0)", $0 * 10, incoming: true) }
let folded = HegotaFlow.band(many)
check(folded?.inLanes.count == HegotaFlow.laneLimit + 1, "past the limit the tail folds into one lane")
check(folded?.inLanes.last?.isOther == true, "the folded lane says it is a fold")
check(folded?.inWei == Decimal(360), "a folded band still totals EVERY move — no silent cap")
check(HegotaFlow.modes(of: [fmv("0xa", 1, incoming: true, modes: [.utxo, .utxo, .verify])]).first == .utxo,
      "a lane's leading mode is the one that did most of its work")
check(HegotaFlow.modes(of: [fmv("0xa", 1, incoming: true)]).isEmpty,
      "an ordinary transfer reports no modes — it is tinted neutral, not given a step")

// ───────────────── who the other side is ─────────────────
check(HegotaParty.of(HegotaChain.vault, watched: []) == .vault, "the vault is named, not filed as a stranger")
check(HegotaParty.of("0xAbC", watched: ["0xabc"]) == .mine("0xabc"),
      "matching is case-INSENSITIVE — EIP-55 case is a checksum, not an identity")
check(HegotaParty.of("0xzzz", watched: ["0xabc"]).isMine == false,
      "an address you do not watch is a stranger")

// ───────────────── sponsors ─────────────────
func spon(_ payer: String, _ block: UInt64, fee: Int?) -> HegotaMove {
    var m = HegotaMove(hash: "0x\(payer)\(block)", counterparty: "0xc", wei: Decimal(1),
                       incoming: true, block: block)
    m.sender = "0xme"; m.payer = payer
    m.feeWei = fee.map { Decimal($0) }
    return m
}
let sponsors = HegotaSponsor.group([spon("0xp1", 3, fee: 10), spon("0xp1", 2, fee: 5),
                                    spon("0xp2", 1, fee: 7)])
check(sponsors.count == 2, "sponsors group by who PAID")
check(sponsors.first?.payer == "0xp1", "the sponsor who paid for most leads")
check(sponsors.first?.feeWei == Decimal(15), "a sponsor's gas is summed")
check(sponsors.first?.moves.first?.block == 3, "a sponsor's moves come back newest first")
check(HegotaSponsor.group([spon("0xp1", 1, fee: 10), spon("0xp1", 2, fee: nil)]).first?.feeWei == nil,
      "one unread fee makes the WHOLE total nil — a partial sum understates a gift, silently")
check(HegotaSponsor.group([mv(nil, sender: "0xme")]).isEmpty,
      "a self-paid move has no sponsor")

// ───────────────── the nonce totals ─────────────────
func keyed(_ key: String, sends: Int) -> HegotaNonceLane {
    HegotaNonceLane(key: key, seq: "0x0", lastBlock: 1, sends: sends)
}
// **TWO SENDS ARE TWO HASHES.** This fixture used to pass one move twice, which
// counted 2 only because the implementation counted rows — and a self-payment
// lands as two moves under ONE hash, so that shape now (correctly) counts 1.
// A fixture only tests the rule it names if it fails that rule and passes every
// other one, so the two sends are two transactions, as they are on chain.
let plain = HegotaMove(hash: "0xp1", counterparty: "0xc", wei: Decimal(1), incoming: false, block: 1)
let plain2 = HegotaMove(hash: "0xp2", counterparty: "0xc", wei: Decimal(1), incoming: false, block: 2)
let inbound = HegotaMove(hash: "0xi", counterparty: "0xc", wei: Decimal(1), incoming: true, block: 1)
let totals = HegotaNonceTotals.of([plain, plain2, inbound], lanes: [keyed("0xbeef", sends: 2)])
check(totals.ordinarySends == 2,
      "key 0 counts only what this address SENT — an inbound move was somebody else's nonce")
check(totals.keyedSends == 2, "named keys sum their own sends")
check(totals.counters == 2, "key 0 is a counter too — the one the list can never show")
check(totals.total == 4, "the total spans both kinds")
check(HegotaNonceTotals.of([inbound], lanes: []).counters == 0,
      "an address that has never sent keeps no counters")

// **A MULTI-OUTPUT SPEND is one transaction and advanced ONE counter**, and it
// lands as several OUTGOING moves sharing a hash — which is the ordinary shape
// of a UTXO spend on this chain, not a corner case (§500's own worked example:
// 1.0 ETH in, 0.4 out, 0.5 out, 0.099941 change). Counting rows reports three.
//
// The first cut of this fixture used a self-payment — one outgoing move and one
// incoming — and the mutation SURVIVED, because `!move.incoming` already
// dropped the second one and the hash fold never ran. A fixture only tests the
// rule it names if it fails that rule and passes every other one.
let splitA = HegotaMove(hash: "0xsplit", counterparty: "0xr1", wei: Decimal(4),
                        incoming: false, block: 3)
let splitB = HegotaMove(hash: "0xsplit", counterparty: "0xr2", wei: Decimal(5),
                        incoming: false, block: 3)
check(HegotaNonceTotals.of([splitA, splitB], lanes: []).ordinarySends == 1,
      "a spend paying two recipients advances ONE ordinary nonce, not two")

// **THE CHAIN'S OWN COUNTER WINS, and the gap is the finding.** A transaction
// that moved no ETH emits no transfer log, so the observable moves undercount —
// on the chain whose whole subject is transactions that verify and check.
let counted = HegotaNonceTotals.of([plain, plain2, inbound], lanes: [],
                                   nonceCount: 5, valuelessSends: 3)
check(counted.ordinarySends == 5, "the read nonce is the number of ordinary sends")
check(counted.nonceRead, "a read nonce is marked as read")
check(counted.valuelessSends == 3, "the sends that moved nothing are carried")
check(!HegotaNonceTotals.of([plain], lanes: []).nonceRead,
      "a derived count is NOT narrated as the chain's own")
// A counter BELOW what we can already name is impossible on chain, so the
// observed floor is kept — reporting fewer sends than the list beneath it
// enumerates is the one output worse than not knowing.
check(HegotaNonceTotals.of([plain, plain2], lanes: [], nonceCount: 1).ordinarySends == 2,
      "a nonce below the observed moves keeps the observed floor")

// ───────────────── frames: what the transactions DID ─────────────────
func framed(_ hash: String, _ modes: [HegotaFrame.Mode],
            ok: Bool? = true, incoming: Bool = false) -> HegotaMove {
    var m = HegotaMove(hash: hash, counterparty: "0xc", wei: Decimal(1),
                       incoming: incoming, block: 1)
    m.frames = modes.map { HegotaFrame(mode: $0, target: nil, wei: 0,
                                       succeeded: ok, gasUsed: 1, stateGasUsed: 0) }
    return m
}
check(HegotaFrameMix.of([plain]) == nil,
      "a transaction whose frames were never read composes NO mix — not an empty one")
let mix = HegotaFrameMix.of([framed("0xa", [.utxo, .utxo, .verify]),
                             framed("0xb", [.utxo])])!
check(mix.transactions == 2, "transactions are counted, not frames")
check(mix.total == 4, "every frame is counted")
check(mix.busiest?.mode == .utxo && mix.busiest?.count == 3,
      "the commonest mode leads the mix")
check(mix.slices.count == 2, "one slice per distinct mode")
// Ties break by the mode's own name, so the drawing is stable between opens —
// a figure that reshuffles over identical data reads as broken.
let tied = HegotaFrameMix.of([framed("0xt", [.verify, .utxo])])!
check(tied.slices.map(\.mode) == [.utxo, .verify], "a tie breaks by name, not by chance")
// ...and the ORDER that tiebreak produces must never be narrated as a WINNER.
// The shipped caption read `busiest` as a superlative, so a 7–7 Send/Verify
// split said "mostly Send steps" — `sender` sorts before `verify` — directly
// above a legend printing both sevens. `leaders` is the caption's question.
check(tied.leaders.count == 2, "a tie has TWO leaders, not a winner picked by the alphabet")
check(!tied.hasCommonest, "a tie has no commonest step")
check(mix.leaders.count == 1 && mix.hasCommonest,
      "a real winner is still one leader")
// The fixture must FAIL the rule it names and pass every other one: this one
// is tied on the top count while a THIRD mode sits below it, so a `leaders`
// that simply returned every slice would pass a two-way fixture by accident.
let threeWay = HegotaFrameMix.of([framed("0x1", [.utxo, .verify, .sender, .sender, .utxo, .verify]),
                                  framed("0x2", [.general])])!
check(threeWay.leaders.count == 3,
      "every mode sharing the top count is a leader — and the one below it is not")
check(threeWay.leaders.allSatisfy { $0.count == 2 },
      "a leader shares the TOP count, never merely appears")
// A single-mode mix is not "mostly" anything either. `hasCommonest` is false
// so the caption can say "all", which is both true and a stronger reading.
let sweep = HegotaFrameMix.of([framed("0xw", [.utxo, .utxo])])!
check(sweep.leaders.count == 1 && !sweep.hasCommonest,
      "one mode present is ALL of them, never 'mostly' one of them")
// A self-payment is ONE transaction here too.
check(HegotaFrameMix.of([framed("0xs", [.utxo]),
                         framed("0xs", [.utxo], incoming: true)])!.transactions == 1,
      "both directions of one transaction count once")
// Failure and unreadability are different, and the strip draws them differently.
let broken = HegotaFrameMix.of([framed("0xf", [.utxo], ok: false),
                                framed("0xu", [.verify], ok: nil)])!
check(broken.failed == 1, "a failed frame is counted as failed")
check(broken.unknown == 1, "a frame whose receipt would not pair is NOT counted as failed")

// ───────────────── the chain-wide vault census ─────────────────
func owned(_ i: UInt64, _ wei: Int, _ who: String) -> HegotaCoin {
    HegotaCoin(index: i, wei: Decimal(wei), source: "0xsrc", owner: who, block: 1)
}
let everyCoin = [owned(1, 70, "0xme"), owned(2, 20, "0xthem"), owned(3, 10, "0xother")]
check(HegotaCensus.of(everyCoin, mine: ["0xme"], reconciled: false) == nil,
      "an unreconciled set yields NO census — a denominator nobody should read")
check(HegotaCensus.of([], mine: ["0xme"], reconciled: true) == nil,
      "an empty vault yields no census")
let census = HegotaCensus.of(everyCoin, mine: ["0xME"], reconciled: true)!
check(census.coins == 3 && census.owners == 3, "the census spans every owner on the chain")
check(census.mineCoins == 1 && census.mineWei == Decimal(70),
      "our slice is matched case-insensitively — EIP-55 and an RPC's lowercase are one address")
check(abs((census.share ?? 0) - 0.7) < 0.0001, "the share is ours over the whole vault")
check(!census.soleOwner, "a vault with three owners is not solely ours")
let alone = HegotaCensus.of([owned(1, 5, "0xme")], mine: ["0xme"], reconciled: true)!
check(alone.soleOwner, "one owner holding every coin is the sole owner")
check(HegotaCensus(coins: 0, owners: 0, wei: 0, mineCoins: 0, mineWei: 0).share == nil,
      "a share of an empty vault is undefined, never zero")

// ───────────────── dominance: what a rank-ordered treemap cannot show ────────
check(HegotaCoins.dominance([coin(1, 100)]) == nil, "one coin has no dominance to report")
check(HegotaCoins.dominance([coin(1, 50), coin(2, 50)]) == nil,
      "an even split is not narrated as concentration")
let heavy = HegotaCoins.dominance([coin(1, 970), coin(2, 20), coin(3, 10)])!
check(abs(heavy - 0.97) < 0.0001, "the largest piece's share is reported exactly")

// ───────────────── the clock past the header window ─────────────────
let t0 = Date(timeIntervalSince1970: 1_786_025_702)
let known: [UInt64: Date] = [100: t0, 200: t0.addingTimeInterval(600)]
check(HegotaClock.estimate(block: 100, from: known) == t0,
      "a block we READ returns its own header time")
check(HegotaClock.estimate(block: 150, from: known)?.timeIntervalSince1970
        == t0.addingTimeInterval(300).timeIntervalSince1970,
      "a bracketed block interpolates between the two headers")
// **NOTHING IS EXTRAPOLATED.** Past the newest header we hold, drift has no
// measured ceiling — 12 missed slots across 310,833 blocks says how much the
// chain drifted in total, not where the gaps sit.
check(HegotaClock.estimate(block: 300, from: known) == nil,
      "a block past every header is refused, never extrapolated")
check(HegotaClock.estimate(block: 50, from: known) == nil,
      "a block before every header is refused")
check(HegotaClock.estimate(block: 150, from: [:]) == nil, "no headers, no estimate")
check(HegotaClock.estimate(block: 150, from: [100: t0]) == nil,
      "one header cannot bracket anything")

// ───────────────── is this still the same chain? ─────────────────
let g1 = "0x" + String(repeating: "a", count: 64)
let g2 = "0x" + String(repeating: "b", count: 64)
check(HegotaGenesis.verdict(chainID: HegotaChain.chainID, genesis: g1, knownGenesis: g1) == .same,
      "the same genesis is the same chain")
check(HegotaGenesis.verdict(chainID: HegotaChain.chainID, genesis: g2, knownGenesis: g1) == .restarted,
      "a new genesis is a relaunched devnet")
// A host serving some OTHER chain is a different finding from a relaunch, and
// gets the id check FIRST — its genesis differing is a consequence, not the
// finding, and "the devnet restarted" would be the wrong sentence to show.
check(HegotaGenesis.verdict(chainID: 1, genesis: g2, knownGenesis: g1) == .differentChain,
      "a wrong chain id outranks a differing genesis")
check(HegotaGenesis.verdict(chainID: nil, genesis: nil, knownGenesis: g1) == .unknown,
      "a read that did not answer is UNKNOWN, never `same`")
check(HegotaGenesis.verdict(chainID: HegotaChain.chainID, genesis: g1, knownGenesis: nil) == .unknown,
      "a first sight has nothing to compare against")
check(HegotaGenesis.verdict(chainID: HegotaChain.chainID, genesis: "0xnothex",
                            knownGenesis: g1) == .unknown,
      "an unparseable hash claims nothing")

// ───────────── the balance line undoes the fees it can see (§509) ─────────────
// **This reconstruction had NO fixtures at all before today**, which is how the
// sponsored case slipped through: a fee leaves the balance and emits no
// transfer log (measured — a frame transaction's receipt carries only its
// value-move log), so a line built from logs alone drifts by exactly the gas
// this address spent. `feeWei` is held for the newest moves, so the recent
// stretch can be exact.
func weiOf(_ n: String) -> Decimal { Decimal(string: n)! }
func paidMove(fee: String?, sponsored: Bool) -> HegotaMove {
    var m = HegotaMove(hash: "0xfee", counterparty: "0xc",
                       wei: weiOf("1000000000000000000"), incoming: false, block: 9)
    m.sender = "0xme"
    m.payer = sponsored ? "0xsomebodyelse" : "0xme"
    m.feeWei = fee.map(weiOf)
    return m
}
func lineFor(_ move: HegotaMove) -> [Double]? {
    var a = HegotaAccount(address: "0xme")
    a.reached = true
    a.balanceWei = weiOf("2000000000000000000")   // 2 ETH now
    a.moves = [move]
    return HegotaRoom.valueSeries(a)
}
// Self-paid: the 0.1 ETH of gas was this address's, so undoing the move has to
// put it back — the balance before was 2 + 1 + 0.1.
let ownGasLine = lineFor(paidMove(fee: "100000000000000000", sponsored: false))
check(ownGasLine?.count == 2, "a line is one point per move plus today")
check(abs((ownGasLine?.first ?? 0) - 3.1) < 0.000001,
      "a self-paid fee is undone with the move — the line starts at 3.1")
check(abs((ownGasLine?.last ?? 0) - 2.0) < 0.000001, "the line ends at today's balance")
// **THE DISCRIMINATING CASE.** Sponsored: somebody else's gas never left this
// balance, so adding it back bends the line — on exactly the transactions this
// chain exists to show off.
let sponsoredLine = lineFor(paidMove(fee: "100000000000000000", sponsored: true))
check(abs((sponsoredLine?.first ?? 0) - 3.0) < 0.000001,
      "a SPONSORED fee is not added back — the line starts at 3.0, not 3.1")
// An unread fee is a gap we cannot close, not a zero: the line is simply the
// move, which is what every move past the receipt window gets.
let noFee = lineFor(paidMove(fee: nil, sponsored: false))
check(abs((noFee?.first ?? 0) - 3.0) < 0.000001, "an unread fee changes nothing")

// ───────────── where a keyed nonce's counter lives (§509) ─────────────
// **PINNED TO A LIVE MEASUREMENT.** The nonce manager cannot be called at all
// (its runtime is PUSH0 PUSH0 REVERT), so this slot was derived by reading the
// chain: the one address here that sends on named keys reads a non-zero counter
// at keccak256(pad32(addr) ‖ pad32(key)) for BOTH its keys, while four rival
// layouts read zero. The expected digest below is that derivation computed over
// the real address and key — so a changed padding, a swapped operand order or a
// different hash all move it.
let nonceAddr = "0x8943545177806ed17b9f23f0a21ee5948ecaa776"
let beefSlot = HegotaNonceStorage.slot(address: nonceAddr, key: "0xbeef01")
check(beefSlot != nil, "the slot derives for a real address and key")
// **THE DIGEST ITSELF, pinned — and only this catches an operand swap.** The
// first cut asserted `slot(addr, key) != slot(key, addr)`, which SURVIVED a
// mutation that reversed the preimage: reversing it swaps BOTH sides, so the
// inequality holds either way. A fixture only tests the rule it names if it
// fails that rule and passes every other one, so the expected value is the real
// keccak over the real address and key — the slot that reads non-zero on chain.
check(beefSlot == "0xda044a8c3d82789bdc1c91449ad8e65d908ba47b4ce2370774f2d7eb18c55aa7",
      "the slot is keccak256(pad32(address) ‖ pad32(key)) — the live-measured digest")
check(HegotaNonceStorage.slot(address: nonceAddr, key: "0x1234")
        == "0x1e300cfea071585e2819c8e9355ad35d312a0dfd1bb2cc4b924f7733aa9b4468",
      "the second live key's slot matches too — one digest could be a coincidence")
// Both keys of the same address must differ, or every key would share a counter.
check(beefSlot != HegotaNonceStorage.slot(address: nonceAddr, key: "0x1234"),
      "two keys on one address occupy different slots")
check(HegotaNonceStorage.slot(address: nonceAddr, key: "0xbeef01") == beefSlot,
      "the derivation is deterministic")
// The 0x prefix is not part of the preimage — a slot that changed with it would
// depend on how the caller happened to spell the key.
check(HegotaNonceStorage.slot(address: nonceAddr, key: "beef01") == beefSlot,
      "the 0x prefix is not part of the preimage")
check(beefSlot?.count == 66, "a slot is an 0x-prefixed 32-byte word")
// REFUSES rather than guesses: a wrong slot reads a legitimate ZERO, which
// would say "never sent on this key" about a key the room lists BECAUSE it was.
check(HegotaNonceStorage.slot(address: "0xnothex", key: "0x1") == nil,
      "a non-hex address yields no slot rather than a guessed one")
check(HegotaNonceStorage.slot(address: nonceAddr, key: "") == nil,
      "an empty key yields no slot")
check(HegotaNonceStorage.slot(address: nonceAddr,
                              key: String(repeating: "f", count: 65)) == nil,
      "a key too wide for a word is refused")

// ───────────── a lane says the chain's count, or admits it cannot ─────────────
func lane(_ sends: Int, counter: UInt64?) -> HegotaNonceLane {
    var l = HegotaNonceLane(key: "0xbeef01", seq: "0x0", lastBlock: 1, sends: sends)
    l.counter = counter
    return l
}
check(lane(1, counter: 3).sendCount == 3, "the chain's counter is what the lane states")
check(lane(1, counter: 3).countIsExact, "a read counter is marked exact")
check(lane(1, counter: nil).sendCount == 1, "without it the lane falls back to what it saw")
check(!lane(1, counter: nil).countIsExact,
      "a derived count is NOT narrated as the chain's own")
// The observed moves are a FLOOR: every value-moving send also advanced the
// counter, so a counter below them describes a different address than the logs
// do, and reporting fewer sends than the list beneath enumerates is worse than
// not knowing.
check(lane(4, counter: 2).sendCount == 4, "a counter below the observed keeps the floor")
check(lane(1, counter: 3).valuelessSends == 2,
      "the gap is the sends that moved no value")
check(lane(3, counter: 3).valuelessSends == nil, "no gap says nothing")
check(lane(1, counter: nil).valuelessSends == nil, "an unread counter claims no gap")

// ───────────────── the predeploys are named ─────────────────
check(HegotaParty.of(HegotaChain.vault, watched: []) == .vault, "the vault is named")
check(HegotaParty.of(HegotaChain.nonceManager, watched: []) == .nonceManager,
      "the nonce manager is named, not left as a bare hex counterparty")
check(HegotaParty.of(HegotaChain.nonceManager.uppercased(), watched: []) == .nonceManager,
      "the predeploys match case-insensitively")
check(HegotaParty.of("0xstranger", watched: []) == .stranger("0xstranger"),
      "an ordinary address is still a stranger")

if failures > 0 { print("\(failures) assertion(s) failed"); exit(1) }
print("  ok   \(HegotaSection.allCases.count) scopes, words, the spent bitmap, coins, reconciliation, fees")
SWIFT

build() {
  swiftc -O -o "$work/run" "$1" "$2" "$3" "$4" "$work/Keccak256.swift" "$work/main.swift" 2>"$work/err" || return 1
}

cp "$SECTION" "$work/HegotaSection.swift"
cp "$COINS" "$work/HegotaCoins.swift"
cp "$ACCOUNT" "$work/HegotaAccount.swift"
cp "$ROOM" "$work/HegotaRoom.swift"
cp "$KECCAK" "$work/Keccak256.swift"
build "$work/HegotaSection.swift" "$work/HegotaCoins.swift" "$work/HegotaAccount.swift" "$work/HegotaRoom.swift" \
  || { cat "$work/err"; fail "the shipped source does not compile"; }
"$work/run" || fail "assertions failed against the shipped source"

# ── mutations ────────────────────────────────────────────────────────────────
# A check that cannot fail proves nothing. Each of these is a silent wrong
# answer that renders as an ordinary room.
mutate() {
  local why="$1" file="$2" expr="$3"
  cp "$SECTION" "$work/HegotaSection.swift"
  cp "$COINS" "$work/HegotaCoins.swift"
  cp "$ACCOUNT" "$work/HegotaAccount.swift"
  cp "$ROOM" "$work/HegotaRoom.swift"
  cp "$KECCAK" "$work/Keccak256.swift"
  perl -0pi -e "$expr" "$work/$file"
  local src="Casberi/Casberi/Model/$file"
  cmp -s "$src" "$work/$file" && fail "mutation matched nothing: $why"
  if build "$work/HegotaSection.swift" "$work/HegotaCoins.swift" "$work/HegotaAccount.swift" "$work/HegotaRoom.swift" && "$work/run" >/dev/null 2>&1; then
    fail "mutation SURVIVED — $why"
  fi
  echo "  ok   catches  $why"
}

# THE TIE, three ways. Each renders as a perfectly ordinary caption asserting a
# winner the legend beneath it refutes — the shipped bug, reported as the card
# not adding up.
mutate "the caption's leader set collapses to the drawing's first slice (a tie narrated as a winner)" \
  HegotaRoom.swift 's/return Array\(slices\.prefix \{ \$0\.count == top\.count \}\)/return [top]/'
mutate "every slice counts as a leader (a clear winner reported as a tie)" \
  HegotaRoom.swift 's/return Array\(slices\.prefix \{ \$0\.count == top\.count \}\)/return slices/'
mutate "a single-mode mix claims a commonest step (\"mostly\" said of all of them)" \
  HegotaRoom.swift 's/leaders\.count == 1 && slices\.count > 1/leaders.count == 1/'

mutate "a conditional scope moved ahead of an unconditional one (the strip's head reflows)" \
  HegotaSection.swift 's/\[\.home, \.activity, \.accounts, \.frames, \.coins, \.nonces, \.sponsors\]/[.home, .coins, .activity, .accounts, .frames, .nonces, .sponsors]/'
mutate "home no longer leads" \
  HegotaSection.swift 's/\[\.home, \.activity, \.accounts/[.coins, .home, .activity/'
mutate "resolve falls back to the first present scope instead of home" \
  HegotaSection.swift 's/guard let wanted, present\.contains\(wanted\) else \{ return \.home \}/guard let wanted, present.contains(wanted) else { return present.first ?? .home }/'
mutate "shows() lets a single scope draw a control" \
  HegotaSection.swift 's/present\.count > 1/present.count > 0/'
mutate "a flag governs the wrong scope (coins reads nonces')" \
  HegotaSection.swift 's/case \.coins:    return coins/case .coins:    return nonces/'
mutate "coins is marked unconditional, so the head-reflow rule stops being enforced" \
  HegotaSection.swift 's/case \.frames, \.coins, \.nonces, \.sponsors: return true/case .frames, .nonces, .sponsors: return true\n        case .coins: return false/'
mutate "the unspent-output scope goes back to the friendly gloss" \
  HegotaSection.swift 's/String\(localized: "UTXOs"\)/String(localized: "Coins")/'
mutate "the literal term becomes a metaphor again" \
  HegotaSection.swift 's/String\(localized: "Nonces"\)/String(localized: "Queues")/'
mutate "a scope quietly grows an attention dot nothing here can honestly light" \
  HegotaSection.swift 's/static func attention\(\) -> Set<HegotaSection> \{ \[\] \}/static func attention() -> Set<HegotaSection> { [.coins] }/'

mutate "the spent bitmap is read one storage region over — EVERY coin reads unspent" \
  HegotaCoins.swift 's/nibbles\[31\] = "2"/nibbles[30] = "2"/'
mutate "the word index carries into the marker bit instead of the low nibbles" \
  HegotaCoins.swift 's/nibbles\[63 - offset\] = ch/nibbles[offset] = ch/'
mutate "spent bits are counted from the wrong end of the word" \
  HegotaCoins.swift 's/chars\[63 - bit \/ 4\]/chars[bit \/ 4]/'
mutate "one word stops covering 256 coins" \
  HegotaCoins.swift 's/static func word\(index: UInt64\) -> UInt64 \{ index >> 8 \}/static func word(index: UInt64) -> UInt64 { index >> 4 }/'
mutate "a coin whose spent bit could not be read is treated as UNSPENT (money already gone, shown as held)" \
  HegotaCoins.swift 's/else \{ return nil \}\n            if !spent \{ out\.append\(coin\) \}/else { continue }\n            if !spent { out.append(coin) }/'
mutate "unspent coins come back in whatever order the logs arrived" \
  HegotaCoins.swift 's/return out\.sorted \{ \$0\.index < \$1\.index \}/return out/'
mutate "reconciliation accepts a near-enough total" \
  HegotaCoins.swift 's/total\(unspent\) == vaultWei/abs\(total(unspent) - vaultWei) < 1000/'
mutate "a negative fee is reported as a number" \
  HegotaCoins.swift 's/return out > spent \? nil : spent - out/return spent - out/'
mutate "a topic that is not address-shaped still yields an address (an invented counterparty)" \
  HegotaCoins.swift 's/guard body\.prefix\(24\)\.allSatisfy\(\{ \$0 == "0" \}\) else \{ return nil \}\n        return "0x" \+ body\.suffix\(40\)\.lowercased\(\)/return "0x" + body.suffix(40).lowercased()/'
mutate "an oversized value word is rounded instead of refused" \
  HegotaCoins.swift 's/guard body\.prefix\(40\)\.allSatisfy\(\{ \$0 == "0" \}\) else \{ return nil \}/\/\/ removed/'
mutate "the change coin stops being recognisable" \
  HegotaCoins.swift 's/var isChange: Bool \{ source == owner \}/var isChange: Bool { false }/'
mutate "a log wearing any signature at all parses as a coin" \
  HegotaCoins.swift 's/HegotaWord\.normalized\(topics\[0\]\)\?\.lowercased\(\)\n                == HegotaWord\.normalized\(HegotaChain\.utxoCreatedTopic\)\?\.lowercased\(\),/topics[0].count > 0,/'

mutate "a watched address with no sweep yet draws NO room (the reported blank)" \
  HegotaRoom.swift 's/guard watching > 0 else \{ return nil \}/return nil; if false {/'
mutate "an unreached account is folded into the total as zero (reads as money leaving)" \
  HegotaRoom.swift 's/let balance: Decimal\? = reached\.isEmpty/let balance: Decimal? = accounts.isEmpty/'
mutate "coins from a set that never reconciled are counted anyway" \
  HegotaRoom.swift 's/\$0\.hasCoins \? \(\$0\.unspent \?\? \[\]\) : \[\]/(\$0.unspent ?? [])/'
mutate "the head ranks sponsorship above coins" \
  HegotaRoom.swift 's/if !coins\.isEmpty \{ lead = \.coins \}\n        else if sponsored > 0 \{ lead = \.sponsored \}/if sponsored > 0 { lead = .sponsored }\n        else if !coins.isEmpty { lead = .coins }/'
mutate "scopes are derived from every account rather than the reached ones" \
  HegotaRoom.swift 's/let reached = accounts\.filter\(\\\.reached\)\n        guard !reached\.isEmpty else \{ return \[\] \}/let reached = accounts\n        guard !reached.isEmpty else { return [] }/'

# ── §504: the frames scope, the census, the clock, the reset ─────────────────
# Each of these renders as an ordinary room too. A mis-scoped census is a
# confident share of the wrong denominator; an extrapolated time is a date
# nobody can tell is invented; a relaunch read as `same` is the whole failure
# this pass exists to catch, drawn as an account whose money left.

mutate "the ordinary nonce falls back to counting moves even when the chain answered" \
  HegotaRoom.swift 's/let ordinary = nonceCount\.map \{ max\(Int\(\$0\), observed\) \} \?\? observed/let ordinary = observed/'
mutate "a nonce BELOW the moves we can already name is believed (fewer sends than the list shows)" \
  HegotaRoom.swift 's/nonceCount\.map \{ max\(Int\(\$0\), observed\) \}/nonceCount.map { Int($0) }/'
mutate "a derived send count is narrated as the chain's own counter" \
  HegotaRoom.swift 's/nonceRead: nonceCount != nil/nonceRead: true/'
mutate "a self-payment advances the ordinary nonce twice" \
  HegotaRoom.swift 's/return seen\.insert\(move\.hash\.lowercased\(\)\)\.inserted\n        \}\.count\n        \/\/ \*\*The chain/return true\n        }.count\n        \/\/ **The chain/'
mutate "frames are counted as transactions" \
  HegotaRoom.swift 's/transactions: framed\.count/transactions: total/'
mutate "a frame whose receipt would not pair is counted as FAILED" \
  HegotaRoom.swift 's/case \.none:        unknown \+= 1/case .none:        failed += 1/'
# Anchored on `.map { Slice` because `HegotaFlow.modes` carries a byte-identical
# comparator earlier in this same file, and an unanchored substitution mutates
# THAT one instead — a mutation that proves a different function than it names.
# Reversed rather than replaced with `true`: `true` preserves the dictionary's
# own arbitrary order, which on a two-mode tally happens to be right often
# enough that the mutation survives at random.
mutate "the frame mix reshuffles between opens (ties break the wrong way)" \
  HegotaRoom.swift 's/: \$0\.key\.rawValue < \$1\.key\.rawValue\n        \}\.map \{ Slice/: \$0.key.rawValue > \$1.key.rawValue\n        }.map { Slice/'
mutate "the nonce manager predeploy goes back to a bare hex counterparty" \
  HegotaRoom.swift 's/if address\.caseInsensitiveCompare\(HegotaChain\.nonceManager\) == \.orderedSame \{\n            return \.nonceManager\n        \}//'
mutate "the census measures our share against our own coins instead of the whole vault" \
  HegotaCoins.swift 's/let mine = all\.filter \{ keys\.contains\(\$0\.owner\.lowercased\(\)\) \}/let mine = all/'
mutate "a census is composed over a set that never reconciled" \
  HegotaCoins.swift 's/guard reconciled, !all\.isEmpty else \{ return nil \}/guard !all.isEmpty else { return nil }/'
mutate "our share of an EMPTY vault reads as zero rather than undefined" \
  HegotaCoins.swift 's/guard wei > 0 else \{ return nil \}/if wei == 0 { return 0 }/'
mutate "an even split is narrated as concentration" \
  HegotaCoins.swift 's/return share >= 0\.6 \? share : nil/return share/'
mutate "a block past every header we hold is EXTRAPOLATED into a date" \
  HegotaCoins.swift 's/guard let low = below, let high = above, high\.0 > low\.0 else \{ return nil \}/guard let low = below else { return nil }\n        guard let high = above, high.0 > low.0 else {\n            return low.1.addingTimeInterval(Double(block - low.0) * slotSeconds)\n        }/'
mutate "a relaunched devnet reads as the same chain (the room draws a zeroed balance)" \
  HegotaCoins.swift 's/return seen == known \? \.same : \.restarted/return .same/'
mutate "an unreadable genesis reads as the same chain — not knowing becomes knowing" \
  HegotaCoins.swift 's/else \{ return \.unknown \}\n        return seen == known/else { return .same }\n        return seen == known/'
mutate "a host serving a different chain is reported as a relaunch" \
  HegotaCoins.swift 's/if let chainID, chainID != HegotaChain\.chainID \{ return \.differentChain \}//'

# ── §509: the pinned block, the nonce slot, the lane's counter ───────────────
# Each renders as an ordinary room. A swapped slot preimage reads a legitimate
# ZERO and the lane quietly falls back to its observed floor; a lane that
# believes a counter below what it can already name reports fewer sends than the
# list beneath it enumerates; and a fee added back on a SPONSORED move bends the
# balance line on exactly the transactions this chain exists to show off.

mutate "the nonce slot hashes key-then-address (a legitimate-looking zero, and the lane silently falls back)" \
  HegotaCoins.swift 's/return "0x" \+ Keccak256\.hexString\(Keccak256\.hash\(a \+ k\)\)/return "0x" + Keccak256.hexString(Keccak256.hash(k + a))/'
mutate "the nonce slot stops padding, so two differently-spelled keys collide" \
  HegotaCoins.swift 's/let padded = String\(repeating: "0", count: 64 - body\.count\) \+ body/let padded = body.count % 2 == 0 ? String(body) : "0" + body/'
# BOTH guards, in one mutation, and that is the honest shape here: the
# `allSatisfy(\.isHexDigit)` early-out and the byte loop's `guard let` refuse the
# same input, so breaking EITHER alone leaves the other standing and the
# mutation survives — which is a fact about redundant defence, not a gap. What
# is load-bearing is the RULE ("a non-hex input yields no slot"), so the
# mutation removes both and proves the pair enforces it.
mutate "a non-hex address yields a guessed slot instead of nothing (both guards gone)" \
  HegotaCoins.swift 's/guard !body\.isEmpty, body\.count <= 64, body\.allSatisfy\(\\.isHexDigit\) else \{ return nil \}/guard !body.isEmpty, body.count <= 64 else { return nil }/; s/guard let b = UInt8\(padded\[i\.\.<j\], radix: 16\) else \{ return nil \}/let b = UInt8(padded[i..<j], radix: 16) ?? 0/'
mutate "a lane believes a counter BELOW the moves it can already name" \
  HegotaAccount.swift 's/var sendCount: Int \{ counter\.map \{ max\(Int\(\$0\), sends\) \} \?\? sends \}/var sendCount: Int { counter.map { Int($0) } ?? sends }/'
mutate "a derived send count is narrated as the chain's own" \
  HegotaAccount.swift 's/var countIsExact: Bool \{ counter != nil \}/var countIsExact: Bool { true }/'
mutate "the balance line adds back gas somebody ELSE paid (a sponsored move bends the wrong way)" \
  HegotaRoom.swift 's/if !move\.incoming, !move\.isSponsored, let fee = move\.feeWei \{/if !move.incoming, let fee = move.feeWei {/'
mutate "the balance line stops undoing the fee at all (it drifts by the gas this address spent)" \
  HegotaRoom.swift 's/if !move\.incoming, !move\.isSponsored, let fee = move\.feeWei \{\n                running \+= fee\n            \}//'

# ── drift guards ─────────────────────────────────────────────────────────────
# Read from a COMMENT-STRIPPED copy: both files DOCUMENT their rules by naming
# exactly what they must not do — the rejected scope names, the price that is
# never shown — so a guard grepping raw source scores prose as compliance (the
# Obsidian/Cursor lesson).
strip_comments() { perl -pe 's{//.*$}{}g' "$1"; }
strip_comments "$SECTION" > "$work/section.bare"
strip_comments "$COINS" > "$work/coins.bare"
strip_comments "$ROOM" > "$work/room.bare"
strip_comments "$ACCOUNT" > "$work/account.bare"

have() { [[ -f "$work/$1" ]] || fail "guard points at a file that was never prepared: $1"; }
deny() { have "$1"; if grep -q -- "$2" "$work/$1"; then fail "drift: $3"; fi }

# The Foundation-only promise. Without it this harness cannot run at all.
deny section.bare "import SwiftUI" "HegotaSection imports SwiftUI — it must stay compilable without it"
deny coins.bare   "import SwiftUI" "HegotaCoins imports SwiftUI — it must stay compilable without it"
deny room.bare    "import SwiftUI" "HegotaRoom imports SwiftUI — it must stay compilable without it"
deny room.bare    "usd" "HegotaRoom reaches for a dollar figure — test ETH has no price"
deny account.bare "import SwiftUI" "HegotaAccount imports SwiftUI — it must stay compilable without it"
deny account.bare "import Observation" "HegotaAccount imports Observation — the value types must stay Foundation-only or the room's rules leave the harness"
deny account.bare "URLSession" "HegotaAccount reaches the network — it is value types only"

# THE THREE DEVICE-REPORTED FIXES, as guards rather than as memory. Each was
# invisible to every check here and visible only by opening the room.
BRIDGE="Casberi/Casberi/Model/HegotaBridge.swift"
CARD="Casberi/Casberi/Screens/HegotaRoomCard.swift"
FEED="Casberi/Casberi/Screens/FeedScreen.swift"
SCREEN="Casberi/Casberi/Screens/HegotaScreen.swift"
LIVE="Casberi/Casberi/Model/LiveRoomSources.swift"
for f in "$BRIDGE" "$CARD" "$SCREEN" "$LIVE" "$FEED"; do
  strip_comments "$f" > "$work/$(basename $f).bare"
done
need() { [[ -f "$work/$1" ]] || fail "guard points at a file never prepared: $1"; \
         grep -q -- "$2" "$work/$1" || fail "drift: $3"; }

# The seat lands no `Thing`, so without this entry its chip can never appear
# and the whole room is unreachable.
need LiveRoomSources.swift.bare "HegotaIdentity.source" \
  "Hegota left LiveRoomSources — a landless seat with no entry there has no chip and no room"
# The registry carries TWO sets now and the split IS the fix. Hegota must be in
# the general one and never in the venue one: gating the browse book on `has`
# is what drew Kalshi's markets inside the Hegota room on a device.
deny LiveRoomSources.swift.bare 'predictionVenues.*Hegota' \
  "Hegota joined predictionVenues — its room would draw the prediction browse book"
need FeedScreen.swift.bare "LiveRoomSources.isPredictionVenue(source)" \
  "the prediction book is gated on the general set again — every landless seat draws Kalshi markets"
# A live sweep in demo mode reads an EMPTY watch list and wipes the fixture.
need HegotaBridge.swift.bare "DemoMode.isActive" \
  "the sweep no longer stands down in demo mode — it would wipe the seeded fixture"
# The room must read for itself, or watching an address lands you in a blank room.
need HegotaRoomCard.swift.bare "refreshIfStale" \
  "the room no longer reads on appear — a freshly watched address shows nothing until the next foreground"
# Reading and unreachable are different sentences.
need HegotaRoomCard.swift.bare "head.hasRead" \
  "the card no longer distinguishes 'not read yet' from 'could not reach'"
# Both worked examples must stay reachable: nobody on this chain has both
# halves of the room, so losing one loses half the room permanently.
need HegotaScreen.swift.bare "unwatchedExamples" \
  "the examples are gated on !connected again — watching one loses the other for good"

# THE FRAMES CAPTION AND ITS LEGEND, as guards rather than as memory. Both
# were reported from a device as "how does this math add up" and neither is
# reachable by any other check here: the counts were always correct, so the
# build, the sweep and every probe pass while the card contradicts itself.
need HegotaRoomCard.swift.bare "mix.leaders" \
  "the frames caption reads the drawing's first slice again — a tie renders as a winner the legend refutes"
deny HegotaRoomCard.swift.bare "mix.busiest" \
  "the frames caption is built from busiest again — that property is the drawing's head, never a superlative"
# The legend is a census over EVERY framed transaction while the bars are
# capped at `frameRows`, so the card must say which population each covers.
# Without it the legend totals nineteen steps above six bars carrying nine.
need HegotaRoomCard.swift.bare "step counts cover all" \
  "the drawing no longer names its population — the legend and the bars count different things in silence"
# The note has to FIT, or the one line stopping the cap being silent is itself
# clipped by DSRoomSlot's 210pt. The arithmetic is in the constant's own doc.
need HegotaRoomCard.swift.bare "frameRows = 5" \
  "the frame row cap moved without re-doing the 180pt sum — six rows plus the population note clips at 185"

# NO PRICE, EVER. This is test ETH; an amount here is a quantity, never a value.
# A fiat conversion on this card would be §83's fake status in the one place a
# reader has no way to check us.
deny coins.bare "usd" "HegotaCoins reaches for a dollar figure — test ETH has no price"
deny coins.bare "priceValue" "HegotaCoins reaches for a price — test ETH has no price"

# NOTHING IN THE ROOM IS WORTH A LOCK SCREEN, and the scope strip says so by
# carrying no dot. §500's rule, and it still holds for the room's CONTENT: no
# balance, coin, lane or move is urgent, because the asset is test ETH and
# nothing can move against you.
#
# §522 amended it in exactly one place and these two guards are what keep the
# amendment honest: a devnet RELAUNCH is not room content — it is the statement
# that every reading here describes a chain that no longer exists — so it is
# composed in `NotifyDevnet` off `HegotaLiveState`, and neither room model may
# reach the sweep. If either of these starts to fail, the rule has been widened
# from "the chain was wiped" to "something in the room happened", which is the
# overclaim §500 wrote the sentence for.
deny section.bare "NotifySweep" "the scope model reaches the notification sweep — nothing in this room is urgent"
deny coins.bare   "NotifySweep" "the coin model reaches the notification sweep — nothing in this room is urgent"
# …and the room draws no dot for any of it (§500's other half, unchanged).
deny section.bare "NotifyKind" "the scope model reaches a notification kind — the strip must stay dotless"

# THE NAMING RULING (2026-08-27), as a mechanical guard rather than a memory:
# the label is the literal term. Checked on the comment-stripped copy precisely
# because the source explains the ruling by naming both rejected words.
deny section.bare 'localized: "Queues"' "the keyed-nonce scope is named Queues again — the ruling is the literal term"
deny section.bare 'localized: "Lanes"'  "the keyed-nonce scope is named Lanes again — it collides with WalletFlowBand's lanes"
deny section.bare 'localized: "Orders"' "the keyed-nonce scope is named Orders — that word is spent on trades"

# THE READ PATH STAYS A READ PATH FOR THIS FILE — AND THE COPY STAYS TRUE
# (amended 2026-08-29, prd §525). This guard used to say Hegota could never
# send at all, three sentences and a denylist enforcing it. That stopped being
# the feature's intent the same afternoon vibenet's did: `HegotaKey` holds a
# device-stored secp256k1 scalar (a deliberately WEAKER promise than vibenet's
# Enclave key — the user's own ruling that a devnet with worthless money does
# not need hardware-backed non-export) and `HegotaSend` is the one file that
# signs and sends with it. What has NOT changed, and is what this guard is
# really for, is that `HegotaBridge.swift` — the room and the sync sweep — is a
# READER: it must never sign, never name a signing type, and never request a
# write-shaped method. Signing lives in its own files behind their own harness
# (`scripts/hegota-tx-selftest.sh`), the same split that keeps a big bridge file
# from quietly growing the ability to move something.
#
# The three COPY surfaces must move WITH the code, exactly as vibenet's do: the
# catalog offer's last feature bullet, the bridge's own `can:` sentence on the
# detail screen, and the reach registry's purpose on the privacy screen. All
# three are TRUE now — reading needs no key, and a key that exists is described
# honestly as a plain device-stored scalar rather than an Enclave key. The tie
# runs both ways: a signing path appearing while the OLD read-only sentences
# still stood would be the §83 lie in the place it is most expensive to tell;
# the sentences vanishing while nothing signs would give up a guarantee the
# seat still keeps.
#
# SCOPED TO HEGOTÁ'S OWN OFFER AND ITS OWN REACH ENTRY, not the whole file —
# vibenet's sibling guard hit this exact bug twice (prd §523): both seats once
# carried the word-identical sentences, so an unscoped grep kept one seat's
# retired promise alive by finding the OTHER seat's still-true one. Anchored
# here from the start rather than learned the same way twice.
CATALOG_H="Casberi/Casberi/Model/BridgeCatalog.swift"
REACH_H="Casberi/Casberi/Model/NetworkReach.swift"
for f in "$CATALOG_H" "$REACH_H"; do
  strip_comments "$f" > "$work/$(basename $f).bare"
done
for m in eth_sendTransaction eth_sendRawTransaction eth_sign eth_signTransaction \
         personal_sign eth_signTypedData SignerKey SafeSigner VibenetDeviceKey \
         HegotaKey HegotaSend; do
  deny HegotaBridge.swift.bare "$m" \
    "HegotaBridge names $m — this file must only ever read; signing lives in HegotaKey/HegotaSend"
done

HEGOTA_SIGN_CALLERS=""
for f in $(grep -rl 'Hegota' --include='*.swift' Casberi/ 2>/dev/null \
             | grep -v 'Model/HegotaKey.swift$' | grep -v 'Model/HegotaTransaction.swift$'); do
  nc="$work/hg-scan.nc.swift"
  strip_comments "$f" > "$nc"
  grep -q 'HegotaKey\.sign' "$nc" && HEGOTA_SIGN_CALLERS="$HEGOTA_SIGN_CALLERS $f"
done

python3 - "$work/BridgeCatalog.swift.bare" <<'PYCAT' > "$work/hegota-catalog-promise.txt" || true
import sys
src = open(sys.argv[1]).read()
start = src.find('Offer(name: "Ethrex Hegot')
if start < 0:
    print("NONE"); sys.exit(0)
nxt = src.find('Offer(name:', start + 10)
block = src[start:nxt if nxt > 0 else len(src)]
print("STANDS" if "Never signs or sends anything" in block else "RETIRED")
PYCAT
CATALOG_PROMISE="$(cat "$work/hegota-catalog-promise.txt" 2>/dev/null || echo NONE)"

python3 - "$work/NetworkReach.swift.bare" <<'PYREACH' > "$work/hegota-reach-promise.txt" || true
import sys
src = open(sys.argv[1]).read()
start = src.find('service: "Ethrex Hegot')
if start < 0:
    print("NONE"); sys.exit(0)
nxt = src.find('Endpoint(service:', start + 10)
block = src[start:nxt if nxt > 0 else len(src)]
print("STANDS" if "nothing is ever signed or sent" in block else "RETIRED")
PYREACH
REACH_PROMISE="$(cat "$work/hegota-reach-promise.txt" 2>/dev/null || echo NONE)"

hegota_promises=0
[[ "$CATALOG_PROMISE" == "STANDS" ]] && hegota_promises=$((hegota_promises + 1))
grep -q 'Read-only — this app never signs or sends anything against it' "$work/HegotaBridge.swift.bare" && hegota_promises=$((hegota_promises + 1))
[[ "$REACH_PROMISE" == "STANDS" ]] && hegota_promises=$((hegota_promises + 1))

if [[ -n "$HEGOTA_SIGN_CALLERS" && $hegota_promises -gt 0 ]]; then
  fail "Hegota can now sign ($HEGOTA_SIGN_CALLERS) while $hegota_promises never-signs promise(s) still stand — amend the catalog bullet, HegotaBridge's can: line, and NetworkReach's purpose in the same commit"
fi
if [[ -z "$HEGOTA_SIGN_CALLERS" && $hegota_promises -lt 3 ]]; then
  fail "Hegota's never-signs promises are retired ($hegota_promises of 3 stand) but nothing calls HegotaKey.sign — restore the copy or land the write with it"
fi

# THE WRITE PATH SAYS WHY IT FAILED (prd §530) — vibenet's guard, one chain
# over, because this file carried the IDENTICAL placeholder line. `HegotaSend`
# touches SwiftData, so no harness here can compile it and these greps are the
# only checks that reach it; both failures are invisible to everything else.
SENDF="Casberi/Casberi/Model/HegotaSend.swift"
[[ -f "$SENDF" ]] || fail "$SENDF not found"
strip_comments "$SENDF" > "$work/send.bare"
deny send.bare "the node refused the transaction" \
  "HegotaSend broadcasts a placeholder refusal again — prd §530: the reason must be the node's own words"
grep -qF 'IngestSupport.postJSONBody' "$work/send.bare" \
  || fail "HegotaSend no longer reads the broadcast body — a 400 carrying the node's reason would be dropped before any parse"
deny send.bare 'HegotaRPC.call(method: "eth_sendRawTransaction"' \
  "HegotaSend broadcasts through HegotaRPC.call again — that function discards the node's error object"
# ANCHORED to end-of-line: the unanchored form is satisfied by a RENAMED case,
# which is how vibenet's twin survived its own mutation on its first run.
grep -qE 'case chainUnreachable[[:space:]]*$' "$work/send.bare" \
  || fail "HegotaSend can no longer tell an unreached node from a refusing one (§515a)"

# This harness must stay in verify.sh's hand list (that guard fails the build
# until it is named WITH its reason, which is the part that gets skipped).
grep -q "hegota-selftest.sh" "$VERIFY" \
  || fail "not wired into verify.sh — the completeness guard requires it, with its reason"

echo "  ok   drift guards: Foundation-only, no price, no notification, the naming ruling, the frames caption and its populations, the read-only conduct guard"
echo "✓ hegota: scopes, words, spent bitmap, coins, reconciliation, fees, room head, frames, census, clock, genesis, 45 mutations, 19 drift guards"
