#!/bin/zsh
# The Wallet's Subscriptions tile (prd §1105), compiled AS SHIPPED.
#
# `Model/Subscriptions.swift`, the `AppleWalletRoom.swift` it reads and the
# `RoomLede.swift` that one needs are Foundation-only, so this compiles them
# WHOLE — no stubs, no copied logic.
# Every failure it catches renders as an ordinary list of subscriptions:
#
#   • groceries, rides or a weekly coffee listed as something you subscribe to
#     (measured on the demo: Uber, with a "price rise")
#   • a plan you cancelled still listed, and still in the monthly total
#   • $20.29 a month for a $20 plan, from a cadence divided by 30.4375
#   • a bill or a hand-added plan counted twice when a card also shows it
#   • a price typed by hand overriding the charge the card actually saw
#   • a euro plan counted at par in a dollar total
#
# None of that fails a build or a screen sweep: the demo's numbers would just
# be wrong in a way nobody re-adds by hand.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Casberi/Casberi/Model/Subscriptions.swift"
AWR="Casberi/Casberi/Model/AppleWalletRoom.swift"
LEDE="Casberi/Casberi/Model/RoomLede.swift"   # AppleWalletRoom.lede returns one
VERIFY="scripts/verify.sh"

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
let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 12))!
func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }
typealias Spend = AppleWalletRoom.Spend

func series(_ merchant: String, _ charges: [(Double, Double)], currency: String = "USD") -> AppleWalletRoom.Series? {
    let spends = charges.map { Spend(merchant: merchant, amount: $0.0, currency: currency, date: ago($0.1)) }
    return AppleWalletRoom.recurringSeries(spends, now: now).first
}
func found(_ s: AppleWalletRoom.Series?, was: Double? = nil) -> [Subscriptions.Found] {
    guard let s else { return [] }
    return [.init(series: s, paysWith: "Apple Card", source: "Apple Wallet", was: was)]
}
func compose(_ f: [Subscriptions.Found], bills: [Subscriptions.Bill] = [],
             manual: [Subscriptions.Manual] = []) -> [Subscriptions.Item] {
    Subscriptions.compose(found: f, bills: bills, manual: manual, now: now, calendar: cal)
}

// A plan: one price, a month apart.
let claude = series("Claude", [(20, 66), (20, 36), (20, 6)])
let items1 = compose(found(claude))
check(items1.count == 1 && items1[0].name == "Claude", "a steady monthly charge is a subscription")
check(items1.first?.monthly == 20, "a monthly plan costs its price a month, not price × 30.4375 / 30")
check(items1.first?.next.map { abs($0.timeIntervalSince(ago(-24))) < 86_400 } ?? false,
      "the next renewal is the last charge plus the cadence")
check(items1.first?.paid == 60 && items1.first?.since == ago(66), "paid so far and since read the charges")

// Shopping recurs and is not a subscription.
check(compose(found(series("Whole Foods", [(84.20, 62), (61.05, 32), (73.40, 2)]))).isEmpty,
      "a monthly bill whose amount moves every time is not a subscription")
check(compose(found(series("Blue Bottle", [(6.50, 21), (6.50, 14), (6.50, 7), (6.50, 0.5)]))).isEmpty,
      "a weekly charge at one price is not a subscription (the cadence floor)")

// A rise on the latest charge is the same plan, wearing the word.
let notion = series("Notion", [(10, 70), (10, 40), (12, 10)])
let items2 = compose(found(notion, was: 10))
check(items2.count == 1 && items2.first?.was == 10 && items2.first?.amount == 12,
      "a price rise on the latest charge keeps the plan and says what it was")

// A plan that stopped is not listed.
check(compose(found(series("Hulu", [(8, 160), (8, 130), (8, 100)]))).isEmpty,
      "a charge that stopped is not a subscription any more")

// A bill merges with the card's charge by name, once.
let bill = Subscriptions.Bill(name: "CLAUDE", amount: 20, currency: "USD", due: ago(-20), source: "Rocket Money")
let items3 = compose(found(claude), bills: [bill])
check(items3.count == 1 && items3.first?.foundIn == ["Apple Wallet", "Rocket Money"],
      "a bill and a card charge for one plan are one subscription, found twice")

// A bill alone has no known cadence: listed, never totalled.
let gym = Subscriptions.Bill(name: "Gym", amount: 40, currency: "USD", due: ago(-3), source: "Rocket Money")
let items4 = compose([], bills: [gym])
check(items4.first?.cadenceDays == nil && items4.first?.monthly == nil, "a bill's frequency is never guessed")
let total4 = Subscriptions.total(items4) { a, c in c == "USD" ? a : nil }
check(total4.counted == 0 && total4.uncounted == ["Gym"], "a bill with no cadence is named, not counted")

// The hand adds what a reading lacks; the reading wins on the charge itself.
let typed = Subscriptions.Manual(id: "claude", name: "Claude", amount: 25, currency: "USD", yearly: false,
                                 anchor: ago(-3), paysWith: "Visa", site: "claude.ai", at: now)
let items5 = compose(found(claude), manual: [typed])
check(items5.count == 1 && items5.first?.amount == 20, "a typed price never overrides the charge the card saw")
check(items5.first?.site == "claude.ai" && items5.first?.manualID == "claude",
      "the hand-added entry contributes its site and can be removed")
check(items5.first?.paysWith == "Apple Card", "what the card saw pays it, not what was typed")

// A yearly plan typed by hand: a twelfth a month, the renewal rolled forward.
let yearly = Subscriptions.Manual(id: "1password", name: "1Password", amount: 36, currency: "USD", yearly: true,
                                  anchor: cal.date(from: DateComponents(year: 2025, month: 2, day: 2))!,
                                  paysWith: nil, site: nil, at: now)
let items6 = compose([], manual: [yearly])
check(items6.first?.monthly == 3, "a yearly plan costs a twelfth a month")
check(items6.first?.next == cal.date(from: DateComponents(year: 2027, month: 2, day: 2)),
      "a past renewal rolls forward by whole years")
check(Subscriptions.nextRenewal(anchor: cal.date(from: DateComponents(year: 2026, month: 1, day: 31))!,
                                yearly: false, now: cal.date(from: DateComponents(year: 2026, month: 3, day: 5))!,
                                calendar: cal) == cal.date(from: DateComponents(year: 2026, month: 3, day: 31)),
      "a monthly renewal steps from its anchor, so the 31st does not drift to the 28th")

// Order: most a month first; unknown cadence last.
let items7 = compose(found(claude) + found(notion, was: 10), bills: [gym], manual: [yearly])
check(items7.map(\.name) == ["Claude", "Notion", "1Password", "Gym"], "most expensive a month first, unknown last")

// The total: dollars summed, another currency only at a rate.
let euro = series("Spotify", [(10.99, 66), (10.99, 36), (10.99, 6)], currency: "EUR")
let items8 = compose(found(claude) + found(euro))
check(Subscriptions.total(items8) { a, c in c == "USD" ? a : nil }.uncounted == ["Spotify"],
      "a currency with no rate is named, never counted at par")
check(abs(Subscriptions.total(items8) { a, c in c == "USD" ? a : (c == "EUR" ? a * 1.1 : nil) }.monthly
          - (20 + 10.99 * 1.1)) < 0.001, "with a rate it converts")

if failures > 0 { print("\(failures) assertion(s) failed"); exit(1) }
print("  ok   detection, merge, cadence, renewals, order, total")
SWIFT

build() { swiftc -Onone -o "$work/run" "$AWR" "$LEDE" "$1" "$work/main.swift" 2>"$work/err" || return 1 }

cp "$SRC" "$work/Subscriptions.swift"
build "$work/Subscriptions.swift" || { cat "$work/err"; fail "the shipped source does not compile"; }
"$work/run" || fail "assertions failed against the shipped source"

mutate() {
  local why="$1" expr="$2"
  cp "$SRC" "$work/m.swift"
  perl -0pi -e "$expr" "$work/m.swift"
  cmp -s "$SRC" "$work/m.swift" && fail "mutation matched nothing: $why"
  if build "$work/m.swift" && "$work/run" >/dev/null 2>&1; then
    fail "mutation SURVIVED — $why"
  fi
  echo "  ok   catches  $why"
}

mutate "a weekly charge believed (the cadence floor dropped)" \
  's/guard series\.cadenceDays >= minCadenceDays else \{ return false \}//'
mutate "a bill that moves believed (the one-price rule dropped)" \
  's/return earlier\.allSatisfy \{ abs\(\$0 - median\) <= median \* steadyTolerance \}/return true/'
mutate "a stopped plan still listed" \
  's/guard believes\(f\.series\), !stopped\.contains\(k\) else/guard believes(f.series) else/'
mutate "a monthly plan costs price × 30.4375 / 30" \
  's/if Subscriptions\.monthlyDays\.contains\(days\) \{ return amount \}//'
mutate "a typed price overrides the charge" \
  's/if standing\.amount == nil \{ standing\.amount = m\.amount \}/standing.amount = m.amount/'
mutate "a currency with no rate counted at par" \
  's/guard let monthly = item\.monthly, let dollars = usd\(monthly, item\.currency\) else \{/guard let monthly = item.monthly else { uncounted.append(item.name); continue }\n            let dollars = usd(monthly, item.currency) ?? monthly\n            if false {/'
mutate "a bill and a charge for one plan listed twice" \
  's/if var standing = byKey\[k\] \{\n                if !standing\.foundIn\.contains\(bill\.source\)/if false, var standing = byKey[k] {\n                if !standing.foundIn.contains(bill.source)/'

# Wiring: the reading feeds this function, the tile reads the reading.
grep -q "Subscriptions.compose(found: found, bills: bills" Casberi/Casberi/Model/SubscriptionsSource.swift \
  || fail "drift: SubscriptionsReading no longer composes through Subscriptions.compose"
grep -q "subscriptions-selftest.sh" "$VERIFY" \
  || fail "not wired into verify.sh — the completeness guard requires it, with its reason"

echo "✓ subscriptions: detection, merge, cadence, renewals, order, total, 7 mutations"
