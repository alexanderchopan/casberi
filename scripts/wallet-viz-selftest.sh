#!/bin/zsh
# Casberi wallet-visualization self-test — verifies the SHIPPED pure models
# behind the three cards added 2026-08-01 (design/wallet-viz):
#
#   Casberi/Casberi/Model/WalletFlow.swift       — the flow band's grouping
#   Casberi/Casberi/Model/WalletRiskScale.swift  — the distance-to-liquidation axis
#   Casberi/Casberi/Model/WalletStables.swift    — the stable share
#
# Each source is compiled AS SHIPPED with a driver appended — never a copy, so
# the harness cannot pass against code the app doesn't run. All three files are
# deliberately Foundation-only for exactly this reason; the `Thing`/book-reading
# adapters live in separate *Source.swift files and are not compiled here.
#
# Why a harness rather than a sim check: all three are pure functions whose
# failure mode is a WRONG NUMBER, not a crash or a blank screen. A band drawn
# from two of nine moves, an axis that orders a safe position ahead of a
# dangerous one, a stable share that swallowed a scam token named "USDCoin" —
# every one of those renders perfectly and looks right. The only way to know
# they work is to feed them cases whose answers are known.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

FLOW="Casberi/Casberi/Model/WalletFlow.swift"
RISK="Casberi/Casberi/Model/WalletRiskScale.swift"
STABLE="Casberi/Casberi/Model/WalletStables.swift"
for f in "$FLOW" "$RISK" "$STABLE"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# --- drift guards -----------------------------------------------------------
# The risk strip's two alert thresholds are OWNED by the protocol files and
# passed into the pure axis (see WalletRiskScale's type doc — a shared
# threshold would have to disagree with one of the two shipped sweeps). The
# tests below assert against those exact values, so if either constant moves
# and this harness keeps asserting the old one, it would certify a strip that
# disagrees with the alerts. These guards fail the run instead.
grep -q 'static let floor: Double = 1.5' Casberi/Casberi/Model/DeFiRisk.swift \
  || { echo "✗ DeFiRisk.floor changed — update the expectations in $0"; exit 1; }
grep -q 'static let riskProximity = 0.15' Casberi/Casberi/Model/HyperliquidDeFi.swift \
  || { echo "✗ HyperliquidDeFi.riskProximity changed — update the expectations in $0"; exit 1; }
# The perp arm passes `liquidationProximity` straight through rather than
# recomputing it. If that property stops meaning "fraction of mark", the axis
# silently starts comparing two different quantities again.
grep -q 'return abs(markPx - liq) / markPx' Casberi/Casberi/Model/HyperliquidDeFi.swift \
  || { echo "✗ liquidationProximity changed shape — re-derive the axis in $RISK"; exit 1; }

TMP=$(mktemp -d /tmp/wallet-viz-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
# MUST be named main.swift: with several files on the command line, `swift`
# compiles them as a module and runs only `main.swift`'s top-level code. Named
# anything else, the driver below is compiled and never executed — the run
# exits 0 having asserted NOTHING, which is how this harness first "passed".
DRIVER="$TMP/main.swift"

cat > "$DRIVER" <<'SWIFT'
import Foundation

var failures = 0
var checks = 0
func check(_ ok: Bool, _ what: String) {
    checks += 1
    if !ok { failures += 1; print("  ✗ \(what)") }
}
func eq(_ a: Double?, _ b: Double?, _ what: String, tol: Double = 1e-9) {
    checks += 1
    switch (a, b) {
    case let (x?, y?) where abs(x - y) <= tol: return
    case (nil, nil): return
    default:
        failures += 1
        let got: String = a.map { "\($0)" } ?? "nil"
        let want: String = b.map { "\($0)" } ?? "nil"
        print("  ✗ \(what) — got \(got), want \(want)")
    }
}

// ===========================================================================
// WalletFlow — the band's grouping
// ===========================================================================
print("WalletFlow")

func leg(_ received: Bool, _ name: String, _ usd: Double?, key: String? = nil) -> WalletFlow.Leg {
    WalletFlow.Leg(received: received, name: name, key: key ?? name.lowercased(), usd: usd)
}

// The ordinary case: two in, two out, all priced.
do {
    let band = WalletFlow.band(legs: [
        leg(true, "Coinbase", 2100), leg(true, "Peer", 500),
        leg(false, "Aave", 1000), leg(false, "Card", 358),
    ])
    check(band != nil, "an ordinary week draws a band")
    eq(band?.inUSD, 2600, "inflow totals")
    eq(band?.outUSD, 1358, "outflow totals")
    eq(band?.netUSD, 1242, "net is in minus out")
    // ONE shared scale — the band's only real claim is that these two sides
    // are not the same size, so the scale must come from the bigger one.
    eq(band?.scaleUSD, 2600, "both sides share the larger side's scale")
    check(band?.inLanes.count == 2 && band?.outLanes.count == 2, "one lane per counterparty")
    check(band?.inLanes.first?.name == "Coinbase", "lanes rank biggest first")
}

// Legs to the same counterparty fold into one lane, and the count survives.
do {
    let band = WalletFlow.band(legs: [
        leg(true, "Coinbase", 100), leg(true, "Coinbase", 300),
        leg(false, "Aave", 50),
    ])
    check(band?.inLanes.count == 1, "same counterparty is one lane")
    eq(band?.inLanes.first?.usd, 400, "folded lane sums its legs")
    check(band?.inLanes.first?.count == 2, "folded lane keeps its leg count")
}

// Two nameless strangers must NOT merge just because neither has a name.
do {
    let band = WalletFlow.band(legs: [
        leg(true, "0xaaaa…1111", 100, key: "0xaaaa1111"),
        leg(true, "0xbbbb…2222", 100, key: "0xbbbb2222"),
        leg(false, "Aave", 50),
    ])
    check(band?.inLanes.count == 2, "different addresses stay different lanes")
}

// The tail folds into a named "Other" rather than vanishing (no silent caps).
do {
    let band = WalletFlow.band(legs: [
        leg(true, "A", 1000), leg(true, "B", 800), leg(true, "C", 600),
        leg(true, "D", 400), leg(true, "E", 300),
        leg(false, "Out", 100),
    ])
    let lanes = band?.inLanes ?? []
    check(lanes.count == WalletFlow.laneLimit + 1, "tail folds into one extra lane")
    check(lanes.last?.isOther == true, "the fold is marked as Other")
    eq(lanes.last?.usd, 700, "Other carries the folded value")
    check(lanes.last?.count == 2, "Other carries the folded count")
    // Nothing may be lost in the fold — the lanes must still sum to the total.
    eq(lanes.reduce(0) { $0 + $1.usd }, band?.inUSD, "folding loses no money")
}

// The shared scale reaches the FOLD too, not just the drawing. A week that
// took in $200 and sent out $10,000 has in-lanes that are slivers on the
// band's own scale, so they merge — where a per-side scale would have kept
// them as full-width ribbons and drawn a $150 receipt the same size as a
// $9,000 payment. (Caught by mutation: the earlier tests all asserted
// `scaleUSD` and left the fold's own copy of the scale unpinned.)
do {
    let band = WalletFlow.band(legs: [
        leg(true, "A", 150), leg(true, "B", 50),
        leg(false, "Big", 10_000),
    ])
    check(band?.inLanes.count == 1, "in-lanes tiny against the shared scale merge")
    check(band?.inLanes.first?.isOther == true, "and they merge into a named Other")
    eq(band?.inUSD, 200, "the merged side still totals correctly")
}

// A sliver below the minimum share joins the fold instead of drawing a hairline.
do {
    let band = WalletFlow.band(legs: [
        leg(true, "Big", 10_000), leg(true, "Dust", 50),
        leg(false, "Out", 100),
    ])
    let lanes = band?.inLanes ?? []
    check(lanes.count == 2 && lanes.last?.isOther == true, "a sub-2% lane folds")
    eq(lanes.reduce(0) { $0 + $1.usd }, 10_050, "the sliver's money is still counted")
}

// Unpriced legs are COUNTED and reported, never silently dropped or zeroed.
do {
    let band = WalletFlow.band(legs: [
        leg(true, "Coinbase", 2100), leg(true, "Mystery", nil),
        leg(false, "Aave", 1000), leg(false, "Other", nil),
    ])
    check(band?.unpricedCount == 2, "unpriced legs are reported")
    eq(band?.inUSD, 2100, "an unpriced leg adds nothing to the total")
}

// A window that is mostly UNPRICED draws nothing, footnote or no footnote.
// Caught on a real corpus: the card rendered a confident five-lane band from
// 10 priced moves with 84 unpriced beneath it, which is a claim about the
// window that the window does not support.
do {
    var legs = [leg(true, "Coinbase", 2100), leg(false, "Aave", 1000)]
    legs += (0..<84).map { leg(true, "Old\($0)", nil) }
    check(WalletFlow.band(legs: legs) == nil, "declines when most of the window is unpriced")
}
do {
    // Just over the floor still draws — and still says how many it left out.
    let legs = [leg(true, "A", 100), leg(false, "B", 100), leg(true, "C", nil)]
    let band = WalletFlow.band(legs: legs)
    check(band != nil, "two thirds priced is enough to draw")
    check(band?.unpricedCount == 1, "and the leftover is still reported")
}
do {
    // Exactly at the floor is enough — the guard is a floor, not a gap.
    let legs = [leg(true, "A", 100), leg(false, "B", 100),
                leg(true, "C", nil), leg(false, "D", nil)]
    check(WalletFlow.band(legs: legs) != nil, "exactly half priced still draws")
}

// Declines: nothing priced at all is not a smaller band, it's no band.
check(WalletFlow.band(legs: [leg(true, "A", nil), leg(false, "B", nil)]) == nil,
      "declines when nothing could be priced")
check(WalletFlow.band(legs: []) == nil, "declines on no legs")
// One lane is a sentence, not a comparison.
check(WalletFlow.band(legs: [leg(true, "Only", 500)]) == nil, "declines on a single lane")
// A zero or non-finite price can't become a lane or poison the scale.
check(WalletFlow.band(legs: [leg(true, "Zero", 0), leg(false, "Also", 0)]) == nil,
      "declines when every price is zero")
do {
    let band = WalletFlow.band(legs: [
        leg(true, "Real", 100), leg(true, "Broken", .infinity), leg(false, "Out", 40),
    ])
    eq(band?.inUSD, 100, "a non-finite price is refused, not summed")
}

// Determinism: dictionary order must never reach the drawing.
do {
    let a = WalletFlow.band(legs: [leg(true, "A", 100), leg(true, "B", 100), leg(false, "C", 50)])
    for _ in 0..<50 {
        let b = WalletFlow.band(legs: [leg(true, "B", 100), leg(true, "A", 100), leg(false, "C", 50)])
        check(a?.inLanes.map(\.id) == b?.inLanes.map(\.id), "lane order is stable for tied values")
    }
}

// --- the band's geometry ---------------------------------------------------
// This is the part of the card that fails INVISIBLY: an overflowing slab
// stack clips off the bottom and reads as a missing counterparty, not as a
// layout bug. Every case below pins "stays inside its box".
func lanes(_ values: [Double]) -> [WalletFlow.Lane] {
    values.enumerated().map {
        WalletFlow.Lane(id: "l\($0.offset)", name: "L\($0.offset)",
                        usd: $0.element, count: 1, isOther: false)
    }
}
func heightsFit(_ values: [Double], sideTotal: Double, scale: Double,
                band: Double = 132, gap: Double = 3, minH: Double = 6,
                _ what: String) {
    let ls = lanes(values)
    let layout = WalletFlow.laneHeights(lanes: ls, sideTotal: sideTotal, scaleUSD: scale,
                                        bandHeight: band, laneGap: gap, minHeight: minH)
    check(layout.heights.count == ls.count, "\(what): one height per lane")
    let sideHeight = band * (sideTotal / scale)
    check(layout.used <= sideHeight + 1e-6, "\(what): slabs + gaps stay inside the side's height")
    check(layout.used <= band + 1e-6, "\(what): and inside the band")
    check(layout.heights.allSatisfy { $0 >= 0 }, "\(what): no negative slab")
    check(layout.gap <= gap + 1e-9, "\(what): the gap never grows past the design value")
}

// The exact shape that motivated the floor-first allocation: one dominant
// lane and three at the fold threshold. The naive form needs 134pt of 123.
heightsFit([94, 2, 2, 2], sideTotal: 100, scale: 100, "94/2/2/2")
heightsFit([25, 25, 25, 25], sideTotal: 100, scale: 100, "even four")
heightsFit([99, 1], sideTotal: 100, scale: 100, "one dominant lane")
// The smaller side must occupy proportionally less of the band — that IS the
// shared scale, expressed in pixels.
heightsFit([150, 50], sideTotal: 200, scale: 10_000, "a tiny side against a huge one")
heightsFit([1], sideTotal: 1, scale: 1, "a single lane")
do {
    let layout = WalletFlow.laneHeights(lanes: lanes([50, 50]), sideTotal: 100, scaleUSD: 200,
                                        bandHeight: 132, laneGap: 3, minHeight: 6)
    check(abs(layout.used - 66) < 1e-6, "a half-sized side fills half the band")
}
do {
    // Every lane keeps a readable slab even when its share rounds to nothing.
    let hs = WalletFlow.laneHeights(lanes: lanes([1000, 1]), sideTotal: 1001, scaleUSD: 1001,
                                    bandHeight: 132, laneGap: 3, minHeight: 6).heights
    check(hs.allSatisfy { $0 >= 6 - 1e-9 }, "no lane draws thinner than the floor")
    check(hs[0] > hs[1], "and the bigger lane is still visibly bigger")
}
do {
    // Degenerate inputs return zeros rather than NaNs reaching a Path.
    let hs = WalletFlow.laneHeights(lanes: lanes([1, 1]), sideTotal: 0, scaleUSD: 0,
                                    bandHeight: 132, laneGap: 3, minHeight: 6).heights
    check(hs == [0, 0], "an empty side draws nothing rather than NaN")
    check(hs.allSatisfy { $0.isFinite }, "and nothing non-finite reaches the view")
}

// ===========================================================================
// WalletRiskScale — the shared axis
// ===========================================================================
print("WalletRiskScale")

let FLOOR = 1.5      // DeFiRisk.floor, pinned by the drift guard above
let PROX  = 0.15     // HyperliquidDeFi.riskProximity, likewise

// The derivation: an HF of 2 means the collateral can halve before liquidation.
eq(WalletRiskScale.headroom(healthFactor: 2), 0.5, "HF 2 leaves half the value as headroom")
eq(WalletRiskScale.headroom(healthFactor: 4), 0.75, "HF 4 leaves three quarters")
eq(WalletRiskScale.headroom(healthFactor: 1), 0, "HF 1 is the edge itself")
// Already past the edge is still the edge — never a negative dot off the track.
eq(WalletRiskScale.headroom(healthFactor: 0.8), 0, "an underwater position clamps to the edge")
eq(WalletRiskScale.headroom(healthFactor: -1), nil, "a nonsense health factor has no headroom")
eq(WalletRiskScale.headroom(healthFactor: 0), nil, "zero has no headroom")
// An infinite health factor means no debt — so there is nothing to liquidate
// and nothing to place on a liquidation axis. Declining is the same ruling
// DeFiRisk already keeps ("it can't be 'at risk' of losing nothing"), not an
// edge case swallowed.
eq(WalletRiskScale.headroom(healthFactor: .infinity), nil, "no debt is not a dot")
eq(WalletRiskScale.headroom(healthFactor: .nan), nil, "NaN has no headroom")

// A perp's headroom is passed through, not recomputed.
eq(WalletRiskScale.headroom(proximity: 0.18), 0.18, "a perp states its own headroom")
eq(WalletRiskScale.headroom(proximity: 1.4), 1, "an impossible distance clamps")
eq(WalletRiskScale.headroom(proximity: -0.2), nil, "a negative distance is refused")

// THE POINT OF THE WHOLE CARD: a health factor and a percentage-of-mark land
// on one axis in the right order. Morpho at HF 1.62 has 38% headroom; a perp
// 18% from liquidation has less, so the perp must sit closer to the edge —
// which no amount of staring at "1.62" and "18%" side by side would tell you.
do {
    let aave = WalletRiskScale.lendingEntry(id: "a", label: "Aave", hf: 2.4, riskFloor: FLOOR)!
    let morpho = WalletRiskScale.lendingEntry(id: "m", label: "Morpho", hf: 1.62, riskFloor: FLOOR)!
    let perp = WalletRiskScale.perpEntry(id: "h", label: "Hyperliquid · ETH",
                                         proximity: 0.18, riskProximity: PROX)!
    check(perp.axis > morpho.axis, "the perp sits closer to liquidation than HF 1.62")
    check(morpho.axis > aave.axis, "HF 1.62 sits closer than HF 2.4")
    let strip = WalletRiskScale.strip([aave, morpho, perp])!
    check(strip.map(\.id) == ["h", "m", "a"], "the strip orders worst first")
}

// Each dot's alarm comes from its OWN protocol's rule, never from a shared
// crossing point on the track. These two positions have nearly IDENTICAL
// headroom (33% vs 30%) and land in OPPOSITE states, which is precisely why
// one gradient threshold could not have served both.
do {
    let lending = WalletRiskScale.lendingEntry(id: "l", label: "Aave", hf: 1.49, riskFloor: FLOOR)!
    let perp = WalletRiskScale.perpEntry(id: "p", label: "HL", proximity: 0.30,
                                         riskProximity: PROX)!
    check(abs(lending.headroom - perp.headroom) < 0.05, "the two sit at nearly the same headroom")
    check(lending.atRisk, "HF 1.49 is at risk by Aave's own floor")
    check(!perp.atRisk, "30% from liquidation is calm by Hyperliquid's own margin")
}
do {
    let safe = WalletRiskScale.lendingEntry(id: "s", label: "Aave", hf: 1.51, riskFloor: FLOOR)!
    check(!safe.atRisk, "just above the floor is not at risk")
    let near = WalletRiskScale.perpEntry(id: "n", label: "HL", proximity: 0.14,
                                         riskProximity: PROX)!
    check(near.atRisk, "just inside the perp margin is at risk")
}

// Each dot wears its protocol's own words, in its protocol's own unit.
do {
    let l = WalletRiskScale.lendingEntry(id: "l", label: "Aave", hf: 1.62, riskFloor: FLOOR)!
    check(l.detail.contains("1.62"), "a lending dot states its health factor")
    let round = WalletRiskScale.lendingEntry(id: "r", label: "Aave", hf: 2.0, riskFloor: FLOOR)!
    check(round.detail.contains("2.0"), "a round health factor keeps one decimal")
    let p = WalletRiskScale.perpEntry(id: "p", label: "HL", proximity: 0.18, riskProximity: PROX)!
    check(p.detail.contains("18"), "a perp dot states its percentage")
    check(!p.detail.contains("Health"), "a perp never borrows the lending unit")
}

// Declines: one position is a health factor wearing a chart.
check(WalletRiskScale.strip([]) == nil, "declines on nothing")
do {
    let one = WalletRiskScale.lendingEntry(id: "a", label: "Aave", hf: 2, riskFloor: FLOOR)!
    check(WalletRiskScale.strip([one]) == nil, "declines on a single position")
}
// A position with no debt carries no health factor and simply isn't a dot.
check(WalletRiskScale.lendingEntry(id: "x", label: "Aave", hf: 0, riskFloor: FLOOR) == nil,
      "a position with no usable health factor is not a dot")

// ===========================================================================
// WalletStables — the stable share
// ===========================================================================
print("WalletStables")

check(WalletStables.isStable("USDC"), "USDC is stable")
check(WalletStables.isStable("usdc"), "matching folds case")
check(WalletStables.isStable("EURe"), "a euro stablecoin is stable")
check(WalletStables.isStable("sDAI"), "a yield-bearing wrapper is stable")
check(!WalletStables.isStable("ETH"), "ETH is not stable")
// The whole reason this is a set and not a prefix rule: the app already knows
// spoofed symbols are real, and `hasPrefix("USD")` would count every one.
check(!WalletStables.isStable("USDCoin"), "a lookalike symbol is not stable")
check(!WalletStables.isStable("USDT_CLAIM"), "a scam symbol is not stable")
check(!WalletStables.isStable("USD_REWARD"), "another lookalike is refused")

do {
    let book = [("ETH", 30_000.0), ("USDC", 10_000.0), ("AERO", 10_000.0)]
    eq(WalletStables.share(positions: book, totalUSD: 50_000), 0.2, "a fifth in dollars reads 20%")
}
do {
    let book = [("ETH", 30_000.0), ("USDC", 6_000.0), ("EURe", 4_000.0)]
    eq(WalletStables.share(positions: book, totalUSD: 40_000), 0.25, "stables across currencies sum")
}
// Declines — the same guard the concentration line keeps, and for the same
// reason: a $5 stablecoin dust position in a $48k book rounds to 0%, and
// "0% stable" printed beside a real holding is a fake status.
eq(WalletStables.share(positions: [("ETH", 48_000), ("USDC", 5)], totalUSD: 48_005), nil,
   "a dust share that rounds to zero says nothing")
eq(WalletStables.share(positions: [("USDC", 1_000), ("USDT", 9_000)], totalUSD: 10_000), nil,
   "an all-stable book has no split to report")
eq(WalletStables.share(positions: [("ETH", 1_000)], totalUSD: 1_000), nil,
   "one position is not a composition")
eq(WalletStables.share(positions: [("ETH", 1_000), ("AERO", 500)], totalUSD: 1_500), nil,
   "no stables at all draws no line")
eq(WalletStables.share(positions: [("ETH", 1_000), ("USDC", 100)], totalUSD: 0), nil,
   "an empty book has no share")

print("")
if failures == 0 {
    print("✓ wallet-viz self-test: \(checks) checks passed")
} else {
    print("✗ wallet-viz self-test: \(failures) of \(checks) checks FAILED")
    exit(1)
}
SWIFT

# Compiled together so the driver sees all three enums; the shipped sources are
# passed through untouched.
#
# `swiftc` to a binary, NOT `swift file1 file2 …` — that form runs the FIRST
# file as a script and passes the rest as command-line ARGUMENTS to it, so the
# sources were never compiled and the run exited 0 having tested nothing.
swiftc -O -o "$TMP/selftest" "$FLOW" "$RISK" "$STABLE" "$DRIVER"
"$TMP/selftest"
