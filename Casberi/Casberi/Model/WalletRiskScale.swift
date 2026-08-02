import Foundation

/// Every leveraged position on ONE axis — the distance-to-liquidation strip
/// (2026-08-01, ruled in from `design/wallet-viz`).
///
/// The room already states risk per protocol, each in its own units: Aave and
/// Morpho carry a health factor, Hyperliquid carries a percentage of mark
/// (that API has no HF at all). So "which of these is closest to the edge" was
/// arithmetic the person had to do in their head across three different
/// scales, which is exactly the question a wallet screen should answer.
///
/// ## The axis, and why it isn't invented
///
/// The one quantity all three genuinely share is HEADROOM: the fraction the
/// price can move against you before liquidation.
///
///   • A perp states it directly — `liquidationProximity` is `|mark − liq| / mark`.
///   • A health factor implies it. HF is collateral × threshold ÷ debt, so a
///     collateral value multiplied by `k` multiplies HF by `k`; liquidation is
///     HF = 1, which arrives at `k = 1/HF`. The value can therefore fall by
///     `1 − 1/HF` first.
///
/// Same quantity, two sources — so the strip compares like with like rather
/// than normalising two different measures onto a shared bar and hoping.
///
/// **The assumption, stated plainly:** `1 − 1/HF` is exact when the debt is
/// stable-denominated (the ordinary case — stablecoins borrowed against
/// volatile collateral) and an approximation when both sides move together
/// (ETH borrowed against staked ETH, where price moves barely shift HF at
/// all). That is why every dot still wears its protocol's OWN number, and why
/// no dot ever claims a specific "can fall X%" figure on screen: the axis
/// carries the ordering, the label carries the fact.
///
/// ## Why there is no shared danger threshold
///
/// The two alert thresholds already shipped are NOT the same headroom.
/// `DeFiRisk.floor` (HF 1.5) is 33% of headroom; `HyperliquidDeFi
/// .riskProximity` is 15%. A single gradient with one crossing point would
/// therefore have to disagree with one of the two sweeps — painting a position
/// calm that the app had already alerted on, or the reverse. So each dot's
/// alarm state comes from ITS OWN protocol's rule, passed in by the caller,
/// and the track carries no crossing point of its own.
///
/// PURE AND FOUNDATION-ONLY, on purpose: no book types, no thresholds of its
/// own. The adapter that reads the live books lives in
/// `WalletRiskScaleSource.swift`, so this file compiles standalone and
/// `scripts/wallet-viz-selftest.sh` exercises the shipped source rather than
/// a copy.
enum WalletRiskScale {

    /// One leveraged position's seat on the axis.
    struct Entry: Identifiable, Equatable {
        let id: String
        /// "Aave", "Morpho", "Hyperliquid · ETH" — what the dot is called.
        let label: String
        /// The protocol's OWN number, in the protocol's own words ("Health
        /// 1.62", "18% from liquidation"). The strip never restates this in a
        /// unit the protocol doesn't use.
        let detail: String
        /// Fraction the price can move against this position before
        /// liquidation, 0…1. 0 = at the edge, 1 = untouchable.
        let headroom: Double
        /// Whether this position has crossed the threshold ITS OWN protocol
        /// sweep alerts on. Never derived from `headroom` — see the type doc.
        let atRisk: Bool

        /// Where the dot sits, 0 = comfortable … 1 = liquidation. The axis is
        /// simply headroom read from the other end.
        var axis: Double { 1 - headroom }
    }

    /// Headroom implied by a health factor, or nil when there is none to
    /// imply. A position already at or under liquidation reads 0 rather than
    /// a negative number — it is at the edge, and there is no "past" the edge
    /// to draw.
    static func headroom(healthFactor hf: Double) -> Double? {
        guard hf.isFinite, hf > 0 else { return nil }
        return max(0, min(1, 1 - 1 / hf))
    }

    /// Headroom a perp states directly. Passed through rather than
    /// recomputed, so this file can't disagree with `HyperliquidDeFi
    /// .Position.liquidationProximity` about what the number means.
    static func headroom(proximity: Double) -> Double? {
        guard proximity.isFinite, proximity >= 0 else { return nil }
        return max(0, min(1, proximity))
    }

    /// A lending position's dot. `hf` is the protocol's own health factor;
    /// `riskFloor` is the protocol's own alert line (`DeFiRisk.floor`), passed
    /// in rather than read here so the pure file owns no threshold.
    static func lendingEntry(id: String, label: String, hf: Double,
                             riskFloor: Double) -> Entry? {
        guard let headroom = headroom(healthFactor: hf) else { return nil }
        return Entry(id: id, label: label,
                     detail: String(localized: "Health \(decimal(hf))"),
                     headroom: headroom, atRisk: hf < riskFloor)
    }

    /// A perp's dot. `proximity` and `riskProximity` both come from
    /// `HyperliquidDeFi`, for the same reason.
    static func perpEntry(id: String, label: String, proximity: Double,
                          riskProximity: Double) -> Entry? {
        guard let headroom = headroom(proximity: proximity) else { return nil }
        let pct = Int((proximity * 100).rounded())
        return Entry(id: id, label: label,
                     detail: String(localized: "\(pct)% from liquidation"),
                     headroom: headroom, atRisk: proximity < riskProximity)
    }

    /// The strip itself — worst first — or nil when there is nothing to
    /// compare.
    ///
    /// Declines at fewer than two positions on purpose: with one, the cards
    /// below already state it in full, and a lone dot on an axis is a health
    /// factor wearing a chart. This is the same "a hero declines its slot"
    /// rule every room card here keeps.
    static func strip(_ entries: [Entry]) -> [Entry]? {
        guard entries.count >= 2 else { return nil }
        // Sorted by axis descending (closest to liquidation first), then by id
        // so two identical positions can't reshuffle between passes.
        return entries.sorted {
            $0.axis == $1.axis ? $0.id < $1.id : $0.axis > $1.axis
        }
    }

    /// "2.4" / "1.62" — a health factor the way both protocols print it, two
    /// decimals only when the second is doing work.
    private static func decimal(_ v: Double) -> String {
        let rounded = (v * 100).rounded() / 100
        if rounded >= 100 { return String(Int(rounded)) }
        return rounded == rounded.rounded()
            ? String(format: "%.1f", rounded)
            : String(format: "%.2f", rounded)
    }
}
