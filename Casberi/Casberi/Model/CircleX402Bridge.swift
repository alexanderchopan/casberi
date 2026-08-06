import Foundation
import Observation
import SwiftData

/// The Circle x402 bridge (2026-08-06) — the marketplace of APIs that sell
/// themselves to software by the call, watchable the way you watch a market.
/// x402 is the pay-per-request protocol (an HTTP 402 carrying a price); Circle
/// runs the public directory of services that speak it and settle in USDC.
/// Keyless: no account, no key, nothing to mint — `GET api.circle.com` and the
/// whole catalog answers.
///
/// **Read-only, and the ceiling is the point.** Casberi never pays an x402
/// service, never holds a wallet that could, and shows no path to. Watching can
/// never spend — the same promise the wallet seat makes, in a room where the
/// listings are literally priced. What lands is a directory entry: who joined,
/// what they sell, what it costs. Buying is somebody else's app.
///
/// **A PROVIDER is the thing that lands, not a service.** Measured 2026-08-06:
/// 955 listings, 22 providers — Orthogonal alone is 310 of them and QuickNode
/// 132, each a near-identical sibling ("latest spot price", "spot price at
/// timestamp", …). Landing per listing would file 310 rows the day one company
/// onboards, which is the count-as-a-thing failure `PostHogBridge` is built
/// around: the EVENT is a provider arriving on the marketplace, and the endpoint
/// tally is an attribute of it. So endpoints aggregate into one row per provider,
/// which HEALS in place as they add services or reprice (the social-bridge
/// dedupe-hit pattern) rather than re-landing wearing a new number.
///
/// **Measured quirks — re-measure before "fixing" any (all 2026-08-06):**
///
///  1. **`category` filters six values; the data carries seven.** The API
///     rejects `category=DATA_ENRICHMENT` with a 400 naming its six legal
///     options — and 185 of the 955 listings (19%) are stamped exactly that.
///     So a server-side category filter structurally cannot reach a fifth of
///     the marketplace, with no error anywhere. Hence `walk()` fetches
///     UNFILTERED and `X402Store` narrows on device: the seventh lane costs us
///     nothing and reaches rows Circle's own filter refuses to serve. Do not
///     "optimise" this into `?category=` — it would silently empty a lane.
///  2. **A category this build doesn't know still lands.** Falling out of the
///     picker must never mean falling out of the feed (the §307 silent-drop
///     lesson): an unmapped category is our gap, not a reason to hide a
///     provider, so it lands whenever anything is watched and `diagnose()`
///     names the unknown string so drift shows up in one launch — the
///     `-cursorProbe` rule for a status value we don't recognise.
///  3. **`lastUpdated` is bulk-restamped and cannot date an arrival.** Every
///     one of the 955 rows fell inside a three-day window (Jul 29–31), so it
///     records when Circle last reindexed, not when a provider joined. Rows are
///     stamped `.now` — honestly "when this reached your feed", the same claim
///     every other discovery seat makes — and nothing here ever says "just
///     joined", which would be a date we don't have.
///  4. **37 listings quote a zero price**, so a naive minimum reports "$0.0000"
///     for four of the biggest providers. The low end is the cheapest NON-ZERO
///     call and free operations are said separately, because "from $0.00" reads
///     as free and isn't.
///  5. `limit` is capped at 200 (500 is a 400, not a clamp) and `total` rides
///     `pagination`, so the walk reads page one, learns the size, and fetches
///     the rest concurrently rather than crawling.
enum X402Category: String, CaseIterable, Identifiable {
    // Ordered by measured share of the catalog, so the picker's first lanes are
    // the ones with something in them.
    case financial      = "FINANCIAL_ANALYSIS"
    case enrichment     = "DATA_ENRICHMENT"
    case research       = "WEB_SEARCH_RESEARCH"
    case social         = "SOCIAL_INTELLIGENCE"
    case infrastructure = "INFRASTRUCTURE"
    case prediction     = "PREDICTION_MARKETS"
    case creative       = "CREATIVE"

    var id: String { rawValue }

    /// Circle's own taxonomy in sentence case — their categories, our
    /// typography. Not renamed: a directory's lanes are a fact about the
    /// directory, and inventing friendlier names would misreport what a
    /// listing actually says about itself.
    var display: String {
        switch self {
        case .financial:      "Financial analysis"
        case .enrichment:     "Data enrichment"
        case .research:       "Search & research"
        case .social:         "Social intelligence"
        case .infrastructure: "Infrastructure"
        case .prediction:     "Prediction markets"
        case .creative:       "Creative"
        }
    }

    static func from(_ raw: String) -> X402Category? {
        X402Category(rawValue: raw.uppercased())
    }
}

// MARK: - Store (just the watched lanes — no key, nothing to mint)

@Observable
final class X402Store {
    static let shared = X402Store()
    private static let key = "x402.categories.v1"

    private var categoryIDs: [String] { didSet { persist() } }

    /// Connecting with nothing chosen watches the WHOLE marketplace — the seat
    /// is sold as "the marketplace", so the default has to be it. GeckoTerminal
    /// defaults to a subset because ten chains is a real choice; seven lanes
    /// over twenty-two providers is not.
    static var defaultCategories: [String] { X402Category.allCases.map(\.rawValue) }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([String].self, from: data) {
            categoryIDs = saved
        } else {
            categoryIDs = []
        }
    }

    var connected: Bool { !categoryIDs.isEmpty }
    var watched: [X402Category] { categoryIDs.compactMap(X402Category.from) }

    func isWatching(_ category: X402Category) -> Bool {
        categoryIDs.contains(category.rawValue)
    }

    func add(_ category: X402Category) {
        guard !categoryIDs.contains(category.rawValue) else { return }
        categoryIDs.append(category.rawValue)
    }

    func remove(_ category: X402Category) {
        categoryIDs.removeAll { $0 == category.rawValue }
    }

    func connectDefaults() {
        guard categoryIDs.isEmpty else { return }
        categoryIDs = Self.defaultCategories
    }

    func disconnect() { categoryIDs = [] }

    private func persist() {
        if let data = try? JSONEncoder().encode(categoryIDs) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

// MARK: - Ingest

enum X402Ingest {

    /// Serializes refreshes — the launch hook can race the foreground sweep and
    /// both would read `existing` before either saved (the RSS lesson).
    @MainActor private static var running = false

    static let host = "https://api.circle.com/v2/x402/discovery/resources"

    /// The API's own maximum; 500 is a 400, not a clamp.
    static let pageSize = 200
    /// The walk's stated ceiling — 2,000 listings against a catalog measuring
    /// 955, so it has real headroom, and `Walk.truncated` COUNTS the refusal
    /// rather than letting a grown directory read as a complete one (§307).
    static let maxPages = 10
    /// New providers landed per pass. A ONE-OPEN DELAY, not a ceiling: a
    /// provider held back this pass is still absent from `existing` next pass,
    /// so it lands then (the Hugging Face rule).
    static let maxNewPerPass = 40

    // MARK: - Shapes

    /// One provider, folded down from every listing it owns.
    struct Provider {
        let name: String
        let slug: String
        let detail: String?
        let website: String?
        let docsURL: String?
        /// Raw category strings as the directory spells them — kept raw so an
        /// unmapped one survives to `diagnose()` instead of vanishing.
        let categories: Set<String>
        let tags: [String]
        let endpoints: Int
        /// Cheapest and dearest NON-ZERO call, in USDC base units (6 decimals).
        let minPrice: Int?
        let maxPrice: Int?
        /// Whether any listing quotes a zero price (37 do).
        let hasFree: Bool
        /// A sample of what they actually sell — retrieval fodder, never shown.
        let sampleDescriptions: [String]

        var known: [X402Category] {
            categories.compactMap(X402Category.from).sorted { $0.display < $1.display }
        }

        /// True when NO category this provider declares maps to a lane this
        /// build knows — quirk 2's case.
        var allCategoriesUnknown: Bool { known.isEmpty }

        /// "$0.01–$3.50 a call", "$0.0001 a call", "some free, then …", or
        /// "free" — never "$0.0000" (quirk 4).
        var priceLine: String? {
            guard let lo = minPrice, let hi = maxPrice else {
                return hasFree ? String(localized: "free") : nil
            }
            let range = lo == hi ? X402Ingest.usd(lo) : "\(X402Ingest.usd(lo))–\(X402Ingest.usd(hi))"
            return hasFree
                ? String(localized: "some free, then \(range) a call")
                : String(localized: "\(range) a call")
        }
    }

    /// One pass over the directory.
    struct Walk {
        let providers: [Provider]
        let listings: Int
        let total: Int
        /// The catalog outgrew `maxPages` and this walk saw only a prefix.
        let truncated: Bool
        /// Category strings the directory served that this build can't map.
        let unknownCategories: Set<String>
    }

    // MARK: - Reading

    /// The whole directory, folded to providers — or nil when the first page
    /// couldn't be reached. An EMPTY provider list is a real answer (the
    /// directory served nothing), not a failure.
    static func walk() async -> Walk? {
        guard let first = await page(offset: 0) else { return nil }

        let total = first.total
        let wanted = max(0, Int(ceil(Double(total) / Double(pageSize))))
        let pages = min(wanted, maxPages)
        var items = first.items

        if pages > 1 {
            // The first page carries `total`, so the rest are a known set and
            // go out together rather than crawling one at a time.
            let offsets = (1..<pages).map { $0 * pageSize }
            let rest = await IngestSupport.boundedGather(offsets, maxConcurrent: 3) { offset in
                await page(offset: offset)?.items ?? []
            }
            for chunk in rest { items += chunk }
        }

        var byProvider: [String: Builder] = [:]
        var unknown: Set<String> = []

        for item in items {
            guard let metadata = item["metadata"] as? [String: Any],
                  let provider = metadata["provider"] as? [String: Any],
                  let name = (provider["name"] as? String)?
                      .trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty
            else { continue }

            let slug = name.lowercased()
            var builder = byProvider[slug] ?? Builder(name: name, slug: slug)
            builder.absorb(provider: provider, item: item, unknown: &unknown)
            byProvider[slug] = builder
        }

        // Biggest first — a directory read cold should lead with the companies
        // actually serving it, and this is the order the per-pass cap trims
        // from the bottom of.
        let providers = byProvider.values
            .map(\.provider)
            .sorted { ($0.endpoints, $1.slug) > ($1.endpoints, $0.slug) }

        return Walk(providers: providers, listings: items.count, total: total,
                    truncated: wanted > maxPages, unknownCategories: unknown)
    }

    private struct Page {
        let items: [[String: Any]]
        let total: Int
    }

    private static func page(offset: Int) async -> Page? {
        let url = "\(host)?limit=\(pageSize)&offset=\(offset)"
        guard let root = await IngestSupport.getJSON(url) as? [String: Any],
              let items = root["items"] as? [[String: Any]] else { return nil }
        // A missing `total` is not a failure — fall back to what this page held
        // so a single-page read still lands.
        let total = (root["pagination"] as? [String: Any])?["total"] as? Int ?? items.count
        return Page(items: items, total: total)
    }

    /// Accumulates one provider's listings as the walk streams past them.
    private struct Builder {
        let name: String
        let slug: String
        var detail: String?
        var website: String?
        var docsURL: String?
        var categories: Set<String> = []
        var tags: [String] = []
        var endpoints = 0
        var minPrice: Int?
        var maxPrice: Int?
        var hasFree = false
        var sampleDescriptions: [String] = []

        mutating func absorb(provider: [String: Any], item: [String: Any],
                             unknown: inout Set<String>) {
            endpoints += 1
            detail = detail ?? trimmed(provider["description"])
            website = website ?? https(provider["website"])
            docsURL = docsURL ?? https(provider["docsUrl"])

            if let raw = trimmed(provider["category"]) {
                categories.insert(raw)
                if X402Category.from(raw) == nil { unknown.insert(raw) }
            }
            for tag in (provider["tags"] as? [String] ?? []) where tags.count < 12 {
                if let t = trimmed(tag), !tags.contains(t) { tags.append(t) }
            }
            if sampleDescriptions.count < 8,
               let what = trimmed((item["metadata"] as? [String: Any])?["description"]) {
                sampleDescriptions.append(what)
            }

            for accept in (item["accepts"] as? [[String: Any]] ?? []) {
                guard let amount = amount(accept["amount"]) else { continue }
                // Zero is recorded as a FACT, never as the minimum (quirk 4).
                if amount == 0 { hasFree = true; continue }
                minPrice = min(minPrice ?? amount, amount)
                maxPrice = max(maxPrice ?? amount, amount)
            }
        }

        var provider: Provider {
            Provider(name: name, slug: slug, detail: detail, website: website,
                     docsURL: docsURL, categories: categories, tags: tags,
                     endpoints: endpoints, minPrice: minPrice, maxPrice: maxPrice,
                     hasFree: hasFree, sampleDescriptions: sampleDescriptions)
        }

        private func trimmed(_ raw: Any?) -> String? {
            guard let s = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !s.isEmpty else { return nil }
            return s
        }

        /// A directory entry names its own website, so the link a row opens is
        /// third-party data — it has to be a real https URL with a host before
        /// it becomes a tappable thing.
        private func https(_ raw: Any?) -> String? {
            guard let s = trimmed(raw), let url = URL(string: s),
                  url.scheme?.lowercased() == "https",
                  let host = url.host(), host.contains(".") else { return nil }
            return s
        }

        /// Amounts ride the wire as strings ("20000").
        private func amount(_ raw: Any?) -> Int? {
            if let n = raw as? Int { return n }
            if let s = raw as? String { return Int(s) }
            return nil
        }
    }

    // MARK: - Landing

    /// Reads the directory and lands providers newly serving a watched lane.
    /// Returns the number of NEW things, 0 when up to date, nil when the
    /// directory couldn't be reached.
    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        guard X402Store.shared.connected, !running else { return running ? 0 : nil }
        running = true
        defer { running = false }

        // Every await finishes HERE, before a single Thing is fetched — so no
        // model reference is held across a suspension and corollary 6's whole
        // class is out of reach rather than guarded against.
        guard let walk = await walk() else { return nil }

        let watched = Set(X402Store.shared.watched.map(\.rawValue))
        guard !watched.isEmpty else { return nil }

        let existing = IngestSupport.thingsByRef(context, source: source)
        var added = 0
        var healed = false

        for provider in walk.providers {
            // Quirk 2: a provider whose lanes we can't map still lands.
            let inWatchedLane = !provider.categories.isDisjoint(with: watched)
                || provider.allCategoriesUnknown
            guard inWatchedLane else { continue }

            let ref = "x402:\(provider.slug)"
            if let already = existing[ref] {
                // The dedupe hit HEALS: services and prices move, and the row
                // should say what's true now rather than what was true the day
                // it landed. It never re-lands as news.
                if heal(already, with: provider) { healed = true }
                continue
            }
            guard added < maxNewPerPass else { break }

            let thing = Thing(
                kind: .link,
                // A provider's name and blurb are third-party text, so the
                // corpus's one-line-title invariant is enforced at the door
                // exactly as GeckoTerminal does for token names.
                title: IngestSupport.titleLine(headline(provider)),
                content: provider.website ?? provider.docsURL ?? catalogURL,
                source: source,
                capturedAt: .now,          // quirk 3 — never the API's own stamp
                tags: tags(for: provider),
                sourceRef: ref
            )
            thing.summary = summaryLine(provider)
            thing.enrichedText = retrievalText(provider)
            context.insert(thing)
            SpotlightIndex.index([thing])
            added += 1
        }

        if added > 0 || healed { context.saveHonestly() }
        return added
    }

    /// Brings a landed row's facts up to date. Returns whether anything moved.
    @MainActor
    private static func heal(_ thing: Thing, with provider: Provider) -> Bool {
        guard thing.isLive else { return false }
        var moved = false
        let summary = summaryLine(provider)
        if thing.summary != summary { thing.summary = summary; moved = true }
        let text = retrievalText(provider)
        if thing.enrichedText != text { thing.enrichedText = text; moved = true }
        let tags = tags(for: provider)
        if thing.tags != tags { thing.tags = tags; moved = true }
        return moved
    }

    // MARK: - Copy

    static let source = "Circle x402"
    static let catalogURL = "https://agents.circle.com/services"

    private static func headline(_ provider: Provider) -> String {
        guard let detail = provider.detail else { return provider.name }
        return "\(provider.name) · \(detail)"
    }

    /// Display copy — what they sell and what it costs.
    private static func summaryLine(_ provider: Provider) -> String {
        let services = provider.endpoints == 1
            ? String(localized: "1 service on Circle's x402 marketplace")
            : String(localized: "\(provider.endpoints) services on Circle's x402 marketplace")
        guard let price = provider.priceLine else { return services }
        return "\(services) · \(price)"
    }

    /// Retrieval-only (the 2026-07-15 ruling) — the provider's own tags and a
    /// sample of what its endpoints do, so searching "prediction" or
    /// "onchain-data" reaches a row whose title says neither. Capped at the
    /// embedding index's own 800-character window.
    private static func retrievalText(_ provider: Provider) -> String {
        var parts = provider.tags
        parts += provider.sampleDescriptions
        let joined = parts.joined(separator: " · ")
        return joined.count > 800 ? String(joined.prefix(800)) : joined
    }

    private static func tags(for provider: Provider) -> [String] {
        (["x402"] + provider.known.map(\.display)).reduced()
    }

    /// USDC base units (6 decimals) as money, with enough precision to stay
    /// true — a $0.0001 call must not render as "$0.00".
    static func usd(_ base: Int) -> String {
        let value = Double(base) / 1_000_000
        return value >= 0.01
            ? String(format: "$%.2f", value)
            : String(format: "$%.4f", value)
    }

    // MARK: - Probe

    /// What `-x402Probe` reports, line by line. An empty x402 room has five
    /// causes that render as one silence — not connected, the directory
    /// unreachable, every provider already landed, nothing in a watched lane,
    /// or shape drift — and only the last is a bug.
    @MainActor
    static func diagnose(context: ModelContext) async {
        let store = X402Store.shared
        NSLog("x402| connected=%@ watching=%@", store.connected ? "YES" : "NO",
              store.watched.map(\.rawValue).joined(separator: ",") as NSString)
        guard let walk = await walk() else {
            NSLog("x402| walk UNREACHABLE — no page answered")
            return
        }
        NSLog("x402| listings=%d total=%d providers=%d truncated=%@",
              walk.listings, walk.total, walk.providers.count, walk.truncated ? "YES" : "NO")
        if !walk.unknownCategories.isEmpty {
            // Quirk 2 made visible: a lane this build can't map, named.
            NSLog("x402| UNMAPPED categories: %@",
                  walk.unknownCategories.sorted().joined(separator: ",") as NSString)
        }
        let watched = Set(store.watched.map(\.rawValue))
        let existing = IngestSupport.thingsByRef(context, source: source)
        for provider in walk.providers {
            let inLane = !provider.categories.isDisjoint(with: watched) || provider.allCategoriesUnknown
            NSLog("x402Row| %@ eps=%d price=%@ lane=%@ landed=%@ link=%@",
                  provider.name as NSString, provider.endpoints,
                  (provider.priceLine ?? "unpriced") as NSString,
                  inLane ? "watched" : "off",
                  existing["x402:\(provider.slug)"] != nil ? "YES" : "no",
                  (provider.website ?? provider.docsURL ?? "none") as NSString)
        }
    }
}
