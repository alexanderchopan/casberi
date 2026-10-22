#!/bin/zsh
# The Wallet's Spending (prd §1201, §1330), compiled AS SHIPPED.
#
# `Model/Spending.swift` is Foundation-only, so this compiles it WHOLE. What it
# guards renders as an ordinary list of places with a plausible total: a swap,
# a bridge, a deposit into a protocol, or a wallet the person stopped following
# counted as money spent. The user's Wallet read ~$10,000 of somebody else's
# swaps as their spending; none of that fails a build or a screenshot.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Casberi/Casberi/Model/Spending.swift"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { print -u2 "✗ $1"; exit 1; }

cat > "$work/main.swift" <<'SWIFT'
import Foundation
var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { print("  ✗ \(what)"); failures += 1 }
}
let t0 = Date(timeIntervalSince1970: 1_791_000_000)
func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

let mine = "0xaaaa000000000000000000000000000000000001"
let savings = "0xaaaa000000000000000000000000000000000002"
let unfollowed = "0xd8da6bf26964af9d7eed9e03e53415d37aa96045"
let own: Set<String> = [mine, savings]

typealias M = Spending.Move
func send(_ tx: String, _ usd: Double, at m: Double, to: String = "0xfeed", wallet: String = mine,
          operation: String? = nil, machinery: Bool = false, place: String? = "Somewhere") -> M {
    M(wallet: wallet, tx: tx, way: .sent, usd: usd, at: at(m), counterparty: to,
      operation: operation, machinery: machinery, place: place)
}
func receipt(_ tx: String, _ usd: Double?, at m: Double, from: String = "0xbeef", wallet: String = mine) -> M {
    M(wallet: wallet, tx: tx, way: .received, usd: usd, at: at(m), counterparty: from)
}

func spent(_ moves: [M]) -> [String] { Spending.walletSpends(moves, own: own).map(\.tx) }

// The plain case still counts: a send to a person and to an exchange.
check(spent([send("a", 477, at: 0), send("b", 500, at: 10, to: "0xcoinbase")]) == ["a", "b"],
      "a send to a person or an exchange is spending")

// A same-symbol swap never folds into a swap row: both legs land, one transaction.
check(spent([send("sw", 5_000, at: 0, to: "0xrouter"), receipt("sw", 4_998, at: 0, from: "0xrouter")]).isEmpty,
      "a send in a transaction that paid you back is a trade, not spending")
// The other leg landed in a later pass, or as a folded swap row.
check(spent([send("sw", 5_000, at: 0), M(wallet: mine, tx: "sw", way: .swap, usd: nil, at: at(0))]).isEmpty,
      "a send whose transaction is a swap row is a trade")
// A trade the read classified, whose other leg never landed (a cross-chain
// swap's source, a token sold for ETH an L2 read never returned).
check(spent([send("t", 2_500, at: 0, operation: "trade")]).isEmpty,
      "a send the read called a trade is not spending")
check(spent([send("d", 1_000, at: 0, operation: "deposit")]).isEmpty,
      "a deposit into a protocol is not spending")
check(spent([send("e", 300, at: 0, operation: "execute")]).isEmpty,
      "a contract call is not spending")
check(spent([send("s", 40, at: 0, operation: "send")]) == ["s"],
      "a plain send the read classified still counts")
// A bridge or a cross-chain swap: money back within minutes, worth the same.
check(spent([send("x1", 3_000, at: 0), receipt("x2", 2_985, at: 3)]).isEmpty,
      "a send answered by a matching arrival minutes later is a round trip")
check(spent([send("x1", 3_000, at: 0), receipt("x2", 2_985, at: 90)]) == ["x1"],
      "an arrival hours later answers nothing")
check(spent([send("x1", 3_000, at: 0), receipt("x2", 1_000, at: 3)]) == ["x1"],
      "an arrival worth a third answers nothing")
check(spent([send("x1", 3_000, at: 0), send("x3", 3_000, at: 1), receipt("x2", 3_000, at: 3)]).count == 1,
      "one arrival answers one send")
check(spent([send("x1", 3_000, at: 0), receipt("x2", 3_000, at: 3, from: savings)]) == ["x1"],
      "a move in from your own wallet is not money coming back")
check(spent([send("x1", 3_000, at: 0), receipt("x2", nil, at: 3)]) == ["x1"],
      "an unpriced arrival answers nothing")

// A wallet the person no longer follows (prd §1330).
check(spent([send("v", 10_000, at: 0, wallet: unfollowed)]).isEmpty,
      "a send from a wallet you do not follow is not your spending")
check(spent([send("v", 3_000, at: 0), receipt("w", 3_000, at: 2, wallet: unfollowed)]) == ["v"],
      "money into a wallet you do not follow answers nothing")

// The rules that stood before.
check(spent([send("o", 1_590, at: 0, to: savings)]).isEmpty, "a move between your own wallets")
check(spent([send("m", 1_200, at: 0, machinery: true)]).isEmpty, "a send to a known router or a Safe")
check(spent([send("n", 0, at: 0)]).isEmpty, "an unpriced send")
check(spent([send("p", 12, at: 0, place: nil)]).isEmpty, "a send with no place to name")

// ── The tile's reading (prd §1468): a window, the recurring half, each
// place against the last window. ──────────────────────────────────────────
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "UTC")!
// Thursday 2026-10-22 12:00 UTC.
let now = Date(timeIntervalSince1970: 1_792_670_400)
func day(_ n: Double) -> Date { now.addingTimeInterval(-n * 86_400) }
typealias C = Spending.Charge
let charges = [
    C(place: "Uber", usd: 48, at: day(1)),      C(place: "Uber", usd: 30, at: day(2)),
    C(place: "Spotify", usd: 12, at: day(3)),
    C(place: "Amazon", usd: 100, at: day(5)),
    // Last month, before this day of it (Sep 22 12:00 and earlier) and after.
    C(place: "Uber", usd: 20, at: day(32)),     C(place: "Spotify", usd: 12, at: day(33)),
    C(place: "Amazon", usd: 10, at: day(40)),   // Sep 12: in last month to this day
    C(place: "Whole Foods", usd: 70, at: day(25)), // Sep 27: last month, AFTER this day — not counted
    // Last week to this point: Thu Oct 15 12:00 and earlier, from Mon Oct 12.
    C(place: "Uber", usd: 10, at: day(8)),      // Oct 14: last week
    C(place: "Amazon", usd: 5, at: day(6.5)),   // Oct 16 00:00: last week, after this point
]
let isPlan: (String) -> Bool = { $0.lowercased() == "spotify" }

let month = Spending.read(charges, now: now, calendar: cal, window: .month, isRecurring: isPlan)
// This month: Uber 48 + 30 + 10, Spotify 12, Amazon 100 + 5.
check(month.total == 205, "the month's total is every place (\(month.total))")
check(month.recurring == 12, "the recurring half is what the caller believes recurs (\(month.recurring))")
check(month.rest == 193, "the rest is the remainder (\(month.rest))")
// Last month to this day (Sep 1–22 12:00): Uber 20 + Spotify 12 + Amazon 10 = 42; Whole Foods on Sep 27 is after it.
check(month.earlier == 42, "last month to the same day, not last month whole (\(String(describing: month.earlier)))")
check(month.earlierRecurring == 12, "the recurring half is told apart last month too")
check(month.earlierRest == 30, "the rest last month")
check(month.places.first?.name == "Amazon", "largest first")
let uber = month.places.first { $0.name == "Uber" }
check(uber?.earlier == 20, "a place carries its own last-month figure (\(String(describing: uber?.earlier)))")
check(uber?.recurring == false, "a shop is not recurring")
// **TWO GROUPS (prd §1469):** a plan stands in Subscriptions, never in
// Places, and each box row is its group's sum.
check(month.subscriptions.map(\.name) == ["Spotify"], "a plan stands in the Subscriptions group")
check(month.places.first { $0.name == "Spotify" } == nil, "a plan is never also a place")
check(month.recurring == month.subscriptions.reduce(0) { $0 + $1.usd }, "Recurring is the Subscriptions group's sum")
check(month.rest == month.places.reduce(0) { $0 + $1.usd }, "The rest is the Places group's sum")
check(month.total == month.recurring + month.rest, "the total is both groups")
check(month.places.first { $0.name == "Amazon" }?.earlier == 10, "Amazon's Sep 12 charge is in last month to this day")

let week = Spending.read(charges, now: now, calendar: cal, window: .week, isRecurring: isPlan)
// This week from Mon Oct 19: Uber 48 + 30, Spotify 12 (Oct 19 12:00).
check(week.total == 90, "the week runs from the calendar's week start (\(week.total))")
// Last week to this point (Mon Oct 12 → Thu Oct 15 12:00): Uber 10 only;
// Amazon's Oct 16 charge is after this point.
check(week.earlier == 10, "last week to the same point (\(String(describing: week.earlier)))")
check(week.places.first { $0.name == "Uber" }?.earlier == 10, "a place against last week")
check(week.places.first { $0.name == "Amazon" } == nil, "a place with nothing this week is not listed")

// A subscription says its newest charge and what paid it.
let paid = Spending.read([C(place: "Netflix", usd: 13, at: day(8), via: "Apple Card"),
                          C(place: "Netflix", usd: 13, at: day(1), via: "Apple Card"),
                          C(place: "iCloud+", usd: 3, at: day(2), via: "You")],
                         now: now, calendar: cal, window: .month, isRecurring: { _ in true })
check(paid.subscriptions.first?.name == "Netflix" && paid.subscriptions.first?.lastAt == day(1),
      "subscriptions are newest charge first, carrying its day")
check(paid.subscriptions.first?.via == "Apple Card", "a subscription carries what paid it")

let plain = Spending.read(charges, now: now, calendar: cal)
check(plain.recurring == 0 && plain.places.allSatisfy { !$0.recurring }, "Home's reading believes nothing recurs")
check(plain.total == month.total && plain.earlier == month.earlier, "Home's reading is the month, unchanged (§1201)")

if failures > 0 { print("\(failures) assertion(s) failed"); exit(1) }
print("  ok   swaps, trades, deposits, round trips, unfollowed wallets, own moves, the window and the recurring half")
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
mutate "a trade's send counts"            's/if paidBack\.contains\(send\.tx\) \{ continue \}//'
mutate "the read's classification ignored" 's/if let op = send\.operation, op != "send" \{ continue \}//'
mutate "a round trip counts"              's/arrivals\.remove\(at: i\)\n                continue/arrivals.remove(at: i)/'
mutate "an unfollowed wallet counts"      's/guard own\.contains\(send\.wallet\) else \{ continue \}//'
mutate "own moves count"                  's/if let to = send\.counterparty, own\.contains\(to\) \{ continue \}//'
mutate "one arrival answers every send"   's/arrivals\.remove\(at: i\)//'
mutate "the recurring half never told apart"   's/p\.recurring = isRecurring\(place\.name\)/p.recurring = false/'
mutate "a week reads as a month"              's/case \.week:\n            guard let week = calendar\.dateInterval\(of: \.weekOfYear, for: now\)/case .week:\n            guard let week = calendar.dateInterval(of: .month, for: now)/'
mutate "last window whole, not to this point" 's/let lastEnd = calendar\.date\(byAdding: \.month, value: -1, to: now\) \?\? month\.start/let lastEnd = month.start.addingTimeInterval(-1)/'
mutate "a place forgets its last-window figure" 's/p\.earlier = earlierUSD\.map \{ max\(0, \$0\) \}/p.earlier = nil/'
mutate "a plan also stands in Places"          's/if p\.recurring \{ subscriptions\.append\(p\) \} else \{ places\.append\(p\) \}/places.append(p); if p.recurring { subscriptions.append(p) }/'
mutate "a subscription names its oldest charge" 's/charge\.at > \(place\.lastAt \?\? \.distantPast\)/charge.at < (place.lastAt ?? .distantFuture)/'
