import Foundation
import SwiftData

/// The one row a bulk import puts in the All feed (2026-07-31).
///
/// Instagram and Snapchat land thousands of things in a single pass, dated
/// across years, so `Corpus.bulkImportSources` keeps their things out of the
/// All feed entirely — one import would otherwise bury every real capture the
/// day it ran. Their source chip still opens a room holding all of it; what
/// All gets instead is this: one line saying the import happened.
///
/// RECONCILING, never stacking — the `ENSExpiry` shape. The ref is stable per
/// source (`Corpus.importReceiptRef`), so a second import rewrites this same
/// row with the new total rather than leaving a pile of "you imported" rows
/// behind it. A pile is exactly what All is being protected from, so the
/// receipt must not become one.
///
/// It carries the source's OWN name, so it sits in that source's room too —
/// correct, since the import is a real event in that room's history, and the
/// room is where the count sends you.
enum ImportReceipt {

    /// Lands (or updates) the receipt for one bulk-import source.
    ///
    /// `count` is what the importer actually landed; `detail` is the honest
    /// breakdown ("312 saved · 1,204 comments"), shown as the row's content.
    /// A zero count writes nothing — an import that landed nothing is not an
    /// event, and a "0 things" row in All would be noise claiming to be news.
    @MainActor
    static func land(source: String, count: Int, detail: String,
                     context: ModelContext) {
        guard count > 0 else { return }
        let ref = Corpus.importReceiptRef(source: source)
        let title = count == 1
            ? String(localized: "Imported 1 thing from \(source)")
            : String(localized: "Imported \(count) things from \(source)")

        if let existing = try? context.fetch(FetchDescriptor<Thing>(
            predicate: #Predicate { $0.sourceRef == ref })).first {
            existing.title = title
            existing.content = detail
            // Re-dated on purpose: the second import IS today's news, and a
            // receipt still wearing the first import's date would sort back
            // into the past where nobody would see that it ran again.
            existing.capturedAt = .now
            return
        }

        let thing = Thing(kind: .note, title: title, content: detail,
                          source: source, sourceRef: ref)
        context.insert(thing)
        SpotlightIndex.index([thing])
    }
}
