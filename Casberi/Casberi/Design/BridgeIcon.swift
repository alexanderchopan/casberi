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
    @Environment(\.colorScheme) private var scheme

    private var assetName: String {
        "brand-" + name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: ".", with: "")
    }

    var body: some View {
        let radius = DS.Radius.appIcon(size)
        if let ui = UIImage(named: assetName) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            let brand = BridgeGlyph.color(for: name)
            // Light mode pulls bright brand hues (Notes yellow, Reminders
            // orange) toward black and deepens the fill so the glyph reads
            // on light chips and cards.
            let glyph = scheme == .light ? brand.mix(with: .black, by: 0.35) : brand
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(brand.opacity(scheme == .light ? 0.24 : 0.18))
                .frame(width: size, height: size)
                .overlay(
                    // 0.45 read as undersized for glyphs with more internal
                    // whitespace ("checklist", "photo") — several symbols
                    // looked lost in their badge (report 2026-07-09).
                    Image(systemName: BridgeGlyph.symbol(for: name))
                        .font(.system(size: size * 0.54,
                                      weight: scheme == .light ? .semibold : .medium))
                        .foregroundStyle(glyph)
                )
        }
    }
}
