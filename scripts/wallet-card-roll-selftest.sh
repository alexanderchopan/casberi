#!/bin/zsh
# Home's Cards (prd §1232), compiled AS SHIPPED.
#
# `Model/WalletCardRoll.swift` is Foundation-only, so this compiles it WHOLE.
# What it guards renders as an ordinary list: a card that asks for money
# drawn under one that merely spent the most, last month's purchases counted
# as this month's, a refund counted as a purchase, an offer already past its
# end still offered. None of that fails a build or a screenshot.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Casberi/Casberi/Model/WalletCardRoll.swift"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { print -u2 "✗ $1"; exit 1; }

cat > "$work/main.swift" <<'SWIFT'
import Foundation
var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { print("  ✗ \(what)"); failures += 1 }
}
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "UTC")!
let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 12))!
func day(_ d: Int, month: Int = 10) -> Date { cal.date(from: DateComponents(year: 2026, month: month, day: d, hour: 9))! }

let roll = WalletCardRoll.compose(
    spends: [
        .init(card: "Big Spender", app: "Gnosis Pay", usd: 900, at: day(3)),
        .init(card: "Big Spender", app: "Gnosis Pay", usd: 400, at: day(20, month: 9)),
        .init(card: "Apple Card", app: "Apple Wallet", usd: 50, at: day(5)),
        .init(card: "Apple Card", app: "Apple Wallet", usd: -20, at: day(6)),
        .init(card: "Small", app: "MetaMask Card", usd: 10, at: day(7)),
    ],
    owed: [.init(card: "Apple Card", app: "Apple Wallet", amount: 412, currency: "USD", due: day(24))],
    offers: [
        .init(card: "Amex Gold", app: "CardPointers", expires: day(19)),
        .init(card: "Amex Gold", app: "CardPointers", expires: nil),
        .init(card: "Stale", app: "CardPointers", expires: day(1)),
    ],
    now: now, calendar: cal)

check(roll.map(\.name) == ["Amex Gold", "Apple Card", "Big Spender", "Small"],
      "what asks soonest leads, then the most spent — got \(roll.map(\.name))")
let apple = roll.first { $0.name == "Apple Card" }
check(apple?.spent == 30, "a refund nets against the month")
check(apple?.purchases == 1, "a refund is not a purchase")
check(apple?.owed == 412 && apple?.due == day(24), "the issuer's owed and due are kept")
let big = roll.first { $0.name == "Big Spender" }
check(big?.spent == 900 && big?.purchases == 1, "last month is not this month")
check(big?.lastSpend == day(3), "the newest purchase is kept whatever the month")
let amex = roll.first { $0.name == "Amex Gold" }
check(amex?.offers == 2 && amex?.offerEnds == day(19), "offers count, the first end is the soonest")
check(!roll.contains { $0.name == "Stale" }, "an offer past its end is not offered")
check(WalletCardRoll.compose(spends: [], owed: [], offers: [], now: now, calendar: cal).isEmpty,
      "no card, no list")
if failures > 0 { print("\(failures) assertion(s) failed"); exit(1) }
print("  ok   order, month, refunds, owed, offers")
SWIFT

xcrun swiftc -O "$SRC" "$work/main.swift" -o "$work/t" 2>&1 | grep -v "^$" || true
[[ -x "$work/t" ]] || fail "the shipped source did not compile"
"$work/t" || fail "assertions failed against the shipped source"

# Mutations: each must turn the run red.
mutate() {
  local why="$1" expr="$2"
  cp "$SRC" "$work/m.swift"
  perl -0pi -e "$expr" "$work/m.swift"
  cmp -s "$SRC" "$work/m.swift" && fail "mutation matched nothing: $why"
  xcrun swiftc -O "$work/m.swift" "$work/main.swift" -o "$work/m" >/dev/null 2>&1 || fail "mutation did not compile: $why"
  if "$work/m" >/dev/null 2>&1; then fail "mutation SURVIVED — $why"; fi
  print "  ok   catches  $why"
}
mutate "the most spent leads over what asks" 's/case \(_\?, nil\): return true/case (_?, nil): return false/'
mutate "every month counts" 's/if let month, spend\.at >= month\.start, spend\.at <= now \{/if true {/'
mutate "a refund counts as a purchase" 's/if spend\.usd > 0 \{ c\.purchases \+= 1 \}/c.purchases += 1/'
mutate "a past offer is offered" 's/if let ends = offer\.expires, ends < now \{ continue \}//'

echo "✓ wallet card roll: order, month, refunds, owed, offers, 4 mutations"
