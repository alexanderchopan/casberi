import Foundation
import SwiftData

/// Landing a large import without freezing the app (2026-08-05, prd §310).
///
/// WHY THIS EXISTS. Every importer here ends the same way: build every row,
/// insert them all, save once, hand the whole array to Spotlight. That is fine
/// for a few hundred rows and it is what all four did — because until
/// 2026-08-05 all four were capped at a few hundred rows. §307 and §309 raised
/// those caps by more than an order of magnitude, for good reasons, and in
/// doing so turned a shape that was merely unhurried into one that holds the
/// main thread for as long as the work takes. A person importing fifteen years
/// of anything would have watched the app stop responding with no explanation.
///
/// Every importer is `@MainActor` and must stay that way — they insert into the
/// main context while a live `@Query` feed is watching, which is exactly the
/// arrangement the liveness rules in CLAUDE.md exist to protect. So this does
/// not move the work off the main actor; it BREAKS IT UP, saving each chunk and
/// then yielding so the run loop can draw a frame and the progress line can
/// move. Same actor, same context, same transaction semantics per chunk.
///
/// A CHUNK IS A COMMIT, and that is a deliberate change in failure mode rather
/// than an accident. The old shape was all-or-nothing: one `save()` at the end,
/// so a failure left nothing behind. This lands what it managed, which for an
/// import is the better half of the trade — a person whose 12,000-row import
/// died at row 9,000 keeps 9,000 real things and a re-import fills the rest in
/// (every importer dedupes on `sourceRef`, so re-importing is already the
/// supported repair). The receipt is landed by the CALLER after this returns,
/// so a partial run is never crowned with a receipt claiming a total it didn't
/// reach.
enum ImportCommit {

    /// Rows per chunk. Big enough that the per-save overhead stays amortised,
    /// small enough that one chunk is well under a frame's budget on the
    /// oldest device this ships to. Not tuned against a real import — no real
    /// export has ever been held by this project — so treat it as a starting
    /// point rather than a measured optimum.
    static let chunk = 200

    /// Inserts, saves and indexes in chunks, yielding between each so the UI
    /// keeps breathing. `progress` is called with the running total after every
    /// chunk, on the main actor, for a screen to render.
    ///
    /// Returns false if a save threw — the caller reports that as a failed
    /// import, exactly as it did when there was one save to throw.
    @MainActor
    @discardableResult
    static func commit(_ things: [Thing], context: ModelContext,
                       progress: ((Int) -> Void)? = nil) async -> Bool {
        guard !things.isEmpty else { return true }
        var landed = 0
        for start in stride(from: 0, to: things.count, by: chunk) {
            let slice = Array(things[start..<min(start + chunk, things.count)])
            for thing in slice { context.insert(thing) }
            do {
                try context.save()
            } catch {
                return false
            }
            // Spotlight per chunk rather than one call with fifteen thousand
            // items in it: the donation crosses an XPC boundary, and handing it
            // the whole library at once is the same mistake this file exists to
            // undo, one process over.
            SpotlightIndex.index(slice)
            landed += slice.count
            progress?(landed)
            // The yield is the entire point. Without it every chunk runs
            // back-to-back inside one turn of the run loop and the batching
            // buys nothing at all.
            await Task.yield()
        }
        return true
    }
}
