import Foundation

/// Per-category "since I last checked" memory for scoped "What's going on"
/// briefs (spec: scoped-brief-spec.md). `TodayBrief.compose(category:)` reads
/// this to decide how far back a category-scoped ask reaches; the unscoped
/// daily brief is untouched and keeps reading `DayBrief.windowStart` exactly
/// as it always has.
///
/// One UserDefaults dictionary, keyed by a BRIEF SCOPE name (`scopes` below —
/// "Money", "Work", "Life"), not the app catalog's own ten category names.
/// Never an agent label: the vocabulary is fixed and code-owned, not
/// something a person or the model can create or rename (spec: "Out of
/// scope — user-created categories… scoping by agent-generated labels").
///
/// Viewing an ALL-APPS brief counts as having viewed every scope (spec:
/// "since = the last time the user viewed a brief that included this
/// category — a scoped brief for it, OR an all-apps brief"), so
/// `markViewed(category: nil)` stamps every scope name at once. A "What's
/// going on with Work?" asked five minutes after the scheduled daily brief
/// ran starts its window from the daily brief's own moment, not from
/// midnight — the same fact was already shown once, and re-showing it would
/// read as the brief forgetting itself the way `BriefLedger`'s header (§214)
/// already describes for the unscoped brief.
@MainActor
enum BriefScope {
    private static let key = "brief.scope.lastViewed"

    /// The three scopes a "what's going on" brief can be asked about —
    /// DELIBERATELY smaller than the app catalog's own ten categories
    /// (`BridgeCatalog.categories`, unchanged everywhere else: Browse,
    /// `SourcesTray`, the wall's own carefully ruled band order). Five was
    /// tried first and cut to three (user, 2026-08-08) — a chip row you hold
    /// in your head, and fewer, wider buckets are the structural fix for a
    /// thin account: someone who's only connected two apps is far more
    /// likely to have SOMETHING in a 3-way split than a 10-way one.
    ///
    /// `nonisolated` (this and the mapping below) — pure lookups, no
    /// UserDefaults touched, so they're callable from `KeptAskComposers
    /// .NamedAskTarget.pool(in:)`, which is synchronous and not main-actor
    /// isolated. The REST of this enum stays `@MainActor`: `load`/`save`
    /// genuinely do read/write UserDefaults and every real caller
    /// (`TodayBrief.compose`, `Composer`) is already on the main actor.
    nonisolated static let scopes: [String] = ["Money", "Work", "Life"]

    /// Catalog category → brief scope (user ruling, 2026-08-08). Markets
    /// folds into Money — a watchlist mover and a wallet balance are both
    /// "what your money did", and splitting them was two crypto chips for
    /// one kind of question. Agents folds into Work — a coding/chat tool is
    /// work activity even outside the Work catalog group. Everything else
    /// (Life, Shopping, Notes, Media, Social, Reading) folds into Life: the
    /// personal catch-all, deliberately the widest bucket, since it's also
    /// the one asked to carry named-people richness (avatars) that a thin
    /// account still has via Calendar/Contacts alone.
    nonisolated private static let catalogToScope: [String: String] = [
        "Wallet": "Money", "Markets": "Money",
        "Work": "Work", "Agents": "Work",
        "Life": "Life", "Shopping": "Life", "Notes": "Life",
        "Media": "Life", "Social": "Life", "Reading": "Life",
    ]

    /// A catalog category's brief scope — the one place this mapping is
    /// read, so chip building, NL parsing, and `TodayBrief`'s own Stage-1
    /// filter can never quietly disagree about which apps a scope covers.
    /// Falls back to "Life" for a category name this table doesn't know
    /// (mirrors `BridgeCatalog.category(of:)`'s own unknown-group default),
    /// since Life is already the catch-all by design.
    nonisolated static func scope(forCatalogCategory category: String) -> String {
        catalogToScope[category] ?? "Life"
    }

    private static func load() -> [String: Date] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: Date].self, from: data)
        else { return [:] }
        return decoded
    }

    private static func save(_ dict: [String: Date]) {
        guard let data = try? JSONEncoder().encode(dict) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// The last moment a brief covering this category actually rendered, or
    /// nil on a first ask.
    static func lastViewed(category: String) -> Date? { load()[category] }

    /// The window boundary for a scoped brief: last viewed, else the start of
    /// today in the user's own calendar (spec's first-run fallback — the same
    /// "no ledger yet" floor `DayBrief.windowStart` uses for the unscoped
    /// brief, just per-category rather than global).
    static func since(category: String, now: Date = .now) -> Date {
        lastViewed(category: category) ?? Calendar.current.startOfDay(for: now)
    }

    /// Records that a brief covering `category` — or, when nil, EVERY
    /// category — actually rendered. Mirrors `BriefLedger`'s own
    /// `presenting`-only discipline (§214): call this only when a person is
    /// really looking at the result, never from a background digest refresh,
    /// or a kept pill's silent `KeptAskStore.refreshDigests` pass would mark
    /// a category "checked" nobody actually saw.
    static func markViewed(category: String?, at now: Date = .now) {
        var dict = load()
        if let category {
            dict[category] = now
        } else {
            for name in scopes { dict[name] = now }
        }
        save(dict)
    }

    #if DEBUG
    private static var seededThisLaunch = false
    /// `-briefScope "<Category>:<hoursAgo>[,…]"|clear` — seed a category's
    /// last-viewed stamp headlessly (mirrors `AskMemory.seedFromLaunchArgs`'s
    /// shape), so the "since I last checked" window verifies in one launch
    /// instead of a real wait. Self-guarded to once per launch.
    static func seedFromLaunchArgs() {
        guard !seededThisLaunch else { return }
        seededThisLaunch = true
        guard let spec = UserDefaults.standard.string(forKey: "briefScope"), !spec.isEmpty
        else { return }
        if spec == "clear" { save([:]); return }
        var dict = load()
        for pair in spec.split(separator: ",") {
            let parts = pair.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, let hours = Double(parts[1]) else { continue }
            dict[parts[0]] = Date.now.addingTimeInterval(-hours * 3600)
        }
        save(dict)
    }
    #endif
}
