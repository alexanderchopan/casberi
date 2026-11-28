#!/bin/zsh
# Tacit's farms (prd §1993). Earn shows each farm's rate, priced from Tacit's
# own pools: a year's TAC over what the bonded shares are worth, the pool
# worth twice the side we can name, cETH named in TAC by the TAC/cETH pool.
# The figures are Ethereum's, read through Tacit's farm program 2026-11-26.
set -euo pipefail
cd "$(dirname "$0")/.."
M="Casberi/Casberi/Model"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { print -u2 "✗ $1"; exit 1; }

cat > "$work/stub.swift" <<'SWIFT'
import Foundation
enum PrivacyEngineWire { struct Failure: Error, Equatable, Decodable { let name: String; let message: String } }
SWIFT

cat > "$work/main.swift" <<'SWIFT'
import Foundation
var failures = 0
func check(_ ok: Bool, _ what: String) { if !ok { print("  ✗ \(what)"); failures += 1 } }
func near(_ a: Double?, _ b: Double, _ tol: Double = 0.01) -> Bool { a.map { abs($0 - b) <= tol * abs(b) } ?? false }
typealias F = TacitFarms
typealias W = TacitEngineWire

// The wire as the engine hands it: 0x-hex, value units of 8 decimals.
let h = { (n: UInt64) in "0x" + String(n, radix: 16) }
let wire = W.Farms(active: true, remaining: 1_957_464, pools: [
    .init(pair: "TAC/cETH", lpAsset: "0x17C5", perYear: h(20_216_941_200_000), staked: h(104_617_537_650), shares: h(104_762_795_228),
          a: "cETH", b: "TAC", reserveA: h(2_582_372_527), reserveB: h(5_001_356_202_952)),
    .init(pair: "cETH/cUSD", lpAsset: "0xd608", perYear: h(12_130_164_720_000), staked: h(12_203_290_494), shares: h(12_218_544_622),
          a: "cETH", b: "cUSD", reserveA: h(376_331_492), reserveB: h(402_236_127_933)),
    .init(pair: "SPX/TAC", lpAsset: "0x6aee", perYear: h(2_433_317_760_000), staked: h(508_265_522_775), shares: h(508_265_523_775),
          a: "", b: "TAC", reserveA: h(933_267_334_991), reserveB: h(292_251_795_708)),
    .init(pair: "AAA/BBB", lpAsset: "0xaaaa", perYear: h(100_000_000), staked: h(1), shares: h(1),
          a: "AAA", b: "BBB", reserveA: h(1), reserveB: h(1)),
    .init(pair: "TAC/cETH-idle", lpAsset: "0xidle", perYear: h(100_000_000), staked: h(0), shares: h(10),
          a: "TAC", b: "cETH", reserveA: h(100_000_000), reserveB: h(100_000_000)),
    .init(pair: "TAC/HALF", lpAsset: "0xhalf", perYear: h(100_000_000_000), staked: h(5), shares: h(10),
          a: "TAC", b: "HALF", reserveA: h(100_000_000_000), reserveB: h(1)),
], ms: 1)
let now = Date(timeIntervalSince1970: 1_795_755_000)
guard let r = F.reading(wire, at: now) else { print("  ✗ the wire did not read"); exit(1) }
check(r.pools.count == 6, "a pool was dropped")
check(near(r.pools[0].tacPerYear, 202_169.412, 0.0001), "TAC per year is not 8-decimal value units")
check(r.endsAt == now.addingTimeInterval(1_957_464), "the round's end is not now plus what remains")
check(r.pools[0].lpAsset == "0x17c5", "the LP asset is not kept lower-case")

// One ETH in TAC, off the TAC/cETH pool, whichever side ETH stands.
check(near(F.ethInTAC(r.pools), 1_936.73), "ETH is not priced in TAC by the TAC/cETH pool")

// The rates Tacit's own pools put on them.
check(near(F.rate(r.pools[0], in: r), 2.0240), "TAC/cETH is not 202%")
check(near(F.rate(r.pools[1], in: r), 8.3355), "ETH/cUSD is not 833%: the cETH side is not priced in TAC")
check(near(F.rate(r.pools[2], in: r), 4.1631), "SPX/TAC is not 416%: the TAC side is not doubled")
check(near(F.rate(r.pools[5], in: r), 1.0), "half the shares bonded do not earn the whole stream")
check(F.rate(r.pools[3], in: r) == nil, "a pool with neither TAC nor cETH has a rate")
check(F.rate(r.pools[4], in: r) == nil, "a pool nobody is bonded in has a rate")
let ended = F.Reading(pools: r.pools, active: false, endsAt: now, asOf: now)
check(F.rate(r.pools[0], in: ended) == nil, "a farm whose rewards ended still has a rate")

// A position: its share of the whole pool, in TAC.
let mine = F.Position(pair: "TAC/cETH", lpAsset: "0x17c5", shares: 104_762_795_228 * 0.002, pendingTAC: 3.42)
check(near(F.worthTAC(mine, in: r), 200.054), "a position is not its share of the pool's worth")
check(F.position(.init(pair: "TAC/cETH", lpAsset: "0x17C5", shares: "0x0", pending: "0x1")) == nil, "an empty position is kept")
check(near(F.position(.init(pair: "TAC/cETH", lpAsset: "0x17C5", shares: "0x10", pending: h(342_000_000)))?.pendingTAC, 3.42), "unclaimed TAC is not 8 decimals")

// Words.
check(F.rateWords(2.024) == "202%", "a rate over 10% is not whole")
check(F.rateWords(0.045) == "4.5%", "a rate under 10% has no tenth")
check(F.rateWords(nil) == nil && F.rateWords(0) == nil, "no rate draws a figure")
check(F.name("TAC/cETH") == "TAC/ETH" && F.name("cETH/cBTC") == "ETH/BTC" && F.name("cETH/cUSD") == "ETH/cUSD", "the pair is not named as Tacit's page names it")

// What a farm pays back (prd §2006): TAC and cTAC are TAC; wTAC is its own coin; cETH is ETH.
let paid = F.coins([W.Held(ticker: "wTAC", value: h(342_000_000), decimals: 8), W.Held(ticker: "TAC", value: h(9_910_000_000), decimals: 8),
                    W.Held(ticker: "cTAC", value: h(100_000_000), decimals: 8), W.Held(ticker: "cETH", value: h(5_120_000), decimals: 8),
                    W.Held(ticker: "cUSDC", value: h(2_000_000), decimals: 6), W.Held(ticker: "SPX", value: "0x0", decimals: 8)])
check(near(paid.tac, 100.1), "cTAC is not counted as TAC, or wTAC is")
check(near(paid.others["wTAC"], 3.42), "wTAC is not its own coin")
check(near(paid.others["ETH"], 0.0512) && near(paid.others["USDC"], 2) && paid.others["SPX"] == nil, "a coin is misnamed, misread, or nothing is kept")

// Needs you: a week before the end, and after it, only for a farm you are in.
let soon = F.Reading(pools: r.pools, active: true, endsAt: now.addingTimeInterval(3 * 86_400), asOf: now)
let far = F.Reading(pools: r.pools, active: true, endsAt: now.addingTimeInterval(20 * 86_400), asOf: now)
check(F.asks([mine], in: soon).count == 1 && F.asks([mine], in: soon).first?.ended == false, "a farm ending in three days is not said")
check(F.asks([mine], in: far).isEmpty, "a farm ending in twenty days is said")
check(F.asks([mine], in: ended).first?.ended == true, "an ended farm you are in is not said")
check(F.asks([], in: ended).isEmpty, "a farm you are not in is said")

if failures > 0 { print("\(failures) assertion(s) failed"); exit(1) }
print("  ok   the wire, ETH in TAC, every rate, a position's worth, and the words")
SWIFT

build() { xcrun swiftc -O "$1" "$M/TacitEngineWire.swift" "$work/stub.swift" "$work/main.swift" -o "$2"; }
build "$M/TacitFarms.swift" "$work/t" 2>&1 | grep -E "error" || true
[[ -x "$work/t" ]] || fail "the shipped source did not compile"
"$work/t" || fail "assertions failed against the shipped source"

mutate() {
  local why="$1" expr="$2"
  cp "$M/TacitFarms.swift" "$work/m.swift"
  perl -0pi -e "$expr" "$work/m.swift"
  cmp -s "$M/TacitFarms.swift" "$work/m.swift" && fail "mutation matched nothing: $why"
  build "$work/m.swift" "$work/m" >/dev/null 2>&1 || fail "mutation did not compile: $why"
  if "$work/m" >/dev/null 2>&1; then fail "mutation SURVIVED — $why"; fi
  print "  ok   catches  $why"
}
mutate "the pool is not doubled"             's/return 2 \* side/return side/'
mutate "the bonded share is ignored"         's/let bonded = worth \* min\(1, pool\.staked \/ pool\.shares\)/let bonded = worth/'
mutate "ETH's price is inverted"             's/return p\.reserveB \/ p\.reserveA/return p.reserveA \/ p.reserveB/'
mutate "an ended round still pays"           's/guard reading\.active, pool\.shares > 0/guard pool.shares > 0/'
mutate "value units are not 8 decimals"      's/static let unit = 1e8/static let unit = 1e18/'
mutate "wTAC is folded into TAC"             's/\["TAC", "cTAC"\]/["TAC", "cTAC", "wTAC"]/'
mutate "Needs you speaks a month ahead"        's/static let askAhead: TimeInterval = 7 \* 86_400/static let askAhead: TimeInterval = 30 * 86_400/'
mutate "cETH's side is not priced"           's/else if pool\.a == "cETH" \{ side = ethInTAC\.map \{ pool\.reserveA \* \$0 \} \}//'
print "✓ tacit farms: rates from Tacit's own pools, positions, what a farm pays back, Needs you (8 mutations)"
