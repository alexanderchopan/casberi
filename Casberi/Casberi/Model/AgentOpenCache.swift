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

    /// The last composed board. Empty means never composed on this launch,
    /// which is the one open that shows the skeleton.
    var board = AgentPanel.Composition()

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
            let corpus = (try? context.fetch(FetchDescriptor<Thing>())) ?? []
            guard !corpus.isEmpty else { return }
            facts = AgentChipFacts.scan(corpus, contextSource: nil, now: .now)
            #if DEBUG
            NSLog("[Casberi] agentCache| warmed from %d things", corpus.count)
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
    /// The newest Tokens row's title, for the per-token invitation.
    var firstTokenTitle: String?
    /// Things from the caller's `contextSource` in the last three days.
    var contextSourceRecent = 0
    /// The publisher (RSS feed, Substack, watched social account — all in
    /// `Thing.authorHandle`) that dominated the recent window, when one
    /// clearly did (2026-07-22). "Recent" is the frozen away window when
    /// one holds, else the last 24h; "dominated" means ≥5 things AND at
    /// least double the next-busiest handle, so an ordinarily-chatty feed
    /// doesn't trip it every day — only a genuine burst. nil = no chip.
    var busyPublisher: (handle: String, count: Int)?

    /// ONE traversal, every counter. The gates are copied verbatim from the
    /// filters they replace, so the chips say exactly what they said before.
    /// Static and pure over `[Thing]`, so `warm` can call it without a view
    /// (2026-08-12).
    @MainActor
    static func scan(_ all: [Thing], contextSource src: String?, now: Date) -> AgentChipFacts {
    var scan = AgentChipFacts()
    let dayStart = Calendar.current.startOfDay(for: now)
    let weekAgo = now.addingTimeInterval(-7 * 86_400)
    let contextRecent = now.addingTimeInterval(-3 * 86_400)
    let horizon = Calendar.current.date(byAdding: .day, value: 7, to: now)
    // The busy-publisher window: the frozen away gap, or the last day.
    let busyStart = AppVisit.away?.lowerBound ?? now.addingTimeInterval(-24 * 3600)
    var busyCounts: [String: Int] = [:]
    var rawTags: Set<String> = []
    var countedHere: Set<String> = []

    for thing in all {
        let source = thing.source
        let captured = thing.capturedAt
        scan.sourcesSeen.insert(source)
        if captured >= dayStart { scan.todayCount += 1 }
        if captured >= weekAgo { scan.weekCount += 1 }
        if let src, source == src, captured >= contextRecent { scan.contextSourceRecent += 1 }
        if scan.firstTokenTitle == nil, source == "Tokens" {
            let title = thing.title
            if !title.isEmpty { scan.firstTokenTitle = title }
        }
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
                scan.overdueCount += 1
            }
            if let horizon, let when = due, when >= now, when <= horizon {
                scan.upcomingCount += 1
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
            if countedHere.insert(lower).inserted { scan.tagCounts[lower, default: 0] += 1 }
        }
    }

    let typeTags = Set(ThingKind.allCases.map(\.typeTag))
    scan.tagPool = Array(rawTags.subtracting(typeTags)).sorted()

    // The old `busyPublisher`'s own gates, unchanged: a real leader (5+),
    // and at least double the runner-up, or it isn't a burst.
    let sorted = busyCounts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
    if let top = sorted.first, top.value >= 5 {
        let runnerUp = sorted.count > 1 ? sorted[1].value : 0
        if top.value >= runnerUp * 2 { scan.busyPublisher = (top.key, top.value) }
    }
    return scan
    }
}
