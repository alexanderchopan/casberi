#!/bin/zsh
# Casberi wallet-NFT self-test — the SHIPPED pure logic behind the picked-NFT
# shelf (2026-08-15, prd §387):
#
#   Casberi/Casberi/Model/WalletNFTPicks.swift
#     — NFTPickKey         (a pick's identity: one collection on one chain)
#     — NFTCollectionOrder (what the picker lists first)
#     — NFTPickBook        (the pick arithmetic, and the shelf's cache key)
#
# That file is Foundation-only BY DESIGN, so it is compiled WHOLE AND
# UNMODIFIED here — no extraction, no `private ` stripping, no copy. Every
# assertion below is about the bytes the app runs.
#
# WHY A HARNESS. This feature exists to REDUCE what the wallet path spends
# (§72/§124a's shelf was cut on 2026-07-19 as one of the two biggest credit
# sinks on that path), and every failure below either spends more than it
# should or shows the wrong art — all of them rendering perfectly:
#
#   • a pick key built from a checksummed address never matching the lowercased
#     one the read returns, so a tapped collection stays off forever and every
#     tap looks ignored;
#   • `contracts(wallet:network:)` returning an UNSORTED list, which is the
#     shelf's cache key — a Set's iteration order is not stable, so an unchanged
#     set of picks misses its own cache at random and re-buys the read the
#     window exists to avoid;
#   • that same list not filtered by chain, which asks Ethereum for a Base
#     contract and quietly returns nothing;
#   • an emptied pick set left behind as an empty Set, so `hasPicks` answers YES
#     for a wallet whose every pick was just cleared and the room draws a card
#     with nothing in it;
#   • a picker order that reshuffles between opens, on the one screen somebody
#     returns to in order to change a decision made against the previous order;
#   • `retain` not dropping unwatched wallets, so re-watching an address
#     silently restores a previous life's shelf.
#
# Pure, local, deterministic — no network, no simulator, no wallet. Exit
# non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

PICKS="Casberi/Casberi/Model/WalletNFTPicks.swift"
ORIGIN="Casberi/Casberi/Model/WalletNFTOrigin.swift"
VERBS="Casberi/Casberi/Model/WalletVerbs.swift"
USEROPS="Casberi/Casberi/Model/WalletUserOps.swift"
SHELF="Casberi/Casberi/Model/WalletNFTShelf.swift"
INGEST="Casberi/Casberi/Model/WalletIngest.swift"
FEED="Casberi/Casberi/Screens/FeedScreen.swift"
CARD="Casberi/Casberi/Screens/WalletNFTShelfCard.swift"
PICKER="Casberi/Casberi/Screens/WalletNFTPickerSheet.swift"
STORE="Casberi/Casberi/Model/WalletStore.swift"
REACH="Casberi/Casberi/Model/NetworkReach.swift"
# Compiled WHOLE and unmodified, all three Foundation-only BY DESIGN — so
# `WalletNFTOrigin` can USE `WalletVerbs.isVoid` and `NFTPickKey.make` rather
# than mirroring either. A copied void-address set or a second key format is
# exactly the drift this project keeps paying for.
SOURCES=("$PICKS" "$ORIGIN" "$VERBS")

for f in "$PICKS" "$ORIGIN" "$VERBS" "$USEROPS" "$SHELF" "$INGEST" "$FEED" "$CARD" "$PICKER" "$STORE" "$REACH"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# A comment-stripped copy for every NEGATIVE guard below. These files DOCUMENT
# the things they must never do — the shelf's header names `getNFTsForOwner`
# and `excludeFilters` while explaining why the narrow read omits the filter —
# so a guard grepping raw source fires on the prose explaining it. (The
# Obsidian/Cursor lesson, and it caught this harness on its first run.)
strip_comments() {
  python3 - "$1" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
src = re.sub(r'^\s*//.*$', '', src, flags=re.M)
src = re.sub(r'(?<!:)//.*$', '', src, flags=re.M)
sys.stdout.write(src)
PY
}
strip_comments "$SHELF"  > "$TMP/shelf.nc"
strip_comments "$INGEST" > "$TMP/ingest.nc"
strip_comments "$FEED"   > "$TMP/feed.nc"
strip_comments "$CARD"   > "$TMP/card.nc"
strip_comments "$ORIGIN"  > "$TMP/origin.nc"
strip_comments "$USEROPS" > "$TMP/userops.nc"
strip_comments "$PICKER"  > "$TMP/picker.nc"

fail() { echo "  ✗ $1"; exit 1; }
ok()   { echo "  ✓ $1"; }

echo "drift guards"

# 1. THE COST CLAIM, AS A TEST. The whole argument for reviving this feature is
#    that detection is a read the app ALREADY makes: `ownedNFTContracts` (the
#    NFT spam allowlist, every wallet refresh since 2026-07-15) and the picker
#    must be one cached read with two projections. If the allowlist ever grows
#    its own `getContractsForOwner` call again, the picker stops being free and
#    the feature costs double what its own PRD entry claims.
grep -q "WalletNFTShelf.collections" "$TMP/ingest.nc" \
  || fail "ownedNFTContracts no longer projects WalletNFTShelf.collections — detection is paying twice"
ok "the spam allowlist is a projection of the picker's read, not a second one"

grep -q "getContractsForOwner" "$TMP/ingest.nc" \
  && fail "WalletIngest fetches getContractsForOwner again — the shared read was forked"
ok "WalletIngest issues no NFT-contract read of its own"

grep -q "getContractsForOwner" "$TMP/shelf.nc" \
  || fail "WalletNFTShelf no longer reads getContractsForOwner"
ok "the one detection read lives in WalletNFTShelf"

# 2. THE NARROW READ IS ACTUALLY NARROW. `getNFTsForOwner` with no
#    `contractAddresses[]` filter is the 2026-07-19 shelf that got cut: every
#    piece on every chain, every time. It renders identically to the picked
#    shelf for anyone whose picks happen to be most of their wallet.
grep -q "contractAddresses" "$TMP/shelf.nc" \
  || fail "the shelf read dropped its contractAddresses filter — this is the unbounded read that was cut"
ok "the shelf read is scoped to picked contracts"

# 3. A PICK OVERRIDES THE VENDOR'S GUESS. The narrow read must NOT exclude
#    spam: these contracts were named by the person, and honouring Alchemy's
#    flag over an explicit pick empties a shelf somebody built on purpose with
#    nothing on screen to say why.
grep -q "excludeFilters" "$TMP/shelf.nc" \
  && fail "the shelf read excludes SPAM — a pick must override the vendor's guess"
ok "the shelf read honours a pick over the isSpam flag"

# 4. THE PICKER NEVER HIDES AND NEVER LABELS. The user's ruling was explicit
#    ("i'd rather let user pick which nfts to show than hide a bunch in
#    'junk'"), and §83 forbids printing a third party's guess as a fact beside
#    somebody's own collection. isSpam may reach ORDER and nothing else.
grep -qE 'isSpam' "$TMP/card.nc" \
  && fail "the shelf card reads isSpam — the flag may only reach NFTCollectionOrder"
grep -qE '(filter|drop).*isSpam|isSpam.*(filter|hidden)' "$PICKER" \
  && fail "the picker filters on isSpam — every collection must stay listed and pickable"
grep -qiE '"[^"]*\b(spam|junk)\b[^"]*"' "$PICKER" \
  && fail "the picker prints a spam/junk label — §83, that is a guess stated as a fact"
ok "isSpam reaches order alone: nothing hidden, nothing labelled"

# 5. THE DEMO REACHES NOTHING, but it does DRAW. The seeded wallet address is
#    invented, so neither read may spend a request; the shelf is still shown, on
#    generated art, so the feature is discoverable on a tour (prd §387).
grep -q "if await DemoMode.isActive { return \[:\] }" "$TMP/shelf.nc" \
  || fail "the collections read lost its demo gate — the demo would reach Alchemy"
grep -q "if DemoMode.isActive { return demoPieces() }" "$TMP/shelf.nc" \
  || fail "the shelf read lost its demo fixture — the demo would reach Alchemy, or draw nothing"
ok "neither read reaches in demo mode"

# The demo's pieces must be GENERATED, never a real collection's artwork and
# never a door onto a page that doesn't exist (user's ruling: "it can be
# generated art that is free, not real nfts").
python3 - "$TMP/shelf.nc" <<'PY'
import sys, re
src = open(sys.argv[1]).read()
m = re.search(r'static func demoPieces\(\).*?\n    \}', src, re.S)
if not m:
    sys.exit("  ✗ demoPieces() not found")
body = m.group(0)
if 'imageURL: ""' not in body:
    sys.exit("  ✗ a demo piece carries an image URL — demo art must be generated, not loaded")
if 'chainPath: ""' not in body:
    sys.exit("  ✗ a demo piece carries a chain path, so it would offer an OpenSea door that 404s")
if 'demoSeed' not in body:
    sys.exit("  ✗ demo pieces carry no seed, so nothing draws them")
PY
ok "the demo's pieces are generated, doorless and load no image"

# THE DEMO HAS NO PICKER. A picker there is a control over invented
# collections — it would work, and teach a decision that evaporates.
grep -q "if !demo {" "$TMP/card.nc" \
  || fail "the shelf card no longer hides its Edit control in demo mode"
ok "the demo shows the shelf and not the picker"

# 6. PLACEMENT. The shelf belongs directly under the holdings treemap — the two
#    are one "what you hold" pair (§124a's placement, restored). Asserted by
#    ORDER in the wallet room's own section list, since that is the only place
#    the decision exists.
python3 - "$TMP/feed.nc" <<'PY'
import sys, re
src = open(sys.argv[1]).read()
m = re.search(r'case \.wallet:(.*?)case \.calendar:', src, re.S)
if not m:
    sys.exit("  ✗ could not find the wallet room's section list")
body = m.group(1)
order = [s for s in ["holdingsBlockSection", "walletNFTSection", "walletRiskSection",
                     "walletStreamSections"] if s in body]
if order != ["holdingsBlockSection", "walletNFTSection", "walletRiskSection",
             "walletStreamSections"]:
    sys.exit(f"  ✗ the NFT shelf moved out of place: {order}")
PY
ok "the shelf sits under the treemap and above risk, before the transactions"

# 7. ONE SCREEN, ONE PRESENTATION. A `.sheet` on a view inside the feed's List
#    resolves to the same presenting controller as the screen's own, and rises
#    part way then closes (ruling 2026-07-28). The picker must route through
#    FeedSheetRoute, and the card must present nothing itself.
grep -qE '\.sheet\(' "$TMP/card.nc" \
  && fail "the shelf card presents its own sheet — the half-open-then-close bug"
grep -q "case nftPicks" "$TMP/feed.nc" \
  || fail "the picker is not routed through FeedSheetRoute"
ok "the picker rides the screen's single sheet"

# 8. AN UNWATCH REALLY FORGETS.
grep -q "WalletNFTStore.shared.retain" "$STORE" \
  || fail "removing a watched wallet no longer prunes its NFT picks"
ok "unwatching a wallet forgets its picks"

# 9. NO NEW HOST. The revival reuses the Alchemy hosts the reach registry has
#    declared since §289; a new one would need its own registry entry.
for host in "eth-mainnet.g.alchemy.com" "base-mainnet.g.alchemy.com"; do
  grep -q "$host" "$REACH" || fail "$host is not in the reach registry"
done
ok "the shelf reaches only already-declared hosts"


# --- the NFT-origin rule (2026-08-26, prd §481) ------------------------------

# 10. THE RULE IS ACTUALLY WIRED. `WalletNFTOrigin` is a pure decision with no
#     callers of its own; if the landing loop stops consulting it, every
#     assertion below still passes over dead code while the feed goes back to
#     showing every spam mint. This is the guard the whole file rests on.
grep -q "WalletNFTOrigin.verdict" "$TMP/ingest.nc" \
  || fail "WalletIngest no longer calls WalletNFTOrigin.verdict — the rule is dead code"
ok "the landing loop consults the NFT-origin rule"

grep -q "nftSignatures" "$TMP/ingest.nc" \
  || fail "WalletIngest no longer reads who sent a received NFT — only the 2026-07-15 arm is left"
ok "the pass asks who sent each undecided NFT"

# 11. THE RECEIPT READ IS KEYLESS. The argument for asking at all is that it
#     costs no Alchemy credits: `WalletApprovals.rpcRead` is the measured public
#     pool `WalletGas` already uses. Routed at a `g.alchemy.com` host instead,
#     this feature starts spending on every airdrop a stranger sends.
grep -q "WalletApprovals.rpcRead" "$TMP/ingest.nc" \
  || fail "the NFT receipt read left the keyless public RPC pool"
ok "the receipt read is keyless (no Alchemy credits)"

# 12. ONE READING OF A RECEIPT. `wasSentByWallet` must DELEGATE to
#     `attribution` rather than re-deriving the answer — two readings of the
#     same receipt eventually disagree about a Safe, and then the gas total and
#     the feed filter tell different stories about the same transaction.
grep -q "attribution(logs:" "$TMP/userops.nc" \
  || fail "wasSentByWallet no longer delegates to attribution — there are two readings now"
ok "who-sent-it delegates to the one receipt reading"

# 13. NO DOLLAR FLOOR, ANYWHERE. §387's standing ruling, now mechanical: a
#     floor is a bid on the thinnest book in this app, it moves without you, and
#     it is a number people believe (§83). It also fails BY CONSTRUCTION on the
#     case this feature exists for — a collection minted an hour ago has no
#     floor, so a dollar rule hides the mint somebody just performed — and it is
#     the one rule a spammer can buy past with a wash trade.
for nc in "$TMP/origin.nc" "$TMP/shelf.nc" "$TMP/ingest.nc"; do
  grep -q "floorPrice" "$nc" \
    && fail "a floor price reached $nc — §387 ruled it out and §481 restated why"
done
ok "no floor price reaches the shelf, the ingest or the origin rule"

# 14. DROP, NEVER FLAG. `FeedFold.tier` puts `isFlagged` in `.concerns`, the
#     feed's HIGHEST tier — so flagging a spam mint would PROMOTE it to sit
#     beside a dispute deadline. The received side drops by rule; flagging is
#     the sent-side pattern and only because dropping there eats real history.
grep -qE "addSecurityFlag|isFlagged" "$TMP/origin.nc" \
  && fail "the NFT-origin rule reaches a security flag — flagging promotes a spam mint to .concerns"
ok "the origin rule drops rather than flags"

# 15. THE VERIFIED PROJECTION COSTS NOTHING. Same claim as guard 1, for the
#     third projection: safelisting is worth having ONLY because it rides bytes
#     the wallet refresh already bought.
grep -q "WalletNFTShelf.collections" "$TMP/ingest.nc" \
  || fail "verifiedNFTKeys no longer projects the cached collections read"
grep -q "safelistRequestStatus" "$TMP/shelf.nc" \
  || fail "the safelist standing is no longer parsed — verified= is silently always 0"
ok "safelisting is a third projection of the one cached read"

# 16. SAFELISTING IS ORDER-AND-EVIDENCE, NEVER A LABEL. §387 ruled that a third
#     party's classification may sort the picker and must never print beside
#     somebody's own collection — "verified" states a guess as a fact exactly as
#     loudly as "spam" does.
grep -q "isVerified" "$TMP/picker.nc" \
  && fail "the picker draws isVerified — §387 forbids labelling a collection with a vendor's guess"
grep -q "isVerified" "$TMP/card.nc" \
  && fail "the shelf card draws isVerified — §387 forbids labelling a collection with a vendor's guess"
ok "safelisting is never drawn"

echo
echo "assertions"

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ what: String, _ cond: Bool) {
    if !cond { failures += 1; print("  ✗ \(what)") }
}

func col(_ network: String, _ contract: String, name: String = "N",
         count: Int = 1, arrival: Int = 0, spam: Bool = false) -> NFTCollection {
    NFTCollection(network: network, contract: contract, name: name,
                  imageURL: nil, count: count, isSpam: spam, arrival: arrival)
}

// MARK: - NFTPickKey

// An EVM address's case is an EIP-55 checksum, not identity. The read returns
// lowercase; a pick made from a checksummed string must match it or the tap
// looks ignored forever.
check("make lowercases the contract",
      NFTPickKey.make(network: "eth-mainnet", contract: "0xABCdef")
        == "eth-mainnet|0xabcdef")
check("make keeps the network verbatim",
      NFTPickKey.make(network: "base-mainnet", contract: "0x1").hasPrefix("base-mainnet|"))
check("split round-trips a real key",
      NFTPickKey.split("eth-mainnet|0xabc")?.network == "eth-mainnet"
        && NFTPickKey.split("eth-mainnet|0xabc")?.contract == "0xabc")
// A stored book is decoded from UserDefaults, so a truncated or hand-edited
// value must not resolve to a plausible-looking half.
check("split rejects a key with no separator", NFTPickKey.split("eth-mainnet") == nil)
check("split rejects an empty network", NFTPickKey.split("|0xabc") == nil)
check("split rejects an empty contract", NFTPickKey.split("eth-mainnet|") == nil)
check("split rejects an empty string", NFTPickKey.split("") == nil)
// A contract address can't contain a pipe, but a maxSplits of 1 is what makes
// that assumption safe rather than lucky.
check("split keeps everything after the first separator",
      NFTPickKey.split("eth-mainnet|0xa|b")?.contract == "0xa|b")

// MARK: - NFTCountField (MEASURED 2026-08-15 against a real wallet)

// The API sends STRINGS. A bare `as? Int` yields nil for every collection, so
// they all fall back to 1 and the whole picker ranking flattens.
check("a string count parses", NFTCountField.parse("912") == 912)
check("a numeric count parses", NFTCountField.parse(912) == 912)
// THE RANKING FIX. Measured on one real contract: totalBalance 912,
// numDistinctTokensOwned 80. totalBalance sums ERC-1155 quantities, so an
// edition held in many copies would outrank the collection somebody collects.
check("distinct pieces beat summed quantities",
      NFTCountField.count(distinct: "80", total: "912") == 80)
check("totalBalance is the fallback, not the preference",
      NFTCountField.count(distinct: nil, total: "912") == 912)
// A collection the read RETURNED is one the wallet holds — never 0, which
// would sort a real collection below every other as the least held.
check("an unreadable count falls back to 1",
      NFTCountField.count(distinct: nil, total: nil) == 1)
check("a zero is not believed", NFTCountField.count(distinct: "0", total: "5") == 5)
check("a negative is not believed", NFTCountField.parse("-1486618624") == nil)
// Some chains answer with a huge JSON number, and `as? Int` on an NSNumber
// backed by a large Double truncates to nonsense — that is the shipped
// `count=-1486618624` this whole type exists to stop.
check("an implausible count reads as unknown",
      NFTCountField.parse(10_000_000_000) == nil)
check("a huge string is not believed", NFTCountField.parse("10000000001") == nil)
check("a fractional double is not a count", NFTCountField.parse(3.5) == nil)
check("garbage is not a count", NFTCountField.parse("many") == nil)
check("the ceiling itself is allowed",
      NFTCountField.parse(NFTCountField.ceiling) == NFTCountField.ceiling)

// MARK: - NFTCollectionOrder

let mixed = [
    col("eth-mainnet", "0x1", name: "Zebra", count: 2, spam: false),
    col("eth-mainnet", "0x2", name: "Alpha", count: 90, spam: true),
    col("eth-mainnet", "0x3", name: "Beta",  count: 40, spam: false),
]
let sorted = NFTCollectionOrder.sorted(mixed)
// THE BAND, which is the part doing the work: measured on a real wallet, 81 of
// 100 contracts were isSpam. A dusted collection must never lead the picker,
// however much of it there is — and "Alpha" would lead any A–Z list.
check("non-spam leads, whatever the name or count",
      sorted.map(\.name) == ["Beta", "Zebra", "Alpha"])
check("A–Z is the default sort",
      NFTCollectionOrder.sorted(mixed).map(\.name)
        == NFTCollectionOrder.sorted(mixed, by: .name).map(\.name))

// COUNT IS NOT A RANK (2026-08-15). It was, and the first live run refuted the
// reasoning: the picker led with 2,001 airdropped pieces. It stays on the cell
// as a fact and reaches the order nowhere.
let counted = NFTCollectionOrder.sorted([
    col("eth-mainnet", "0x1", name: "Ant",  count: 1),
    col("eth-mainnet", "0x2", name: "Zebu", count: 2001),
])
check("a huge count does not outrank a name", counted.map(\.name) == ["Ant", "Zebu"])

let byName = NFTCollectionOrder.sorted([
    col("eth-mainnet", "0x1", name: "beta", count: 5),
    col("eth-mainnet", "0x2", name: "Alpha", count: 5),
])
check("A–Z is case-insensitive", byName.map(\.name) == ["Alpha", "beta"])

// RECENT. Lower arrival is more recent; the band still wins over it.
let recent = NFTCollectionOrder.sorted([
    col("eth-mainnet", "0x1", name: "Older", arrival: 5),
    col("eth-mainnet", "0x2", name: "Newer", arrival: 0),
    col("eth-mainnet", "0x3", name: "Fresh spam", arrival: 1, spam: true),
], by: .recent)
check("recent puts the newest arrival first", recent.map(\.name) == ["Newer", "Older", "Fresh spam"])
// Arrival is only meaningful WITHIN a chain (nothing relates two chains'
// positions), so a cross-chain tie must fall through to something stable or
// two chains' #0 swap places between opens.
let crossChain = NFTCollectionOrder.sorted([
    col("base-mainnet", "0xb", name: "Zeta", arrival: 0),
    col("eth-mainnet", "0xe", name: "Beta", arrival: 0),
], by: .recent)
check("a cross-chain arrival tie is broken by name, not left unstable",
      crossChain.map(\.name) == ["Beta", "Zeta"])
check("recent is total across two orderings",
      NFTCollectionOrder.sorted(recent, by: .recent).map(\.id)
        == NFTCollectionOrder.sorted(recent.reversed(), by: .recent).map(\.id))

// TOTALITY. A picker that reshuffles between opens over identical data reads as
// broken, and this is the screen somebody returns to in order to CHANGE a
// decision they made against the previous ordering. Two collections identical
// in every ranked field must still come out in one fixed order — proven by
// sorting the same set from two different input orders.
let twins = [
    col("base-mainnet", "0xbbb", name: "Same", count: 4),
    col("base-mainnet", "0xaaa", name: "Same", count: 4),
]
check("the order is total (id breaks a full tie)",
      NFTCollectionOrder.sorted(twins).map(\.id)
        == NFTCollectionOrder.sorted(twins.reversed()).map(\.id))
check("the id tiebreak is ascending",
      NFTCollectionOrder.sorted(twins).first?.contract == "0xaaa")
check("sorting is idempotent",
      NFTCollectionOrder.sorted(NFTCollectionOrder.sorted(mixed)).map(\.id)
        == sorted.map(\.id))
check("an empty list sorts to empty", NFTCollectionOrder.sorted([]).isEmpty)

// MARK: - NFTPickBook

var book = NFTPickBook()
let W = "0xWALLET"
let k1 = NFTPickKey.make(network: "eth-mainnet", contract: "0xaaa")
let k2 = NFTPickKey.make(network: "eth-mainnet", contract: "0xbbb")
let k3 = NFTPickKey.make(network: "base-mainnet", contract: "0xccc")

check("a fresh book is empty", book.isEmpty)
check("nothing is preselected", !book.isPicked(wallet: W, collection: k1))
check("toggle on reports ON", book.toggle(wallet: W, collection: k1) == true)
check("a picked collection reads as picked", book.isPicked(wallet: W, collection: k1))
check("hasPicks follows", book.hasPicks(wallet: W))
check("toggle off reports OFF", book.toggle(wallet: W, collection: k1) == false)
check("an unpicked collection reads as unpicked", !book.isPicked(wallet: W, collection: k1))
// PRUNING. An emptied set left behind answers "yes, picks exist" for a wallet
// whose every pick was just cleared, and the room then draws an empty card.
check("emptying prunes the wallet entirely", !book.hasPicks(wallet: W))
check("and the book reads empty again", book.isEmpty)

book.toggle(wallet: W, collection: k1)
book.toggle(wallet: W, collection: k2)
book.toggle(wallet: W, collection: k3)
check("three picks are held", book.picks(wallet: W).count == 3)

// The wallet key arrives from several call sites — a watch-list entry, a probe
// argument, a resolved name. Normalising in one place is what keeps toggle and
// isPicked from disagreeing about the same wallet.
check("the wallet key is case-insensitive",
      book.isPicked(wallet: "0xwallet", collection: k1))
check("the wallet key is whitespace-trimmed",
      book.isPicked(wallet: "  0xWALLET \n", collection: k1))
check("a different wallet shares nothing",
      !book.isPicked(wallet: "0xOTHER", collection: k1))

// THE SHELF'S CACHE KEY. Unsorted here means an unchanged set of picks misses
// its own cache at random, re-buying the read the window exists to avoid.
check("contracts are chain-scoped",
      book.contracts(wallet: W, network: "eth-mainnet") == ["0xaaa", "0xbbb"])
check("the other chain gets only its own",
      book.contracts(wallet: W, network: "base-mainnet") == ["0xccc"])
check("an unpicked chain gets nothing",
      book.contracts(wallet: W, network: "arb-mainnet").isEmpty)
check("networks lists each picked chain once, sorted",
      book.networks(wallet: W) == ["base-mainnet", "eth-mainnet"])
check("an unknown wallet has no networks", book.networks(wallet: "0xNOBODY").isEmpty)

// THE CACHE KEY, tested with enough elements to be deterministic.
//
// Two contracts is not a test: a Set's iteration order is a function of its
// CONTENTS, so inserting the same pair in a different order gives the identical
// sequence, and with two elements an unsorted Set is sorted half the time
// anyway. The "unsorted" mutation passed against exactly that. Twelve elements
// makes an accidentally-sorted permutation a 1-in-479-million event, which is
// the difference between a gate and a coin flip.
var wide = NFTPickBook()
let many = (0..<12).map { String(format: "0x%02x", (0..<12).reversed()[$0]) }
for c in many { wide.toggle(wallet: W, collection: NFTPickKey.make(network: "eth-mainnet", contract: c)) }
let got = wide.contracts(wallet: W, network: "eth-mainnet")
check("contracts come out sorted", got == got.sorted())
check("and hold every pick", got.count == 12)

// RETAIN. Re-watching an address must not restore a previous life's shelf.
var kept = book
kept.retain(wallets: ["0xOTHER"])
check("retain drops a wallet that is no longer watched", !kept.hasPicks(wallet: W))
var keptSelf = book
keptSelf.retain(wallets: ["0xWaLLeT"])
check("retain matches case-insensitively", keptSelf.hasPicks(wallet: W))
var cleared = book
cleared.clear(wallet: W)
check("clear empties one wallet", !cleared.hasPicks(wallet: W))

// Codable, because the book is persisted and a decode failure would silently
// unpick everything.
let data = try! JSONEncoder().encode(book)
let back = try! JSONDecoder().decode(NFTPickBook.self, from: data)
check("the book round-trips through JSON", back == book)


// ---------------------------------------------------------------------------
// WalletNFTOrigin — where a received NFT came from (2026-08-26, prd §481).
//
// Every failure below renders as a perfectly ordinary wallet feed. A spam mint
// that keeps showing looks exactly like one the rule has not reached yet, and a
// legitimate mint that vanishes looks exactly like a chain that went quiet —
// which is why none of this can be judged by opening the app.

let NET   = "eth-mainnet"
let MINE  = "0xmine"
let JUNK  = "0xjunk"
let FRIEND = "0xfriend"
let VOID0 = "0x0000000000000000000000000000000000000000"
let DEAD  = "0x000000000000000000000000000000000000dead"

func nftLeg(_ contract: String?, from: String?,
            category: String = "erc721") -> WalletNFTOrigin.Leg {
    WalletNFTOrigin.Leg(network: NET, category: category,
                        contract: contract, counterparty: from)
}
func pk(_ contract: String) -> String { NFTPickKey.make(network: NET, contract: contract) }

func say(_ leg: WalletNFTOrigin.Leg,
         owned: Set<String>? = [MINE, JUNK],
         picked: Set<String> = [],
         verified: Set<String> = [],
         knownGood: Set<String> = [],
         signed: Bool? = nil) -> WalletNFTOrigin.Verdict {
    WalletNFTOrigin.verdict(leg, ownedContracts: owned, picked: picked,
                            verified: verified, knownGood: knownGood, signed: signed)
}

// THE HEADLINE, and the whole reason the file exists. A mint arrives from the
// void, so the 2026-07-15 "do you hold it" arm passes by construction; the only
// thing that separates the one you performed from the one pushed at you is who
// sent the transaction.
check("a mint you sent is kept",
      say(nftLeg(MINE, from: VOID0), signed: true) == .keep)
check("a mint somebody else sent is dropped",
      say(nftLeg(MINE, from: VOID0), signed: false) == .drop)
check("a mint nobody has read a receipt for is undecided, not dropped",
      say(nftLeg(MINE, from: VOID0), signed: nil) == .askWhoSent)

// THE VOID GUARD — the sharpest edge in the rule. Burning is done by SENDING to
// the void, so a wallet that has ever burned anything carries `0x…0000` in its
// known-good set. Without the guard the counterparty rung would vouch for every
// mint ever, and the whole filter would be switched off by one old burn, with
// nothing on screen to say so.
check("the void is never a known-good counterparty (0x0)",
      say(nftLeg(MINE, from: VOID0), knownGood: [VOID0], signed: false) == .drop)
check("the void is never a known-good counterparty (0x…dEaD)",
      say(nftLeg(MINE, from: DEAD), knownGood: [DEAD], signed: false) == .drop)
check("a real address you have sent to still vouches",
      say(nftLeg(MINE, from: FRIEND), knownGood: [FRIEND], signed: false) == .keep)
check("a known-good counterparty is matched case-insensitively",
      say(nftLeg(MINE, from: "0xFRIEND"), knownGood: [FRIEND], signed: false) == .keep)
check("an address you have NOT sent to does not vouch",
      say(nftLeg(MINE, from: "0xstranger"), knownGood: [FRIEND], signed: false) == .drop)

// THE FREE KEEPS. Both can only ever ADD a row, so both must beat the drop.
check("a picked collection is kept even when everything else says drop",
      say(nftLeg(JUNK, from: VOID0), owned: [], picked: [pk(JUNK)], signed: false) == .keep)
check("a safelisted collection is kept even when everything else says drop",
      say(nftLeg(JUNK, from: VOID0), owned: [], verified: [pk(JUNK)], signed: false) == .keep)
check("a pick for a DIFFERENT collection does not vouch",
      say(nftLeg(JUNK, from: VOID0), picked: [pk(MINE)], signed: false) == .drop)
check("a pick key is the picker's own format",
      WalletNFTOrigin.key(for: nftLeg(MINE, from: nil)) == pk(MINE))
check("a leg with no contract has no key",
      WalletNFTOrigin.key(for: nftLeg(nil, from: nil)) == nil)

// THE 2026-07-15 RULE, UNCHANGED — and it still runs BEFORE the receipt
// question, so a collection you do not hold costs no read.
check("a received NFT you do not hold is dropped",
      say(nftLeg("0xother", from: FRIEND), signed: true) == .drop)
check("and it is dropped without asking who sent it",
      say(nftLeg("0xother", from: FRIEND), signed: nil) == .drop)

// FAIL OPEN, EVERY ARM. A nil owned set means the READ failed; a nil `signed`
// means the receipt did. Neither may become a silent spam filter.
check("an unread holdings set still asks who sent it",
      say(nftLeg(MINE, from: VOID0), owned: nil, signed: nil) == .askWhoSent)
check("an unread holdings set plus a known sender is still a drop",
      say(nftLeg(MINE, from: VOID0), owned: nil, signed: false) == .drop)

// SCOPE. This rule speaks about NFTs and nothing else — an ERC-20 has the dust
// floor and a native coin has no filter by design. Widening it here would drop
// tokens twice and coins wrongly.
check("erc1155 is an NFT too",
      say(nftLeg(MINE, from: VOID0, category: "erc1155"), signed: false) == .drop)
check("an erc20 is not this rule's business",
      say(nftLeg(MINE, from: VOID0, category: "erc20"), signed: false) == .keep)
check("a native transfer is not this rule's business",
      say(nftLeg(nil, from: FRIEND, category: "external"), signed: false) == .keep)
check("an NFT with no contract is kept",
      say(nftLeg(nil, from: VOID0), signed: false) == .keep)
check("isNFT names both NFT categories and nothing else",
      WalletNFTOrigin.isNFT("erc721") && WalletNFTOrigin.isNFT("erc1155")
        && !WalletNFTOrigin.isNFT("erc20") && !WalletNFTOrigin.isNFT("external"))

print(failures == 0 ? "\nAll assertions passed." : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

if ! swiftc -O -o "$TMP/run" "${SOURCES[@]}" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "✗ the shipped sources did not compile against the harness"
  grep -E 'error:' "$TMP/build.log" | head -20
  exit 1
fi
"$TMP/run"

# --- mutations --------------------------------------------------------------
# A check that cannot fail proves nothing. Each mutation is a plausible
# "simplification" of the shipped source, and each must break the run.
echo
echo "mutations (each must be caught)"

WORK="$TMP/work"
# Mutates ONE of the compiled sources and rebuilds the whole set, so a
# mutation in `WalletNFTOrigin.swift` is still linked against the real
# `WalletNFTPicks`/`WalletVerbs` it leans on. `target` is the file to break;
# every other source is copied through untouched.
mutate_in() {
  local target="$1" name="$2" from="$3" to="$4"
  rm -rf "$WORK"; mkdir -p "$WORK"
  local copies=()
  for src in "${SOURCES[@]}"; do
    cp "$src" "$WORK/$(basename "$src")"
    copies+=("$WORK/$(basename "$src")")
  done
  local broken="$WORK/$(basename "$target")"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$broken" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$broken"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -O -o "$TMP/mut" "${copies[@]}" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

mutate()        { mutate_in "$PICKS"  "$@"; }
mutate_origin() { mutate_in "$ORIGIN" "$@"; }

# 1. A checksummed pick key never matches the lowercased read — every tap on
#    that collection looks ignored, forever.
mutate "the contract's case left alone" \
  '"\(network)|\(contract.lowercased())"' \
  '"\(network)|\(contract)"'

# 2. A truncated stored key resolving to a plausible half.
mutate "split accepting an empty half" \
  'guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }' \
  'guard parts.count == 2 else { return nil }'

# 2b. THE SHIPPED BUG, as a mutation. `totalBalance` sums ERC-1155 quantities,
#     so preferring it makes an edition held in many copies outrank the
#     collection somebody actually collects (measured: 912 vs 80).
mutate "summed quantities preferred over distinct pieces" \
  'parse(distinct) ?? parse(total) ?? 1' \
  'parse(total) ?? parse(distinct) ?? 1'

# 2c. The other half of it: believing a value that cannot be a count, which is
#     what put `count=-1486618624` on screen.
mutate "the plausibility ceiling removed" \
  '(n > 0 && n <= ceiling) ? n : nil' \
  'n'

# 3. Spam leading the picker.
mutate "the spam band removed from the order" \
  'if a.isSpam != b.isSpam { return !a.isSpam }' \
  'if a.isSpam != b.isSpam { return a.isSpam }'

# 4. Least-held first — the picker leading with the airdrops.
mutate "the recency direction inverted" \
  'if a.arrival != b.arrival { return a.arrival < b.arrival }' \
  'if a.arrival != b.arrival { return a.arrival > b.arrival }'

# 5. A non-total order: the picker reshuffles between opens.
mutate "the id tiebreak dropped" \
  'return a.id < b.id' \
  'return false'

# 6. An emptied set left behind, so hasPicks lies and the room draws an
#    empty card.
mutate "the empty pick set left in place" \
  'if set.isEmpty { byWallet.removeValue(forKey: key) } else { byWallet[key] = set }' \
  'byWallet[key] = set'

# 7. The shelf's cache key becomes unstable — an unchanged set of picks misses
#    its own cache at random and re-buys the windowed read.
mutate "the contract list left unsorted" \
  '.map(\.contract)
            .sorted()' \
  '.map(\.contract)'

# 8. Ethereum asked for a Base contract; the shelf quietly returns nothing.
mutate "the chain filter dropped from contracts" \
  'filter { $0.network == network }' \
  'filter { _ in true }'

# 9. toggle and isPicked disagree about the same wallet.
mutate "the wallet key left un-normalised" \
  'address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()' \
  'address'

# 10. Re-watching an address restores a previous life's shelf.
# Spelled as a real filter rather than `byWallet = byWallet`, which the
# compiler rejects outright: a mutation caught at compile time proves the
# assertion set never had to look at it.
mutate "retain keeping everything" \
  'byWallet = byWallet.filter { keep.contains($0.key) }' \
  'byWallet = byWallet.filter { _ in true }'

# --- the NFT-origin rule's mutations (prd §481) ------------------------------
# Each is a plausible simplification, and each ships a feed that renders
# perfectly while saying the wrong thing about what arrived.

# 11. THE HEADLINE. A mint pushed at you by a stranger reads as one you made.
mutate_origin "a mint sent by somebody else kept" \
  'case .some(false): return .drop' \
  'case .some(false): return .keep'

# 12. An unread receipt becoming a decision rather than an absence — the point
#     at which "we don't know" and "you sent it" stop being different answers.
mutate_origin "an unread receipt treated as a yes" \
  'case .none:        return .askWhoSent' \
  'case .none:        return .keep'

# 13. THE VOID GUARD. A wallet that once burned something has 0x…0000 in its
#     known-good set, so without this the counterparty rung vouches for EVERY
#     mint and the whole filter is off — silently, and only for the wallets that
#     have been around long enough to have burned anything.
mutate_origin "the void allowed to vouch as a counterparty" \
  '!WalletVerbs.isVoid(counterparty),' \
  'counterparty.count >= 0,'

# 14. A counterparty compared without folding case — the addresses arrive
#     checksummed from one source and lowercased from another, so a friend's
#     gift is dropped depending on which read found it.
mutate_origin "a counterparty compared without folding case" \
  'knownGood.contains(counterparty.lowercased())' \
  'knownGood.contains(counterparty)'

# 15/16. The two free keeps neutered. Both are the only thing standing between a
#     collection somebody chose (§387) and a vendor's classification of it.
mutate_origin "a pick no longer overriding the vendor's guess" \
  'if picked.contains(key) { return .keep }' \
  'if picked.contains(key + "!") { return .keep }'

mutate_origin "safelisting no longer vouching" \
  'if verified.contains(key) { return .keep }' \
  'if verified.contains(key + "!") { return .keep }'

# 17. The 2026-07-15 arm inverted — every junk airdrop kept and every real
#     collection dropped, which is the loudest possible version of this bug and
#     still invisible to a build.
mutate_origin "the holdings arm inverted" \
  'if let ownedContracts, !ownedContracts.contains(leg.contract ?? "") { return .drop }' \
  'if let ownedContracts, ownedContracts.contains(leg.contract ?? "") { return .drop }'

# 18. The holdings arm made undecided rather than decisive, which is what buys a
#     receipt read for every junk airdrop the free rung already answered — the
#     budget spent on exactly the rows it was meant to skip.
mutate_origin "the holdings arm no longer decisive" \
  'if let ownedContracts, !ownedContracts.contains(leg.contract ?? "") { return .drop }' \
  'if let ownedContracts, !ownedContracts.contains(leg.contract ?? "") { return .askWhoSent }'

# 19. ERC-1155 falling out of the definition. Half of NFT spam is 1155s, so the
#     filter would look like it works and let through most of what it is for.
mutate_origin "erc1155 dropped from the NFT definition" \
  'category == "erc721" || category == "erc1155"' \
  'category == "erc721"'

echo
echo "wallet-nft self-test passed."
