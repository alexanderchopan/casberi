import Foundation
import SwiftData

/// CloudKit sync (M1) can land the same thing twice — two devices insert it
/// before they've synced, and CloudKit has no unique constraint to stop it. This
/// collapses duplicates that share a `sourceRef` (the stable source identity
/// ingestion already dedupes on), keeping the earliest and removing the rest.
///
/// Inert until sync is on: nothing makes duplicates on a single local device, so
/// the guard returns immediately and this never touches the store pre-sync.
@MainActor
enum SyncReconcile {
    static func dedupeBySourceRef(context: ModelContext) {
        guard SharedStore.syncEnabled else { return }
        let all = (try? context.fetch(FetchDescriptor<Thing>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        ))) ?? []

        var seen: Set<String> = []
        var duplicates: [Thing] = []
        for thing in all {
            guard let ref = thing.sourceRef, !ref.isEmpty else { continue }
            if seen.contains(ref) { duplicates.append(thing) } else { seen.insert(ref) }
        }
        guard !duplicates.isEmpty else { return }

        SpotlightIndex.remove(ids: duplicates.map(\.id))
        for duplicate in duplicates { context.delete(duplicate) }
        try? context.save()
    }
}
