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
    /// Every company behind every app, one index (prd §1082).
    static let everything = TokensScope(category: "\u{1}all")
    /// The verb, last: search the index and the market, and watch (prd
    /// §1081, renamed from Add by §1082 when it began searching the index).
    static let search = TokensScope(category: "\u{1}search")

    var id: String { category ?? "\u{1}watchlist" }

    /// A catalogue category's companies, or all of them: an index page.
    var isPack: Bool { self == .everything || (category.map { !$0.hasPrefix("\u{1}") } ?? false) }

    var label: String {
        if self == .alerts { return String(localized: "Alerts") }
        if self == .everything { return String(localized: "All") }
        if self == .search { return String(localized: "Search") }
        return category ?? String(localized: "Watchlist")
    }

    var glyph: String {
        if self == .alerts { return ScopeTileGlyph.alerts }
        if self == .everything { return ScopeTileGlyph.all }
        if self == .search { return ScopeTileGlyph.search }
        return category.map(CategoryFold.glyph(for:)) ?? ScopeTileGlyph.watch
    }

    var summary: String {
        if self == .alerts { return String(localized: "The price alerts you set") }
        if self == .everything { return String(localized: "Every company behind every app") }
        if self == .search { return String(localized: "Find something to watch") }
        guard let category else { return String(localized: "What you watch") }
        return String(localized: "The companies behind \(category)")
    }

    /// The pack under this tile; empty for the room's own tiles.
    var pack: [CompanyPacks.Company] {
        if self == .everything { return Self.everyCompany }
        guard isPack, let category else { return [] }
        return Self.packs[category] ?? []
    }

    /// Every pack as one, each company once with all its apps (prd §1082).
    static let everyCompany: [CompanyPacks.Company] = {
        var order: [String] = []
        var merged: [String: CompanyPacks.Company] = [:]
        for company in packs.keys.sorted().flatMap({ packs[$0] ?? [] }) {
            if let seen = merged[company.name] {
                let seats = seen.seats + company.seats.filter { !seen.seats.contains($0) }
                merged[company.name] = .init(name: company.name, listing: seen.listing, seats: seats)
            } else {
                order.append(company.name)
                merged[company.name] = company
            }
        }
        return order.compactMap { merged[$0] }
    }()

    /// Watchlist, Alerts and All, then every category whose pack holds a company
    /// — a tile that opens an empty list is a dead control (§83) — in the
    /// person's category order (prd §1050j), read fresh so a rearrangement
    /// moves it, then Add, the verb, last (§1039).
    @MainActor static var all: [TokensScope] {
        [.watchlist, .alerts, .everything] + CategoryOrder.sorted(Array(packs.keys)).map { TokensScope(category: $0) }
            + [.search]
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
