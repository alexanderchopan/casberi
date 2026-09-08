import Foundation
import SwiftData

/// The corpus's convergence onto a renamed seat's current name (prd §647,
/// 2026-09-08) — `Corpus.renamedSources` applied to the rows and to the bridge
/// record, at EVERY launch.
///
/// ## Why this is not a migration
///
/// It was one. §629's rename shipped as `RootShell`'s migration v9: one pass
/// over the corpus, gated on the `migrations.version` stamp in `UserDefaults`,
/// i.e. once per install, ever. That is the right shape for a fact about data
/// that is already on the device and the WRONG shape for this store, which
/// mirrors to CloudKit — a row landed on another device, or sitting unmerged in
/// the iCloud zone, arrives whenever it arrives, and every one that lands after
/// the stamp is written keeps the old name for good. A second device still on
/// an older build re-lands them indefinitely. The migration did not merely miss
/// some rows; it could not have caught them, because it answered a question
/// about data that had not arrived yet.
///
/// It reached a device exactly as its own comment predicted it would if it were
/// skipped — *"there is a random tile in the nav bar. looks like ethers gegota
/// and should be in the wallet room! icon missing too"*: no seat, so no
/// category, so the chip escaped `CategoryFold` and drew as a bare circle
/// beside a row of category words, wearing `BridgeGlyph`'s `app` fallback.
///
/// ## Why RESOLUTION being tolerant is not enough on its own
///
/// `Corpus.canonicalSource` (read by `BridgeCatalog.seatNameBySource`,
/// `BridgeIcon`, `BridgeGlyph` and `DS.brandHue`) already fixes what a stale row
/// LOOKS like, on the frame it arrives, with nothing having swept anything —
/// and that half is what makes a mid-session CloudKit merge render correctly.
/// But a ROOM is entered by `Thing.source`, and the surfaces that decide what a
/// room draws compare that string to a seat's own identity (`FeedScreen`'s room
/// heads: `source == HegotaIdentity.source`; the venue switcher's scopes). Every
/// one of those would have to learn the alias independently, which is the
/// cross-file promise `Thing.swift`'s own corollary 4 was written about. So the
/// strings converge instead, and only display is tolerant.
///
/// ## The bound
///
/// One `fetchCount` per entry in `Corpus.renamedSources` (two today), on an
/// indexed `source ==` predicate, behind the first paint. Rows are only
/// materialised when a count comes back non-zero, which in the steady state is
/// never. NOT MEASURED on a device — the claim here is structural (two counted
/// reads whose fetch is skipped when they answer zero), and that is the only
/// claim it is entitled to make until a launch is sampled.
enum SourceRename {
    /// Rewrite every row still carrying a renamed seat's old `source`, and
    /// point the bridge record at the current name. Returns how many rows moved
    /// — zero on every launch but the one that finds stragglers.
    ///
    /// Runs BEFORE `SyncReconcile.dedupeBySourceRef` at the call site, so an
    /// old-named row and its new-named twin (both carrying the same
    /// `sourceRef`) collapse in the same pass rather than the next launch.
    @MainActor
    @discardableResult
    static func sweep(context: ModelContext) -> Int {
        var moved = 0
        for (old, current) in Corpus.renamedSources {
            let descriptor = FetchDescriptor<Thing>(predicate: #Predicate { $0.source == old })
            // Counted first: the whole point of running this every launch is
            // that the launch it finds nothing must cost a count and not a
            // fetch.
            guard let count = try? context.fetchCount(descriptor), count > 0 else { continue }
            let rows = (try? context.fetch(descriptor)) ?? []
            for thing in rows where thing.isLive {
                thing.source = current
                moved += 1
            }
        }
        // SAVED HERE, not by a caller. The one-shot this replaces sat inside
        // the migration block and rode ITS `saveHonestly()`; this runs on every
        // launch, where that block does not run at all, so a sweep that left
        // the save to somebody else would rewrite the rows in memory and lose
        // them — the same correct-looking screen for one session, wrong again
        // on the next launch.
        if moved > 0 { _ = context.saveHonestly() }
        return moved
    }

    /// The seat record's own name. Separate from the rows because it is a
    /// different store (`BridgeStore`'s JSON, not SwiftData) and free to run —
    /// `BridgeStore.rename` returns immediately when the name already matches,
    /// so this costs a walk of ~25 in-memory bridges and no write.
    ///
    /// Keyed by SEAT ID, not by the old name: an id never changes, so this is
    /// correct for a seat renamed twice and for one whose record was written by
    /// a build that never knew the old name at all.
    @MainActor
    static func sweepSeats(_ store: BridgeStore) {
        for (id, name) in seatNames { store.rename(id, to: name) }
    }

    /// Seat id → the name that seat answers to now. Only seats that have been
    /// renamed need an entry; every other bridge record was written under its
    /// current name and has nothing to correct.
    private static let seatNames: [String: String] = [
        HegotaIdentity.seatID: HegotaIdentity.source,
        PrivacyDevnetIdentity.seatID: PrivacyDevnetIdentity.source,
    ]
}
