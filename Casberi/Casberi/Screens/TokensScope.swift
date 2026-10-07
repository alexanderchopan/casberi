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
    /// and watch it (prd §1081). New since prd §1171b (Search from §1082,
    /// Add in §1171): the one word every capsule's `plus` says, as Notes'.
    static let new = TokensScope(category: "\u{1}new")

    var id: String { category ?? "\u{1}watchlist" }

    /// A catalogue category's companies, or all of them: an index page.
    var isPack: Bool { category.map { !$0.hasPrefix("\u{1}") } ?? false }

    var label: String {
        if self == .alerts { return String(localized: "Alerts") }
        if self == .new { return String(localized: "New") }
        return category ?? String(localized: "Watchlist")
    }

    var glyph: String {
        if self == .alerts { return ScopeTileGlyph.alerts }
        if self == .new { return ScopeTileGlyph.new }
        return category.map(CategoryFold.glyph(for:)) ?? ScopeTileGlyph.watch
    }

    var summary: String {
        if self == .alerts { return String(localized: "The price alerts you set") }
        if self == .new { return String(localized: "Find something to watch") }
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
    /// glyph and name"): every category whose pack holds a company A–Z — a
    /// tile onto an empty list is a dead control (§83). Testnets has no
    /// market and Markets is a place in You (§1123). Watchlist and Alerts
    /// moved to the bar (prd §1171b, user: "put watchlist and alerts in it so
    /// markets and notes have their own lil menu capsule"), so the box is the
    /// eight categories two across, as Settings' eight counts stand.
    static let box: [TokensScope] = packs.keys.filter { $0 != "Testnets" && $0 != HomeScope.markets }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { TokensScope(category: $0) }

    /// The bar: Watchlist, Alerts, then New, the verb (prd §1171b), as Notes'
    /// bar holds its own views and its New.
    static let bar: [TokensScope] = [.watchlist, .alerts, .new]

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
