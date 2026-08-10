import SwiftUI

/// A small identity mark for a token or a counterparty — the real brand asset
/// where the app bundles one, an honestly-neutral monogram where it doesn't
/// (2026-08-01, user ruling: "reuse BridgeIcon where the name is a known app").
///
/// The rule is `TokenIcon`'s, kept deliberately (and was `TokenHue`'s too,
/// for color, before that file's 2026-08-10 retirement in favor of the
/// neutral ink ramp every treemap now shares): a name OUTSIDE the known set
/// gets no invented artwork and no invented colour. A
/// hashed hue would look exactly as confident as a real one while meaning
/// nothing — so an unknown counterparty wears the neutral fill every other
/// unnamed thing in this app wears, and half a row of real logos beside half a
/// row of neutral discs is the honest picture of what we actually know.
///
/// Nothing here fetches. Every surface that uses it is a scrolling list, and
/// per-row image requests would mean a new host in `NetworkReach` plus network
/// traffic on a scroll — refused for the same reason the website inlines its
/// icons. When a symbol has no bundled mark the answer is to BUNDLE one, not
/// to reach for it at render time.
struct AssetMark: View {
    /// A token symbol ("ETH", "USDC") or a counterparty/protocol name
    /// ("Coinbase", "Aave").
    let name: String
    var size: CGFloat = 20
    /// Colours the MONOGRAM branch only — a real brand mark is the brand's own
    /// colours and never gets re-tinted. nil keeps the neutral disc.
    var tint: Color? = nil
    /// A small filled dot on the trailing edge, for a row whose mark used to
    /// carry its state in its tint (`WalletLendingCard`'s at-risk orange).
    /// Real artwork can't be tinted without lying about the brand, so the
    /// state moves to a badge — `WalletRow`'s own flagged-badge grammar.
    var badge: Color? = nil

    /// Whether a real brand asset exists for this name. `BridgeIcon` already
    /// resolves and falls back on its own; this is asked separately so the
    /// caller can pick the NEUTRAL branch deliberately rather than get
    /// `BridgeIcon`'s app-shaped glyph fallback, which reads as "this is an
    /// app we know" for a name we don't.
    static func hasAsset(_ name: String) -> Bool {
        BrandMark.image(for: name) != nil
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
        Group {
            if let ui = BrandMark.image(for: name) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(tint.map { $0.opacity(0.16) } ?? DS.fillStrong)
                    .frame(width: size, height: size)
                    .overlay(
                        Text(monogram)
                            .font(.system(size: size * 0.40, weight: .semibold, design: .rounded))
                            .foregroundStyle(tint ?? DS.textSecondary)
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                    )
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let badge {
                Circle()
                    .fill(badge)
                    .frame(width: size * 0.3, height: size * 0.3)
                    // The page showing through, not a stroke — a hairline by
                    // another name is still a hairline.
                    .overlay(Circle().stroke(DS.page, lineWidth: size * 0.06))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Which bundled `brand-*` image a token symbol or protocol name resolves to —
/// the ONE resolver, shared by `AssetMark` (which falls back to a monogram)
/// and `TokenIcon` (which falls back to nothing).
///
/// It was two tables until 2026-08-04, and they disagreed: `AssetMark` aliased
/// wrapped forms while `TokenIcon` aliased only `btc`, so the holdings treemap
/// drew nothing at all for wstETH and cbBTC while the same symbol wore a real
/// mark one card below. One table means a mark added for either surface lands
/// on both.
enum BrandMark {
    /// Wrapped, bridged and staked forms wear their underlying asset's mark —
    /// the wrapper-shares-identity rule ("a wrapper is a representation, not
    /// a different identity", first stated for `TokenHue`'s color table)
    /// applied to artwork. Only forms whose target asset is actually bundled
    /// are listed; anything else falls through honestly.
    ///
    /// stETH and wstETH are NOT here: they have their own bundled marks now,
    /// and Lido's mark is a different thing from Ethereum's.
    private static let alias: [String: String] = [
        "usdbc": "usdc", "usdce": "usdc", "usdte": "usdt",
        "cbbtc": "wbtc", "btc": "wbtc",
        "wsol": "sol", "msol": "sol", "jitosol": "sol",
        "pol": "matic",
        // A protocol's token and the protocol share one mark — `HYPE` is
        // Hyperliquid's own logo, and the composition strip names the venue
        // "ether.fi Cash" where the roster names it "ether.fi".
        "hype": "hyperliquid", "aave-token": "aave",
        "etherfi-cash": "etherfi", "etherfi-liquid": "etherfi",
    ]

    static func slug(for name: String) -> String {
        let cleaned = name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: ".", with: "")
        return alias[cleaned] ?? cleaned
    }

    static func image(for name: String) -> UIImage? {
        UIImage(named: "brand-" + slug(for: name))
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
