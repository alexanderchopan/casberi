import Foundation
import SwiftData

/// CloudKit sync (M1) can land the same thing twice — two devices insert it
/// before they've synced, and CloudKit has no unique constraint to stop it. This
/// collapses duplicates that share a `sourceRef` (the stable source identity
/// ingestion already dedupes on), keeping the earliest and removing the rest.
///
/// A manual capture (a typed note, a voice memo, a composer paste) has no
/// `sourceRef` — nothing ties it to a stable source identity — so it fell
/// through this reconciliation entirely; the same capture made just before a
/// sync landed could duplicate across devices with no cleanup. Below the
/// sourceRef pass, a second, deliberately narrow pass catches only an EXACT
/// title+content+kind+source match within a few seconds: tight enough that
/// it should only ever fire on the literal same capture racing, never on two
/// genuinely different things that happen to look alike — an over-eager
/// heuristic here would silently delete real, distinct user data, which is
/// worse than leaving a rare duplicate in place.
///
/// Inert until sync is on: nothing makes duplicates on a single local device, so
/// the guard returns immediately and this never touches the store pre-sync.
@MainActor
enum SyncReconcile {
    /// How close together two sourceRef-less captures with identical content
    /// must land to be treated as the same write racing across devices,
    /// rather than a coincidence.
    private static let exactMatchWindow: TimeInterval = 5

    /// Two passes, not one (2026-07-31 perf). This runs on the main actor at
    /// every launch, and its single unqualified `fetch` materialized the WHOLE
    /// corpus with every column — including `content`/`enrichedText`/`postText`,
    /// the heavy inline text — to read, for almost every row, one short string.
    /// The two passes want genuinely different columns, so asking for the union
    /// of them made the common case pay for the rare one: things WITH a
    /// sourceRef (every bridge row, i.e. nearly the entire corpus) `continue`
    /// before the text is ever touched, and only the ref-LESS handful (manual
    /// notes, voice memos, composer pastes) need it.
    ///
    /// Splitting them changes no outcome: the two groups never compare against
    /// each other, so running them separately is the same walk in two parts.
    ///
    /// CHUNKED, so both walks are interruptible (PERF 2026-09-01, perf-spec
    /// P5.4). Pass 1's fetch is unqualified — every row in the corpus, and the
    /// 2026-07-31 split above made it CHEAP per row without making it
    /// BOUNDED — and it runs 400ms after the first frame, i.e. while the
    /// person is starting to scroll. Same rows, same signatures, same
    /// duplicates, same single save; the difference is that the walk is now a
    /// run of short blocks the run loop can draw between instead of one
    /// uninterruptible main-actor call.
    ///
    /// Not a truncation: no `fetchLimit` is added to either fetch, and a
    /// duplicate seen after any yield is collapsed exactly as before. Only the
    /// WALK is sliced, never the fetch — paging a `createdAt`-sorted fetch
    /// would re-sort the table per page (`AgentOpenCache.scanPaged`'s ruling),
    /// which trades a freeze for a longer total wait.
    ///
    /// The delete runs AFTER the last yield with no suspension of its own, so
    /// one `.live` filter at that point is the whole guard: from there the
    /// main actor is held exclusively and nothing can delete underneath it.
    /// That is corollary 6's own stated condition, spelled out here because it
    /// is the reason this doesn't need a re-check per delete.
    ///
    /// LIVENESS: `withRefs` and `looseThings` are both held across yields —
    /// the corollary-6 shape, and this function's own concurrent heal (a
    /// bridge sweep deleting upstream-gone rows) is exactly what makes it
    /// real. Every row is re-checked inside its chunk immediately before it is
    /// read, the way `scanPaged` does it.
    static func dedupeBySourceRef(context: ModelContext, chunk: Int = 1500) async {
        guard SharedStore.syncEnabled else { return }

        // Pass 1 — the sourceRef duplicates. Three columns, no text. `createdAt`
        // is in the set because it's the sort key, and a sort on an unfetched
        // property would fault every row back in and undo the whole point.
        var refDescriptor = FetchDescriptor<Thing>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)])
        refDescriptor.propertiesToFetch = [\.id, \.sourceRef, \.createdAt]
        let withRefs = (try? context.fetch(refDescriptor)) ?? []

        var seenRefs: Set<String> = []
        var duplicates: [Thing] = []
        var i = 0
        while i < withRefs.count {
            let end = min(i + chunk, withRefs.count)
            for n in i..<end where withRefs[n].isLive {
                let thing = withRefs[n]
                guard let ref = thing.sourceRef, !ref.isEmpty else { continue }
                if seenRefs.contains(ref) { duplicates.append(thing) } else { seenRefs.insert(ref) }
            }
            i = end
            if i < withRefs.count { await Task.yield() }
        }

        // Pass 2 — the ref-less captures, fully hydrated because the signature
        // IS their text. Scoped by predicate so this is the small set, not the
        // corpus.
        var looseDescriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.sourceRef == nil || $0.sourceRef == "" },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)])
        looseDescriptor.propertiesToFetch = [
            \.id, \.createdAt, \.kind, \.source, \.title, \.content,
        ]
        let looseThings = (try? context.fetch(looseDescriptor)) ?? []

        var seenSignatures: [String: Date] = [:]
        var j = 0
        while j < looseThings.count {
            let end = min(j + chunk, looseThings.count)
            for n in j..<end where looseThings[n].isLive {
                let thing = looseThings[n]
                // Nothing meaningful to compare (an empty note) — never collapse.
                guard !thing.title.isEmpty || !thing.content.isEmpty else { continue }
                let signature = "\(thing.kind.rawValue)|\(thing.source)|\(thing.title)|\(thing.content)"
                if let priorCreatedAt = seenSignatures[signature],
                   abs(thing.createdAt.timeIntervalSince(priorCreatedAt)) < exactMatchWindow {
                    duplicates.append(thing)
                } else {
                    seenSignatures[signature] = thing.createdAt
                }
            }
            j = end
            if j < looseThings.count { await Task.yield() }
        }

        // The last await is above; from here nothing suspends, so this one
        // filter covers every read below (corollary 6's own condition). A row
        // collected before a yield may have been deleted by a heal since —
        // reading `.id` off it, or deleting it twice, is the trap.
        let doomed = duplicates.filter(\.isLive)
        guard !doomed.isEmpty else { return }

        SpotlightIndex.remove(ids: doomed.map(\.id))
        for duplicate in doomed { context.delete(duplicate) }
        context.saveHonestly()
    }
}
