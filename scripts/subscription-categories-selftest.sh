#!/bin/zsh
# Subscriptions by category (the Wallet's Subscriptions tile, prd §1112),
# compiled AS SHIPPED.
#
# `Model/SubscriptionCategories.swift`, the `Subscriptions.swift` whose items
# it reads (with the `AppleWalletRoom.swift` and `RoomLede.swift` that one
# needs) are Foundation-only and compile WHOLE. The treemap's layout,
# `HoldingsTreemapLayout`, is lifted out of `Design/HoldingsTreemap.swift` as
# shipped (the file's View half imports SwiftUI; the enum itself is pure), so
# the fold this map shares with Holdings is the real one.
#
# Every failure it catches renders as an ordinary-looking map:
#
#   • a "Wallet" tile, because the catalogue's fallback was drawn under its
#     Addresses name — the money goes to money
#   • TWO Other tiles, the fallback's and the layout's fold side by side
#   • a bill with no known cadence counted in the total at its price
#   • a one-tile map drawn, which states nothing (§83)
#   • a pressed Other that totals the fallback and forgets the folded tail,
#     so its number disagrees with its own percentage
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Casberi/Casberi/Model/SubscriptionCategories.swift"
SUBS="Casberi/Casberi/Model/Subscriptions.swift"
AWR="Casberi/Casberi/Model/AppleWalletRoom.swift"
LEDE="Casberi/Casberi/Model/RoomLede.swift"
TREEMAP="Casberi/Casberi/Design/HoldingsTreemap.swift"
SCREEN="Casberi/Casberi/Screens/FeedScreen+Subscriptions.swift"
VERIFY="scripts/verify.sh"
for f in "$SRC" "$SUBS" "$AWR" "$LEDE" "$TREEMAP" "$SCREEN"; do
  [[ -f "$f" ]] || { print -u2 "✗ $f not found"; exit 1; }
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { print -u2 "✗ $1"; exit 1; }

# The layout enum, as shipped: from its declaration to its closing brace.
{ print "import Foundation\nimport CoreGraphics"; awk '/^enum HoldingsTreemapLayout \{/{p=1} p{print} p&&/^\}/{exit}' "$TREEMAP"; } \
  > "$work/Layout.swift"
grep -q "static func layout" "$work/Layout.swift" || fail "drift: HoldingsTreemapLayout could not be lifted out of $TREEMAP"

cat > "$work/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { print("  ✗ \(what)"); failures += 1 }
}

func item(_ name: String, _ amount: Double?, cadence: Int? = 30, currency: String = "USD") -> Subscriptions.Item {
    Subscriptions.Item(id: name.lowercased(), name: name, amount: amount, currency: currency,
                       cadenceDays: cadence, next: nil, paysWith: nil, since: nil, paid: nil,
                       was: nil, site: nil, manualID: nil, foundIn: ["Apple Wallet"])
}
// The catalogue, as `BillersSource.category(ofMerchant:)` answers it.
let catalogue = ["Claude": "Agents", "Cursor": "Agents", "Linear": "Work", "Notion": "Work",
                 "Spotify": "Media", "Strava": "Life"]
let category: (String) -> String = { catalogue[$0] ?? "Wallet" }
let usd: (Double, String) -> Double? = { a, c in c == "USD" ? a : nil }
func read(_ items: [Subscriptions.Item]) -> SubscriptionCategories.Reading {
    SubscriptionCategories.read(items, usd: usd, category: category, fallback: "Wallet")
}
let rect = CGRect(x: 0, y: 0, width: 343, height: 200)
func tiles(_ r: SubscriptionCategories.Reading) -> [HoldingsTreemapLayout.Tile] {
    HoldingsTreemapLayout.layout(r.slices.map { (id: $0.key, share: $0.share) },
                                 in: rect, gap: 4, minSide: 44)
}
let other = SubscriptionCategories.otherKey
check(other == HoldingsTreemapLayout.otherID,
      "the map's Other key is the layout's fold key, so the two are one tile")

// The fallback reads as Other, never Wallet.
let r1 = read([item("Claude", 20), item("Netflix", 12.99), item("Apple", 2.99)])
check(!r1.slices.contains { $0.key == "Wallet" }, "the catalogue's fallback never draws a Wallet tile")
check(r1.slices.first { $0.key == other }.map { abs($0.monthly - 15.98) < 0.001 && $0.count == 2 } ?? false,
      "every unknown merchant lands in Other, summed")
check(r1.slices.map(\.key) == ["Agents", other], "most a month first")
check(abs(r1.monthly - 35.98) < 0.001 && r1.counted == 3, "the total is every counted monthly")

// The layout's fold and the fallback are ONE Other tile.
let r2 = read([item("Claude", 20), item("Cursor", 20), item("Linear", 30),
               item("Netflix", 18), item("Spotify", 1), item("Strava", 1)])   // Media, Life: 1% each
let t2 = tiles(r2)
check(t2.filter { $0.id == other }.count == 1, "the fallback and the folded tail draw one Other tile")
check(!t2.contains { $0.id == "Media" || $0.id == "Life" }, "a sliver folds")
let otherTile = t2.first { $0.id == other }
check(otherTile.map { abs($0.share - 20.0 / 90.0) < 0.0001 } ?? false,
      "Other's label is the fallback plus the folded tail")
let drawn2 = t2.map(\.id)
check(SubscriptionCategories.members(of: other, drawn: drawn2, slices: r2.slices) == [other, "Media", "Life"],
      "a pressed Other stands for the fallback and every folded category")
let p2 = SubscriptionCategories.picked(other, drawn: drawn2, reading: r2)
check(abs(p2.monthly - 20) < 0.001 && p2.counted == 3, "a pressed Other totals what its label counts")
check(SubscriptionCategories.items([item("Netflix", 18), item("Spotify", 1), item("Claude", 20)], in: other,
                                   drawn: drawn2, slices: r2.slices, category: category, fallback: "Wallet")
          .map(\.name) == ["Netflix", "Spotify"], "a pressed Other lists the fallback's rows and the folded ones")

// Only a monthly cost counts; the rest stays in the list.
let gym = item("Gym", 40, cadence: nil)                 // a bill: no known cadence
let euro = item("Notion", 10, currency: "EUR")          // no rate
let r3 = read([item("Claude", 20), item("Linear", 10), gym, euro])
check(r3.counted == 2 && abs(r3.monthly - 30) < 0.001, "no cadence or no rate: out of the total")
check(!r3.slices.contains { $0.key == other } && r3.slices.count == 2, "and out of the map")
check(SubscriptionCategories.items([item("Claude", 20), gym], in: nil, drawn: [], slices: r3.slices,
                                   category: category, fallback: "Wallet").count == 2,
      "unpicked, every row stands, a monthly cost or not")

// A one-tile map says nothing.
let r4 = read([item("Netflix", 12.99), item("Apple", 2.99)])
check(r4.slices.count == 1 && !SubscriptionCategories.drawsMap(tiles: tiles(r4).count),
      "every merchant unknown: one tile, no map")
let r5 = read([item("Netflix", 98), item("Claude", 2)])   // Agents at 2% folds into Other
check(!SubscriptionCategories.drawsMap(tiles: tiles(r5).count), "everything folded into Other: no map")
check(SubscriptionCategories.drawsMap(tiles: tiles(r1).count), "two categories: a map")
check(read([]) == .empty, "none: nothing to draw")

// The filter's sum.
let r6 = read([item("Claude", 20), item("Cursor", 20), item("Linear", 10), item("Netflix", 15)])
let d6 = tiles(r6).map(\.id)
let p6 = SubscriptionCategories.picked("Agents", drawn: d6, reading: r6)
check(abs(p6.monthly - 40) < 0.001 && p6.counted == 2, "a pressed category totals its own")
check(SubscriptionCategories.items([item("Claude", 20), item("Linear", 10), item("Cursor", 20)], in: "Agents",
                                   drawn: d6, slices: r6.slices, category: category, fallback: "Wallet")
          .map(\.name) == ["Claude", "Cursor"], "and lists only its own rows, in order")

// A pick is keyed on the set it was made over.
check(SubscriptionCategories.signature([item("Claude", 20), item("Linear", 10)])
          == SubscriptionCategories.signature([item("Linear", 12), item("Claude", 20)]),
      "the same subscriptions in another order or price keep the pick")
check(SubscriptionCategories.signature([item("Claude", 20)])
          != SubscriptionCategories.signature([item("Claude", 20), item("Linear", 10)]),
      "a different set clears it")

if failures > 0 { print("\(failures) assertion(s) failed"); exit(1) }
print("  ok   fallback, fold merge, monthly only, the two-tile floor, the filter")
SWIFT

build() { swiftc -Onone -o "$work/run" "$SUBS" "$AWR" "$LEDE" "$work/Layout.swift" "$1" "$work/main.swift" 2>"$work/err" || return 1 }

cp "$SRC" "$work/SubscriptionCategories.swift"
build "$work/SubscriptionCategories.swift" || { cat "$work/err"; fail "the shipped source does not compile"; }
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

mutate "the fallback drawn as Wallet" \
  's/return c == fallback \? otherKey : c/return c/'
mutate "a price with no cadence counted" \
  's/guard let monthly = item\.monthly, let dollars = usd\(monthly, item\.currency\) else \{ continue \}/guard let dollars = usd(item.monthly ?? item.amount ?? 0, item.currency) else { continue }/'
mutate "a pressed Other forgets the folded tail" \
  's/\$0 == otherKey \|\| !shown\.contains\(\$0\)/\$0 == otherKey/'
mutate "a one-tile map drawn" \
  's/static let minTiles = 2/static let minTiles = 1/'
mutate "a pressed tile totals everything" \
  's/let mine = reading\.slices\.filter \{ keys\.contains\(\$0\.key\) \}/let mine = reading.slices/'

# Wiring: the screen reads through this file and the shared layout.
grep -q "SubscriptionCategories.read(" "$SCREEN" || fail "drift: the Subscriptions tile no longer reads SubscriptionCategories"
grep -q "fallback: BillersSource.fallbackCategory" "$SCREEN" \
  || fail "drift: the map no longer maps the catalogue's fallback to Other"
grep -q "HoldingsTreemapLayout.layout(" "$SCREEN" || fail "drift: the map no longer lays out through HoldingsTreemapLayout"
grep -q "subscription-categories-selftest.sh" "$VERIFY" \
  || fail "not wired into verify.sh — the completeness guard requires it, with its reason"

echo "✓ subscription categories: fallback, fold merge, monthly only, two-tile floor, filter, 5 mutations"
