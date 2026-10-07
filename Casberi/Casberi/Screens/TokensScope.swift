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
    /// The verb, last: find a company or coin in the index and the market,
    /// and watch it (prd §1081). Add again since prd §1171 (it was Search
    /// from §1082): the tray's search finds what you have, so the bar's one
    /// verb is the one that finds what you don't.
    static let add = TokensScope(category: "\u{1}add")

    var id: String { category ?? "\u{1}watchlist" }

    /// A catalogue category's companies, or all of them: an index page.
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
        guard let category else { return String(localized: "What you follow") }
        return String(localized: "The companies behind \(category)")
    }

    /// The pack under this tile; empty for the room's own tiles.
    var pack: [CompanyPacks.Company] {
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

    /// THE BOX (prd §1138, user: "the categories w/ no numbers, just their
    /// glyph and name. watchlist being the first", then "get rid of testnets
    /// b/c it won't have a market, and use the extra slot for alerts"):
    /// Watchlist and Alerts lead, then every category whose pack holds a
    /// company A–Z — a tile onto an empty list is a dead control (§83).
    /// Testnets has no market and Markets is a place in You (§1123); the All
    /// index is deleted, Search reaches every company.
    static let box: [TokensScope] = [.watchlist, .alerts]
        + packs.keys.filter { $0 != "Testnets" && $0 != HomeScope.markets }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { TokensScope(category: $0) }

    /// The bar: Add alone, the verb (prd §1171).
    static let bar: [TokensScope] = [.add]

    /// Every tile, for a hook that names one.
    static var all: [TokensScope] { box + bar }

    /// Every pack, built once off the static catalogue.
    private static let packs: [String: [CompanyPacks.Company]] = {
        var offers: [String: [String]] = [:]
        for offer in BridgeCatalog.offers {
            offers[BridgeCatalog.category(of: offer), default: []].append(offer.name)
        }
        return offers.mapValues(CompanyPacks.pack(offers:)).filter { !$0.value.isEmpty }
    }()
}
