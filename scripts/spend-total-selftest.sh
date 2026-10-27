#!/bin/zsh
# The spend limit in all (prd §1569): one total for ETH and the dollar on
# every network, kept by the phone, because no chain can see another's
# spending. A total that counted one network, counted a send outside its
# period, valued ETH at nothing when no price was read, or let a worth it
# could not read through would let the session key spend past what the
# person set, and the chain (each network's whole amount of each coin) would
# not stop it.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="Casberi/Casberi/Model/SpendTotal.swift"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { print -u2 "✗ $1"; exit 1; }

cat > "$work/main.swift" <<'SWIFT'
import Foundation
var failures = 0
func check(_ ok: Bool, _ what: String) { if !ok { print("  ✗ \(what)"); failures += 1 } }
typealias T = SpendTotal

// The period: the window holding now that began first.
let first = T.Period(from: 1_000, until: 2_000)
let later = T.Period(from: 1_500, until: 2_500)
check(T.period(current: [later, first], at: 1_600) == first, "the period is the window that began first")
check(T.period(current: [first], at: 2_000) == nil, "a window's end is not in it")
check(T.period(current: [], at: 1_600) == nil, "no window, no period")

// One total across networks, inside the period only.
let spends = [T.Spend(chainId: 8453, dollars: 40, at: 1_100), T.Spend(chainId: 1, dollars: 30, at: 1_900),
              T.Spend(chainId: 4663, dollars: 50, at: 2_000), T.Spend(chainId: 8453, dollars: 7, at: 999)]
check(T.spent(spends, in: first) == 70, "every network counts in one total, inside the period only")
check(T.left(cap: 100, spends: spends, in: first) == 30, "what is left")
check(T.left(cap: 50, spends: spends, in: first) == 0, "what is left is never below zero")
check(T.fits(30, cap: 100, spends: spends, in: first), "the last dollar fits")
check(!T.fits(30.01, cap: 100, spends: spends, in: first), "a cent over does not")
check(!T.fits(nil, cap: 100, spends: [], in: first), "a worth not read never fits")
check(!T.fits(-1, cap: 100, spends: [], in: first), "a negative worth never fits")
check(!T.fits(1, cap: 0, spends: [], in: first), "with no amount nothing fits")

// What a send is worth.
check(T.worth(dollarUnits: ["1500000"], wei: [], ethPrice: nil) == 1.5, "the dollar at six decimals")
check(T.worth(dollarUnits: [], wei: ["500000000000000000"], ethPrice: 3_000) == 1_500, "ETH at its price")
check(T.worth(dollarUnits: ["1000000"], wei: ["1000000000000000000"], ethPrice: 2_000) == 2_001, "ETH and the dollar in one total")
check(T.worth(dollarUnits: [], wei: ["1"], ethPrice: nil) == nil, "ETH with no price has no worth")
check(T.worth(dollarUnits: [], wei: ["1"], ethPrice: 0) == nil, "nor at a price of zero")
check(T.worth(dollarUnits: ["x"], wei: [], ethPrice: nil) == nil, "an amount that is not a number has no worth")
check(T.worth(dollarUnits: [], wei: [], ethPrice: nil) == 0, "nothing is worth nothing")

// The ledger keeps what a period could still count.
let kept = T.recording(T.Spend(chainId: 1, dollars: 5, at: 10_000),
                       to: [T.Spend(chainId: 1, dollars: 9, at: 100), T.Spend(chainId: 8453, dollars: 2, at: 9_500)],
                       keepSeconds: 1_000)
check(kept.map(\.at) == [9_500, 10_000], "the ledger keeps only what a period could count")
check(T.keepSeconds >= 30 * 24 * 60 * 60, "the ledger outlasts a month's period")

if failures > 0 { print("\(failures) assertion(s) failed"); exit(1) }
print("  ok   one total, every network, inside the period, a worth or both keys")
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
mutate "the period is the newest window"      's/\.min \{ \$0\.from < \$1\.from \}/.max { \$0.from < \$1.from }/'
mutate "a send at the period's end counts"    's/\$0\.at < period\.until/\$0.at <= period.until/'
mutate "an unread worth fits"                 's/guard let dollars, dollars\.isFinite, dollars >= 0, cap > 0 else \{ return false \}/guard let dollars else { return true }/'
mutate "ETH with no price is worth nothing"   's/ *guard n == 0 \|\| \(ethPrice\.map \{ \$0\.isFinite && \$0 > 0 \} \?\? false\) else \{ return nil \}\n//'
mutate "the dollar read as whole dollars"     's/total \+= n \/ 1e6/total += n/'
mutate "ETH counted at one dollar"            's/total \+= n \/ 1e18 \* \(ethPrice \?\? 0\)/total += n \/ 1e18/'
mutate "the ledger keeps everything"          's/\.filter \{ \$0\.at > spend\.at - keepSeconds \}/.filter { _ in true }/'
mutate "the ledger forgets within a month"    's/static let keepSeconds = 31 \* 24 \* 60 \* 60/static let keepSeconds = 24 * 60 * 60/'
