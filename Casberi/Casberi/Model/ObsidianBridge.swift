import Foundation
import Observation
import SwiftData

/// The Obsidian bridge (2026-07-08) — a vault is a plain folder of Markdown,
/// so it connects by POINTING AT THE FOLDER: the person picks their vault in
/// the document picker, a security-scoped bookmark remembers it, and notes
/// land as note things on every sync. Fully local — no account, no key, no
/// network, and the vault itself is never modified (read-only enumeration).
@Observable
final class ObsidianStore {
    static let shared = ObsidianStore()
    private static let bookmarkKey = "obsidian.bookmark"
    private static let nameKey = "obsidian.vaultName"

    /// The vault's display name — proof of WHICH folder is connected, and the
    /// `vault=` half of the `obsidian://` hand-off (`ObsidianLink`): a vault's
    /// name IS its folder name, which is why one field serves both.
    var vaultName: String {
        didSet { UserDefaults.standard.set(vaultName, forKey: Self.nameKey) }
    }

    private init() {
        vaultName = UserDefaults.standard.string(forKey: Self.nameKey) ?? ""
    }

    var connected: Bool {
        UserDefaults.standard.data(forKey: Self.bookmarkKey) != nil
    }

    /// Saves the picked vault folder. Call within the picker's
    /// security-scoped access window.
    func setVault(url: URL) -> Bool {
        guard let bookmark = try? url.bookmarkData() else { return false }
        UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
        vaultName = url.lastPathComponent
        return true
    }

    func disconnect() {
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        vaultName = ""
    }

    /// Resolves the bookmark to a live URL. Caller must balance
    /// `startAccessingSecurityScopedResource` / stop.
    func vaultURL() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale)
        else { return nil }
        if stale, let fresh = try? url.bookmarkData() {
            UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey)
        }
        return url
    }
}

enum ObsidianIngest {

    /// Single-flight, but TIME-BOXED rather than a bare flag (2026-08-06) —
    /// `FilesIngest.runningSince`'s lesson, applied to the bridge that needs
    /// it MORE than Files does.
    ///
    /// It was `running: Bool`, set before the walk and cleared in a `defer`.
    /// The walk reads Markdown files with `String(contentsOf:)`, and for an
    /// iCloud Drive vault whose bytes aren't on this device that call blocks
    /// with no timeout — so the `defer` never runs, the flag never clears, and
    /// every later refresh returns at the guard for the rest of the app's
    /// life: no new notes, no edits, no deletions, silently and forever. This
    /// bridge's own setup copy tells people their vault is "often iCloud Drive
    /// → Obsidian", so that is the EXPECTED configuration, not an edge case.
    ///
    /// A stuck pass can't be cancelled (the block is inside synchronous
    /// FileManager calls, which ignore Task cancellation), so this doesn't
    /// try: it lets the NEXT pass through once the current one is past
    /// plausibly-alive.
    @MainActor private static var runningSince: Date?
    private static let stuckAfter: TimeInterval = 120

    /// New notes landed per pass, so a giant vault arrives in waves instead of
    /// flooding the feed. Applied AFTER the already-landed filter — see
    /// `refresh`, where applying it before was a silent truncation.
    static let landingCap = 100
    /// Edited notes re-read per pass. Separate from the landing cap so a big
    /// first import can't starve edits, and vice versa.
    static let rereadCap = 100
    /// The one-time repair's cap, deliberately higher than the steady-state
    /// one — see `repairKey`. A vault repairing at 100 a foreground takes
    /// dozens of opens to come right, which to the person who noticed the
    /// broken excerpts reads as the fix not having landed (prd §313's lesson).
    static let repairCap = 500

    /// When the note READER last changed.
    ///
    /// Every landed note carries its file's modification date as `capturedAt`,
    /// which is what lets a pass tell an edited note from an untouched one
    /// with no extra `Thing` field. That watermark has one blind spot, and it
    /// is the same one `ScreenshotTopics.termsEpoch` exists for: a note the
    /// person has NOT edited is untouched by definition, so a change to how we
    /// READ notes reaches only the notes they happen to edit afterwards. For
    /// an established vault — where nearly every note was written months ago —
    /// that is approximately none of them, and the frontmatter excerpts, the
    /// missing tags and the un-indexed bodies would simply stay.
    ///
    /// So a device that has never run the current reader re-reads its whole
    /// vault once, and records that it did. Bumping this date is the entire
    /// procedure for shipping a reader change: the done-flag is keyed by it,
    /// so moving it re-arms the repair by construction rather than by
    /// remembering to clear something.
    static let readerEpoch = Date(timeIntervalSince1970: 1_786_060_000)

    private static var repairKey: String {
        "obsidian.reparse.\(Int(readerEpoch.timeIntervalSince1970))"
    }

    /// What a pass actually did — the probe's view (`-obsidianProbe`). A bare
    /// count can't separate "the vault has nothing new" from "the walk never
    /// ran", and after this pass it also can't separate a note that landed
    /// from one that was re-read or pruned.
    struct Report {
        var walked = 0
        var landed = 0
        var reread = 0
        var pruned = 0
        var pending = 0
        var notDownloaded = 0
        var prunePassed = false
        var repairing = false
        var repairDone = false
    }

    /// One Markdown file from a vault walk, with a FRESH `url` resolved in
    /// THIS walk — never reconstructed from a path string later
    /// (`FilesIngest.WalkedFile`'s lesson: two resolutions of the same
    /// bookmark can standardize differently, and the rebuilt URL then points
    /// at nothing with no error anywhere).
    private struct WalkedNote {
        let ref: String
        let url: URL
        let title: String
        let modified: Date
        /// False for an iCloud Drive note whose bytes aren't on this device
        /// yet. Reading one BLOCKS with no timeout, which is the stall that
        /// used to latch the single-flight flag forever, so a note in this
        /// state lands on its title alone and its words arrive on the pass
        /// after the download.
        ///
        /// It is still PRESENT: it stays in the walk and therefore in the
        /// ref set the prune reads, or "not downloaded" would be mistaken for
        /// "deleted from the vault" and remove a note sitting right there.
        let isDownloaded: Bool
    }

    /// Every `.md` file in the vault, outside dot-directories. Must run inside
    /// an active `startAccessingSecurityScopedResource` window and off the
    /// main actor. nil means the walk itself couldn't start (vault moved or
    /// permission lost) — distinct from an empty array, which is a vault that
    /// genuinely has no notes right now, and the callers rely on that
    /// difference.
    private static func walk(_ vault: URL) -> [WalkedNote]? {
        let fm = FileManager.default
        let base = vault.standardizedFileURL.path
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey,
                                      .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        guard let walker = fm.enumerator(at: vault, includingPropertiesForKeys: keys,
                                         options: [.skipsHiddenFiles]) else { return nil }
        // `allObjects` materializes the walk synchronously — iterating the
        // NSEnumerator directly is unavailable from async contexts in Swift 6.
        var notes: [WalkedNote] = []
        for case let url as URL in walker.allObjects {
            guard url.pathExtension.lowercased() == "md" else { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            let std = url.standardizedFileURL
            let rel = String(std.path.dropFirst(base.count))
            // Metadata reads (dates, download status) are LOCAL even for an
            // evicted iCloud file — it's reading the CONTENTS that blocks.
            let ubiquitous = values?.isUbiquitousItem == true
            let status = values?.ubiquitousItemDownloadingStatus
            notes.append(WalkedNote(
                ref: "obsidian:\(rel)",
                url: std,
                title: std.deletingPathExtension().lastPathComponent,
                modified: values?.contentModificationDate ?? .distantPast,
                isDownloaded: !ubiquitous || status == .current || status == .downloaded))
        }
        return notes
    }

    /// A note's words as they'll be stored, read off disk. Only ever called
    /// for a downloaded file.
    private static func read(_ note: WalkedNote) -> ObsidianNote.Parsed {
        let body = (try? String(contentsOf: note.url, encoding: .utf8)) ?? ""
        return ObsidianNote.parse(body)
    }

    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        await pass(context: context)?.landed
    }

    /// One walk, four jobs: land what's new, re-read what CHANGED, prune what's
    /// gone, and leave a report the probe can read.
    ///
    /// It is one pass rather than a `refresh` + `heal` pair (the shape Photos
    /// and Files use) because a Markdown note is a few kilobytes of text with
    /// no thumbnail to render and no OCR to run — the expensive halves those
    /// bridges split out don't exist here, and a second walk of the same
    /// folder every foreground would cost more than it saves.
    @MainActor
    static func pass(context: ModelContext) async -> Report? {
        let store = ObsidianStore.shared
        guard store.connected else { return nil }
        if let since = runningSince, Date.now.timeIntervalSince(since) < Self.stuckAfter {
            return Report()
        }
        // Clear only OUR marker: a stuck pass that finally returns must not
        // clear the marker of the pass that has since taken over.
        let mine = Date.now
        runningSince = mine
        defer { if runningSince == mine { runningSince = nil } }

        guard let vault = store.vaultURL() else { return nil }

        // What we already hold, and what state we hold it in. `capturedAt` is
        // the file's own modification date at the time we read it, so it
        // doubles as the read watermark and no new `Thing` field (and no
        // CloudKit Production deploy) is needed to know a note has changed.
        //
        // `parsed` is the one-time repair's marker (`readerEpoch`): a note the
        // current reader has handled carries its body on `enrichedText`, and
        // one that predates it carries nil there no matter how old its file is.
        let landedByRef = IngestSupport.thingsByRef(context, source: "Obsidian")
        var prior: [String: (modified: Date, hasWords: Bool, parsed: Bool)] = [:]
        for (ref, thing) in landedByRef where thing.isLive {
            prior[ref] = (thing.capturedAt, !thing.content.isEmpty, thing.enrichedText != nil)
        }
        let existing = Set(prior.keys)
        let repairing = !UserDefaults.standard.bool(forKey: repairKey) && !existing.isEmpty

        // The walk + per-note read happen off the main thread: the vault can
        // be iCloud Drive, and FileManager/String(contentsOf:) silently block
        // on the iCloud download for any file they touch, synchronously on the
        // calling thread. Left on @MainActor, a large or not-yet-downloaded
        // vault freezes the UI and can trip the main-thread watchdog.
        typealias Landing = (note: WalkedNote, parsed: ObsidianNote.Parsed?)
        typealias Outcome = (fresh: [Landing], changed: [Landing],
                             allRefs: Set<String>, walked: Int,
                             pending: Int, notDownloaded: Int, backlog: Int)

        let outcome: Outcome? = await Task.detached(priority: .userInitiated) { () -> Outcome? in
            // False just means the URL wasn't security-scoped (an in-sandbox
            // vault) — reading still works; only balance the stop when it
            // began.
            let scoped = vault.startAccessingSecurityScopedResource()
            defer { if scoped { vault.stopAccessingSecurityScopedResource() } }

            guard let notes = walk(vault) else { return nil }
            let sorted = notes.sorted { $0.modified > $1.modified }

            // THE CAP GOES HERE, AFTER THE FILTER — not before it (2026-08-06).
            //
            // This read `sorted.prefix(100)` and THEN skipped already-landed
            // refs, which meant a vault of more than 100 notes could never
            // finish arriving: pass one landed the newest 100, and every pass
            // after it looked at those same 100, found them all landed, and
            // added nothing. Note 101 and everything older were unreachable
            // unless an edit pushed them into the newest hundred. The doc
            // above it said a big vault "arrives in waves"; the waves never
            // advanced. Filtering first makes that comment true — each pass
            // takes the next hundred it does NOT have.
            let unseen = sorted.filter { !existing.contains($0.ref) }
            var fresh: [Landing] = []
            for note in unseen.prefix(landingCap) {
                // An evicted iCloud note lands on its TITLE — reading it would
                // block this whole pass on a download nobody asked for. Its
                // words arrive below, on a later pass, once the bytes are here.
                fresh.append((note, note.isDownloaded ? read(note) : nil))
            }

            // Re-read: the file has been written since we read it, we landed
            // it without its words (evicted, now downloaded), or the one-time
            // reader repair hasn't reached it. A note is the one thing in this
            // corpus that is EXPECTED to change — every other bridge's rows
            // are events, final when they land — and until now a note's text,
            // tags and links froze at first sight forever.
            let cap = repairing ? repairCap : rereadCap
            var changed: [Landing] = []
            var notDownloaded = 0
            var backlog = 0
            for note in sorted {
                guard let was = prior[note.ref] else { continue }
                let wanted = !was.hasWords || (repairing && !was.parsed)
                guard note.isDownloaded else {
                    if wanted { notDownloaded += 1 }
                    continue
                }
                // A one-second slack: some filesystems and sync clients round
                // modification times, and re-reading an unchanged note every
                // foreground forever is the failure mode to avoid here.
                let edited = note.modified.timeIntervalSince(was.modified) > 1
                guard edited || wanted else { continue }
                guard changed.count < cap else { backlog += 1; continue }
                changed.append((note, read(note)))
            }

            return (fresh, changed, Set(notes.map(\.ref)), notes.count,
                    max(0, unseen.count - fresh.count), notDownloaded, backlog)
        }.value

        guard let outcome else { return nil }
        var report = Report(walked: outcome.walked, pending: outcome.pending,
                            notDownloaded: outcome.notDownloaded, repairing: repairing)

        for (note, parsed) in outcome.fresh {
            let thing = Thing(
                kind: .note,
                title: note.title,
                content: parsed?.excerpt ?? "",
                source: "Obsidian",
                capturedAt: note.modified,
                sourceRef: note.ref
            )
            apply(parsed, to: thing)
            context.insert(thing)
            SpotlightIndex.index([thing])
            report.landed += 1
        }

        var reindex: [Thing] = []
        for (index, (note, parsed)) in outcome.changed.enumerated() {
            // Per-ROW liveness at the point of the read, not a filter that ran
            // before the walk's await (COROLLARY 6): a delete-sync or a
            // CloudKit merge can tombstone a row while this pass is off-actor,
            // and the yield below reopens that window on every chunk.
            if let thing = landedByRef[note.ref], thing.isLive {
                thing.title = note.title
                thing.content = parsed?.excerpt ?? ""
                thing.capturedAt = note.modified
                apply(parsed, to: thing)
                reindex.append(thing)
                report.reread += 1
            }
            // Hand the actor back periodically. A repair pass writes up to
            // `repairCap` rows, and a run of mutations that large on the actor
            // the app draws with is a visible freeze (`ImportCommit`'s shape).
            if index % 100 == 99 { await Task.yield() }
        }

        // Prune — any landed note whose ref this walk didn't see is gone from
        // the vault (deleted, or renamed, which a filesystem reports as
        // exactly that: the old path stops existing and a new one appears).
        //
        // ONE GUARD, and it is not a precaution: a walk that returns ZERO
        // notes while we hold some is treated as a bad read, never as an
        // emptied vault. An iCloud Drive folder whose contents aren't
        // materialized can enumerate empty, and this bridge's own setup copy
        // says that is where vaults usually live — so the plausible cause of
        // "no files at all" here is a sync state, not a deletion. Erring
        // toward KEEP can only leave a stale row; erring the other way deletes
        // somebody's whole vault out of the corpus, and CloudKit carries that
        // to their other devices. (`ScreenshotIngest.pruneDeleted`'s
        // `found.isEmpty` guard, for the same reason.)
        var removedIDs: [UUID] = []
        if !existing.isEmpty && !outcome.allRefs.isEmpty {
            report.prunePassed = true
            let gone = existing.subtracting(outcome.allRefs)
            for ref in gone {
                guard let thing = landedByRef[ref], thing.isLive else { continue }
                removedIDs.append(thing.id)
                context.delete(thing)
                report.pruned += 1
            }
        }

        if report.landed > 0 || report.reread > 0 || report.pruned > 0 {
            context.saveHonestly()
            if !removedIDs.isEmpty { SpotlightIndex.remove(ids: removedIDs) }
            if !reindex.isEmpty { SpotlightIndex.index(reindex) }
        }

        // The repair declares itself done only once nothing is left OWED —
        // no capped-out backlog, and no note still waiting on an iCloud
        // download. Withholding the flag on an incomplete pass is
        // `YouTubeFollowRepair`'s rule: a repair that marks itself finished
        // while some of its subjects were unreachable has silently decided
        // those notes will never be repaired.
        if repairing && outcome.backlog == 0 && outcome.notDownloaded == 0 {
            UserDefaults.standard.set(true, forKey: repairKey)
            report.repairDone = true
        }
        return report
    }

    /// The parsed note's words and subjects onto the thing.
    ///
    /// `enrichedText` carries the FULL body (retrieval-only by the 2026-07-15
    /// ruling — nothing draws it) while `content` keeps the excerpt, so open
    /// and route logic are untouched and a long note stops being findable only
    /// by its opening paragraph. Clearing `embedding` is what makes the
    /// re-read reach the semantic index too: without it an edited note keeps
    /// the vector it was first embedded with, and search would answer with
    /// what the note USED to be about.
    @MainActor
    private static func apply(_ parsed: ObsidianNote.Parsed?, to thing: Thing) {
        guard let parsed else { return }
        let body = parsed.body.isEmpty ? nil : parsed.body
        if thing.enrichedText != body {
            thing.enrichedText = body
            thing.embedding = nil
        }
        // The vault's own tags become the room's filter surface. Wikilinks are
        // extracted against the RETRIEVAL body, never the 300-char excerpt —
        // a link past that point would otherwise be lost the moment it's
        // parsed (2026-07-28). That is a clamp too, at `retrievalLimit`, and
        // saying so is the honest version of the older "the FULL body": a link
        // past 8,000 characters is not walkable, and no note measured here
        // comes close.
        thing.tags = parsed.tags
        thing.wikilinks = NoteLinks.extract(from: parsed.body)
        // The subjects sweep re-reads a note whose words just changed —
        // `topicsAt` is a "we looked" mark, so without clearing it an edited
        // note keeps the topics of its first draft forever.
        thing.topicsAt = nil
    }
}
