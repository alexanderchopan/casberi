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
    static func dedupeBySourceRef(context: ModelContext) {
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
        for thing in withRefs {
            guard let ref = thing.sourceRef, !ref.isEmpty else { continue }
            if seenRefs.contains(ref) { duplicates.append(thing) } else { seenRefs.insert(ref) }
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
        for thing in looseThings {
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
        guard !duplicates.isEmpty else { return }

        SpotlightIndex.remove(ids: duplicates.map(\.id))
        for duplicate in duplicates { context.delete(duplicate) }
        context.saveHonestly()
    }
}
