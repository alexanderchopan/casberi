import Foundation

/// How much of a portfolio is sitting still — the stable share (2026-08-01,
/// ruled in from `design/wallet-viz`).
///
/// This shipped as the surviving half of a two-bar "splits" card. The other
/// half — a by-chain breakdown — was cut in review as trivia: knowing 27% of
/// the book is on Base changes no decision, while the treemap and the
/// concentration line already answer "too much in one thing". What survived
/// answers something neither of them does — how exposed the whole book is —
/// and it earns one quiet line rather than a card, in the concentration
/// line's own idiom.
///
/// PURE AND FOUNDATION-ONLY: `WalletPortfolio` calls in, nothing calls out,
/// so the shipped source compiles standalone under
/// `scripts/wallet-viz-selftest.sh`.
enum WalletStables {

    /// The symbols that count as stable — an EXPLICIT set, never a prefix or
    /// substring rule.
    ///
    /// A `hasPrefix("USD")` test would be shorter and would also swallow
    /// every scam token that names itself `USDCoin`, `USDT_CLAIM` or similar —
    /// and this app already knows spoofed symbols are a live problem (it
    /// raises a `spoofedSymbol` warning for exactly that). A set can be read,
    /// audited and argued with; a prefix rule quietly decides.
    ///
    /// Fiat-referenced only. A yield-bearing wrapper (sDAI, sUSDe) is
    /// deliberately IN — it tracks the same unit and the person holding it
    /// means it as dollars — while a governance token of a stablecoin
    /// protocol is not, however closely it is associated.
    static let symbols: Set<String> = [
        // US dollar
        "USDC", "USDC.E", "USDBC", "USDT", "USDT.E", "DAI", "SDAI", "USDS", "SUSDS",
        "USDE", "SUSDE", "PYUSD", "TUSD", "FDUSD", "LUSD", "SUSD", "CRVUSD",
        "GHO", "FRAX", "BUSD", "RLUSD", "USDG", "USDP", "GUSD", "USDD", "USD0",
        "DOLA", "MIM", "USDL", "AUSD", "USDF", "BUIDL", "USDY",
        // Euro, sterling and the cards that settle in them
        "EURE", "EURC", "EURS", "AGEUR", "EURT", "GBPE", "GBPT",
    ]

    /// Whether a held symbol is stable. Case-folded because the symbol
    /// reaching us is whatever the token contract says it is, and casing is
    /// not consistent across chains or sources.
    static func isStable(_ symbol: String) -> Bool {
        symbols.contains(symbol.trimmingCharacters(in: .whitespaces).uppercased())
    }

    /// The stable share of a book, 0…1, or nil when there is no share worth
    /// stating.
    ///
    /// Declines when the rounded percentage would be 0 or 100 — the same guard
    /// `WalletPortfolio.concentrationLine` keeps, and for the same reason: $5
    /// of USDC in a $48,000 book rounds to 0%, and a line reading "0% stable"
    /// beside a real stablecoin holding is a fake status, not a rounding
    /// nicety. At the other end, "100% stable" is what a book of nothing but
    /// dollars looks like, where the treemap has already said so with one
    /// cell.
    ///
    /// Note this counts what the portfolio could PRICE, which is what every
    /// other number on this screen counts too — an unpriced holding is absent
    /// from the denominator rather than assumed volatile.
    static func share(positions: [(symbol: String, usd: Double)],
                      totalUSD: Double) -> Double? {
        guard totalUSD > 0, positions.count >= 2 else { return nil }
        let stable = positions
            .filter { isStable($0.symbol) }
            .reduce(0.0) { $0 + max(0, $1.usd) }
        guard stable > 0 else { return nil }
        let share = stable / totalUSD
        let pct = Int((share * 100).rounded())
        guard pct > 0, pct < 100 else { return nil }
        return share
    }
}
