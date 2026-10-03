import Foundation

/// The Tokens room's tiles: Watchlist, then one pack per catalogue category
/// (`CompanyPacks`), A to Z like the Accounts catalogue's own strip. The
/// category tiles wear the dock's category glyphs, so a pack reads as the
/// same thing as the folder of accounts it prices.
///
/// ONE stored property, for the reason `CatalogScope` gives: `DSScopeTiles`
/// compares `active` against its elements with `==`.
struct TokensScope: DSTileScope {
    /// nil is the Watchlist; otherwise a `BridgeCatalog.categories` name,
    /// or one of the two room tiles below (their keys start with \u{1}, which
    /// no category name does).
    let category: String?

    static let watchlist = TokensScope(category: nil)
    /// Every alert you set, and the ones that fired (prd §1081).
    static let alerts = TokensScope(category: "\u{1}alerts")
    /// The verb, last: find a token or a stock and watch it (prd §1081).
    static let add = TokensScope(category: "\u{1}add")

    var id: String { category ?? "\u{1}watchlist" }

    /// A catalogue category's pack, not one of the room's own tiles.
    var isPack: Bool { category.map { !$0.hasPrefix("\u{1}") } ?? false }

    var label: String {
        if self == .alerts { return String(localized: "Alerts") }
        if self == .add { return String(localized: "Add") }
        return category ?? String(localized: "Watchlist")
    }

    var glyph: String {
        if self == .alerts { return ScopeTileGlyph.alerts }
        if self == .add { return ScopeTileGlyph.new }
        return category.map(CategoryFold.glyph(for:)) ?? ScopeTileGlyph.watch
    }

    var summary: String {
        if self == .alerts { return String(localized: "The price alerts you set") }
        if self == .add { return String(localized: "Find something to watch") }
        guard let category else { return String(localized: "What you watch") }
        return String(localized: "The companies behind \(category)")
    }

    /// The pack under this tile; empty for the room's own tiles.
    var pack: [CompanyPacks.Company] {
        guard isPack, let category else { return [] }
        return Self.packs[category] ?? []
    }

    /// Watchlist and Alerts, then every category whose pack holds a company
    /// — a tile that opens an empty list is a dead control (§83) — in the
    /// person's category order (prd §1050j), read fresh so a rearrangement
    /// moves it, then Add, the verb, last (§1039).
    @MainActor static var all: [TokensScope] {
        [.watchlist, .alerts] + CategoryOrder.sorted(Array(packs.keys)).map { TokensScope(category: $0) }
            + [.add]
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
