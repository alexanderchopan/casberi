import Foundation

/// Borrowing risk across both lending protocols, in one place (2026-07-25).
///
/// The 1.5 health-factor margin had quietly reached FOUR copies — `WalletDeFi`
/// and `MorphoDeFi` each held a private `riskThreshold` for their own
/// risk-crossing alerts (Morpho's comment already pointed at Aave's, which is
/// the codebase noticing the duplication without fixing it), `WalletWarnings`
/// hardcoded it twice in its roll-up, and prd §214's brief lede wanted the
/// same line for its top rung. A threshold that decides whether the app tells
/// you your position is in danger must not be able to disagree with itself, so
/// it lives here and everything reads it.
///
/// The same went for the READ. `WalletDeFiAsk.answer` and the brief's lede
/// both fetched Aave and Morpho concurrently, flattened each into an identical
/// local `Debt` struct, and took the minimum health factor — the same twenty
/// lines twice. That flattening is now `debts(aave:morpho:)`, which is pure,
/// and the fetch is `read(addresses:)`. Callers still do their own thing with
/// the rest of the book (the ask also reports deposits; the brief doesn't), so
/// only the duplicated half moved.
enum DeFiRisk {

    /// The health-factor line below which a borrow is worth a heads-up. NOT
    /// the liquidation point — that's 1.0; 1.5 is the standing margin before
    /// it gets there, which is the number both protocols' alerts, the Wallet
    /// room's warnings and the brief's lede all mean by "at risk".
    static let floor: Double = 1.5

    /// One open borrow, wherever it lives.
    struct Debt {
        let hf: Double
        let protocolName: String
        let network: String
    }

    /// Both protocols, read concurrently — the caller pays the slower one
    /// rather than the sum. `addresses` must already be resolved hex.
    static func read(addresses: [String]) async -> (aave: [WalletDeFi.Position],
                                                    morpho: MorphoDeFi.Book) {
        async let aaveRead = WalletDeFi.positions(addresses: addresses)
        async let morphoRead = MorphoDeFi.book(addresses: addresses)
        return (await aaveRead, await morphoRead ?? MorphoDeFi.Book())
    }

    /// Every open borrow across both books, WORST FIRST. Pure, so a caller
    /// that already holds the reads (the Wallet room does) doesn't pay for
    /// them twice. A position with no debt carries no health factor and
    /// simply isn't here — it can't be "at risk" of losing nothing.
    static func debts(aave: [WalletDeFi.Position], morpho: MorphoDeFi.Book) -> [Debt] {
        var out: [Debt] = aave.compactMap { position in
            position.healthFactor.map {
                Debt(hf: $0, protocolName: "Aave", network: position.network)
            }
        }
        out += morpho.positions.compactMap { position in
            position.healthFactor.map {
                Debt(hf: $0, protocolName: "Morpho", network: position.network)
            }
        }
        return out.sorted { $0.hf < $1.hf }
    }

    /// The worst borrow, and ONLY when it has actually crossed `floor` — the
    /// shape a headline wants, where "nothing is wrong" and "nothing is
    /// borrowed" are the same answer: no line.
    static func atRisk(addresses: [String]) async -> Debt? {
        let (aave, morpho) = await read(addresses: addresses)
        guard let worst = debts(aave: aave, morpho: morpho).first, worst.hf < floor
        else { return nil }
        return worst
    }
}
