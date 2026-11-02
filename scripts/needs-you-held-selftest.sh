#!/bin/zsh
# Needs you's box states what the asks hold up (prd §1669), compiled AS
# SHIPPED: `Model/NeedsYouHeld.swift` is Foundation-only, so this compiles it
# whole.
#
# Every failure reads as a plausible box:
#   • test money given a dollar figure (a price on Sepolia ETH, §83)
#   • a priced ask hiding behind an unpriced one's quantity
#   • the unpriced claiming a share of the bar by a made-up value
#   • nothing to value, and the box drawing "$0" instead of the count
#   • asks with no money counted negative, or valued
# and the drift no build sees: the page no longer building the box from it.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Casberi/Casberi/Model/NeedsYouHeld.swift"
PAGE="Casberi/Casberi/Screens/FeedScreen+WalletPages.swift"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { print -u2 "✗ $1"; exit 1; }

cat > "$work/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { failures += 1; print("✗ \(what)") }
}
let t0 = Date(timeIntervalSince1970: 1_800_000_000)
func part(_ id: String, _ usd: Double?, _ figure: String, at: TimeInterval = 0) -> NeedsYouHeld.Part {
    .init(id: id, label: "Waiting for approval", figure: figure, usd: usd, since: t0.addingTimeInterval(at), refused: false)
}
let money: (Double) -> String = { String(format: "$%.0f", $0) }

// One unpriced (test money): its quantity, never dollars.
let test = NeedsYouHeld.read([part("a", nil, "0.001 ETH")], others: 0)
check(test.headline(money: money) == "0.001 ETH", "test money keeps its quantity: \(String(describing: test.headline(money: money)))")
check(test.weights == [1], "one part fills the bar")

// Priced and unpriced: dollars of the priced, priced first, largest first.
let mixed = NeedsYouHeld.read([part("t", nil, "0.001 ETH", at: -10), part("s", 9, "9 USDC"), part("b", 4800, "1.2 ETH")], others: 2)
check(mixed.headline(money: money) == "$4809", "dollars of the priced: \(String(describing: mixed.headline(money: money)))")
check(mixed.parts.map(\.id) == ["b", "s", "t"], "priced largest first, then the rest: \(mixed.parts.map(\.id))")
check(mixed.weights == [4800, 9, 9], "the unpriced takes the smallest priced share, nothing bigger: \(mixed.weights)")
check(mixed.others == 2, "the asks with no money are counted")
check(mixed.oldest == t0.addingTimeInterval(-10), "the oldest is the earliest ask")

// Two unpriced: both quantities; three: the count.
let two = NeedsYouHeld.read([part("a", nil, "0.001 ETH"), part("b", nil, "5 USDC", at: 5)], others: 0)
check(two.headline(money: money) == "0.001 ETH + 5 USDC", "two quantities joined")
check(two.weights == [1, 1], "none priced: equal shares")
let three = NeedsYouHeld.read([part("a", nil, "1 A"), part("b", nil, "2 B"), part("c", nil, "3 C")], others: 0)
check(three.headline(money: money) == nil, "three quantities: the box keeps the count")

// Nothing to value: no headline, never "$0"; others never negative.
let none = NeedsYouHeld.read([], others: 3)
check(none.headline(money: money) == nil, "no money: the count stands")
check(NeedsYouHeld.read([], others: -1).others == 0, "others never negative")

if failures > 0 { exit(1) }
print("✓ needs-you-held: 13 checks")
SWIFT

swiftc -O -o "$work/run" "$SRC" "$work/main.swift" 2>"$work/err" || { cat "$work/err" >&2; fail "NeedsYouHeld.swift did not compile alone"; }
"$work/run" || fail "NeedsYouHeld's rules broke"

# The page builds the box from it, and test money never reaches a price.
grep -q 'WalletNeedsHeldFigure(reading: NeedsYouHeld.read(' "$PAGE" || fail "Needs you's box no longer reads NeedsYouHeld"
grep -q 'PrivateMoney.testnets.contains(note.chainId) ? nil' "$PAGE" || fail "test money can take a price in Needs you's box"
