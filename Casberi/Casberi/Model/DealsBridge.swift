import Foundation
import Observation
import SwiftData

/// The Deals bridge (2026-07-14) — the deal aggregators' own feeds, landing as
/// product things in your shopping corpus. Where Shopify follows a store you
/// name, Deals follows the editors who surface the discounts: turn on a source
/// and its newest deals (each already "Product · $price" in the headline) land
/// in your feed. Read-only public feeds, fetched by this iPhone — no account,
/// no algorithm in between, and it never buys anything.
///
/// It reuses the RSS bridge's fetch-and-parse whole (`FeedParser`); the only
/// differences are a curated source list (not a pasted URL — these are a
/// handful of known aggregators, toggled like OpenSea's chains) and that a
/// deal lands as a `.product`, not a `.link`, so it joins the Products pile.

// MARK: - Sources

/// The deal aggregators Casberi can follow — a curated, verified set (each feed
/// checked live), not exhaustive. A source with a dead feed would only pad the
/// list, so the list stays short and known-good.
enum DealSource: String, CaseIterable, Identifiable {
    case slickdealsFrontpage, slickdealsPopular, dealnews

    var id: String { rawValue }

    var display: String {
        switch self {
        case .slickdealsFrontpage: "Slickdeals — Frontpage"
        case .slickdealsPopular:   "Slickdeals — Popular"
        case .dealnews:            "DealNews"
        }
    }

    /// The publisher name a landed deal wears in its trailing label.
    var publisher: String {
        switch self {
        case .slickdealsFrontpage, .slickdealsPopular: "Slickdeals"
        case .dealnews: "DealNews"
        }
    }

    var feedURL: String {
        switch self {
        case .slickdealsFrontpage: "https://feeds.feedburner.com/SlickdealsnetFP"
        case .slickdealsPopular:   "https://feeds.feedburner.com/SlickdealsHotDeals"
        case .dealnews:            "https://www.dealnews.com/rss/todays-edition/"
        }
    }

    static func from(_ id: String) -> DealSource? {
        DealSource(rawValue: id) ?? allCases.first { $0.rawValue.caseInsensitiveCompare(id) == .orderedSame }
    }
}

// MARK: - Store (the enabled sources)

@Observable
final class DealsStore {
    static let shared = DealsStore()
    private static let key = "deals.sources.v1"

    private var enabled: [String] { didSet { persist() } }

    /// The default when someone connects with nothing chosen — the two
    /// highest-signal sources.
    static let defaults = [DealSource.slickdealsFrontpage.rawValue,
                           DealSource.slickdealsPopular.rawValue]

    private init() {
        if let saved = UserDefaults.standard.stringArray(forKey: Self.key) {
            enabled = saved
        } else {
            enabled = []
        }
    }

    var sources: [String] { enabled }
    var connected: Bool { !enabled.isEmpty }
    var enabledSources: [DealSource] { enabled.compactMap(DealSource.from) }

    func isOn(_ source: DealSource) -> Bool { enabled.contains(source.rawValue) }

    func add(_ source: DealSource) {
        guard !enabled.contains(source.rawValue) else { return }
        enabled.append(source.rawValue)
    }

    func remove(_ source: DealSource) {
        enabled.removeAll { $0 == source.rawValue }
    }

    func connectDefaults() {
        guard enabled.isEmpty else { return }
        enabled = Self.defaults
    }

    func disconnect() { enabled = [] }

    private func persist() {
        UserDefaults.standard.set(enabled, forKey: Self.key)
    }
}

// MARK: - Ingest

enum DealsIngest {

    @MainActor private static var running = false

    /// One source's parsed feed, or nil when it couldn't be reached.
    private static func fetch(_ source: DealSource) async -> FeedParser.Parsed? {
        guard let url = URL(string: source.feedURL),
              let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        let parsed = FeedParser.parse(data)
        return parsed.items.isEmpty ? nil : parsed
    }

    /// Fetches every enabled source and lands new deals as product things.
    /// Returns the number of NEW things, 0 when up to date, nil when nothing
    /// was reachable.
    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        let store = DealsStore.shared
        let sources = store.enabledSources
        guard !sources.isEmpty, !running else { return running ? 0 : nil }
        running = true
        defer { running = false }

        let results = await IngestSupport.boundedGather(sources, maxConcurrent: 4) { source in
            await fetch(source)
        }

        var existing = IngestSupport.existingSourceRefs(context, source: "Deals")
        let backfill = ArtlessBackfill(context, source: "Deals")
        var added = 0
        var reachedAny = false

        for (source, parsed) in zip(sources, results) {
            guard let parsed else { continue }
            reachedAny = true
            // Newest 15 per source — the feed is a firehose; the corpus isn't.
            for item in parsed.items.prefix(15) {
                let ref = "deals:\(item.guid.isEmpty ? item.link : item.guid)"
                if existing.contains(ref) {
                    backfill.patch(ref, image: item.imageURL)
                    continue
                }
                guard !item.title.isEmpty else { continue }
                let thing = Thing(
                    kind: .product,
                    title: IngestSupport.titleLine(IngestSupport.decodeHTMLEntities(item.title)),
                    content: item.link,
                    source: "Deals",
                    capturedAt: item.date ?? .now,
                    tags: ["Deal"],
                    sourceRef: ref
                )
                thing.previewImageURL = IngestSupport.imageURL(item.imageURL)
                thing.authorHandle = source.publisher
                context.insert(thing)
                existing.insert(ref)
                SpotlightIndex.index([thing])
                added += 1
            }
        }
        if added > 0 || backfill.any { context.saveHonestly() }
        return reachedAny ? added : nil
    }
}
