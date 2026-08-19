import Foundation
import Observation
import SwiftData

/// What the agent already knew last time it was open.
///
/// WHY THIS EXISTS OUTSIDE THE VIEW. `RootShell` renders the composer as
/// `if composerOpen { agentSurface }`, so the whole `Composer` is CREATED on
/// every raise and DESTROYED on every lower. Everything it held in `@State`
/// went with it — including the composed board and the corpus counters behind
/// the ask chips — so each open rebuilt both from nothing: a full-corpus fetch
/// (~761ms measured on 13,412 rows, one uninterruptible call on the main actor
/// during the rise animation) and a fresh panel composition (~1.6s).
///
/// That is what "the agent is laggy opening" was. Not the first open — every
/// open, identically, forever.
///
/// Two caches, and they are cached for different reasons:
///
///   • `board` is EXPENSIVE and slow-changing. Showing the previous one
///     immediately and swapping when the new one lands is the same
///     "kick async, repaint on arrival" shape `HomeInsightStore` uses. Without
///     it the bento skeleton is what you see on every single open.
///   • `facts` exists because the two "Show <tag>" chips need a whole-corpus
///     walk that nothing else on the open path needs: `tags` is a
///     transformable array, so it can be neither predicated nor counted in
///     SQL, while every other counter could be a `fetchCount` or a
///     date-predicated read.
///
/// The freshness cost is one open — a chip count or a figure can be one
/// arrival behind until the refresh lands, which `Composer.composeBoard` does
/// on every open behind the board. That is the same trade the debounced feed
/// and the scoped brief's partial already make, and being one behind is a
/// different thing from being wrong.
///
/// Process-wide rather than per-window: which chips the agent offers is a fact
/// about the corpus, not about a window (`ChipMemory` and `KeptAskStore` are
/// process-wide for the same reason). A second window opening the agent should
/// see what the first one already computed, not pay for it again.
    @MainActor
    @Observable
    final class AgentOpenCache {
    static let shared = AgentOpenCache()

    // The cached BOARD is gone with the panel it served (prd §386p). Its
    // sibling — the chip counters — is the reason this type still exists:
    // that walk is the expensive one, and it is still paid once per launch
    // rather than once per open.

    /// The last corpus-wide chip counters, or nil if never computed. Nil is
    /// the one open that pays the full walk.
    var facts: AgentChipFacts?

    private init() {}

    /// Compute the chip counters before anyone asks for them, so the FIRST
    /// agent open of a launch is as cheap as every one after it (2026-08-12).
    ///
    /// DELAYED, and that is the design rather than a detail. The walk costs
    /// ~761ms of main actor on a 13,412-row corpus, so running it inside the
    /// foreground sweep would move the stall off the agent's rise and onto the
    /// launch — trading the lag just reported for the one reported before it.
    /// It runs once the app has settled, when nobody is waiting on the actor.
    ///
    /// No-ops if a real open already populated the cache: an open computes the
    /// same thing, and its copy is both newer and knows which room it came
    /// from (`contextSourceRecent`, which this pass cannot know).
    func warm(context: ModelContext, after delay: Duration = .seconds(4)) {
        guard facts == nil else { return }
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard facts == nil else { return }   // an open beat us to it
            let scanned = await AgentChipFacts.scanPaged(context: context,
                                                         contextSource: nil, now: .now)
            // An empty corpus leaves nothing worth caching. Asked of the walk's
            // own row count rather than of the fetched array, so it counts what
            // was actually READ — a store holding nothing and a store whose
            // every row was a tombstone are the same answer here, and both
            // should leave the cache cold for the next open to try again.
            guard scanned.rowsScanned > 0 else { return }
            facts = scanned
            #if DEBUG
            NSLog("[Casberi] agentCache| warmed from %d things", scanned.rowsScanned)
            #endif
        }
    }
}

/// Every corpus-wide counter `computeSuggestions()` needs, gathered in ONE
/// walk (PERF 2026-08-11 — see the call site for why eleven walks was the
/// composer's open latency). Each field below replaces a `filter`/
/// `contains`/`first` that used to traverse the whole corpus on its own.
    struct AgentChipFacts {
    /// The person's own tags — every tag minus the built-in kind tags —
    /// sorted, exactly as `RootShell.projectTags` returned them.
    var tagPool: [String] = []
    /// Things per tag, keyed by the LOWERCASED tag, each thing counted
    /// once per distinct tag (matching the old case-insensitive filter).
    var tagCounts: [String: Int] = [:]
    /// Every distinct `source` present — answers all three of the old
    /// `contains(where: { $0.source == … })` scans at once.
    var sourcesSeen: Set<String> = []
    var todayCount = 0
    var weekCount = 0
    var overdueCount = 0
    var upcomingCount = 0
    /// Things from the caller's `contextSource` in the last three days.
    var contextSourceRecent = 0
    /// The publisher (RSS feed, Substack, watched social account — all in
    /// `Thing.authorHandle`) that dominated the recent window, when one
    /// clearly did (2026-07-22). "Recent" is the frozen away window when
    /// one holds, else the last 24h; "dominated" means ≥5 things AND at
    /// least double the next-busiest handle, so an ordinarily-chatty feed
    /// doesn't trip it every day — only a genuine burst. nil = no chip.
    var busyPublisher: (handle: String, count: Int)?
    /// How many rows the walk that produced these counters actually read.
    /// Its one job is to tell an empty corpus from a corpus that was read and
    /// had nothing to say — the paged walk below never holds the array the
    /// old `!corpus.isEmpty` guard tested.
    var rowsScanned = 0

    /// The state ONE walk accumulates.
    ///
    /// Pulled out of `scan` (PERF 2026-08-18) so `scanPaged` below can split
    /// the walk across several turns of the run loop: a single `fetch` of the
    /// whole store is one uninterruptible main-actor call, and on the agent's
    /// FIRST open of a launch — before `warm` has landed — that call is the
    /// rise animation's dropped frames. Paging needs somewhere to keep the
    /// running totals between pages, and this is it.
    ///
    /// The gates live here and ONLY here, so the paged walk and the
    /// whole-array walk can never come to different answers. They are still
    /// the same gates copied verbatim from the eleven filters they replaced.
    @MainActor
    struct Accumulator {
        private(set) var facts = AgentChipFacts()
        private let src: String?
        private let now: Date
        private let dayStart: Date
        private let weekAgo: Date
        private let contextRecent: Date
        private let horizon: Date?
        /// The busy-publisher window: the frozen away gap, or the last day.
        private let busyStart: Date
        private var busyCounts: [String: Int] = [:]
        private var rawTags: Set<String> = []
        private var countedHere: Set<String> = []

        init(contextSource src: String?, now: Date) {
            self.src = src
            self.now = now
            dayStart = Calendar.current.startOfDay(for: now)
            weekAgo = now.addingTimeInterval(-7 * 86_400)
            contextRecent = now.addingTimeInterval(-3 * 86_400)
            horizon = Calendar.current.date(byAdding: .day, value: 7, to: now)
            busyStart = AppVisit.away?.lowerBound ?? now.addingTimeInterval(-24 * 3600)
        }

        mutating func absorb(_ thing: Thing) {
            facts.rowsScanned += 1
            let source = thing.source
            let captured = thing.capturedAt
            facts.sourcesSeen.insert(source)
            if captured >= dayStart { facts.todayCount += 1 }
            if captured >= weekAgo { facts.weekCount += 1 }
            if let src, source == src, captured >= contextRecent { facts.contextSourceRecent += 1 }
            if captured >= busyStart,
               let raw = thing.authorHandle?.trimmingCharacters(in: .whitespaces),
               !raw.isEmpty {
                busyCounts[raw, default: 0] += 1
            }
            // The two deadline counters share one `mark`/`dueAt` read.
            if thing.mark != .done {
                let due = thing.dueAt
                if source == "Reminders" || source == "Todoist",
                   (due ?? .distantFuture) < now {
                    facts.overdueCount += 1
                }
                if let horizon, let when = due, when >= now, when <= horizon {
                    facts.upcomingCount += 1
                }
            }
            // One `tags` read feeds both the vocabulary and the counts.
            //
            // `countedHere` is hoisted and cleared rather than built per row:
            // a thing carries a handful of tags, and allocating a `Set` for
            // each of 12,000 rows costs more than the dedupe it performs. It
            // exists at all so "Recipes" and "recipes" on ONE thing still
            // count that thing once, matching the case-insensitive `filter`
            // this replaced.
            countedHere.removeAll(keepingCapacity: true)
            for tag in thing.tags {
                rawTags.insert(tag)
                let lower = tag.lowercased()
                if countedHere.insert(lower).inserted { facts.tagCounts[lower, default: 0] += 1 }
            }
        }

        func finish() -> AgentChipFacts {
            var out = facts
            let typeTags = Set(ThingKind.allCases.map(\.typeTag))
            out.tagPool = Array(rawTags.subtracting(typeTags)).sorted()
            // The old `busyPublisher`'s own gates, unchanged: a real leader
            // (5+), and at least double the runner-up, or it isn't a burst.
            let sorted = busyCounts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            if let top = sorted.first, top.value >= 5 {
                let runnerUp = sorted.count > 1 ? sorted[1].value : 0
                if top.value >= runnerUp * 2 { out.busyPublisher = (top.key, top.value) }
            }
            return out
        }
    }

    /// ONE traversal, every counter — CHUNKED, so reading the rows yields
    /// between chunks instead of holding the main actor for all of it
    /// (PERF 2026-08-18).
    ///
    /// Identical arithmetic to the single-pass walk it replaces, and identical
    /// total cost; the difference is that it is INTERRUPTIBLE. It measured ~761ms on a
    /// 13,412-row corpus as one uninterruptible main-actor call, and the one
    /// moment it is reachable is the agent's FIRST open of a launch — before
    /// `AgentOpenCache.warm` has landed — i.e. exactly during the rise
    /// animation. Chunked, the same work becomes a run of short blocks the run
    /// loop can draw between: the chips arrive when they always did, the morph
    /// no longer freezes waiting for them.
    ///
    /// WHAT THIS DELIBERATELY DOES NOT DO: page the FETCH. The obvious version
    /// asks SQLite for the rows `fetchOffset`/`fetchLimit` at a time, which
    /// would make the fetch interruptible too — and would very likely cost
    /// MORE in total. Paging needs a deterministic order, `Thing.capturedAt`
    /// carries no index, so every page would re-sort the whole table and then
    /// discard the rows before its offset: nine pages of a 13,000-row corpus
    /// is nine full sorts in place of one unordered scan. Trading a freeze for
    /// a longer total wait is not a fix, and nothing on this host can measure
    /// which way it lands — so the fetch is left exactly as it was and only
    /// the half that is provably safe to slice gets sliced.
    ///
    /// Not tuning: `chunk` decides how finely the work is divided, never how
    /// much of it there is.
    ///
    /// LIVENESS: `all` is held across the yields, which is the corollary-6
    /// shape (a `[Thing]` across a suspension is stale on resume) — a
    /// foreground heal really can delete a row mid-walk. Guarded the way that
    /// corollary prescribes, one step stronger than a re-filter: every row is
    /// re-checked immediately before it is read, so a tombstone is skipped
    /// rather than merely filtered out a chunk late.
    @MainActor
    static func scanPaged(context: ModelContext, contextSource src: String?,
                          now: Date, chunk: Int = 1500) async -> AgentChipFacts {
        let all = (try? context.fetch(FetchDescriptor<Thing>())) ?? []
        var acc = Accumulator(contextSource: src, now: now)
        var i = 0
        while i < all.count {
            let end = min(i + chunk, all.count)
            for n in i..<end where all[n].isLive { acc.absorb(all[n]) }
            i = end
            if i < all.count { await Task.yield() }
        }
        return acc.finish()
    }
}
