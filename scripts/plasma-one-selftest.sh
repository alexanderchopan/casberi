#!/bin/zsh
# Plasma One's settlement decoder (prd §1311), compiled AS SHIPPED.
#
# `Model/PlasmaOneSettlement.swift` is Foundation-only, so this compiles it
# WHOLE with the app's own `Keccak256.swift` and feeds it a REAL batch: the
# receipt logs of one settlement transaction on Plasma
# (`scripts/fixtures/plasma-one/settlement-batch.json`, 20 settlements).
#
# What it guards draws as an ordinary row and fails nothing on its own: an
# amount read off the wrong log, a settlement to some other address counted
# as card spending, a hash that disagrees landed anyway, a part counted twice
# when a cursor rewinds, a day split by the phone's time zone.
#
# Then each guard is MUTATED and must turn the pass red — a check that cannot
# fail certifies nothing.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Casberi/Casberi/Model/PlasmaOneSettlement.swift"
KECCAK="Casberi/Casberi/Model/Keccak256.swift"
FIXTURE="scripts/fixtures/plasma-one/settlement-batch.json"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { print -u2 "✗ $1"; exit 1; }

[[ -f $SRC && -f $KECCAK && -f $FIXTURE ]] || fail "a source or the fixture is missing"

cat > "$work/main.swift" <<'SWIFT'
import Foundation
var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { print("  ✗ \(what)"); failures += 1 }
}
let path = CommandLine.arguments[1]
let root = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as! [String: Any]
let logs = root["logs"] as! [[String: Any]]
let P = PlasmaOneSettlement.self
let settled = logs.filter { ($0["topics"] as? [String])?.first == P.settledBalanceTopic }
let transfers = logs.filter { ($0["topics"] as? [String])?.first == P.transferTopic }
check(settled.count == 20 && transfers.count == 20, "the fixture holds 20 settlements and 20 transfers")

// 1. Every real settlement pairs and its hash checks.
let read = P.settlements(settled: settled, transfers: transfers)
check(read.paired.count == 20 && read.rejected == 0,
      "all 20 real settlements pair and verify — got \(read.paired.count), rejected \(read.rejected)")
let first = read.paired.first { $0.card == "0x8faffd0f04deb7ca7d3d938a4bce1e6146615110" }
check(first?.amount == 246.31, "the amount is the paired USDT0 transfer, six decimals — got \(String(describing: first?.amount))")
check(first?.owner == "0x1371b891eeffe62be15013b055f2a3508a2649e8", "the owner is topic1")
check(first?.at == Date(timeIntervalSince1970: 1792067461), "the time is the log's own block time")
let amounts = Set(read.paired.map(\.amount))
check(amounts.contains(56.9) && amounts.contains(632.31) && amounts.contains(21.69),
      "three more real amounts read exactly")

// 2. A transfer whose amount was changed fails the hash and is refused.
var forged = transfers
var t0 = forged[0]
let data = t0["data"] as! String
t0["data"] = String(data.dropLast()) + (data.last == "0" ? "1" : "0")
forged[0] = t0
let forgedRead = P.settlements(settled: settled, transfers: forged)
check(forgedRead.paired.count == 19 && forgedRead.rejected == 1, "a changed amount is refused by the hash")

// 3. A settlement to another recipient is not card spending.
var stranger = settled
var s0 = stranger[0]
var topics = s0["topics"] as! [String]
topics[2] = P.topic("0x000000000000000000000000000000000000dead")
s0["topics"] = topics
stranger[0] = s0
check(P.settlements(settled: stranger, transfers: transfers).paired.count == 19,
      "a SettledBalance to another address is refused")

// 4. No transfer, no settlement — never an amount of zero.
check(P.settlements(settled: settled, transfers: []).paired.isEmpty,
      "a settlement with no paired transfer lands nothing")

// 5. Days: UTC, one row per owner per day, parts deduped.
let days = P.days(read.paired)
check(days.count == 20 && days.allSatisfy { $0.key == "2026-10-15" }, "twenty owners, one UTC day each")
check(P.dayKey(Date(timeIntervalSince1970: 1792067461)) == "2026-10-15",
      "the day key is UTC, not the phone's zone")
let owner = first!.owner
let second = PlasmaOneSettlement.Settlement(owner: owner, card: first!.card, txHash: "0xabc",
                                            logIndex: 7, block: first!.block + 120,
                                            at: first!.at!.addingTimeInterval(120), amount: 3.80)
let twoParts = P.days([first!, second])
check(twoParts.count == 1 && abs(twoParts[0].total - 250.11) < 0.0001,
      "two settlements on one day are ONE row, summed")
check(P.newParts(of: twoParts[0], alreadyKept: [first!.key]).map(\.key) == [second.key],
      "a part already on the row is not added again")
check(P.newParts(of: twoParts[0], alreadyKept: [first!.key, second.key]).isEmpty,
      "a re-read of a whole day adds nothing")
let kept = twoParts[0].parts.compactMap(P.factValue).compactMap(PlasmaOneSettlement.Kept.init)
check(kept.count == 2, "every part is kept on the row in a shape that reads back")
let total = P.total(of: kept)
check(total?.amount == 250.11 && total?.newest.key == second.key,
      "the row's money is every kept part summed, its time the newest — got \(String(describing: total?.amount))")
check(PlasmaOneSettlement.Kept("0xabc:7") == nil && PlasmaOneSettlement.Kept("0xabc:7|x|1") == nil,
      "a fact of another shape counts toward nothing")
check(twoParts[0].ref == "plasmaone:day:\(owner):2026-10-15", "the row's ref is the owner and the day")

// 6. Code gates.
let card = "0x" + String(repeating: "00", count: 100) + P.cardBeacon + String(repeating: "00", count: 379)
check(P.isCardCode(card), "a 499-byte contract carrying the beacon is a card")
check(!P.isCardCode(card + "00"), "a contract of another size is not")
check(!P.hasCode("0x") && P.hasCode("0x6080"), "a plain key has no code; a smart account does")

if failures > 0 { print("\(failures) assertion(s) failed"); exit(1) }
print("  ok   pairing, hash, recipient, days, dedupe, code gates")
SWIFT

compile_and_run() {
  local src=$1
  swiftc -O -o "$work/t" "$src" "$KECCAK" "$work/main.swift" 2>"$work/err" || { cat "$work/err" >&2; return 2; }
  "$work/t" "$FIXTURE"
}

print "plasma-one-selftest: real batch"
compile_and_run "$SRC" || fail "the shipped decoder failed its checks"

# Mutations — each must turn the pass red.
mutate() {
  local name=$1 from=$2 to=$3
  local m="$work/mut.swift"
  perl -0pe "s/\Q$from\E/$to/" "$SRC" > "$m"
  cmp -s "$SRC" "$m" && fail "mutation '$name' changed nothing — its anchor drifted"
  if compile_and_run "$m" >/dev/null 2>&1; then fail "mutation '$name' SURVIVED"; fi
  print "  ok   mutation killed: $name"
}
mutate "hash check skipped" 'assetHash(token: usdt0, word: word) == topics[3].lowercased(),' 'true,'
mutate "pairs the same log, not the one before" 'byPosition["\(tx):\(index - 1)"]' 'byPosition["\(tx):\(index)"]'
mutate "recipient not checked" 'address(fromTopic: topics[2]) == settlementSafe,
                  let card' 'let card'
mutate "eighteen decimals" 'static let usdt0Decimals = 6' 'static let usdt0Decimals = 18'
mutate "day in the phone's zone" 'calendar.timeZone = TimeZone(identifier: "UTC")!' 'calendar.timeZone = TimeZone(identifier: "Pacific\/Kiritimati")!'
# Anchors carry no `$`: perl interpolates `$0` inside \Q…\E before quoting.
mutate "parts never deduped" 'day.parts.filter { !kept' 'day.parts.filter { true || !kept'
mutate "a grown row keeps only its first part" 'for k in kept { sum +=' 'for k in kept.prefix(1) { sum +='
print "plasma-one-selftest: ok"
