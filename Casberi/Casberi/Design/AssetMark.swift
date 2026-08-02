import SwiftUI

/// A small identity mark for a token or a counterparty — the real brand asset
/// where the app bundles one, an honestly-neutral monogram where it doesn't
/// (2026-08-01, user ruling: "reuse BridgeIcon where the name is a known app").
///
/// The rule is `TokenHue`'s and `TokenIcon`'s, kept deliberately: a name
/// OUTSIDE the known set gets no invented artwork and no invented colour. A
/// hashed hue would look exactly as confident as a real one while meaning
/// nothing — so an unknown counterparty wears the neutral fill every other
/// unnamed thing in this app wears, and half a row of real logos beside half a
/// row of neutral discs is the honest picture of what we actually know.
///
/// Nothing here fetches. Both surfaces that use it (the flow band and the
/// Liquidity card) are scrolling lists, and per-row image requests would mean
/// a new host in `NetworkReach` plus network traffic on a scroll — refused for
/// the same reason the website inlines its icons.
struct AssetMark: View {
    /// A token symbol ("ETH", "USDC") or a counterparty name ("Coinbase").
    let name: String
    var size: CGFloat = 20

    /// Whether a real brand asset exists for this name. `BridgeIcon` already
    /// resolves and falls back on its own; this is asked separately so the
    /// caller can pick the NEUTRAL branch deliberately rather than get
    /// `BridgeIcon`'s app-shaped glyph fallback, which reads as "this is an
    /// app we know" for a name we don't.
    static func hasAsset(_ name: String) -> Bool {
        UIImage(named: assetName(name)) != nil
    }

    /// Wrapped and bridged forms wear their underlying asset's mark — the
    /// `TokenHue` rule ("a wrapper is a representation, not a different
    /// identity") applied to artwork. Only forms whose target asset is
    /// actually bundled are listed; anything else falls through to the
    /// monogram honestly.
    private static let alias: [String: String] = [
        "usdbc": "usdc", "usdce": "usdc", "usdte": "usdt",
        "steth": "eth", "wsteth": "eth", "cbbtc": "wbtc", "btc": "wbtc",
    ]

    private static func assetName(_ name: String) -> String {
        let slug = name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: ".", with: "")
        return "brand-" + (alias[slug] ?? slug)
    }

    /// One or two letters — enough to tell two lanes apart, never enough to
    /// pretend to be a logo.
    private var monogram: String {
        let cleaned = name.trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return "?" }
        // A multi-word counterparty takes its initials ("Cold Wallet" → CW);
        // a single word takes its first two ("Rent" → Re), which reads better
        // than one lonely capital at this size.
        let words = cleaned.split(separator: " ")
        if words.count >= 2 {
            return words.prefix(2).compactMap { $0.first }.map(String.init)
                .joined().uppercased()
        }
        return String(cleaned.prefix(2)).uppercased()
    }

    var body: some View {
        if Self.hasAsset(name) {
            BridgeIcon(name: name, size: size, circular: true)
        } else {
            Circle()
                .fill(DS.fillStrong)
                .frame(width: size, height: size)
                .overlay(
                    Text(monogram)
                        .font(.system(size: size * 0.40, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.textSecondary)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                )
        }
    }
}

/// A liquidity pair's two assets, overlapped the way every exchange draws a
/// pair (2026-08-01). The second disc carries a page-coloured ring so the two
/// read as two even when their brand colours are close — the page showing
/// through, not a stroke, so the no-hairlines rule stands.
struct AssetPairMark: View {
    let first: String
    let second: String
    var size: CGFloat = 22

    /// How far the second disc sits behind the first — enough to read as a
    /// pair, not so far that the row's title has to move.
    private var overlap: CGFloat { size * 0.34 }

    var body: some View {
        HStack(spacing: -overlap) {
            AssetMark(name: first, size: size)
                .zIndex(1)
            AssetMark(name: second, size: size)
                .overlay(Circle().stroke(DS.page, lineWidth: 1.5))
        }
        .accessibilityElement()
        .accessibilityLabel("\(first) and \(second)")
    }
}
