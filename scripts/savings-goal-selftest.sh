#!/bin/zsh
# A savings goal on your private balance (prd §1667): one number and maybe a
# day, kept on this phone. The percent must never round up to "100%" before
# it is reached, the weekly pace must divide what is LEFT over whole weeks
# to the day, a passed day must not divide by zero or read as a pace, and a
# stored goal of nothing must not stand.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="Casberi/Casberi/Model/SavingsGoal.swift"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { print -u2 "✗ $1"; exit 1; }

cat > "$work/main.swift" <<'SWIFT'
import Foundation
var failures = 0
func check(_ ok: Bool, _ what: String) { if !ok { print("  ✗ \(what)"); failures += 1 } }
typealias G = SavingsGoal
var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
let now = Date(timeIntervalSince1970: 1_793_620_800)   // 2026-11-02 UTC
let in28 = now.addingTimeInterval(28 * 86_400), in10 = now.addingTimeInterval(10 * 86_400)

check(G.dollars(typed: "500") == 500 && G.dollars(typed: "$1,250.50") == 1250.5 && G.dollars(typed: " 80 ") == 80,
      "a typed amount is misread")
check(G.dollars(typed: "") == nil && G.dollars(typed: "0") == nil && G.dollars(typed: "-5") == nil && G.dollars(typed: "abc") == nil,
      "nothing, zero, a minus or words make a goal")

let g = G.Goal(dollars: 500, by: nil)
check(G.percent(saved: 140, goal: g) == "28%" && G.percent(saved: 498, goal: g) == "99%" && G.percent(saved: 900, goal: g) == "100%"
      && G.percent(saved: -3, goal: g) == "0%", "the percent rounds up or runs past the ends")
check(G.line(saved: 140, goal: g, now: now, calendar: cal) == .left(360), "no day does not say what is left")
check(G.line(saved: 500, goal: g, now: now, calendar: cal) == .reached, "the goal met is not reached")

let dated = G.Goal(dollars: 500, by: in28)
check(G.pace(saved: 100, goal: dated, now: now, calendar: cal).map { $0.weeks == 4 && $0.weekly == 100 } == true,
      "four weeks to $400 more is not $100 a week")
let tenDays = G.Goal(dollars: 500, by: in10)
check(G.pace(saved: 200, goal: tenDays, now: now, calendar: cal).map { $0.weeks == 2 && $0.weekly == 150 } == true,
      "ten days is not two whole weeks")
let past = G.Goal(dollars: 500, by: now.addingTimeInterval(-86_400))
check(G.pace(saved: 100, goal: past, now: now, calendar: cal) == nil, "a passed day still paces")
check(G.line(saved: 100, goal: past, now: now, calendar: cal) == .overdue(left: 400, was: past.by!), "a passed day does not say so")
let today = G.Goal(dollars: 500, by: now)
check(G.pace(saved: 100, goal: today, now: now, calendar: cal) == nil, "today divides by no weeks")

check(G.decode(G.encode(dated)) == dated, "a goal does not come back as kept")
check(G.decode(G.encode(G.Goal(dollars: 0, by: nil))) == nil && G.decode(nil) == nil && G.decode(Data("x".utf8)) == nil,
      "a goal of nothing, or nonsense, stands")

if failures > 0 { print("\(failures) assertion(s) failed"); exit(1) }
print("  ok   the percent, what is left, the weekly pace and a passed day")
SWIFT

xcrun swiftc -O "$SRC" "$work/main.swift" -o "$work/t" 2>&1 | grep -v "^$" || true
[[ -x "$work/t" ]] || fail "the shipped source did not compile"
"$work/t" || fail "assertions failed against the shipped source"

mutate() {
  local why="$1" expr="$2"
  cp "$SRC" "$work/m.swift"
  perl -0pi -e "$expr" "$work/m.swift"
  cmp -s "$SRC" "$work/m.swift" && fail "mutation matched nothing: $why"
  xcrun swiftc -O "$work/m.swift" "$work/main.swift" -o "$work/m" >/dev/null 2>&1 || fail "mutation did not compile: $why"
  if "$work/m" >/dev/null 2>&1; then fail "mutation SURVIVED — $why"; fi
  print "  ok   catches  $why"
}
mutate "the percent rounds"          's/\* 100\)\.rounded\(\.down\)/* 100).rounded()/'
mutate "weeks round down"            's/\(Double\(days\) \/ 7\)\.rounded\(\.up\)/(Double(days) \/ 7).rounded(.down)/'
mutate "the pace divides the goal"   's/\(goal\.dollars - max\(0, saved\)\) \/ Double\(weeks\)/goal.dollars \/ Double(weeks)/'
mutate "today paces"                 's/guard days > 0 else \{ return nil \}/guard days >= 0 else { return nil }/'
mutate "a goal of nothing stands"    's/goal\.dollars > 0, goal\.dollars\.isFinite else/goal.dollars.isFinite else/'
mutate "reached never says so"       's/if saved >= goal\.dollars \{ return \.reached \}//'
