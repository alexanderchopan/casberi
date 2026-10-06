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
/// **THE NAME AND THE IMAGE ARE RESOLVED ONCE PER BRAND, NOT PER BODY (prd
/// §668, 2026-09-10).** `assetName` folds diacritics and runs three
/// `replacingOccurrences` passes, and `UIImage(named:)` is a catalog lookup;
/// both ran in `body`, so both ran again for every mark on every body build —
/// 64 call sites, the feed's rows among them, and up to twenty venues in one
/// dock folder that rebuilds when the room lands. The brands are a closed set
/// of about ninety, so the memo is bounded by construction. `nil` is cached
/// too: a seat with no art must not re-miss the catalog on every pass.
@MainActor
private enum BridgeIconArt {
    private static var names: [String: String] = [:]
    private static var images: [String: UIImage?] = [:]

    static func assetName(for name: String) -> String {
        if let hit = names[name] { return hit }
        let made = "brand-" + Corpus.canonicalSource(name).lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: ".", with: "")
        names[name] = made
        return made
    }

    static func image(_ asset: String) -> UIImage? {
        if let hit = images[asset] { return hit }
        let found = UIImage(named: asset)
        images[asset] = found
        return found
    }
}

struct BridgeIcon: View {
    let name: String
    var size: CGFloat = 44
    /// Clip to a circle instead of the app-icon squircle — for chip
    /// contexts, where a square asset inside a round chip read as a square
    /// floating in a circle (report 2026-07-10).
    var circular: Bool = false
    /// A glyph drawn on the brand fill in place of the seat's own mark —
    /// `noteSymbol(for:)`'s answer for a note of yours, nil everywhere else.
    var symbol: String? = nil

    var assetName: String {
        // DIACRITICS ARE FOLDED (2026-08-27, "Ethrex Hegotá"). An asset
        // catalog name is a FILENAME, and macOS normalizes those to NFD while
        // a Swift literal is NFC — so `brand-ethrex-hegotá` is a lookup that
        // can silently miss on exactly the seats whose names carry an accent,
        // and the failure renders as the generic glyph rather than as an
        // error. Folding is a no-op for every existing brand, all of which are
        // ASCII, and it makes the asset name typeable.
        // A RENAMED SEAT'S OLD NAME RESOLVES TO ITS MARK (prd §647,
        // 2026-09-08). This view is handed `thing.source` at 64 call sites, and
        // a row landed before a rename keeps the old string forever — so
        // without this it falls to `BridgeGlyph.symbol`'s `app` glyph, a blank
        // rounded square, on every row of a seat that is sitting right there
        // wearing its real mark two rooms over. See `Corpus.renamedSources`.
        BridgeIconArt.assetName(for: name)
    }

    /// Whether `name` wears a mark of its own — bundled art, or a seat's
    /// glyph — rather than the blank `app` square a stranger's name falls to.
    static func hasMark(_ name: String) -> Bool {
        BridgeIconArt.image(BridgeIconArt.assetName(for: name)) != nil
            || BridgeGlyph.symbol(for: name) != "app"
    }

    private var shape: AnyShape {
        // An app is a rounded square and a person a circle (prd §1122,
        // reversing 2026-09-26's round leads): the feed row and the tray
        // draw an app's mark in its own shape.
        circular ? AnyShape(Circle())
                 : AnyShape(RoundedRectangle(cornerRadius: DS.Radius.appIcon(size), style: .continuous))
    }

    /// **A NOTE OF YOURS WEARS THE NOTE, NOT THE PERSON (user: "there is a
    /// silhouette icon in the top left … should be the notes icon").** A note
    /// lands under `You`, whose mark is `person` — right for a link you
    /// shared, wrong in the Notes room, where every row and the cover led
    /// with a silhouette. The kind's glyph instead: `note.text` (the tray's
    /// Notes door) for a note, `waveform` for a voice note. A pinned thing
    /// from a seat keeps its seat's mark, which is how the room tells a pin
    /// from a note. Callers hold a live model.
    static func noteSymbol(for thing: Thing) -> String? {
        guard Pinboard.isNote(thing) else { return nil }
        return Highlight.isHighlight(thing) ? "text.quote" : thing.kind.symbol
    }

    var body: some View {
        if symbol == nil, let ui = BridgeIconArt.image(assetName) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(shape)
        } else if let symbol {
            // A NOTE OF YOURS wears the tray's You door (user, 2026-09-29:
            // "this should be black and pink like it is in the tray"; prd
            // §976a): a black circle, the glyph in the brand pink, at the same
            // fallback scale — the note's mark and the door to its room are
            // one drawing.
            shape
                .fill(Color.black)
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.54, weight: .semibold))
                        .foregroundStyle(DS.brand)
                )
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
                    Image(systemName: symbol ?? BridgeGlyph.symbol(for: name))
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
///
/// Resolution is `BrandMark`'s, shared with `AssetMark` since 2026-08-04: this
/// file used to alias only `btc`, so the treemap drew nothing for wstETH, POL
/// or wSOL while the rows beneath it wore real marks for the same holdings.
struct TokenIcon: View {
    let symbol: String
    var size: CGFloat = 20

    var body: some View {
        if let ui = BrandMark.image(for: symbol) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else if !DemoMode.isActive, let url = TokenIconBook.url(for: symbol) {
            // The picture the holdings read named (prd §931) — the same
            // middle rung `AssetMark` draws, so a list row and the pack above
            // it wear the same mark for the same coin.
            RemoteAssetMark(urlString: url, size: size,
                            monogram: String(symbol.prefix(2)).uppercased(), tint: nil)
        }
    }
}

extension EnvironmentValues {
    /// The source whose app header this subtree stands under (prd §1103a);
    /// `DSFeedRow` draws no lead under it.
    var dsGroupedSource: String? {
        get { self[DSGroupedSourceKey.self] }
        set { self[DSGroupedSourceKey.self] = newValue }
    }
}

private struct DSGroupedSourceKey: EnvironmentKey {
    static let defaultValue: String? = nil
}
