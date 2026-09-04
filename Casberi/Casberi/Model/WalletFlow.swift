import Foundation

/// Where the money actually went — the flow band's model (2026-08-01, ruled
/// in from `design/wallet-viz`).
///
/// The room's sparkline says the total MOVED. Nothing on any screen said
/// through WHOM, which is the question a moving line actually raises. This
/// groups a window of landed transfers by counterparty into two sides — in and
/// out — so the band can draw the wallet as a spine with ribbons either side.
///
/// Money moving is the module doctrine's one standing exception to "never a
/// tally", and this is the shape that exception exists for: every ribbon here
/// is a real landed thing, not a count of them.
///
/// PURE AND FOUNDATION-ONLY, on purpose. The `Thing`-reading half lives in
/// `WalletFlowSource.swift` so this file compiles standalone and
/// `scripts/wallet-viz-selftest.sh` can exercise it against the shipped
/// source rather than a copy. Nothing here formats currency either — the view
/// owns that (`TokenStats.compact`), so the model returns numbers a test can
/// assert on.
enum WalletFlow {

    /// One in-or-out leg, already reduced to values. The adapter builds these
    /// while the model objects are live; from here on nothing touches
    /// SwiftData, which is what keeps the whole band immune to the liveness
    /// crash class (CLAUDE.md corollaries 1–5) rather than merely guarded
    /// against it.
    struct Leg: Equatable {
        let received: Bool
        /// What the other side is CALLED — a resolved name ("Uniswap", "Mom",
        /// a watched wallet's own label) or a shortened address. Never a raw
        /// full hash; the title rule the transfer sentence already keeps.
        let name: String
        /// What legs fold together. A named counterparty groups by NAME (one
        /// venue behind several router addresses is one lane), a nameless one
        /// groups by its address, so two unrelated strangers never merge.
        let key: String
        /// USD at the time it moved, straight from the transfer read — nil
        /// when nobody priced it. Deliberately optional rather than defaulted
        /// to zero: an unpriced move is unknown, and a zero would shrink the
        /// band's own scale while pretending to be a measurement.
        let usd: Double?
    }

    /// One counterparty's share of one side.
    struct Lane: Identifiable, Equatable {
        /// `"in:uniswap"` — the side is part of the identity, since the same
        /// counterparty legitimately appears on both.
        let id: String
        let name: String
        let usd: Double
        /// How many legs folded into this lane; the view says so when > 1.
        let count: Int
        /// True for the folded tail (see `laneLimit`) — the view names it
        /// rather than dropping it silently.
        let isOther: Bool
    }

    /// Both sides of one window.
    struct Band: Equatable {
        let inLanes: [Lane]
        let outLanes: [Lane]
        let inUSD: Double
        let outUSD: Double
        /// Legs that reached us with no price. Carried, never hidden: a band
        /// drawn from 6 of 9 moves is a different claim from one drawn from
        /// all 9, and the no-silent-caps rule says the drawing has to say so.
        let unpricedCount: Int
        /// Legs older than price data itself — see `WalletFlowSource.pricingEra`.
        /// Counted apart from `unpricedCount` because they are a different
        /// fact: those COULD have been priced and weren't, these never can be,
        /// and only the first kind says anything about how well the read is
        /// working. Still disclosed, for the same no-silent-caps reason.
        var predatingCount: Int = 0

        /// The dollars-per-point both sides share. ONE scale on purpose — if
        /// each side normalised to its own total, a $200 week of outflow would
        /// draw exactly as wide as a $20,000 week of inflow, and the band's
        /// only real claim (these two are not the same size) would be the one
        /// thing it got wrong.
        var scaleUSD: Double { max(inUSD, outUSD) }

        var laneCount: Int { inLanes.count + outLanes.count }

        /// The net move across the window. Not a balance and never presented
        /// as one — the crown number is the balance, and this is only what
        /// crossed the edge while the window was open.
        var netUSD: Double { inUSD - outUSD }
    }

    /// How many named lanes a side shows before the tail folds into "Other".
    /// Small because the band is a glance, and because a 30-point ribbon is
    /// not a readable quantity — the tail is more honest merged than drawn.
    static let laneLimit = 3

    /// How much of a window must be priced before a band is worth drawing.
    ///
    /// Measured on a real corpus, not guessed: the first build to render this
    /// card drew a confident five-lane band out of 10 priced moves while 84
    /// sat unpriced beneath it, and the footnote saying so did not undo the
    /// picture above it. A band claiming to be "where it moved" while covering
    /// a tenth of the window is the fake-status rule wearing a chart.
    ///
    /// The share is measured over legs that COULD have been priced. Legs older
    /// than price data itself are removed before this applies
    /// (`WalletFlowSource.pricingEra`) rather than counted as failures —
    /// **that distinction is the whole reason this floor was reachable at
    /// all** (2026-08-03).
    ///
    /// It wasn't, before. The original reasoning said the decline "resolves on
    /// its own — old moves leave a 7- or 30-day window", which is true of those
    /// two ranges and false of the DEFAULT one: `WalletRange.watched` has a nil
    /// span, so its window is the entire corpus and nothing ever leaves it. On
    /// any wallet with real history the unpriceable rows outnumbered the
    /// priceable ones permanently, the floor never cleared, and the card was
    /// invisible — reported by the user as "I have never seen it", which is
    /// exactly right and had nothing to do with their four wallets.
    ///
    /// The floor itself was never the bug and is unchanged: a band claiming to
    /// be "where it moved" while covering a tenth of what it could see is the
    /// fake-status rule wearing a chart. Only its denominator was wrong.
    static let minPricedShare = 0.5

    /// A lane this small can't be drawn honestly (it would round to a
    /// hairline) and can't be read, so it joins the fold instead of becoming
    /// a decorative sliver. Expressed as a share of the band's own scale, not
    /// a dollar figure, so it means the same thing on a $500 week and a
    /// $500,000 one.
    static let minLaneShare = 0.02

    /// Why `band(legs:predating:)` answered nil — one case per gate, in the
    /// order the gates fire, so the slot can SAY which rather than stand
    /// empty (2026-09-03, prd §589, user: "the activity chart isn't showing.
    /// for me or vitalik").
    ///
    /// A blank slot has four causes that render identically, and only one —
    /// a read that failed to price moves it could have priced — is a bug. The
    /// other three are honest answers about the window, and §83 says an
    /// honest answer is drawn, never left as air. The probe and the screen
    /// both read THIS enum, so the log and the slot cannot disagree about why
    /// nothing was drawn.
    enum Decline: Equatable {
        /// No directional transfer in the window: swaps, self-moves and
        /// flagged spam carry no side. `predating` legs were set aside as
        /// older than price data (`WalletFlowSource.pricingEra`).
        case noLegs(predating: Int)
        /// Legs reached us and none carries a usable price — no scale.
        case nothingPriced(total: Int)
        /// Fewer than `minPricedShare` of the priceable legs are priced.
        case belowFloor(priced: Int, total: Int)
        /// Everything moved with one counterparty — a sentence, not a
        /// comparison.
        case oneLane
    }

    /// The reason the band declines, or nil when it draws. The exact inverse
    /// of `band` on every input — asserted by the harness, because two
    /// functions implementing one ladder is how a figure and its excuse come
    /// to describe different windows.
    static func decline(legs: [Leg], predating: Int = 0) -> Decline? {
        guard band(legs: legs, predating: predating) == nil else { return nil }
        if legs.isEmpty { return .noLegs(predating: predating) }
        let priced = legs.filter { leg in
            guard let usd = leg.usd, usd > 0, usd.isFinite else { return false }
            return true
        }.count
        if priced == 0 { return .nothingPriced(total: legs.count) }
        if Double(priced) / Double(legs.count) < minPricedShare {
            return .belowFloor(priced: priced, total: legs.count)
        }
        return .oneLane
    }

    /// Groups legs into a drawable band, or nil when there's nothing worth
    /// drawing.
    ///
    /// Declines (returns nil) when no leg carried a price — a band with no
    /// scale is not a smaller band, it's a different claim — or when fewer
    /// than two lanes survive, since one lane is a sentence and this is a
    /// comparison.
    /// `predating` is how many legs the adapter dropped as older than price
    /// data — they never reach the floor, and are carried only so the card can
    /// say they exist.
    static func band(legs: [Leg], predating: Int = 0) -> Band? {
        let unpriced = legs.filter { $0.usd == nil }.count
        let priced = legs.compactMap { leg -> (Leg, Double)? in
            guard let usd = leg.usd, usd > 0, usd.isFinite else { return nil }
            return (leg, usd)
        }
        guard !priced.isEmpty else { return nil }
        // Enough of the window has to be priced for the picture to be about
        // the window — see `minPricedShare`. The footnote alone doesn't undo a
        // confident five-lane band drawn over a tenth of the moves.
        guard Double(priced.count) / Double(legs.count) >= minPricedShare else { return nil }

        let inTotal = priced.filter { $0.0.received }.reduce(0.0) { $0 + $1.1 }
        let outTotal = priced.filter { !$0.0.received }.reduce(0.0) { $0 + $1.1 }
        let scale = max(inTotal, outTotal)
        guard scale > 0 else { return nil }

        let inLanes = lanes(from: priced.filter { $0.0.received },
                            side: "in", scale: scale)
        let outLanes = lanes(from: priced.filter { !$0.0.received },
                             side: "out", scale: scale)
        let band = Band(inLanes: inLanes, outLanes: outLanes,
                        inUSD: inTotal, outUSD: outTotal, unpricedCount: unpriced,
                        predatingCount: predating)
        guard band.laneCount >= 2 else { return nil }
        return band
    }

    /// How tall each lane's slab draws on one side of the band.
    ///
    /// Pure, and here rather than in the view, because it is the one part of
    /// this card that can fail INVISIBLY: a naive `max(minHeight, share ×
    /// available)` overflows its box whenever small lanes take the floor —
    /// four lanes at 94/2/2/2 need 134pt of a 123pt side — and the surplus
    /// clips silently off the bottom of the card, which reads as "the last
    /// counterparty is missing" rather than as a layout bug.
    ///
    /// So the floors are allocated FIRST and only the remainder is shared out
    /// by value. That makes the sum exactly the space available (shares sum to
    /// 1) while still guaranteeing every lane a readable slab.
    ///
    /// `sideTotal` is this side's dollars, `scaleUSD` the band's shared scale
    /// — so the smaller side occupies proportionally less height, which is the
    /// band's whole claim.
    /// One side's slab heights AND the gap to stack them with. Both together,
    /// because the view stacking with a gap the model didn't budget for is
    /// exactly how the two disagree: a side worth 2% of the scale is 2.6pt
    /// tall, which a fixed 3pt gap alone already overruns.
    struct SideLayout: Equatable {
        let heights: [Double]
        let gap: Double
        /// What the stack actually occupies, gaps included.
        var used: Double {
            heights.reduce(0, +) + gap * Double(max(0, heights.count - 1))
        }
    }

    static func laneHeights(lanes: [Lane], sideTotal: Double, scaleUSD: Double,
                            bandHeight: Double, laneGap: Double,
                            minHeight: Double) -> SideLayout {
        guard !lanes.isEmpty, scaleUSD > 0, sideTotal > 0, bandHeight > 0 else {
            return SideLayout(heights: Array(repeating: 0, count: lanes.count), gap: 0)
        }
        let sideHeight = bandHeight * (sideTotal / scaleUSD)
        let gapCount = Double(lanes.count - 1)
        // The gap yields before the slabs do. Air between bars is a nicety;
        // the bars are the measurement, so a side too thin to afford both
        // spends what it has on the thing that carries meaning.
        let gap = gapCount > 0
            ? min(laneGap, max(0, sideHeight * 0.25) / gapCount)
            : 0
        let drawable = max(0, sideHeight - gap * gapCount)
        // Still too little room to honour the floors — split what there is
        // evenly rather than overflowing.
        guard drawable >= minHeight * Double(lanes.count) else {
            return SideLayout(
                heights: Array(repeating: drawable / Double(lanes.count), count: lanes.count),
                gap: gap)
        }
        let flexible = drawable - minHeight * Double(lanes.count)
        return SideLayout(heights: lanes.map { minHeight + flexible * ($0.usd / sideTotal) },
                          gap: gap)
    }

    /// One counterparty's running total while a side is being folded. A named
    /// struct rather than a tuple: the tuple form of this pipeline defeated
    /// the type checker outright ("unable to type-check in reasonable time").
    private struct Ranked {
        let key: String
        let name: String
        let usd: Double
        let count: Int
    }

    /// One side's lanes, biggest first, tail folded.
    private static func lanes(from priced: [(Leg, Double)],
                              side: String, scale: Double) -> [Lane] {
        guard !priced.isEmpty else { return [] }

        var totals: [String: (name: String, usd: Double, count: Int)] = [:]
        for (leg, usd) in priced {
            var entry = totals[leg.key] ?? (leg.name, 0, 0)
            entry.usd += usd
            entry.count += 1
            // The first spelling seen wins, so a lane's name can't flicker
            // between passes when one leg resolved a name and another didn't.
            if entry.name.isEmpty { entry.name = leg.name }
            totals[leg.key] = entry
        }

        // Sorted by value, then by key — never by dictionary order, which is
        // not stable across launches and would reshuffle the band for free.
        var ranked: [Ranked] = []
        for (key, entry) in totals {
            ranked.append(Ranked(key: key, name: entry.name, usd: entry.usd, count: entry.count))
        }
        ranked.sort { $0.usd == $1.usd ? $0.key < $1.key : $0.usd > $1.usd }

        var kept: [Lane] = []
        var folded: (usd: Double, count: Int) = (0, 0)
        for entry in ranked {
            let tooSmall = entry.usd / scale < minLaneShare
            if kept.count < laneLimit && !tooSmall {
                kept.append(Lane(id: "\(side):\(entry.key)", name: entry.name,
                                 usd: entry.usd, count: entry.count, isOther: false))
            } else {
                folded.usd += entry.usd
                folded.count += entry.count
            }
        }
        if folded.count > 0 {
            kept.append(Lane(id: "\(side):other", name: String(localized: "Other"),
                             usd: folded.usd, count: folded.count, isOther: true))
        }
        return kept
    }
}
