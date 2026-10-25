import SwiftUI

/// A followed thing's face — a person, a subscription, a token: its logo,
/// else its first letters on the tint. Kept from Markets (§1529) for the
/// screens that still draw one.
/// A stock's logo is drawn on white, because company marks are made for a
/// light ground and a black one vanishes on the dark page.
struct WatchFace: View {
    let url: String?
    let lettered: String
    var size: CGFloat = DS.Face.rowCircle
    var onWhite = false
    /// A system symbol drawn in place of the logo — Apple's, which no third
    /// party may draw as a picture (`systemMark`).
    var symbol: String? = nil
    /// The image failed: the letters stand (measured 2026-10-21, prd §1467:
    /// CoinPaprika's logo host resolves and then times out, so every
    /// followed coin wore the broken-image glyph until this).
    @State private var dead = false

    /// The company whose mark is a system symbol, by ticker: Apple wears
    /// `apple.logo`, the glyph an Apple charge wears (prd §1202), never a
    /// fetched or drawn copy of its logo.
    static func systemMark(forTicker ticker: String) -> String? {
        ticker.uppercased() == "AAPL" ? BridgeGlyph.symbol(for: "Apple") : nil
    }

    var body: some View {
        ZStack {
            Circle().fill(onWhite ? Color.white : DS.brandInk.opacity(0.85))
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(onWhite ? Color.black : Color.white)
            } else if url == nil || dead {
                Text(verbatim: String(lettered.prefix(2)).uppercased())
                    .font(.system(size: size * 0.38, weight: .bold))
                    .foregroundStyle(onWhite ? Color.black : Color.white)
            }
            if symbol == nil, !dead, let url {
                RemoteThumb(urlString: url, size: onWhite ? size * 0.72 : size,
                            fallback: TokenWatch.source, circular: !onWhite,
                            onFailed: { dead = true })
                    .onChange(of: url) { _, _ in dead = false }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
