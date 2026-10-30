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
// The running line (prd §1480 item 14): Mon Oct 19 → Thu Oct 22, one point a day.
check(week.running == [12, 42, 90, 90], "the running line adds each day's charges (\(week.running))")
check(month.running.count == 22 && month.running.last == month.total, "the month's line ends on its total")

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

// ── Fees (prd §1476): gas on what your wallets sent, one per transaction. ──
func gas(_ tx: String, _ fee: Double?, at m: Double, way: M.Way = .sent, wallet: String = mine, net: String = "Base") -> M {
    M(wallet: wallet, tx: tx, way: way, usd: 100, at: at(m), counterparty: "0xfeed", place: "Somewhere",
      feeUSD: fee, network: fee == nil ? nil : net)
}
let fees = Spending.walletFees([gas("f1", 0.10, at: 0), gas("f1", 0.10, at: 0), gas("f2", 0.25, at: 1, net: "Ethereum"),
                                gas("f3", 0.05, at: 2, wallet: unfollowed), gas("f4", nil, at: 3),
                                gas("f5", 0.02, at: 4, way: .swap)], own: own)
check(fees.map(\.tx) == ["f1", "f2", "f5"], "one fee per transaction; an unfollowed wallet's and an unpriced one are left out (\(fees.map(\.tx)))")
check(fees.first?.usd == 0.10, "two legs of one transaction pay its gas once")
let feeRows = Spending.read([], now: now, calendar: cal, window: .month,
                            fees: [Spending.Fee(tx: "a", network: "Base", usd: 0.30, at: day(1)),
                                   Spending.Fee(tx: "b", network: "Base", usd: 0.10, at: day(2)),
                                   Spending.Fee(tx: "c", network: "Ethereum", usd: 3.00, at: day(3)),
                                   Spending.Fee(tx: "d", network: "Base", usd: 0.50, at: day(35))],
                            unpricedSends: [day(10)])
check(feeRows.fees.map(\.name) == ["Ethereum", "Base"], "fees stand by network, largest first (\(feeRows.fees.map(\.name)))")
check(feeRows.fees.last?.count == 2 && abs((feeRows.fees.last?.usd ?? 0) - 0.40) < 1e-9, "a network's row counts its transactions and adds their gas")
check(feeRows.fees.last?.earlier == 0.50, "a network carries last window's gas")
check(abs(feeRows.feesTotal - 3.40) < 1e-9 && feeRows.earlierFees == 0.50, "the box's Fees row is the window's sum, against the last")
check(feeRows.total == 0, "fees are never part of the total")
check(feeRows.feesFrom == day(3), "an unpriced send before the first fee makes the row say which day fees start from")
check(Spending.read([], now: now, calendar: cal, fees: [Spending.Fee(tx: "a", network: "Base", usd: 0.30, at: day(1))],
                    unpricedSends: [day(0.5)]).feesFrom == nil, "an unpriced send after the first fee says nothing")

// ── Round-ups (prd §1523): the change a send rounded up, paid to Relay for
// a token you picked. Kept, never spent, and never in the total. ──────────
let eth = Spending.RoundUp.Bought(symbol: "ETH", network: "Base")
func buy(_ tx: String, _ usd: Double?, at m: Double, wallet: String = mine, way: M.Way = .sent) -> M {
    M(wallet: wallet, tx: tx, way: way, usd: usd, at: at(m), counterparty: "0xde90517", place: "Relay", roundUp: eth)
}
check(spent([buy("r1", 5, at: 0), send("s1", 40, at: 1)]) == ["s1"],
      "a round-up's buy is not spending; the send beside it still is")
// The buy rides the send's operation; Relay's fill comes back minutes later
// and is the buy's, never an answer to a $5 send beside it.
check(spent([buy("op", 5, at: 0), send("op", 5, at: 0), receipt("fill", 4.97, at: 1, from: "0x5011e4")]) == ["op"],
      "Relay's fill answers the round-up's buy, not the send it rode with")
// An exchange buy (prd §1545) rides the send in ONE transaction: the token it
// bought comes back in that transaction, stamped, and the read calls the
// whole transaction a trade. The send is still spending.
func fill(_ tx: String, _ usd: Double, at m: Double) -> M {
    M(wallet: mine, tx: tx, way: .received, usd: usd, at: at(m), counterparty: "0x2626664c", roundUp: eth)
}
check(spent([buy("x", 5.20, at: 0), send("x", 4.30, at: 0, operation: "trade"), fill("x", 5.18, at: 0)]) == ["x"],
      "a send riding an exchange round-up read as a trade: the buy's token, or the buy's trade, took it")
check(spent([buy("x", 5, at: 0), fill("x", 5, at: 0), send("z", 5, at: 1)]) == ["z"],
      "an exchange round-up's token answered a $5 send beside it as a round trip")
check(spent([buy("x", 5, at: 0), fill("x", 5, at: 0), send("y", 5, at: 1), receipt("back", 5, at: 2)]).isEmpty,
      "an exchange buy took an arrival its own transaction already answered, so a real round trip counted")
check(spent([buy("x", 5.20, at: 0), send("x", 4.30, at: 0, operation: "trade"), receipt("x", 9, at: 0)]).isEmpty,
      "a transaction that also paid you something other than the round-up's token counted its send")
check(Spending.walletRoundUps([buy("x", 5.20, at: 0), fill("x", 5.18, at: 0)], own: own).map(\.usd) == [5.20],
      "an exchange buy is not one round-up, or its token is counted as one")
let buys = Spending.walletRoundUps([buy("r1", 5, at: 0), buy("r1", 5, at: 0), buy("r2", 5.20, at: 1),
                                    buy("r3", 5, at: 2, wallet: unfollowed), buy("r4", nil, at: 3),
                                    buy("r5", 5, at: 4, way: .received), send("s1", 40, at: 5)], own: own)
check(buys.map(\.tx) == ["r1", "r2"],
      "one buy per transaction; an unfollowed wallet's, an unpriced one, a received leg and a plain send are left out (\(buys.map(\.tx)))")
check(buys.first?.bought == eth, "a buy carries the token it bought and its network")
typealias R = Spending.RoundUp
let roundUpRows = Spending.read([C(place: "Uber", usd: 48, at: day(1))], now: now, calendar: cal, window: .month,
                                roundUps: [R(tx: "a", usd: 5, at: day(4), bought: eth),
                                           R(tx: "b", usd: 5.20, at: day(2), bought: eth),
                                           R(tx: "c", usd: 5, at: day(35), bought: eth)],
                                roundUpsWaiting: 2.60)
check(roundUpRows.roundUps.map(\.tx) == ["b", "a"], "this window's buys, newest first (\(roundUpRows.roundUps.map(\.tx)))")
check(abs(roundUpRows.roundUpsTotal - 10.20) < 1e-9 && roundUpRows.earlierRoundUps == 5,
      "the door's figure is this window's buys, against the last")
check(roundUpRows.total == 48, "round-ups are never part of the total (\(roundUpRows.total))")
check(roundUpRows.roundUpsWaiting == 2.60, "the change still waiting is carried as the caller read it")
check(roundUpRows.roundUpsFrom == nil, "a buy marked last window means this window's count is whole")
check(Spending.read([], now: now, calendar: cal, roundUps: [R(tx: "a", usd: 5, at: day(4), bought: eth)]).roundUpsFrom == day(4),
      "the first buy ever marked, inside this window, is the day the count starts from")

// ── Whose (prd §1524): All adds every account; an account the search tray
// picked reads its own rows alone. ─────────────────────────────────────────
let mineOnly = Spending.Scope.wallet([mine])
let appleOnly = Spending.Scope.app(["Apple Wallet"])
check(Spending.Scope.all.holds(app: nil, wallet: nil), "All holds a plan tracked by hand")
check(mineOnly.holds(app: "Wallet", wallet: mine.uppercased()), "a wallet's page holds its own sends, however spelt")
check(mineOnly.holds(app: "MetaMask Card", wallet: mine), "a wallet's page holds a card read off it")
check(!mineOnly.holds(app: "Wallet", wallet: savings), "a wallet's page never holds another wallet's sends")
check(!mineOnly.holds(app: "Apple Wallet", wallet: nil), "a wallet's page never holds a card no wallet pays")
check(appleOnly.holds(app: "Apple Wallet", wallet: nil), "an app's page holds its own charges")
check(!appleOnly.holds(app: "Privacy", wallet: nil), "an app's page never holds another app's")
check(!appleOnly.holds(app: nil, wallet: nil) && !mineOnly.holds(app: nil, wallet: nil),
      "a plan tracked by hand is no account's: All's only")

if failures > 0 { print("\(failures) assertion(s) failed"); exit(1) }
print("  ok   swaps, trades, deposits, round trips, unfollowed wallets, own moves, the window, the recurring half, fees and round-ups")
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
mutate "the read's classification ignored" 's/if let op = send\.operation, op != "send", !boughtHere\.contains\(send\.tx\) \{ continue \}//'
mutate "an exchange round-up's token reads as paid back" 's/\$0\.way != \.sent && \$0\.roundUp == nil/\$0.way != .sent/'
mutate "an exchange round-up's token answers a send"    's/guard m\.way == \.received, m\.roundUp == nil, own/guard m.way == .received, own/'
mutate "an exchange buy takes another arrival"          's/\n            && !boughtHere\.contains\(buy\.tx\) \{/ {/'
mutate "the buy's trade hides the send it rode with"    's/op != "send", !boughtHere\.contains\(send\.tx\)/op != "send"/'
mutate "a round trip counts"              's/arrivals\.remove\(at: i\)\n                continue/arrivals.remove(at: i)/'
mutate "an unfollowed wallet counts"      's/guard own\.contains\(send\.wallet\) else \{ continue \}//'
mutate "own moves count"                  's/if let to = send\.counterparty, own\.contains\(to\) \{ continue \}//'
mutate "one arrival answers every send"   's/arrivals\.remove\(at: i\)//'
mutate "the recurring half never told apart"   's/p\.recurring = isRecurring\(place\.name\)/p.recurring = false/'
mutate "a week reads as a month"              's/case \.week:\n            guard let week = calendar\.dateInterval\(of: \.weekOfYear, for: now\)/case .week:\n            guard let week = calendar.dateInterval(of: .month, for: now)/'
mutate "last window whole, not to this point" 's/let lastEnd = calendar\.date\(byAdding: \.month, value: -1, to: now\) \?\? month\.start/let lastEnd = month.start.addingTimeInterval(-1)/'
mutate "the running line forgets earlier days"  's/var sum: Double = 0\n        reading\.running = perDay\.map \{ sum \+= \$0; return sum \}/reading.running = perDay/'
mutate "a place forgets its last-window figure" 's/p\.earlier = earlierUSD\.map \{ max\(0, \$0\) \}/p.earlier = nil/'
mutate "a plan also stands in Places"          's/if p\.recurring \{ subscriptions\.append\(p\) \} else \{ places\.append\(p\) \}/places.append(p); if p.recurring { subscriptions.append(p) }/'
mutate "a subscription names its oldest charge" 's/charge\.at > \(place\.lastAt \?\? \.distantPast\)/charge.at < (place.lastAt ?? .distantFuture)/'
mutate "a transaction's gas counted once per leg"   's/seen\.insert\(m\.tx\)//'
mutate "an unfollowed wallet's gas counts"           's/for m in moves where own\.contains\(m\.wallet\) \{/for m in moves {/'
mutate "a round-up's buy counts as spending"         's/if send\.roundUp != nil \{ continue \}//'
mutate "Relay's fill answers a send of yours"        's/arrivals\.remove\(at: taken\)//'
mutate "a round-up counted once per leg"             's/counted\.insert\(m\.tx\)//'
mutate "an unfollowed wallet's round-ups count"      's/for m in moves where m\.way == \.sent && own\.contains\(m\.wallet\) \{/for m in moves where m.way == .sent {/'
mutate "a round-up added to the total"               's/reading\.roundUpsTotal \+= buy\.usd/reading.roundUpsTotal += buy.usd; reading.total += buy.usd/'
mutate "the day the count starts from never said"    's/reading\.roundUpsFrom = first/reading.roundUpsFrom = nil/'
mutate "a plan tracked by hand on an app's page"     's/return app\.map \{ sources\.contains\(\$0\) \} \?\? false/return app.map { sources.contains(\$0) } ?? true/'
mutate "a wallet's page reads every wallet"          's/return wallet\.map \{ forms\.contains\(\$0\.lowercased\(\)\) \} \?\? false/return wallet.map { _ in true } ?? false/'
mutate "a wallet spelt in capitals is not its own"   's/forms\.contains\(\$0\.lowercased\(\)\)/forms.contains(\$0)/'
