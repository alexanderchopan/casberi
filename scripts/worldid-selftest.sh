#!/bin/zsh
# Casberi World ID self-test (prd §785, 2026-09-16) — the SHIPPED pure logic
# behind "is this address a verified human":
#
#   Casberi/Casberi/Model/WorldID.swift
#     — selector / verifiedUntilCalldata / addressWord   what goes on the wire
#     — word / verifiedUntilSeconds                      what comes back
#     — status(untilUnix:asOf:)                          THE four-case verdict
#
# That file is Foundation-only BY DESIGN (`Keccak256` beside it is pure too),
# so BOTH are compiled WHOLE AND UNMODIFIED here — no extraction, no `private `
# stripping, no copy. Every assertion is about the bytes the app runs.
#
# WHY A HARNESS. Nothing on this host can verify an address at an Orb, and the
# read is one `eth_call` whose every failure mode arrives as the SAME silence:
#
#   • A WRONG SELECTOR. `addressVerifiedUntil(address)` mistyped reverts, the
#     return is empty, and every address on earth reads as "not in the book" —
#     which is also the correct answer for almost every address on earth. So
#     the feature would look like it works, forever, while proving nothing.
#     The selector is computed off `Keccak256` at call time (`WeiNames`' rule)
#     and pinned here against a value computed by a keccak implementation
#     written outside this app and checked on the two published vectors
#     (`keccak256("")` and `keccak256("abc")`).
#   • AN UNREACHABLE CHAIN READ AS A ZERO. `WorldIDSource.fill` must write a
#     record only when the chain ANSWERED; a zero written on a network failure
#     turns "we could not ask" into "this person is not verified" — the one
#     lie this feature exists to avoid (§83). A drift guard below.
#   • AN EXPIRED VERIFICATION STILL CLAIMING. The book stores a second, not a
#     boolean, so the verdict has to be read against a clock — and a card that
#     keeps saying "verified human" three years after the mark ran out is a
#     stale claim about a person, made beside money.
#   • ABSENCE DRAWN AS A FACT. `.absent` and `.unknown` must draw nothing on
#     both surfaces. "Not in World ID's book" is not "not a human", and an
#     address card is the last place to imply it.
#
# WHAT IT DELIBERATELY DOES NOT PROVE. It never reaches World Chain, so it says
# nothing about whether the contract still answers, in what shape, or how a
# PERMANENT verification is stored there (a far-future second, or a sentinel
# this file would read as malformed) — that is `-worldIDProbe`'s job, and the
# probe prints the raw word for exactly that reason.
#
# Pure, local, deterministic — no network, no simulator, no key. Exit non-zero
# on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

WORLDID="Casberi/Casberi/Model/WorldID.swift"
KECCAK="Casberi/Casberi/Model/Keccak256.swift"
SOURCE="Casberi/Casberi/Model/WorldIDSource.swift"
CARD="Casberi/Casberi/Screens/AddressBookViews.swift"
ROOM="Casberi/Casberi/Screens/PersonRoomScreen.swift"
REACH="Casberi/Casberi/Model/NetworkReach.swift"
CHAINS="Casberi/Casberi/Model/WalletChainStore.swift"
for f in "$WORLDID" "$KECCAK" "$SOURCE" "$CARD" "$ROOM" "$REACH" "$CHAINS"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d /tmp/worldid-selftest.XXXXXX)
WORK="$TMP/work"
trap 'rm -rf "$TMP"' EXIT

# A COMMENT-STRIPPED copy for every negative guard. These files document their
# own rules by naming what they must not do — `WorldID`'s header spells out the
# "a zero is not 'not a person'" rule in prose — so a guard grepping raw source
# would fire on the paragraph explaining it (the Obsidian/Cursor lesson).
strip() {
  python3 - "$1" <<'PY'
import re, sys
for line in open(sys.argv[1]).read().split("\n"):
    if line.strip().startswith("//"):
        continue
    print(re.sub(r'\s//(?!/).*$', '', line))
PY
}
strip "$SOURCE" > "$TMP/source.stripped"
strip "$CARD"   > "$TMP/card.stripped"
strip "$ROOM"   > "$TMP/room.stripped"

# --- the compiled assertions -------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { print("  ✗ \(what)"); failures += 1 }
}
func eq(_ a: String?, _ b: String?, _ what: String) {
    if a != b { print("  ✗ \(what) — got \(a ?? "nil"), want \(b ?? "nil")"); failures += 1 }
}

// keccak256("addressVerifiedUntil(address)")[0..<4], computed by an
// implementation written outside this app and checked on the two published
// vectors first. If this line ever fails, the app's Keccak moved — not this
// signature.
let selector = "2bc91fed"
let vitalik = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
let vitalikWord = "000000000000000000000000d8da6bf26964af9d7eed9e03e53415d37aa96045"
let zeroReturn = "0x" + String(repeating: "0", count: 64)
let futureReturn = "0x00000000000000000000000000000000000000000000000000000000713fb300" // 1_900_000_000
let now = Date(timeIntervalSince1970: 1_800_000_000)
let later = Date(timeIntervalSince1970: 1_950_000_000)

// --- what goes on the wire ---------------------------------------------------
eq(WorldID.selector(WorldID.verifiedUntilSignature), selector,
   "the addressVerifiedUntil selector")
check(!WorldID.selector(WorldID.verifiedUntilSignature).hasPrefix("0x"),
      "a selector is a bare fragment, never 0x-prefixed")
eq(WorldID.verifiedUntilSignature, "addressVerifiedUntil(address)", "the mapping's getter")
eq(WorldID.verifiedUntilCalldata(address: vitalik), "0x" + selector + vitalikWord,
   "calldata for a checksummed address")
eq(WorldID.verifiedUntilCalldata(address: vitalik.lowercased()),
   WorldID.verifiedUntilCalldata(address: vitalik),
   "an EIP-55 address is lowercased — the case is a checksum, not identity")
eq(WorldID.addressWord(vitalik), vitalikWord, "the address word is left-padded to 32 bytes")
check(WorldID.addressWord(vitalik)?.count == 64, "one word, exactly")
// REFUSED, never padded: a handle or a Solana address asked here would come
// back "absent", which reads as an answer about somebody.
eq(WorldID.verifiedUntilCalldata(address: "0xd8da"), nil, "a short address is refused")
eq(WorldID.verifiedUntilCalldata(address: "vitalik.eth"), nil, "a name is refused")
eq(WorldID.verifiedUntilCalldata(address: "DYw8jCTfwHNRJhhmFcbXvVDTqWMEVFBX6ZKUmG5CNSKK"), nil,
   "a Solana address is refused")
eq(WorldID.addressWord(""), nil, "an empty string is not an address")

// --- the book's identity ------------------------------------------------------
eq(WorldID.addressBook, "0x57b930D551e677CC36e2fA036Ae2fe8FdaE0330D", "the address book contract")
eq(WorldID.network, "worldchain-mainnet", "Alchemy's id for World Chain")
check(WorldID.chainId == 480, "World Chain is chain id 480")
check(WorldID.rpc.hasPrefix("https://"), "the RPC is https")
check(!WorldID.rpc.contains("/v2/"), "the RPC is the KEYLESS public endpoint — no key in the URL")
// THE HOST IS ITS OWN, and the receipts screen is why: a service is resolved
// BY HOST first, so sharing the wallet's World Chain host filed this read
// under the Wallet bridge for people who never connected it.
check(!WorldID.rpc.contains("g.alchemy.com"),
      "the World ID read does NOT share the wallet's Alchemy host — one host, one service")

// --- what comes back ----------------------------------------------------------
eq(WorldID.word(futureReturn, 0), "00000000000000000000000000000000000000000000000000000000713fb300",
   "the first word of a return")
eq(WorldID.word("0x", 0), nil, "an empty return has no word")
eq(WorldID.word("0xnothex", 0), nil, "a non-hex return has no word")
check(WorldID.verifiedUntilSeconds(from: zeroReturn) == 0, "a zero word reads as zero seconds")
check(WorldID.verifiedUntilSeconds(from: futureReturn) == 1_900_000_000, "a timestamp reads whole")
eq(WorldID.verifiedUntilSeconds(from: "0x").map { String($0) }, nil,
   "an empty return is UNREADABLE, never zero")
eq(WorldID.verifiedUntilSeconds(from: "0x" + String(repeating: "f", count: 64)).map { String($0) }, nil,
   "a word too large for an Int is unreadable rather than wrapped")

// --- THE VERDICT --------------------------------------------------------------
// The whole honesty of the feature: four cases, and only ONE of them draws.
check(WorldID.status(fromReturn: zeroReturn, asOf: now) == .absent,
      "zero is ABSENT — the book has nothing for this address")
check(WorldID.status(fromReturn: "0x", asOf: now) == .unknown,
      "an unreachable/reverted call is UNKNOWN, never absent")
check(WorldID.status(fromReturn: zeroReturn, asOf: now) != .unknown,
      "absent and unknown are different answers")
check(WorldID.status(fromReturn: futureReturn, asOf: now) == .verified(until: Date(timeIntervalSince1970: 1_900_000_000)),
      "a mark that has not run out is VERIFIED")
check(WorldID.status(fromReturn: futureReturn, asOf: later) == .lapsed(at: Date(timeIntervalSince1970: 1_900_000_000)),
      "the same mark, read after its second, is LAPSED")
check(WorldID.status(untilUnix: 1_900_000_000, asOf: now).isVerified, "isVerified says so")
check(!WorldID.status(untilUnix: 1_900_000_000, asOf: later).isVerified, "a lapsed mark is not verified")
check(!WorldID.status(untilUnix: 0, asOf: now).isVerified, "absent is not verified")
check(!WorldID.status(fromReturn: "0x", asOf: now).isVerified, "unknown is not verified")
// THE BOUNDARY. A verification that expires this very second has expired.
check(WorldID.status(untilUnix: 1_800_000_000, asOf: now) == .lapsed(at: now),
      "a mark expiring exactly now is lapsed, not verified")
// AN ANSWER WE CANNOT READ IS STILL AN ANSWER. It is stored so the address is
// not re-asked on every visit forever, and it reads back as UNKNOWN — never as
// absent, which would be a claim about somebody off a word we did not parse.
check(WorldID.status(untilUnix: WorldID.unreadableSeconds, asOf: now) == .unknown,
      "an unreadable answer is UNKNOWN, never absent")
check(!WorldID.status(untilUnix: WorldID.unreadableSeconds, asOf: now).isVerified,
      "an unreadable answer is not verified")
check(WorldID.unreadableSeconds < 0, "the unreadable marker cannot collide with a timestamp")

if failures == 0 { print("  assertions passed") } else { exit(1) }
SWIFT

echo "worldid-selftest: compiling the shipped source…"
swiftc -Onone -o "$TMP/run" "$WORLDID" "$KECCAK" "$TMP/main.swift" 2>&1 | head -20
"$TMP/run" || { echo "✗ assertions failed"; exit 1; }

# --- drift guards -------------------------------------------------------------
# Facts the compiled functions cannot prove: a perfect decoder is worthless if
# a failed read is written as an answer, or if absence is drawn as a fact.

# 1. A READ THAT DID NOT ANSWER MUST NOT BE WRITTEN. The guard and the write
#    in one grep, so reordering them fails here rather than on somebody's card.
grep -q 'guard let returned = await ethCall(data: data) else { return false }' "$TMP/source.stripped" \
  || { echo "✗ WorldIDSource.fill no longer guards on the chain having answered — a zero written on a network failure says 'not a person'"; exit 1; }
grep -q 'WorldID.verifiedUntilSeconds(from: returned) ?? WorldID.unreadableSeconds' "$TMP/source.stripped" \
  || { echo "✗ WorldIDSource.fill no longer keeps an answer it could not read — dropping it re-asks that address on every visit forever"; exit 1; }

# 2. ABSENCE DRAWS NOTHING, on both surfaces. The card switches all four cases
#    and the two silent ones must stay silent; the room draws only on a live
#    mark.
grep -q 'case .absent, .unknown:' "$TMP/card.stripped" \
  || { echo "✗ the address card no longer answers .absent/.unknown together — absence must draw nothing"; exit 1; }
grep -A 1 'case .absent, .unknown:' "$TMP/card.stripped" | grep -q 'EmptyView()' \
  || { echo "✗ the address card draws something for .absent/.unknown — 'not in World ID's book' is not a fact about a person (§83)"; exit 1; }
grep -q 'if case .verified(let until) = worldStatus' "$TMP/room.stripped" \
  || { echo "✗ the person room no longer draws only on a VERIFIED mark"; exit 1; }
# 2b. NOTHING IN THE ROOM WAITS ON THIS READ. Up to `perPassBudget` sequential
#     calls to a public RPC at 15s a timeout; ahead of the room's own loads it
#     left the whole screen spinning to decide one line that usually draws
#     nothing.
fill_line=$(grep -n 'WorldIDSource.shared.fill(' "$TMP/room.stripped" | head -1 | cut -d: -f1)
done_line=$(grep -n 'loading = false' "$TMP/room.stripped" | head -1 | cut -d: -f1)
if [[ -z "$fill_line" || -z "$done_line" || "$fill_line" -lt "$done_line" ]]; then
  echo "✗ the person room awaits the World ID read before it finishes loading — an unreachable World Chain stalls the room"; exit 1
fi
# 2c. BOTH SURFACES READ THE STORE, never a `@State` copy taken after `fill`
#     returns: `fill` returns immediately for an address already in flight, so
#     a copy made then stays `.unknown` for the whole visit.
for _f in "$TMP/card.stripped" "$TMP/room.stripped"; do
  if grep -q '@State private var worldStatus' "$_f"; then
    echo "✗ a surface copies the World ID status into @State — it must read the @Observable store"; exit 1
  fi
done

# 3. THE READ IS BOUGHT BY AN INTENT, never by a row. `fill` may be reached
#    from a card task and the room's load, and from nowhere that scrolls.
callers=$(grep -rn "WorldIDSource.shared" --include="*.swift" Casberi/Casberi | grep -v "Model/WorldIDSource.swift" | wc -l | tr -d ' ')
[[ "$callers" -le 6 ]] \
  || { echo "✗ $callers callers of WorldIDSource — a read is bought by opening a card or a room, never by a row scrolling past (AddressNames' rule)"; exit 1; }

# 4. THE HOST IS DISCLOSED, and under its own service. It is a `g.alchemy.com`
#    subdomain, so the receipts screen would file it under the Wallet bridge —
#    but this read happens whether or not a wallet is watched.
grep -q '"worldchain-mainnet.g.alchemy.com"' "$REACH" \
  || { echo "✗ World Chain's host is not in NetworkReach"; exit 1; }
grep -q 'Endpoint(service: "World ID"' "$REACH" \
  || { echo "✗ NetworkReach has no World ID entry — the read is not tied to any bridge, so it needs its own"; exit 1; }
# …AND THAT ENTRY RESOLVES TO ITSELF. A receipt's service is `service(forHost:)`
# first and the caller's own name second, so a host listed under two entries is
# labelled with one of them — sharing the wallet's Alchemy host filed this read
# under the WALLET BRIDGE, for people who never connected it, while the code
# and this harness both claimed otherwise.
worldid_hosts=$(awk '/Endpoint\(service: "World ID"/,/\]\)/' "$REACH" | grep 'hosts:')
if [[ -z "$worldid_hosts" ]]; then
  echo "✗ could not read the World ID entry's hosts"; exit 1
fi
case "$worldid_hosts" in
  *g.alchemy.com*)
    echo "✗ the World ID entry lists the wallet's Alchemy host — a receipts row for a read that needs no bridge would say 'Wallet'"; exit 1 ;;
esac
worldid_host=$(echo "$worldid_hosts" | sed -E 's/.*"([a-z0-9.-]+)".*/\1/')
grep -q "$worldid_host" "$WORLDID" \
  || { echo "✗ the declared World ID host ($worldid_host) is not the one WorldID.rpc calls"; exit 1; }
grep -q 'service: "World ID"' "$TMP/source.stripped" \
  || { echo "✗ the read no longer names itself to NetworkLedger — the receipts screen would attribute it to the Wallet bridge"; exit 1; }

# 5. WORLD CHAIN IS ON BY DEFAULT, because it was measured (prd §788, which
#    amends §785's off-until-measured guard rather than deleting it). On means
#    three things together, and each alone ships a quiet hole: in the default
#    set (fresh installs), in the seed list (every install that chose its
#    chains before today — `seeded`'s own doc), and mapped in Zerion (else it
#    costs an Alchemy chain per wallet, which is Robinhood's reason to be off).
grep -q '("worldchain-mainnet", "World Chain")' "$CHAINS" \
  || { echo "✗ World Chain is not in the wallet's chain picker"; exit 1; }
grep -A 4 'defaultNetworkIDs = \[' "$CHAINS" | grep -q 'worldchain-mainnet' \
  || { echo "✗ World Chain is not ON by default (prd §788)"; exit 1; }
grep -q '("worldchain-mainnet", *"wallet.chains.worldchainSeeded.v1")' "$CHAINS" \
  || { echo "✗ World Chain is on by default with no seed row — only installs made after today would read it"; exit 1; }
grep -q '"world": "worldchain-mainnet"' "$(dirname "$CHAINS")/ZerionAPI.swift" \
  || { echo "✗ World Chain is on by default but Zerion does not map it — every wallet pays an Alchemy chain for it"; exit 1; }
# …and the Alchemy arm never asks it for `internal` transfers, which refuses
# the WHOLE call there (measured on six chains, prd §788).
if grep -q 'network: "worldchain-mainnet".*internalTransfers: true' "$(dirname "$CHAINS")/WalletIngest.swift"; then
  echo "✗ World Chain asks Alchemy for internal transfers — the call is refused whole"; exit 1
fi

# 6. THE GRANT DOOR LANDS WHERE IT SAYS, ONLY ON A GRANT, ONLY WHEN IT CAN OPEN
#    (prd §792). `worldapp://grants` is the link World's own page uses; an
#    unclaimed custom scheme opens NOTHING, so both dials gate on World App
#    answering it here, and the scheme must be declared or it never answers.
INGEST_W="Casberi/Casberi/Model/WalletIngest.swift"
grep -q 'static let worldAppGrantsLink = URL(string: "worldapp://grants")!' "$INGEST_W" \
  || { echo "✗ the grant door is not World App's grants link"; exit 1; }
grep -q 'knownContracts\[address.lowercased()\] == "World ID grants"' "$INGEST_W" \
  || { echo "✗ isWorldGrantHolder no longer reads the named grant holders"; exit 1; }
grep -q '<string>worldapp</string>' Casberi/Casberi/Info.plist \
  || { echo "✗ worldapp is not in LSApplicationQueriesSchemes — the door can never be offered"; exit 1; }
grep -q '"worldapp"' Casberi/Casberi/Model/Verbs.swift \
  || { echo "✗ worldapp is not a HandOffState candidate — installedSchemes never contains it"; exit 1; }
for _dial in "Casberi/Casberi/Model/Verbs.swift" "Casberi/Casberi/Screens/ThingSheetView.swift"; do
  _gate=$(grep -B4 'WalletIngest.worldAppGrantsLink' "$_dial")
  echo "$_gate" | grep -q 'isWorldGrantHolder(thing.counterpartyAddress)' \
    || { echo "✗ $_dial offers the grant door without the grant-holder gate"; exit 1; }
  echo "$_gate" | grep -q 'installedSchemes.contains("worldapp")' \
    || { echo "✗ $_dial offers the grant door without World App installed — a disc that opens nothing"; exit 1; }
done

# --- mutation liveness --------------------------------------------------------
# Each mutation is a REAL past-or-plausible defect. A mutation that still
# passes means nothing above was testing it.
mutate() {
  local name="$1" from="$2" to="$3"
  rm -rf "$WORK"; mkdir -p "$WORK"
  cp "$WORLDID" "$WORK/WorldID.swift"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$WORK/WorldID.swift" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$WORK/WorldID.swift"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -Onone -o "$TMP/mut" "$WORK/WorldID.swift" "$KECCAK" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# 1. THE ONE THAT MATTERS. An unreadable return treated as zero: every address
#    would read "absent" the moment the chain stopped answering, and the app
#    would be quietly certain about people it never asked about.
mutate "an unreadable return read as zero" \
  'guard let word = word(hex, 0) else { return nil }' \
  'guard let word = word(hex, 0) else { return 0 }'

# 2. The expiry ignored — a mark that ran out in 2024 still saying "verified
#    human" beside an address you are about to pay.
mutate "an expired verification still claiming" \
  'return until > now ? .verified(until: until) : .lapsed(at: until)' \
  'return .verified(until: until)'

# 3. Zero read as a verification — every address on earth verified, including
#    the poisoned look-alike this fact is meant to separate from its target.
mutate "zero read as a verification" \
  'guard seconds > 0 else { return .absent }' \
  'guard seconds >= 0 else { return .absent }'

# 4. The address word not lowercased. EIP-55 case is a checksum; a mixed-case
#    word asks about nothing and answers absent.
mutate "the address word no longer lowercased" \
  'let value = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()' \
  'let value = address.trimmingCharacters(in: .whitespacesAndNewlines)'

# 5. A malformed address padded rather than refused — a truncated paste would
#    be asked about, and answered about, as if it were an address.
mutate "a short address padded rather than refused" \
  'guard value.hasPrefix("0x"), value.count == 42,' \
  'guard value.hasPrefix("0x"), value.count <= 42,'

# 6. The unreadable marker read as an ordinary number — it is negative, so it
#    falls through to `.absent` and claims "this book holds nothing" about a
#    word we simply failed to parse.
mutate "an unreadable answer read as absent" \
  'guard seconds != unreadableSeconds else { return .unknown }' \
  'guard seconds != Int.min else { return .unknown }'

# 7. The selector taken from the wrong signature. It reverts, the return is
#    empty, and every address reads as "not in the book" — forever, silently.
mutate "the selector computed from the wrong signature" \
  'static let verifiedUntilSignature = "addressVerifiedUntil(address)"' \
  'static let verifiedUntilSignature = "addressVerifiedUntil(address,uint256)"'

echo
echo "✓ worldid-selftest passed"
