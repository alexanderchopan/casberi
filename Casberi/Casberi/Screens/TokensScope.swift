import Foundation

/// The Tokens room's tiles: Watchlist, then one pack per catalogue category
/// (`CompanyPacks`), A to Z like the Accounts catalogue's own strip. The
/// category tiles wear the dock's category glyphs, so a pack reads as the
/// same thing as the folder of accounts it prices.
///
/// ONE stored property, for the reason `CatalogScope` gives: `DSScopeTiles`
/// compares `active` against its elements with `==`.
struct TokensScope: DSTileScope {
    /// nil is the Watchlist; otherwise a `BridgeCatalog.categories` name.
    let category: String?

    static let watchlist = TokensScope(category: nil)

    var id: String { category ?? "\u{1}watchlist" }

    var label: String { category ?? String(localized: "Watchlist") }

    var glyph: String { category.map(CategoryFold.glyph(for:)) ?? "eye" }

    var summary: String {
        guard let category else { return String(localized: "The tokens you watch") }
        return String(localized: "The companies behind \(category)")
    }

    /// The pack under this tile; empty for the Watchlist.
    var pack: [CompanyPacks.Company] {
        guard let category else { return [] }
        return Self.packs[category] ?? []
    }

    /// Watchlist, then every category whose pack holds a company — a tile
    /// that opens an empty list is a dead control (§83) — in the person's
    /// category order (prd §1050j), read fresh so a rearrangement moves it.
    @MainActor static var all: [TokensScope] {
        [.watchlist] + CategoryOrder.sorted(Array(packs.keys)).map { TokensScope(category: $0) }
    }

    /// Every pack, built once off the static catalogue.
    private static let packs: [String: [CompanyPacks.Company]] = {
        var offers: [String: [String]] = [:]
        for offer in BridgeCatalog.offers {
            offers[BridgeCatalog.category(of: offer), default: []].append(offer.name)
        }
        return offers.mapValues(CompanyPacks.pack(offers:)).filter { !$0.value.isEmpty }
    }()
}
