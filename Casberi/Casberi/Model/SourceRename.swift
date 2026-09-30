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
/// One `fetchCount` per entry in `Corpus.renamedSources` (three today), on an
/// indexed `source ==` predicate, behind the first paint. Rows are only
/// materialised when a count comes back non-zero, which in the steady state is
/// never. NOT MEASURED on a device — the claim here is structural (two counted
/// reads whose fetch is skipped when they answer zero), and that is the only
/// claim it is entitled to make until a launch is sampled.
enum SourceRename {
    /// Rewrite every row still carrying a renamed seat's old `source` — and,
    /// where the rename moved the ref namespace too, its `sourceRef` prefix —
    /// and point the bridge record at the current name. Returns how many rows
    /// moved: zero on every launch but the one that finds stragglers.
    ///
    /// Runs BEFORE `SyncReconcile.dedupeBySourceRef` at the call site, so an
    /// old-named row and its new-named twin (both carrying the same
    /// `sourceRef`) collapse in the same pass rather than the next launch.
    ///
    /// ## `source ==` is a complete key for the REF too (prd §650)
    ///
    /// The fetch keys on the source alone and rewrites the ref off the rows it
    /// gets back, which is only sound if no build ever wrote the NEW source
    /// beside the OLD prefix. For the one entry that has a prefix it is a
    /// checked fact, not an assumption: a2618a2 (2026-07-13) moved
    /// `Thing.source` and the ref prefix in the same commit, so the two have
    /// never disagreed in a row this app wrote. A future rename that lets them
    /// drift apart must key on the ref instead, and the entry that does it owes
    /// its own note here.
    ///
    /// The alternative — a second fetch predicated on the ref prefix — is
    /// deliberately NOT taken. `sourceRef` is optional, and combining `?? ""`
    /// with `.starts(with:)` inside a `#Predicate` has no precedent in this
    /// tree; migration v6 refused to be the first to find out whether that
    /// combination traps, and a sweep that runs on EVERY launch is a worse
    /// place to find out than a one-shot was.
    @MainActor
    @discardableResult
    static func sweep(context: ModelContext) -> Int {
        var moved = 0
        for (old, rename) in Corpus.renamedSources {
            let descriptor = FetchDescriptor<Thing>(predicate: #Predicate { $0.source == old })
            // Counted first: the whole point of running this every launch is
            // that the launch it finds nothing must cost a count and not a
            // fetch.
            guard let count = try? context.fetchCount(descriptor), count > 0 else { continue }
            let rows = (try? context.fetch(descriptor)) ?? []
            for thing in rows where thing.isLive {
                thing.source = rename.current
                // The ref namespace, when the rename took it along. Converging
                // the source alone would leave the row half-way: it would find
                // its seat, its room and its mark, and stay invisible to every
                // consumer that matches the ref EXACTLY — for the one entry
                // that has a prefix, `TokenWatch.add`'s already-watching guard
                // (so the same coin lands twice), the search list's
                // already-watched filter, and `TokenQuickRoute.watchedThing`
                // (so a held token you watch reads as merely held).
                if let prefix = rename.refPrefix,
                   let ref = thing.sourceRef, ref.hasPrefix(prefix.old) {
                    thing.sourceRef = prefix.current + String(ref.dropFirst(prefix.old.count))
                }
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
    /// Keyed by SEAT ID, not by the old name, so this is correct for a seat
    /// renamed twice and for one whose record was written by a build that never
    /// knew the old name at all.
    ///
    /// ## An id CAN change, and one did — the bound on what this fixes (§650)
    ///
    /// §647 justified the id key by saying an id never changes. That is false:
    /// a2618a2 re-keyed the token-watch seat `"dexscreener"` → `"tokens"` along
    /// with its name. So a record written before 2026-07-13 is not merely
    /// mis-named, it is UNREACHABLE from here — no entry below can find it, and
    /// adding one would not help, because this renames a record it locates by
    /// id and that id is the thing that moved.
    ///
    /// Left unfixed ON PURPOSE, with the consequence stated rather than
    /// implied. `AppsScreen` joins a stored bridge to its offer BY NAME
    /// (`$0.name == offer.name`), so such a record leaves Tokens reading
    /// disconnected while its own phantom is still inside `connectedCount`.
    /// Three things make it a different problem from the corpus one, not a
    /// smaller instance of it: `BridgeStore` is a LOCAL JSON file and does not
    /// mirror, so §647's whole argument — that a one-shot cannot be complete
    /// because rows keep arriving — does not apply to it and a one-shot WOULD
    /// be complete here; the repair is a RE-KEY, which `BridgeStore` has no
    /// operation for (renaming the record alone would leave a seat that looks
    /// connected and whose Disconnect removes nothing, i.e. trade a wrong
    /// label for a §83 dead control); and it can only exist on a device that
    /// connected the seat in the six days between the first TestFlight upload
    /// (2026-07-07) and the rename. Worth doing; not worth doing as a silent
    /// rider on a ruling about the corpus.
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
        // Tokens became Markets (2026-09-29); the id stayed "tokens".
        "tokens": TokenWatch.source,
    ]

    /// Stocktwits' WATCHED TICKERS converge onto Markets (2026-09-29), at
    /// EVERY launch, for `sweepVoice`'s reason. The watches move — a row keyed
    /// `stocktwits:sym:` — and keep that ref, the stock namespace `StockWatch`
    /// still writes. The traders' takes are DELETED (user: drop them): a take
    /// is a mirror of a ticker you watch, and §286 already ruled that such a
    /// mirror goes when its follow stops explaining it. Left under the retired
    /// source they would also make this count non-zero forever, so every
    /// launch would pay a fetch.
    ///
    /// NOT `Corpus.renamedSources`: that table moves every row of a source,
    /// and here half of them must not follow.
    @MainActor
    @discardableResult
    static func sweepStockWatches(context: ModelContext, store: BridgeStore) -> Int {
        // The seat records first, and on EVERY launch: `BridgeStore` is local
        // and does not mirror, so a device whose rows another device already
        // moved finds nothing below to sweep and would otherwise keep a
        // phantom Stocktwits seat and never register Markets. Both calls are
        // in-memory and return at once when there is nothing to change.
        if store.bridges.contains(where: { $0.id == "stocktwits" }) {
            store.remove("stocktwits")
            TokenWatch.registerBridge(store: store, context: context)
        }
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate { $0.source == "Stocktwits" })
        guard let count = try? context.fetchCount(descriptor), count > 0 else { return 0 }
        var moved = 0
        var dropped: [Thing] = []
        for thing in (try? context.fetch(descriptor)) ?? [] where thing.isLive {
            if (thing.sourceRef ?? "").hasPrefix(StockWatch.refPrefix) {
                thing.source = TokenWatch.source
                moved += 1
            } else {
                dropped.append(thing)
            }
        }
        SpotlightIndex.remove(ids: dropped.map(\.id))
        for thing in dropped { context.delete(thing) }
        if moved > 0 || !dropped.isEmpty { _ = context.saveHonestly() }
        // The watches it held keep Markets connected.
        if moved > 0 { TokenWatch.registerBridge(store: store, context: context) }
        return moved
    }

    /// Voice notes converge onto `You` (prd §972), at EVERY launch.
    ///
    /// A voice note's source was "Voice" from 2026-07-06 — a source with no
    /// seat, filed under Notes by hand, which drew a "Voice" room in the tray
    /// and split the kind in two once the note sheet began keeping voice notes
    /// under `You`. The name is retired: every voice note is a note of yours,
    /// in the Notes room, with the kept-note anatomy.
    ///
    /// NOT `Corpus.renamedSources`, whose values must be live offers
    /// (`source-alias-audit.py` check A) — `You` is no seat, and bending that
    /// table would weaken the check that caught a real stranded seat. The
    /// SHAPE is the same one for the same reason: rows from another device
    /// still on an older build, or unmerged in the iCloud zone, land after any
    /// one-shot has run. One counted read on an indexed `source ==` predicate,
    /// and a fetch only when it answers non-zero — which in the steady state
    /// is never.
    @MainActor
    @discardableResult
    static func sweepVoice(context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate { $0.source == "Voice" })
        guard let count = try? context.fetchCount(descriptor), count > 0 else { return 0 }
        var moved = 0
        for thing in (try? context.fetch(descriptor)) ?? [] where thing.isLive {
            thing.source = NoteSheetSource.keptSource
            moved += 1
        }
        // Saved here for the reason `sweep` saves its own: this runs on every
        // launch, where the migration block that used to carry saves does not.
        if moved > 0 { _ = context.saveHonestly() }
        return moved
    }
}
