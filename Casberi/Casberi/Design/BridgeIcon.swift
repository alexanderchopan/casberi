import SwiftUI

/// A bridge/app icon for the catalog — the App-Store move. If a real brand asset
/// is bundled (an image named `brand-<name>` in the asset catalog, e.g.
/// `brand-github`, `brand-notion`), it renders as the actual app icon; otherwise
/// it falls back to the SF-symbol-on-brand-color squircle used everywhere else.
///
/// Legal note: third-party brand logos are permitted in an integration directory
/// under each brand's guidelines — drop the official asset in and it appears.
/// Apple's OWN apps (Photos/Calendar/Reminders/Music) keep the SF fallback:
/// their icons are restricted, so we never bundle those, and the symbol shows.
struct BridgeIcon: View {
    let name: String
    var size: CGFloat = 44
    /// Clip to a circle instead of the app-icon squircle — for chip
    /// contexts, where a square asset inside a round chip read as a square
    /// floating in a circle (report 2026-07-10).
    var circular: Bool = false

    private var assetName: String {
        "brand-" + name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: ".", with: "")
    }

    private var shape: AnyShape {
        circular ? AnyShape(Circle())
                 : AnyShape(RoundedRectangle(cornerRadius: DS.Radius.appIcon(size), style: .continuous))
    }

    var body: some View {
        if let ui = UIImage(named: assetName) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(shape)
        } else {
            let brand = BridgeGlyph.color(for: name)
            // SOLID, like an app icon — the tint fill has now died three
            // times (composer v2 2026-07-12: "solid reads as an app, tint
            // read as a stain"; the Apps shelf lights connected seats
            // saturated; bold bleeds 2026-07-13: a translucent chip simply
            // VANISHED on its own color field — Wallet/Reminders/Tokens/
            // Photos were unreadable on a shaped feed). The composer tool
            // tiles' exact recipe: brand fill, white glyph, a whisper of
            // top sheen. Reads on any field, both themes, no per-scheme
            // darkening needed.
            shape
                .fill(brand)
                .overlay(
                    shape.fill(LinearGradient(colors: [.white.opacity(0.16), .clear],
                                              startPoint: .top, endPoint: .center))
                )
                .frame(width: size, height: size)
                .overlay(
                    // 0.45 read as undersized for glyphs with more internal
                    // whitespace ("checklist", "photo") — several symbols
                    // looked lost in their badge (report 2026-07-09).
                    Image(systemName: BridgeGlyph.symbol(for: name))
                        .font(.system(size: size * 0.54, weight: .semibold))
                        .foregroundStyle(BridgeGlyph.glyphTint(for: name) ?? .white)
                )
        }
    }
}

/// A token's mark for the wallet holdings treemap — a small bundled set
/// (`brand-eth`, `brand-usdc`, …) downloaded once from Trust Wallet's public
/// asset repo, not fetched live (2026-07-09: Alchemy's own logo field came
/// back null for nearly everything, including WETH and USDC — too sparse to
/// build on). Renders nothing at all for a symbol outside the bundled set —
/// text-only stays the honest fallback, never a wrong or generic mark.
struct TokenIcon: View {
    let symbol: String
    var size: CGFloat = 20

    var body: some View {
        if let ui = UIImage(named: "brand-" + symbol.lowercased()) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(Circle())
        }
    }
}
