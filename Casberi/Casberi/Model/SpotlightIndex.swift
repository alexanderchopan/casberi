import Foundation
import CoreSpotlight
import SwiftData

/// Spotlight — things are findable from the system's own search (goal 4 at
/// the OS level: one home, reachable from anywhere). Titles, content, and
/// tags index; tapping a result deep-links into the thing sheet. The index
/// mirrors the store: save indexes, delete deindexes, launch reconciles.
enum SpotlightIndex {

    private static let domain = "things"
    /// The newest `capturedAt` the launch reconcile has already indexed. The
    /// reconcile indexes only things past it, then advances it.
    private static let watermarkKey = "spotlight.watermark"

    static func index(_ things: [Thing]) {
        guard !things.isEmpty else { return }
        let items = things.map { thing in
            let attrs = CSSearchableItemAttributeSet(contentType: .text)
            attrs.title = thing.title
            attrs.contentDescription = thing.content.isEmpty
                ? "A \(thing.kind.typeTag.lowercased()) in Casberi"
                : thing.content
            attrs.keywords = thing.tags + [thing.source, "Casberi"]
            return CSSearchableItem(
                uniqueIdentifier: thing.id.uuidString,
                domainIdentifier: domain,
                attributeSet: attrs
            )
        }
        CSSearchableIndex.default().indexSearchableItems(items)
    }

    static func remove(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        CSSearchableIndex.default()
            .deleteSearchableItems(withIdentifiers: ids.map(\.uuidString))
    }

    static func removeAll() {
        CSSearchableIndex.default()
            .deleteSearchableItems(withDomainIdentifiers: [domain])
        // The index is empty now — clearing the watermark makes the next
        // launch reconcile rebuild it in full (the "explicit reset" path,
        // reached by Delete everything).
        UserDefaults.standard.removeObject(forKey: watermarkKey)
    }

    /// Launch reconciliation — INCREMENTAL. Covers things the share extension
    /// (or a CloudKit merge) landed while the app was closed by indexing only
    /// what's newer than the watermark, then advancing it — the old build
    /// deleted and rewrote the entire index every launch. In-app captures and
    /// bridge ingests already index inline at save, so they're never missed
    /// regardless of the watermark. A full rebuild happens only after
    /// `removeAll()` clears the watermark (Delete everything). Known gap: a
    /// thing synced from another device but authored before the local
    /// watermark won't appear in Spotlight until the next reset — acceptable
    /// against re-indexing the whole corpus on every launch.
    static func reindexAll(context: ModelContext) {
        let defaults = UserDefaults.standard
        let watermark = defaults.object(forKey: watermarkKey) as? Date
        var descriptor = FetchDescriptor<Thing>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        if let watermark {
            descriptor.predicate = #Predicate { $0.capturedAt > watermark }
        }
        let things = (try? context.fetch(descriptor)) ?? []
        guard !things.isEmpty else { return }
        index(things)
        // Sorted newest-first, so the first row carries the new high-water mark.
        if let newest = things.first?.capturedAt {
            defaults.set(newest, forKey: watermarkKey)
        }
    }
}
