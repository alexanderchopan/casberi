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
        // The credential tripwire (prd §277, 2026-08-02). This donation is the
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
    ///
    /// CHUNKED, so the walk is interruptible (PERF 2026-09-01, perf-spec P5.4).
    /// Same rows, same donations, same watermark — the difference is that this
    /// no longer holds the main actor for all of it in one call. It runs 400ms
    /// after the first frame, i.e. exactly as the person starts scrolling, and
    /// the watermark means the steady-state launch indexes a handful of rows
    /// and costs nothing. It is the COLD pass that is whole-corpus — a fresh
    /// install, a CloudKit zone pulling in, or the launch after Delete
    /// everything cleared the watermark — and that is the pass this exists
    /// for: chunked, the same work becomes a run of short blocks the run loop
    /// can draw between.
    ///
    /// Not a truncation and not a `fetchLimit`: the fetch is untouched and
    /// every row it returns is still indexed. Only the WALK is sliced —
    /// `scanPaged`'s ruling, for its reason: paging the fetch needs a
    /// deterministic order, `Thing.capturedAt` carries no index, so every page
    /// would re-sort the whole table (see `AgentOpenCache.scanPaged`).
    ///
    /// The watermark is read off the array BEFORE the first yield and written
    /// only after the last chunk. Both halves matter: reading it at the end
    /// would be a stored-property read on a row a heal may have deleted
    /// (corollary 6), and advancing it early would let a cancelled run claim
    /// rows it never donated — as it stands a cancelled or crashed pass simply
    /// re-indexes next launch, which is what happened before this was async.
    ///
    /// LIVENESS: `things` is held across the yields, which is the corollary-6
    /// shape — a foreground heal really can delete a row mid-walk, and
    /// `attributeSet(for:)` reads `title`/`content`/`tags`/`source` off it.
    /// Guarded the way `scanPaged` guards it: every row is re-checked inside
    /// the chunk, immediately before it is read.
    static func reindexAll(context: ModelContext, chunk: Int = 500) async {
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
        // Sorted newest-first, so the first row carries the new high-water
        // mark — taken here, while nothing has suspended yet.
        let newest = things.first?.capturedAt
        var i = 0
        while i < things.count {
            let end = min(i + chunk, things.count)
            index(things[i..<end].filter(\.isLive))
            i = end
            if i < things.count {
                await Task.yield()
                // A cancelled pass leaves the watermark where it was, so the
                // rows it hadn't reached are indexed next launch rather than
                // silently skipped forever.
                if Task.isCancelled { return }
            }
        }
        if let newest { defaults.set(newest, forKey: watermarkKey) }
    }
}
