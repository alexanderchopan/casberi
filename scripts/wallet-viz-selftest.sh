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
EXPOSURE="Casberi/Casberi/Model/WalletApprovalExposure.swift"
USEROPS="Casberi/Casberi/Model/WalletUserOps.swift"
PARTIES="Casberi/Casberi/Model/WalletActingParties.swift"
for f in "$FLOW" "$RISK" "$STABLE" "$EXPOSURE" "$USEROPS"; do
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

# The exposure card's "unlimited" line is OWNED by WalletApprovals — the same
# number decides whether a ROW's title says "unlimited", and the pure function
# takes it as a parameter precisely so the two can never disagree (see
# `atStake`'s doc). The cases below hard-code it; if the constant moves and
# this harness keeps asserting 1e40, it would certify a card that prices a
# grant the row calls unlimited as if it were capped.
grep -q 'static let unlimitedThreshold: Double = 1e40' Casberi/Casberi/Model/WalletApprovals.swift \
  || { echo "✗ WalletApprovals.unlimitedThreshold changed — update the expectations in $0"; exit 1; }
# The card prices a capped grant as a SHARE of what's held, which needs the
# token count `HeldToken` only started carrying on 2026-08-03. If that field
# goes away the capped arm silently returns nil for every row and the card
# quietly becomes unlimited-only.
grep -q 'var amount: Double? = nil' Casberi/Casberi/Model/WalletIngest.swift \
  || { echo "✗ HeldToken.amount is gone — the capped arm of $EXPOSURE cannot work"; exit 1; }

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

// ═══════════════════════════════════════════════════════════════════════════
// WalletApprovalExposure — what someone else can still move (prd §292)
// ═══════════════════════════════════════════════════════════════════════════
print("\nApproval exposure")

let UNLIMITED = 1e40   // WalletApprovals.unlimitedThreshold, guarded above

func stake(_ allowance: Double, dec: Int? = 6,
           usd: Double? = 6_200, tokens: Double? = 6_200) -> Double? {
    WalletApprovalExposure.atStake(allowanceRaw: allowance, decimals: dec,
                                   heldUSD: usd, heldTokens: tokens,
                                   unlimitedAt: UNLIMITED)
}

// The headline case: an unlimited grant reaches the WHOLE balance. Not the
// allowance — pricing 2^256-1 USDC would print a figure in the trillions.
eq(stake(1.157e77), 6_200, "an unlimited grant reaches the whole balance")
// The boundary is INCLUSIVE, and proving that needs a case where the two arms
// disagree: at the threshold with no decimals, `>=` answers the balance and
// `>` falls through to the capped arm and answers nil. Asserting it with
// decimals present would pass either way (a cap of 1e34 clamps to the balance
// too), which is how a `>=`→`>` mutation first survived this harness.
eq(stake(UNLIMITED, dec: nil, tokens: nil), 6_200, "the threshold itself counts as unlimited")
eq(stake(UNLIMITED * 0.999, dec: nil, tokens: nil), nil, "just under it does not")
// …and it does so WITHOUT decimals, which is the whole reason nil decimals
// isn't fatal here: the answer is the balance either way.
eq(stake(1.157e77, dec: nil, tokens: nil), 6_200, "unlimited needs no decimals")

// A capped grant reaches the smaller of the cap and the balance.
eq(stake(500e6, dec: 6, usd: 6_200, tokens: 6_200), 500, "a 500 cap on 6,200 held reaches 500")
eq(stake(500e6, dec: 6, usd: 80, tokens: 80), 80, "the same cap on 80 held reaches only 80")
eq(stake(9_000e6, dec: 6, usd: 6_200, tokens: 6_200), 6_200, "a cap above the balance is clamped")
// Decimals really are per-token — the Gnosis Pay lesson (EURe 18, USDCe 6) in
// a new place. The SAME raw word means 500 tokens at 18dp and 500 trillion at
// 6dp, so reading the wrong scale either prices a real cap at nothing or
// clamps a small one to the whole balance.
eq(stake(500e18, dec: 18, usd: 6_200, tokens: 6_200), 500, "a 500 cap at 18dp reaches 500")
eq(stake(500e18, dec: 6, usd: 6_200, tokens: 6_200), 6_200,
   "the same word read at 6dp would clamp to the whole balance")

// Price is carried through the SHARE, so a token whose dollars and units
// disagree still prices correctly (held 2 ETH worth $6,000; a 1 ETH cap).
eq(stake(1e18, dec: 18, usd: 6_000, tokens: 2), 3_000, "a half-balance cap is half the dollars")

// "Can't be known" is nil, and nil is NOT zero — the distinction the whole
// unpriced list exists for. A zero here sorts the most dangerous grant last.
eq(stake(500e6, dec: nil), nil, "a capped grant with no decimals can't be priced")
eq(stake(500e6, dec: 6, usd: 6_200, tokens: nil), nil, "…nor one with no token count")
eq(stake(500e6, dec: 6, usd: nil, tokens: nil), nil, "…nor one on an unread holding")
eq(stake(500e6, dec: 6, usd: 6_200, tokens: 0), nil, "…nor one against a zero balance")
// But a REVOKED grant is a real zero, not an unknown.
eq(stake(0), 0, "a spent allowance reaches nothing")

// Untrusted numbers off a malformed reply — the `holdingFloor` .isFinite
// lesson. Every one of these renders as a plausible card if it gets through.
// A value we couldn't parse is NOT evidence that a live grant reaches nothing.
// Both of these read as "we don't know" and land in the unpriced list — the
// first cut of `atStake` folded them in with the genuine zero and answered
// "$0", printing reassurance on the row that had earned it least.
eq(stake(.nan), nil, "a NaN allowance can't be known")
eq(stake(.infinity), nil, "an infinite allowance can't be known either")
eq(stake(-1), nil, "a negative allowance is a parse failure, not a revoke")
eq(stake(500e6, dec: 6, usd: .nan, tokens: 6_200), nil, "a NaN balance can't be priced")
eq(stake(500e6, dec: 6, usd: .infinity, tokens: 6_200), nil, "an infinite balance can't be priced")
eq(stake(500e6, dec: 6, usd: -5, tokens: 6_200), nil, "a negative balance is refused")
eq(stake(500e6, dec: 400, usd: 6_200, tokens: 6_200), nil, "an absurd decimals is refused")

// ── the shape of the card ──────────────────────────────────────────────────
func g(_ spender: String, usd: Double?, unlimited: Bool = true,
       forAll: Bool = false, ago: Double? = nil,
       symbol: String = "USDC", cap: Double? = nil) -> WalletApprovalExposure.Grant {
    WalletApprovalExposure.Grant(
        thingID: UUID(), spender: spender, named: !spender.hasPrefix("0x"),
        symbol: symbol, forAll: forAll, unlimited: unlimited, usd: usd,
        capTokens: cap, grantedAt: ago.map { Date(timeIntervalSinceNow: -$0) })
}
let DAY = 86_400.0

do {
    let e = WalletApprovalExposure(
        priced: [g("Uniswap", usd: 6_200), g("1inch", usd: 2_140, symbol: "WETH"),
                 g("Aave", usd: 500, unlimited: false, cap: 500)],
        unpriced: [g("OpenSea", usd: nil, forAll: true, symbol: "Doodles")])
    eq(e.total, 8_840, "the total sums only the priced rows")
    check(e.spenderCount == 3, "the count is of spenders, not of rows")
    check(e.all.count == 4, "unpriced rows still appear, after the priced ones")
    check(e.unpricedNote != nil, "an unpriced grant earns its footnote")
}
// One spender holding three grants is ONE party who can move your money.
do {
    let e = WalletApprovalExposure(priced: [g("Uniswap", usd: 10, symbol: "A"),
                                            g("Uniswap", usd: 20, symbol: "B"),
                                            g("Uniswap", usd: 30, symbol: "C")])
    check(e.spenderCount == 1, "three grants to one spender is one spender")
    check(WalletApprovalExposure.headline(spenders: e.spenderCount, total: e.total)
            .hasPrefix("1 spender can move"), "and the headline says so, singular")
}
// Nothing unpriced, no footnote — the card grows the line only when it owes one.
check(WalletApprovalExposure(priced: [g("Uniswap", usd: 10)]).unpricedNote == nil,
      "a fully priced card owes no footnote")
check(WalletApprovalExposure().isEmpty, "an empty exposure is empty")

// ── the button ─────────────────────────────────────────────────────────────
// It points at the OLDEST UNLIMITED grant — never the biggest, which is
// already the top row.
do {
    let e = WalletApprovalExposure(priced: [
        g("Uniswap", usd: 6_200, ago: 400 * DAY),
        g("1inch",   usd: 2_140, ago: 30 * DAY),
        g("0x4f2b",  usd: 84,    ago: 1_400 * DAY)])
    check(e.oldestWorthReviewing?.spender == "0x4f2b", "the button picks the oldest, not the biggest")
}
// A capped grant is older, but unlimited is what a revoke list is for.
do {
    let e = WalletApprovalExposure(priced: [
        g("Aave",    usd: 500,   unlimited: false, ago: 2_000 * DAY, cap: 500),
        g("Uniswap", usd: 6_200, ago: 400 * DAY)])
    check(e.oldestWorthReviewing?.spender == "Uniswap", "unlimited outranks merely old")
}
// With no unlimited grant at all it falls back to the oldest of any kind…
do {
    let e = WalletApprovalExposure(priced: [
        g("Aave",  usd: 500, unlimited: false, ago: 90 * DAY, cap: 500),
        g("Curve", usd: 900, unlimited: false, ago: 900 * DAY, cap: 900)])
    check(e.oldestWorthReviewing?.spender == "Curve", "with no unlimited grant, the oldest wins")
}
// …and with no dates at all it still never returns nil while rows exist: a
// dead button on a card full of rows is the honesty rule's own example.
do {
    let e = WalletApprovalExposure(priced: [g("Uniswap", usd: 10), g("1inch", usd: 20)])
    check(e.oldestWorthReviewing != nil, "undated rows still give the button a target")
}
check(WalletApprovalExposure().oldestWorthReviewing == nil, "no rows, no target")

// ── the words ──────────────────────────────────────────────────────────────
check(g("U", usd: 1).stateLine == "Unlimited USDC", "an unlimited grant names its token")
check(g("U", usd: nil, forAll: true, symbol: "Doodles").stateLine == "Manages all Doodles",
      "an operator grant reads as managing, not spending")
check(g("A", usd: 1, unlimited: false, cap: 500).stateLine == "Capped at 500 USDC",
      "a capped grant states its cap")
// A FRACTIONAL cap is the case that catches a formatter rounding to whole
// units: a real quarter-ETH allowance printed as "Capped at 0 WETH" reads as
// a revoked grant. (This is the assertion `money`'s own cases can't make —
// dollars are rounded whole before they reach the formatter.)
check(g("A", usd: 1, unlimited: false, symbol: "WETH", cap: 0.25).stateLine
        == "Capped at 0.25 WETH", "a fractional cap keeps its fraction")
// A cap we couldn't scale must not print a raw-unit number as if it were tokens.
check(g("A", usd: 1, unlimited: false, cap: nil).stateLine == "Limited USDC",
      "a cap with no decimals states no number")

// Money is exact, because the card's job is ranking.
check(WalletApprovalExposure.money(8_924) == "$8,924", "dollars group and keep their resolution")
check(WalletApprovalExposure.money(84) == "$84", "small amounts stay small")
check(WalletApprovalExposure.money(0) == "$0", "zero is zero")
check(WalletApprovalExposure.money(.nan) == "$0", "a NaN total never renders as NaN")

// ═══════════════════════════════════════════════════════════════════════════
// WalletUserOps — who actually paid (prd §293)
// ═══════════════════════════════════════════════════════════════════════════
print("\nUserOperation attribution")

let ME     = "0x1111111111111111111111111111111111111111"
let OTHER  = "0x2222222222222222222222222222222222222222"
let PAYMR  = "0x3333333333333333333333333333333333333333"
let EP07   = "0x0000000071727de22e5e9d8baf0edac6f37da032"
let FAKE_EP = "0x9999999999999999999999999999999999999999"
let UOTOPIC = WalletUserOps.userOperationEventTopic

func pad(_ addr: String) -> String {
    "0x000000000000000000000000" + String(addr.dropFirst(2))
}
func w(_ v: String) -> String { String(repeating: "0", count: 64 - v.count) + v }
/// nonce | success | actualGasCost | actualGasUsed
func uoData(costWei: String) -> String { "0x" + w("1") + w("1") + w(costWei) + w("5208") }

func uoLog(sender: String, paymaster: String, costWei: String,
           emitter: String = EP07) -> [String: Any] {
    ["address": emitter,
     "topics": [UOTOPIC, "0x" + String(repeating: "a", count: 64), pad(sender), pad(paymaster)],
     "data": uoData(costWei: costWei)]
}
let ZERO = "0x0000000000000000000000000000000000000000"
// 0x2386f26fc10000 wei = 0.01 ETH
let TENTH = "2386f26fc10000"

func attr(_ logs: [[String: Any]], from: String?, fallback: Double = 0.5)
    -> WalletUserOps.Attribution {
    WalletUserOps.attribution(logs: logs, from: from, wallet: ME, fallbackNative: fallback)
}

// Rule 1 — our own operation, self-paid. The bundle's whole receipt cost 0.5;
// our operation cost 0.01, and 0.01 is what we owe.
check(attr([uoLog(sender: ME, paymaster: ZERO, costWei: TENTH)], from: OTHER)
        == .paid(native: 0.01),
      "our own UserOperation is charged its own actualGasCost, not the bundle's")

// Rule 1 — SPONSORED. The whole point of the feature.
check(attr([uoLog(sender: ME, paymaster: PAYMR, costWei: TENTH)], from: OTHER)
        == .sponsored(paymaster: PAYMR, native: 0.01),
      "a paymaster-backed operation costs us nothing and names the sponsor")

// The bundle case that motivated all this: a bundler sent it, and the bundle
// also carried a stranger's operation. We must not be charged for theirs.
check(attr([uoLog(sender: OTHER, paymaster: ZERO, costWei: TENTH)], from: OTHER)
        == .notYours,
      "a stranger's operation in the same bundle is not ours to pay")
do {
    let bundle = [uoLog(sender: OTHER, paymaster: ZERO, costWei: "de0b6b3a7640000"),
                  uoLog(sender: ME,    paymaster: ZERO, costWei: TENTH)]
    check(attr(bundle, from: OTHER) == .paid(native: 0.01),
          "…and ours is found beside theirs, charged only its own share")
}

// Rule 2 — a plain EOA. Unchanged behaviour, which is the point: the fix must
// not disturb the case that was already right.
check(attr([], from: ME, fallback: 0.5) == .paid(native: 0.5),
      "an ordinary EOA still pays its whole receipt")

// Rule 3 — a Safe. The owner executed it; the Safe pays nothing. This needs no
// 4337 at all, and it is the half that fixes every executed-by-someone-else
// account.
check(attr([], from: OTHER, fallback: 0.5) == .notYours,
      "a transaction somebody else sent costs us nothing")
check(attr([], from: nil, fallback: 0.5) == .notYours,
      "a receipt with no `from` is never charged to us")

// A FORGED event. Any contract can emit any log; only a known EntryPoint's
// word is taken, or a fake sponsorship could zero out real gas we paid.
check(attr([uoLog(sender: ME, paymaster: PAYMR, costWei: TENTH, emitter: FAKE_EP)],
           from: ME, fallback: 0.5) == .paid(native: 0.5),
      "an unknown emitter's event is ignored — we fall back, never trust it")
check(WalletUserOps.unknownEmitters(
        logs: [uoLog(sender: ME, paymaster: ZERO, costWei: TENTH, emitter: FAKE_EP)])
        == [FAKE_EP],
      "…and the unknown emitter is reported, so a new EntryPoint is visible")
check(WalletUserOps.unknownEmitters(
        logs: [uoLog(sender: ME, paymaster: ZERO, costWei: TENTH)]).isEmpty,
      "a known EntryPoint is not reported as drift")

// Every canonical EntryPoint is trusted, not just the one above.
for ep in WalletUserOps.knownEntryPoints {
    check(attr([uoLog(sender: ME, paymaster: ZERO, costWei: TENTH, emitter: ep)], from: OTHER)
            == .paid(native: 0.01),
          "EntryPoint \(ep.prefix(10)) is trusted")
}

// Malformed replies. Each renders as a plausible number if it gets through.
check(attr([["address": EP07, "topics": [UOTOPIC, "0x00", pad(ME)], "data": "0x"]], from: OTHER)
        == .notYours,
      "an event missing its paymaster topic is not read")
check(attr([["address": EP07,
             "topics": [UOTOPIC, "0x00", pad(ME), pad(ZERO)], "data": "0x1234"]], from: OTHER)
        == .paid(native: 0),
      "a truncated data blob reads as zero cost, never as a guess")
check(attr([["topics": [UOTOPIC, "0x00", pad(ME), pad(ZERO)], "data": uoData(costWei: TENTH)]],
           from: ME, fallback: 0.5) == .paid(native: 0.5),
      "an event with no emitter address at all is ignored")

// ── smart-account vendor naming (prd §294) ────────────────────────────────
// A contract can return ANY string from `accountId()`, so the vendor badge is
// only rendered when the answer is plainly a name — otherwise attacker-chosen
// text lands in the app's own chrome.
func vendor(_ id: String?) -> String? {
    WalletUserOps.SmartAccount(accountID: id, entryPoint: nil).vendor
}
check(vendor("biconomy.nexus.1.0.0") == "Biconomy", "an account names its own vendor")
check(vendor("ZeroDev.Kernel.v3") == "Zerodev", "casing is normalised, never echoed raw")
check(vendor("safe.core.1.4.1") == "Safe", "…and the shortest real vendor still passes")
check(vendor(nil) == nil, "no accountId, no vendor")
check(vendor("") == nil, "an empty id names nobody")
check(vendor("a.b.c") == nil, "a one-letter vendor is not a name")
// SHORT hostile strings — the ones that matter. The first draft of these
// cases used a 25-character sentence and a 25-character <script> tag, so both
// were rejected by the LENGTH guard and neither exercised the character check
// at all; dropping `allSatisfy` entirely left the harness green. Every case
// below is inside the length window on purpose.
check(vendor("a<b>c.x.1") == nil, "markup inside the length window is refused")
check(vendor("send eth.x.1") == nil, "a spaced phrase is refused")
check(vendor("ev/il.x.1") == nil, "a slash is refused")
// A slash in a LATER component is not this parser's business — only the first
// dot-component is ever rendered, and "evil" is a plain word, not an injection.
check(vendor("evil.com/x.a.1") == "Evil", "only the first component is read")
check(vendor("me\u{200b}ta.x.1") == nil, "an invisible character is refused")
check(vendor("Ω.x.1") == nil, "a one-character symbol is refused")
check(vendor("<script>alert(1)</script>.x.1") == nil, "…and long markup is refused too")
check(vendor("drain your wallet at evil.com.account.1") == nil, "…as is a sentence")
check(vendor(String(repeating: "x", count: 40) + ".a.1") == nil, "an overlong vendor is refused")

// The ABI readers.
check(WalletUserOps.addressFromTopic(pad(ME)) == ME, "an address is read from its topic")
check(WalletUserOps.addressFromTopic("0xdead").isEmpty,
      "a short topic yields no address — never a partial one that could collide")
eq(WalletUserOps.word(uoData(costWei: TENTH), at: 2), 1e16, "the cost word is read at index 2")
eq(WalletUserOps.word(uoData(costWei: TENTH), at: 9), 0, "a word past the end reads zero")
eq(WalletUserOps.word(nil, at: 0), 0, "absent data reads zero")

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
swiftc -O -o "$TMP/selftest" "$FLOW" "$RISK" "$STABLE" "$EXPOSURE" "$USEROPS" "$DRIVER"
"$TMP/selftest"
