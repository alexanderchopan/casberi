import Foundation
import SwiftData

/// Taking one import back out (2026-08-05, prd §310).
///
/// WHY THIS EXISTS. Deleting was all-or-nothing: the Data tray's "Delete
/// everything" (and its sibling verb, "Delete access" — ruling 2026-07-13) or
/// nothing at all. Disconnecting a bridge does not remove its things either,
/// deliberately, because for a live bridge the things are yours and the
/// connection is just how they arrived.
///
/// An IMPORT breaks that reasoning, and the caps are what broke it. At five
/// hundred rows a room you regretted was a nuisance; §307 and §309 raised the
/// caps by more than an order of magnitude, so the same regret is now fifteen
/// thousand rows of somebody's teenage Snapchat sitting in a corpus they use
/// for work, with no way out that doesn't also delete everything else they own.
/// A person who can put a decade in with one tap should be able to take that
/// decade back out the same way.
///
/// SCOPED TO IMPORTS ON PURPOSE. This is not a general "delete a source" — a
/// live bridge's rows keep arriving, so removing them is a sync artefact rather
/// than a decision, and the honest verb there is Disconnect. Only
/// `Corpus.bulkImportSources` members qualify, which are exactly the rooms that
/// arrived in one deliberate act and can be re-imported by repeating it.
///
/// CHUNKED for `ImportCommit`'s reason and one more of its own: every delete
/// here lands on the MAIN context while a `@Query` feed may be watching, and
/// dropping fifteen thousand rows in a single transaction is both a long frame
/// and a very large observation storm. Saving per chunk spreads it, and the
/// yield lets the feed repaint between chunks instead of after all of them.
enum ImportRemoval {

    /// Rows per chunk — `ImportCommit.chunk`, deliberately the same number
    /// rather than a second constant that could drift from it.
    private static var chunk: Int { ImportCommit.chunk }

    /// How many things this source would remove, for the button to name before
    /// it is tapped. A count, not a promise: rows can arrive or leave between
    /// the count and the tap, and the removal below re-reads.
    @MainActor
    static func count(source: String, context: ModelContext) -> Int {
        guard Corpus.bulkImportSources.contains(source) else { return 0 }
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate { $0.source == source })
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Removes every thing from an imported source, its receipt included, and
    /// returns how many went. Zero for a source that isn't an import — the
    /// guard is here rather than only at the call site so a future caller
    /// can't route a live bridge through it by accident.
    ///
    /// The RECEIPT goes with them: it is All's only record that the import
    /// happened, so leaving it behind would leave a row saying "Imported 12,431
    /// things from Snapchat" pointing at an empty room.
    @MainActor
    @discardableResult
    static func removeAll(source: String, context: ModelContext,
                          progress: ((Int) -> Void)? = nil) async -> Int {
        guard Corpus.bulkImportSources.contains(source) else { return 0 }
        var removed = 0
        // Re-fetched each round rather than held: the array is a snapshot, and
        // deleting through a stale one is the exact liveness trap CLAUDE.md's
        // corollaries are about. A bounded fetch per round also keeps peak
        // memory flat on a very large room.
        while true {
            var descriptor = FetchDescriptor<Thing>(
                predicate: #Predicate { $0.source == source })
            descriptor.fetchLimit = chunk
            let batch = ((try? context.fetch(descriptor)) ?? []).filter(\.isLive)
            if batch.isEmpty { break }
            // Ids BEFORE the delete — reading a stored property off a
            // tombstoned model traps inside SwiftData, and `remove(ids:)`
            // needs them after.
            let ids = batch.map(\.id)
            for thing in batch { context.delete(thing) }
            guard (try? context.save()) != nil else { break }
            SpotlightIndex.remove(ids: ids)
            removed += batch.count
            progress?(removed)
            await Task.yield()
        }
        return removed
    }

    /// When this source was last imported — the receipt's own date, which
    /// `ImportReceipt.land` re-stamps on every run. nil when nothing was ever
    /// imported from it.
    ///
    /// No new field: the receipt already IS the record of when the import ran,
    /// and it was simply never read for this.
    @MainActor
    static func lastImported(source: String, context: ModelContext) -> Date? {
        let ref = Corpus.importReceiptRef(source: source)
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate { $0.sourceRef == ref })
        guard let receipt = (try? context.fetch(descriptor))?.first, receipt.isLive
        else { return nil }
        return receipt.capturedAt
    }

    /// The line a setup screen shows about how old its import is, or nil while
    /// it's recent enough not to matter.
    ///
    /// EVERY IMPORTED ROOM IS FROZEN at the moment it was imported, and nothing
    /// on any of these screens said so — a room quietly six months behind reads
    /// exactly like a room that is up to date, which is the fake-status ban in
    /// its quietest form. There is no live read behind any of these seats to
    /// fix it automatically; the only remedy is to request a fresh export, so
    /// the copy says that.
    ///
    /// Silent under 30 days on purpose. A line that appears the week after an
    /// import is noise, and a nag people learn to ignore is worse than nothing.
    @MainActor
    static func stalenessLine(source: String, context: ModelContext) -> String? {
        guard let when = lastImported(source: source, context: context) else { return nil }
        let days = Calendar.current.dateComponents([.day], from: when, to: .now).day ?? 0
        guard days >= 30 else { return nil }
        let months = days / 30
        let age = months >= 12
            ? String(localized: "over a year ago")
            : (months <= 1 ? String(localized: "a month ago")
                           : String(localized: "\(months) months ago"))
        return String(localized: "Imported \(age). Nothing new arrives on its own — request a fresh export to catch up.")
    }
}
