import Foundation

/// Reads the live lending and perp books into `WalletRiskScale.Entry` values —
/// the half of the risk strip that knows about protocols, kept apart from the
/// axis arithmetic so `WalletRiskScale.swift` stays Foundation-only and
/// harness-testable (`scripts/wallet-viz-selftest.sh`).
///
/// This is also the single place the two shipped alert thresholds are read.
/// They are passed DOWN into the pure axis rather than duplicated inside it,
/// so the strip can never call a position calm that its own protocol's sweep
/// has already alerted on — see `WalletRiskScale`'s type doc for why one
/// shared threshold could not have served both.
enum WalletRiskScaleSource {

    /// Every leveraged position on one axis, worst first — or nil when there
    /// are fewer than two to compare.
    static func strip(aave: [WalletDeFi.Position],
                      morpho: MorphoDeFi.Book,
                      hyperliquid: HyperliquidDeFi.Book) -> [WalletRiskScale.Entry]? {
        WalletRiskScale.strip(entries(aave: aave, morpho: morpho, hyperliquid: hyperliquid))
    }

    /// `-riskStripProbe YES` — one line per fact.
    ///
    /// Reports what each book CONTAINED as well as what became a dot, because
    /// the two most likely failures look identical on screen (an empty strip):
    /// no leveraged positions at all, versus positions whose health factor
    /// never arrived. It also prints each dot's own protocol threshold verdict
    /// beside its axis, which is the machine-checkable form of this card's
    /// central promise — that it can never call a position calm that its own
    /// protocol's sweep has already alerted on.
    static func probeLines(aave: [WalletDeFi.Position],
                           morpho: MorphoDeFi.Book,
                           hyperliquid: HyperliquidDeFi.Book) -> [String] {
        let all = entries(aave: aave, morpho: morpho, hyperliquid: hyperliquid)
        var out = [
            "books: aave=\(aave.count) morphoMarkets=\(morpho.positions.count) "
                + "perps=\(hyperliquid.positions.count) → dots=\(all.count)",
            String(format: "thresholds: lending hf<%.2f, perp proximity<%.2f",
                   DeFiRisk.floor, HyperliquidDeFi.riskProximity),
        ]
        // Qualified: a bare `strip(all)` binds to this type's OWN
        // `strip(aave:morpho:hyperliquid:)` above, not the pure one.
        guard let strip = WalletRiskScale.strip(all) else {
            out.append(all.isEmpty
                ? "DECLINED: no position carried a usable health factor or liquidation price"
                : "DECLINED: only one position — the cards below already state it")
            return out
        }
        for entry in strip {
            out.append(String(format: "dot | %@ — %@ · headroom=%.3f axis=%.3f %@",
                              entry.label, entry.detail, entry.headroom, entry.axis,
                              entry.atRisk ? "AT-RISK" : "ok"))
        }
        return out
    }

    /// The dots, unsorted. A position with no debt carries no health factor
    /// and contributes nothing — it can't be liquidated, so it has no seat on
    /// a liquidation axis (the ruling `DeFiRisk.debts` already keeps).
    static func entries(aave: [WalletDeFi.Position],
                        morpho: MorphoDeFi.Book,
                        hyperliquid: HyperliquidDeFi.Book) -> [WalletRiskScale.Entry] {
        var out: [WalletRiskScale.Entry] = []

        // Aave and Spark share this book and each names itself, so the dot
        // wears the protocol the person actually borrowed from rather than a
        // merged "lending".
        for position in aave {
            guard let hf = position.healthFactor else { continue }
            let id = "aave:\(position.protocolName):\(position.network):\(position.address)"
            if let entry = WalletRiskScale.lendingEntry(
                id: id, label: position.protocolName, hf: hf, riskFloor: DeFiRisk.floor) {
                out.append(entry)
            }
        }

        // Morpho is isolated markets, so the market is the position — two
        // borrows in different markets are two dots, and merging them would
        // invent a health factor neither has.
        for position in morpho.positions {
            guard let hf = position.healthFactor else { continue }
            let id = "morpho:\(position.network):\(position.address):\(position.marketLabel)"
            let label = String(localized: "Morpho · \(position.marketLabel)")
            if let entry = WalletRiskScale.lendingEntry(
                id: id, label: label, hf: hf, riskFloor: DeFiRisk.floor) {
                out.append(entry)
            }
        }

        // Perps. `liquidationProximity` is passed straight through — the
        // property already IS the headroom, and recomputing it here is how the
        // card and the sweep would start meaning different things.
        for position in hyperliquid.positions {
            guard let proximity = position.liquidationProximity else { continue }
            let id = "hl:\(position.account):\(position.coin)"
            let side = position.isLong ? String(localized: "long")
                                       : String(localized: "short")
            let label = String(localized: "\(position.coin) \(side)")
            if let entry = WalletRiskScale.perpEntry(
                id: id, label: label, proximity: proximity,
                riskProximity: HyperliquidDeFi.riskProximity) {
                out.append(entry)
            }
        }

        return out
    }
}
