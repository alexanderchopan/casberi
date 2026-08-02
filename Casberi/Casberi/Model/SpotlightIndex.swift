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

    /// The shared attribute-set builder — title/description/keywords, the one
    /// place both the manual CoreSpotlight index below and `ThingEntity`'s
    /// semantic-Spotlight `IndexedEntity` conformance draw from, so the two
    /// index surfaces never drift apart on what a thing says about itself.
    static func attributeSet(for thing: Thing) -> CSSearchableItemAttributeSet {
        let attrs = CSSearchableItemAttributeSet(contentType: .text)
        // The credential tripwire (prd §276, 2026-08-02). This donation is the
        // widest surface the corpus has — system-wide Spotlight plus the
        // semantic index Siri and Apple Intelligence ground on — and all of it
        // sits OUTSIDE the app. A screenshot's OCR lands on `content`
        // (ScreenshotIngest.heal) and can name the title too, so a recovery
        // phrase or a password becomes system-searchable text nobody chose to
        // publish. Spans are hidden HERE and only here: the stored thing keeps
        // its real text, so Find and `Retriever` still match on it in-app.
        attrs.title = SecretScan.redacted(thing.title)
        attrs.contentDescription = thing.content.isEmpty
            ? "A \(thing.kind.typeTag.lowercased()) in Casberi"
            : SecretScan.redacted(thing.content)
        attrs.keywords = SecretScan.safeTags(thing.tags) + [thing.source, "Casberi"]
        return attrs
    }

    static func index(_ things: [Thing]) {
        guard !things.isEmpty else { return }
        let items = things.map { thing in
            let attrs = attributeSet(for: thing)
            // The association is what makes `ThingEntity: IndexedEntity` real
            // (2026-07-21): conformance alone donates nothing — until the
            // entity rides an indexed item, the semantic index Siri/Apple
            // Intelligence ground on never receives the corpus, only the
            // plain-text rows. Same uniqueIdentifier as the entity id, so a
            // tapped result and OpenThingIntent agree on which thing it is.
            attrs.associateAppEntity(ThingEntity(thing), priority: 0)
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
