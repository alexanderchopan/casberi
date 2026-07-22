import SwiftUI

/// A token's own brand color, for the holdings treemap's cell wash (prd §157,
/// 2026-07-21 — treatment C of the wallet-look mocks).
///
/// The rule this follows is `TokenIcon`'s, deliberately: a symbol OUTSIDE the
/// known set gets **nothing** — the cell keeps the neutral surface and the
/// magnitude wash it has always worn. A guessed hue (hashing the ticker into a
/// color, say) would look identical to a real one while meaning nothing, and
/// the whole point of this pass is hue doing IDENTITY work. Half a treemap in
/// real colors and half in neutral is the honest picture of what we know.
///
/// Values are each project's own published brand color, sampled from their
/// marks — the same source `brand-*.imageset` came from. Kept as a flat table
/// rather than read off the bundled image: a mark's average pixel is muddy
/// (USDC's is mostly white), and these need to survive as a 10%-opacity wash
/// on black.
enum TokenHue {

    /// symbol (lowercased) → brand hex. Wrapped/bridged forms share their
    /// underlying asset's color (WETH is ETH's indigo, cbBTC is Bitcoin's
    /// orange) — a wrapper is a representation, not a different identity.
    private static let table: [String: String] = [
        "eth": "#627eea", "weth": "#627eea", "steth": "#00a3ff", "wsteth": "#00a3ff",
        "btc": "#f7931a", "wbtc": "#f7931a", "cbbtc": "#f7931a", "tbtc": "#f7931a",
        "usdc": "#2775ca", "usdbc": "#2775ca",
        "usdt": "#26a17b",
        "dai": "#f5ac37",
        "sol": "#14f195", "wsol": "#14f195", "msol": "#14f195", "jitosol": "#14f195",
        "matic": "#8247e5", "pol": "#8247e5",
        "arb": "#12aaff",
        "op": "#ff0420",
        "link": "#2a5ada",
        "uni": "#ff007a",
        "aave": "#b6509e",
        "mkr": "#1aab9b",
        "ldo": "#00a3ff",
        "ens": "#5298ff",
        "crv": "#f2c94c",
        "jup": "#c7f284",
        "degen": "#a36efd",
        "rlusd": "#0080ff",
        "xaut": "#d4af37", "paxg": "#d4af37",
    ]

    /// The token's brand color, or nil when we don't actually know it.
    static func brand(for symbol: String) -> Color? {
        table[symbol.lowercased()].map(Color.fixed)
    }

    /// The cell wash for a token holding: its brand color as a soft diagonal,
    /// with opacity scaled by `share` (0…1 of the map's total) so MAGNITUDE
    /// still rides the fill exactly as `DS.tint(magnitude:)` made it — the
    /// biggest position is both the biggest cell and the most saturated one.
    /// Hue changed; the encoding did not.
    static func wash(for symbol: String, share: Double) -> LinearGradient? {
        guard let hue = brand(for: symbol) else { return nil }
        let t = min(max(share, 0), 1)
        return LinearGradient(colors: [hue.opacity(0.10 + 0.30 * t),
                                       hue.opacity(0.04 + 0.10 * t)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
