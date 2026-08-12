import Foundation
import SwiftData

/// The `Thing` half of the note sheet (prd §366, 2026-08-12) — everything
/// `NoteSheet.swift` deliberately cannot see.
///
/// The split is the house pattern (`SocialSheet`/`SocialSheetSource`,
/// `StripeRoom`/`StripeRoomSource`): the judgement is Foundation-only so a
/// harness can compile it whole, and the reads that touch SwiftData and the
/// catalog live here, where there is no judgement to test — only lookups.
enum NoteSheetSource {

    /// The sources whose things are notes — writing kept to be read back.
    ///
    /// The catalog's `Notes` group (Obsidian, Day One, Apple Journal, Apple
    /// Notes) plus two that sit elsewhere for good reasons and are notes all
    /// the same: **Kindle**, which browses under `Reading` because that is
    /// where you would look for it but lands marked passages, and **Voice**,
    /// which has no catalog seat at all (it is an always-on device capability,
    /// and `BridgeCatalog` maps it to the Notes category by hand).
    ///
    /// **"Apple Notes" is in this set and nothing lands under it**, which is
    /// itself a finding rather than an oversight: the seat is share-sheet
    /// instructions, and a note shared from Apple Notes lands under source
    /// `You` with no record of where it came from. Widening this set to `You`
    /// would give every hand-captured note this anatomy — plausibly right, and
    /// a different ruling than this one, because it first needs an answer to
    /// what `You` means (wrote it, or merely brought it). Left out
    /// deliberately; the name stays here so the catalog guard keeps covering
    /// the seat.
    ///
    /// A literal set rather than a `BridgeCatalog` walk on purpose — this is
    /// read on every sheet open, and the catalog answer is a linear scan over
    /// sixty-odd offers. Guarded against the catalog by
    /// `note-sheet-selftest.sh`, so a renamed or added `Notes` seat fails the
    /// build rather than silently losing its anatomy.
    static let sources: Set<String> = [
        "Obsidian", "Day One", "Apple Journal", "Apple Notes", "Kindle", "Voice",
    ]

    static func isNotes(_ source: String) -> Bool { sources.contains(source) }

    /// The one source whose export is a single named file worth naming.
    static let clippingsFile = "My Clippings.txt"

    // MARK: - Shape

    /// What anatomy this thing's sheet wears, or nil for none.
    ///
    /// Liveness: reads stored properties, so every caller must already hold a
    /// live model — which the sheet does (its `init` and `body` both guard,
    /// and this is only ever reached from inside those guards).
    static func shape(for thing: Thing) -> NoteSheet.Shape? {
        NoteSheet.shape(facts(for: thing))
    }

    static func facts(for thing: Thing) -> NoteSheet.Facts {
        NoteSheet.Facts(
            notes: isNotes(thing.source) && !Corpus.isImportReceipt(thing),
            kind: thing.kind.rawValue,
            cited: citation(for: thing) != nil,
            named: isNamed(thing))
    }

    /// Is the title a NAME the person gave this thing?
    ///
    /// Proven, never guessed: true only when the record carries a file path
    /// whose last component (extension dropped) IS the title — which is
    /// exactly how `ObsidianIngest` derives it. A ref shape that ever changes
    /// makes this false, and the thing degrades to an `.entry`: a weaker
    /// layout, never a wrong claim.
    static func isNamed(_ thing: Thing) -> Bool {
        guard let path = ObsidianLink.relativePath(from: thing.sourceRef) else { return false }
        let name = (path as NSString).lastPathComponent
        let stem = (name as NSString).deletingPathExtension
        return !stem.isEmpty && stem == thing.title
    }

    // MARK: - The passage shape

    /// The work a marked passage came from — "Piranesi — Susanna Clarke".
    ///
    /// **Two eras, read without a migration.** Since §366 the importer stamps
    /// the book on `authorHandle`, where a room can rank it. Before that it
    /// put the book in `content` and the (truncated) passage in `title`, which
    /// is the wrong way round in the record itself. Reading both here means a
    /// corpus imported last month gets the right sheet today with no heal
    /// pass, no done-flag, and no chance of a chunked rewrite touching rows it
    /// shouldn't — the re-import is still the real fix, and it is the only
    /// thing that can restore the words the old importer threw away.
    ///
    /// Scoped to Kindle rather than to "any `authorHandle`": every other
    /// source in this set uses that field for nothing, and a citation is the
    /// gate that decides a shape, so a stray value must not be able to turn a
    /// journal entry into somebody else's book.
    static func citation(for thing: Thing) -> String? {
        guard thing.source == "Kindle" else { return nil }
        let stamped = (thing.authorHandle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !stamped.isEmpty { return stamped }
        let legacy = thing.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return legacy.isEmpty ? nil : legacy
    }

    /// The marked words themselves.
    ///
    /// Post-§366 the passage is `content` and the book is `authorHandle`, so
    /// `content` is the answer. Pre-§366 `content` held the book — which the
    /// citation read above has already claimed — so the passage is whatever is
    /// left, the clamped `title`. Decided by whether the book was STAMPED, not
    /// by a date: a date test would misread any row synced from a device on
    /// the other side of the change.
    static func passage(for thing: Thing) -> String {
        let stamped = (thing.authorHandle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !stamped.isEmpty {
            let body = thing.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { return body }
        }
        return thing.title
    }

    /// Was this passage stored by the importer that kept only its first 80
    /// characters?
    ///
    /// The proof is in the text, not the calendar: `IngestSupport.titleLine`
    /// cuts at exactly 80 and appends one ellipsis character, so a passage of
    /// exactly 81 characters ending in `…` is one it truncated. A passage that
    /// really ends in an ellipsis and happens to be 81 characters long is a
    /// false positive we can live with — the sentence it earns invites a
    /// re-import, which costs nothing and changes nothing for a row that was
    /// already whole.
    static func isTruncatedPassage(_ thing: Thing) -> Bool {
        let words = passage(for: thing)
        return words.count == 81 && words.hasSuffix("…")
    }

    // MARK: - The body

    /// The prose to draw, and whether it is all of it.
    ///
    /// `enrichedText` first for a vault note — §313's exception, where it is
    /// not a machine's paraphrase but the note's own words clamped further out
    /// (8,000 characters against the row excerpt's 300). A note the current
    /// reader hasn't reached yet has none and falls back to the excerpt, which
    /// is honest and is what the sheet has always drawn.
    ///
    /// `clamped` is the field that keeps the receipt from stating a
    /// measurement it cannot make. It is true when the body we hold sits at
    /// the retrieval limit — at which point a word count is a FLOOR, not a
    /// count, and the card says so with a `+`.
    static func body(for thing: Thing) -> (text: String, clamped: Bool) {
        if let enriched = thing.enrichedText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !enriched.isEmpty,
           enriched.count >= thing.content.trimmingCharacters(in: .whitespacesAndNewlines).count {
            return (enriched, enriched.count >= ObsidianNote.retrievalLimit)
        }
        let body = thing.content.trimmingCharacters(in: .whitespacesAndNewlines)
        // The excerpt clamp is a real ceiling too: a vault note whose enriched
        // body hasn't been read yet shows 300 characters and must not report
        // them as the note's length.
        let clamped = thing.source == "Obsidian" && body.count >= ObsidianNote.excerptLimit
        return (body, clamped)
    }

    /// The tags a note sheet shows: the person's own, never the kind tag the
    /// app writes onto every row (`ThingKind.typeTag`), which would put "Note"
    /// beside "#legibility" as though a person had chosen both.
    static func tags(for thing: Thing) -> [String] {
        let typeTags = Set(ThingKind.allCases.map(\.typeTag))
        return thing.tags.filter { !typeTags.contains($0) }
    }

    // MARK: - Reception

    /// The "how it landed" reading for one thing, or nil when there is nothing
    /// honest to say.
    static func reception(for thing: Thing, shape: NoteSheet.Shape,
                          siblings: Int?, now: Date = .now) -> NoteReception? {
        let origin = origin(for: thing.source)
        let measured = shape == .passage ? nil : body(for: thing)
        return NoteReception.compose(.init(
            shape: shape,
            source: thing.source,
            origin: origin,
            originFile: thing.source == "Kindle" ? clippingsFile : nil,
            path: ObsidianLink.relativePath(from: thing.sourceRef),
            words: measured.map { NoteSheet.words(in: $0.text) },
            clamped: measured?.clamped ?? false,
            // A vault note's `capturedAt` IS the file's modification date
            // (`ObsidianIngest` stamps it), so this needs no new field and
            // costs no read — it is the same date the eyebrow is already
            // showing, said in the one place it means something.
            editedAt: shape == .note ? thing.capturedAt : nil,
            markedAt: shape == .passage ? thing.capturedAt : nil,
            siblings: siblings,
            writtenAt: thing.capturedAt,
            landedAt: thing.createdAt,
            truncatedPassage: shape == .passage && isTruncatedPassage(thing),
            now: now))
    }

    /// Where a source's things come from. A lookup, not a judgement — the
    /// wording lives in `NoteReception`.
    static func origin(for source: String) -> NoteReception.Origin {
        switch source {
        case "Obsidian": return .vault
        case "Voice":    return .device
        default:         return .export
        }
    }

    /// What the person did, for the dateline's verb.
    static func act(for thing: Thing) -> NoteSheet.Act {
        switch thing.kind {
        case .voice: return .recorded
        default:     return thing.source == "Kindle" ? .marked : .wrote
        }
    }

    // MARK: - Fetches

    /// The other passages already landed from the same work, newest first,
    /// plus the total.
    ///
    /// This is what makes ONE highlight worth opening: a marked sentence out
    /// of context is a fragment, and the eleven others from the same book are
    /// already in the corpus. Scoped by source AND citation with a hard
    /// `fetchLimit` — never a corpus walk ("no screen reads the whole corpus
    /// to say one thing").
    ///
    /// The count is `total`, which INCLUDES this passage, and the rows exclude
    /// it: a shelf that listed the thing you are looking at would read as a
    /// duplicate, and a count that excluded it would disagree with the book's
    /// own room.
    @MainActor
    static func siblings(of thing: Thing, context: ModelContext,
                         limit: Int = 4) -> (rows: [Thing], total: Int) {
        guard let book = citation(for: thing) else { return ([], 0) }
        let id = thing.id
        // Both eras again: the book is on `authorHandle` after §366 and in
        // `content` before it, and a corpus can hold both at once.
        var d = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Kindle"
                && ($0.authorHandle == book || $0.content == book) },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        d.fetchLimit = limit + 1
        let found = ((try? context.fetch(d)) ?? []).live
        let total = (try? context.fetchCount(FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Kindle"
                && ($0.authorHandle == book || $0.content == book) }))) ?? found.count
        // `.live` at the boundary (corollary 4): this array is handed onward
        // to a view, so the guarantee is made here rather than promised to
        // every reader downstream.
        return (Array(found.filter { $0.id != id }.prefix(limit)), total)
    }

    /// Everything else in the corpus from the same calendar day.
    ///
    /// The single strongest argument that a journal entry belongs in a corpus
    /// rather than in a journal app: the day you wrote about is a day the
    /// corpus already holds photographs, movements and captures for, and no
    /// journal app can show you those. It is one predicate over a bounded
    /// range, not a walk.
    ///
    /// Excludes the entry itself, its own source (a shelf of the same journal
    /// is just the room), and every import receipt.
    @MainActor
    static func sameDay(as thing: Thing, context: ModelContext,
                        calendar: Calendar = .current, limit: Int = 6) -> [Thing] {
        let start = calendar.startOfDay(for: thing.capturedAt)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let source = thing.source
        let id = thing.id
        var d = FetchDescriptor<Thing>(
            predicate: #Predicate {
                $0.capturedAt >= start && $0.capturedAt < end && $0.source != source
            },
            sortBy: [SortDescriptor(\.capturedAt, order: .forward)])
        d.fetchLimit = limit + 2
        let found = ((try? context.fetch(d)) ?? []).live
        return Array(found.lazy
            .filter { $0.id != id && !Corpus.isImportReceipt($0) }
            .prefix(limit))
    }
}
