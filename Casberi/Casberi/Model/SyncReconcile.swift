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

    static func dedupeBySourceRef(context: ModelContext) {
        guard SharedStore.syncEnabled else { return }
        let all = (try? context.fetch(FetchDescriptor<Thing>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        ))) ?? []

        var seenRefs: Set<String> = []
        var seenSignatures: [String: Date] = [:]
        var duplicates: [Thing] = []
        for thing in all {
            if let ref = thing.sourceRef, !ref.isEmpty {
                if seenRefs.contains(ref) { duplicates.append(thing) } else { seenRefs.insert(ref) }
                continue
            }
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
