import Foundation
import SwiftData

/// The Stocktwits bridge (2026-07-15) — stocks, done the keyless way. Watch a
/// TICKER: the takes traders post about it on Stocktwits land as chat things,
/// each wearing its author's own Bullish/Bearish call, and the watchlist
/// row's sheet draws the ticker's live price chart (StockChart, Yahoo v8).
/// Stocktwits' public streams are the same keyless REST its website reads —
/// no account, no key, ~200 requests/hour/IP unauthenticated.
///
/// Two honest boundaries this bridge wears:
///   • It watches tickers, not portfolios — actual holdings are never public
///     anywhere, so nothing here claims to see one. Read-only: never a path
///     to trade.
///   • The sentiment on a post is its AUTHOR's declared call (Stocktwits'
///     own Bullish/Bearish toggle), carried as a tag — never a rating of
///     ours, never derived.
enum StockWatch {

    struct Resolved: Identifiable {
        let symbol: String     // "AAPL"
        let title: String      // "Apple Inc"
        let exchange: String   // "NASDAQ", "NYSE", "CRYPTO", …
        let watchers: Int      // Stocktwits watchlist_count — the row's scale cue
        var id: String { symbol }
    }

    /// The top matching symbols for a typed query — Stocktwits' own keyless
    /// symbol search (the site's autocomplete), its relevance order kept.
    static func search(_ query: String, limit: Int = 6) async -> [Resolved] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty,
              let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let root = await IngestSupport.getJSON(
                "https://api.stocktwits.com/api/2/search/symbols.json?q=\(encoded)")
                as? [String: Any],
              let results = root["results"] as? [[String: Any]]
        else { return [] }

        return results.compactMap { r -> Resolved? in
            guard (r["type"] as? String) == "symbol",
                  let symbol = r["symbol"] as? String, !symbol.isEmpty,
                  let title = r["title"] as? String else { return nil }
            return Resolved(symbol: symbol, title: title,
                            exchange: (r["exchange"] as? String) ?? "",
                            watchers: (r["watchlist_count"] as? Int) ?? 0)
        }
        .prefix(limit).map { $0 }
    }

    /// Resolves a query to its top match — the Watch button's path.
    static func resolve(_ query: String) async -> Resolved? {
        await search(query, limit: 1).first
    }

    static func symbolRef(_ symbol: String) -> String {
        "stocktwits:sym:\(symbol.uppercased())"
    }

    /// Adds a ticker to the watchlist as a thing whose sheet draws the live
    /// chart. Returns nil when it's already watched. The insert is
    /// immediate; the since-you-watched anchor (the live price at this
    /// moment, so the sheet can later say "+12% since you watched" against
    /// a number that was really true) backfills in the background — Yahoo
    /// can be rate-limiting, and a Watch tap must not sit behind its
    /// timeouts. No anchor lands when Yahoo's unreachable: the line simply
    /// never renders (the TokenWatch precedent).
    @MainActor
    @discardableResult
    static func add(_ stock: Resolved, context: ModelContext) -> Thing? {
        let ref = symbolRef(stock.symbol)
        // One-ref dedupe — a targeted count, not the whole-corpus ref set.
        let existing = (try? context.fetchCount(FetchDescriptor<Thing>(
            predicate: #Predicate { $0.sourceRef == ref }))) ?? 0
        guard existing == 0 else { return nil }
        let thing = Thing(
            kind: .link,
            title: IngestSupport.titleLine("\(stock.title) · $\(stock.symbol)"),
            // The Stocktwits symbol page — what StockChart.route reads, and
            // a real page when opened.
            content: "https://stocktwits.com/symbol/\(stock.symbol)",
            source: "Stocktwits",
            capturedAt: .now,
            tags: ["Watchlist"],
            sourceRef: ref
        )
        context.insert(thing)
        context.saveHonestly()
        SpotlightIndex.index([thing])
        let symbol = stock.symbol
        Task { @MainActor in
            guard let price = await StockChart.fetch(ticker: symbol, range: .day)?.price
            else { return }
            thing.watchPriceUsd = price
            context.saveHonestly()
        }
        return thing
    }

    /// Watched tickers, derived from the corpus — the thing IS the watch
    /// (the TokenWatch precedent): deleting the watchlist row is unwatching,
    /// with no separate store to drift out of sync. Scoped to this bridge's
    /// rows, not a whole-corpus ref scan.
    @MainActor
    static func watchedSymbols(context: ModelContext) -> [String] {
        var descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Stocktwits" && $0.sourceRef != nil })
        descriptor.propertiesToFetch = [\.sourceRef]
        let prefix = "stocktwits:sym:"
        return ((try? context.fetch(descriptor)) ?? [])
            .compactMap(\.sourceRef)
            .compactMap { $0.hasPrefix(prefix) ? String($0.dropFirst(prefix.count)) : nil }
            .sorted()
    }

    /// Unwatching everything at once — the Disconnect teardown. Deletes the
    /// WATCHLIST rows only (the watch is access, and disconnecting removes
    /// access — ruling 2026-07-13's two verbs); landed posts are history and
    /// follow the person's own "remove its things too" choice. Without this,
    /// a kept watchlist row would quietly re-register the seat on the next
    /// screen visit.
    /// AMENDED 2026-08-02 (prd §286): the posts go too. This used to keep
    /// them — "landed posts are history and follow the person's own 'remove
    /// its things too' choice" — which was the 2026-07-13 two-verbs ruling
    /// applied to a FOLLOW. That ruling still governs ACCESS (disconnecting a
    /// bridge doesn't erase what it brought), but a watchlist is a follow:
    /// its posts are a mirror of tickers you chose to watch, and once you
    /// stop watching, nothing explains them (user: "all things if you
    /// unfollow them should remove from your all b/c you are no longer
    /// following them"). Leaving them made this the one bridge whose unwatch
    /// disagreed with every other.
    @MainActor
    static func unwatchAll(context: ModelContext) {
        let descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Stocktwits" })
        let rows = ((try? context.fetch(descriptor)) ?? []).filter(\.isLive)
        guard !rows.isEmpty else { return }
        SpotlightIndex.remove(ids: rows.map(\.id))
        for thing in rows { context.delete(thing) }
        context.saveHonestly()
    }

    /// Registers (or clears) the Stocktwits seat with the live watched count.
    @MainActor
    static func registerBridge(store: BridgeStore, context: ModelContext) {
        let count = watchedSymbols(context: context).count
        guard count > 0 else { store.remove("stocktwits"); return }
        store.registerConnected(
            id: "stocktwits", name: "Stocktwits",
            proof: String(localized: "\(count) stock watched"),
            can: ["Reads public posts about the tickers you watch.",
                  "Read-only — never trades, never sees a portfolio."])
    }
}

// MARK: - Ingest

enum StocktwitsIngest {

    /// Serializes refreshes by CHAINING, not skipping — the launch hook,
    /// the screen's onAppear sync, and the foreground refresh can all race,
    /// and the usual `running` bool makes the loser report "0 new" while
    /// posts are actively landing (the documented Farcaster quirk, which
    /// here would surface as a false "Up to date" in the UI — honesty
    /// rule). A concurrent caller queues behind the in-flight pass, then
    /// runs its own with a FRESH watch list — a ticker watched mid-pass
    /// lands now, not next foreground (joining the old pass returned its
    /// stale-list result; caught by the -stockWatch probe 2026-07-15).
    /// Chaining, not a wait-loop: a loop re-awaiting a completed task can
    /// resume ahead of the owner's cleanup and spin the main actor (froze
    /// the same probe). The extra pass is one small GET per ticker, all
    /// dedupe — overlap is rare and cheap.
    @MainActor private static var current: (id: UUID, task: Task<Int?, Never>)?

    private struct Post {
        let id: Int
        let username: String
        let body: String
        let createdAt: Date?
        let followers: Int
        let sentiment: String?   // "Bullish" / "Bearish" — author-declared
        let chart: String?       // an attached chart image, when the post carries one
        let avatar: String?
    }

    /// The last ~30 public messages on one ticker's stream, or nil when the
    /// fetch failed (offline, rate-limited). Empty is a real answer: a quiet
    /// ticker.
    private static func fetchStream(_ symbol: String) async -> [Post]? {
        guard let sym = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let root = await IngestSupport.getJSON(
                "https://api.stocktwits.com/api/2/streams/symbol/\(sym).json")
                as? [String: Any],
              let messages = root["messages"] as? [[String: Any]] else { return nil }

        return messages.compactMap { m -> Post? in
            guard let id = m["id"] as? Int,
                  let body = m["body"] as? String, !body.isEmpty,
                  let user = m["user"] as? [String: Any],
                  let username = user["username"] as? String, !username.isEmpty
            else { return nil }
            let entities = m["entities"] as? [String: Any] ?? [:]
            return Post(
                id: id, username: username, body: body,
                createdAt: IngestSupport.isoDate(m["created_at"]),
                followers: (user["followers"] as? Int) ?? 0,
                sentiment: (entities["sentiment"] as? [String: Any])?["basic"] as? String,
                chart: (entities["chart"] as? [String: Any])?["url"] as? String,
                avatar: user["avatar_url_ssl"] as? String)
        }
    }

    /// Fetches every watched ticker's stream and lands the standout new
    /// posts as chat things. Returns the number of NEW things, 0 when up to
    /// date, nil when nothing was reachable (offline).
    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        let predecessor = current?.task
        let id = UUID()
        let task = Task { () -> Int? in
            if let predecessor { _ = await predecessor.value }
            return await run(context: context)
        }
        current = (id, task)
        let value = await task.value
        // Only the latest link clears the slot — an earlier caller's cleanup
        // must not drop a successor that already chained on.
        if current?.id == id { current = nil }
        return value
    }

    @MainActor
    private static func run(context: ModelContext) async -> Int? {
        let symbols = StockWatch.watchedSymbols(context: context)
        guard !symbols.isEmpty else { return 0 }

        // One call per ticker, capped low — far under Stocktwits' ~200/hour
        // unauthenticated ceiling even across a day of foregrounds.
        let results = await IngestSupport.boundedGather(symbols, maxConcurrent: 3) { sym in
            (sym, await fetchStream(sym))
        }

        var existing = IngestSupport.existingSourceRefs(context, source: "Stocktwits")
        var added = 0
        var reachedAny = false

        for (symbol, posts) in results {
            guard let posts else { continue }
            reachedAny = true
            // The three most-followed voices in the stream's last ~30 —
            // public messages carry no like counts, so author reach is the
            // one honest quality signal available, and it keeps the 0DTE
            // spam accounts out of the feed. `existing` grows as we insert,
            // so a post naming two watched tickers lands once, not twice.
            for post in posts.sorted(by: { $0.followers > $1.followers }).prefix(3) {
                let ref = "stocktwits:msg:\(post.id)"
                guard !existing.contains(ref) else { continue }
                let thing = Thing(
                    kind: .chat,
                    // Post bodies are author-controlled: entities decoded,
                    // newlines flattened, length capped at the door.
                    title: IngestSupport.titleLine(IngestSupport.decodeHTMLEntities(post.body)),
                    content: "https://stocktwits.com/\(post.username)/message/\(post.id)",
                    source: "Stocktwits",
                    // The post's own time — it rides "while I was away"
                    // honestly instead of clustering at sync time.
                    capturedAt: post.createdAt ?? .now,
                    tags: [symbol] + (post.sentiment.map { [$0] } ?? []),
                    sourceRef: ref
                )
                thing.authorHandle = post.username
                thing.authorAvatarURL = IngestSupport.imageURL(post.avatar)
                thing.previewImageURL = IngestSupport.imageURL(post.chart)
                context.insert(thing)
                existing.insert(ref)
                SpotlightIndex.index([thing])
                added += 1
            }
        }
        if added > 0 { context.saveHonestly() }
        return reachedAny ? added : nil
    }
}
