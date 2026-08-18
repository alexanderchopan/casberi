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

    /// A note you kept here (prd §399, 2026-08-17) — the case §366 left out and
    /// said why.
    ///
    /// A note shared out of Apple Notes lands under source `You` with no record
    /// of where it came from, so that seat's things had NO anatomy at all: the
    /// sheet drew a title cut out of the note's own first line and then the same
    /// line again beneath it at footnote size, which is the exact defect this
    /// whole category was fixed for.
    ///
    /// §366 declined to widen because it "first needs an answer to what `You`
    /// means (wrote it, or merely brought it)". The answer is that we cannot
    /// know, and it turns out not to matter: the anatomy claims nothing about
    /// authorship once the verb is `Act.kept`. What DOES matter is that `You`
    /// holds every hand capture — links, screenshots, files, pastes — so this
    /// is scoped by KIND. A `.note` under `You` is writing somebody kept; a
    /// `.link` is a saved page and keeps the generic sheet it has always had.
    ///
    /// It is NOT in `sources`, and that is deliberate rather than tidy: that set
    /// is checked against `BridgeCatalog`'s Notes group by the harness, and
    /// `You` is not a catalog seat — adding it would either break that guard or
    /// force it to carry an exception forever.
    static let keptSource = "You"

    static func isKeptNote(_ thing: Thing) -> Bool {
        thing.source == keptSource && thing.kind == .note
    }

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
            notes: (isNotes(thing.source) || isKeptNote(thing))
                && !Corpus.isImportReceipt(thing),
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

    /// Sources whose body really IS markdown (prd §399).
    ///
    /// A FACT about each export, not a preference — Day One writes markdown
    /// (`DayOneImport.unescapeMarkdown` exists because it backslash-escapes
    /// markdown punctuation on the way out) and an Obsidian vault is markdown by
    /// definition. Apple Journal's body is HTML run through
    /// `plainText(fromHTML:)`, a Kindle passage is a sentence from a book, and a
    /// `You` note is whatever somebody typed or shared. Rendering those as
    /// markdown would eat a literal asterisk somebody meant and promote a dash
    /// into a bullet.
    static let markdownSources: Set<String> = ["Day One", "Obsidian"]

    /// The body to draw and everything the renderer needs to draw it right.
    static func prose(for thing: Thing) -> (text: String, clamped: Bool,
                                            markdown: Bool, wikilinks: Bool) {
        let body = self.body(for: thing)
        return (body.text, body.clamped,
                markdownSources.contains(thing.source),
                // Only a vault-shaped bridge populates `Thing.wikilinks`, and
                // only Obsidian's own syntax means anything to a reader —
                // rendering `[[x]]` as a link anywhere else would invent a
                // destination the corpus has no way to resolve.
                thing.source == "Obsidian")
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
            act: act(for: thing),
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
        case "Obsidian":  return .vault
        // Nothing was brought and nothing is read for either of these. The
        // sentence they earn differs by ACT, not by origin — see
        // `NoteReception.sentence`.
        case "Voice":     return .device
        case keptSource:  return .device
        default:          return .export
        }
    }

    /// What the person did, for the dateline's verb.
    static func act(for thing: Thing) -> NoteSheet.Act {
        switch thing.kind {
        case .voice: return .recorded
        default:
            if thing.source == "Kindle" { return .marked }
            // "kept", never "written" (prd §399): a `You` note may have been
            // typed here or shared in from another app, the record cannot tell
            // them apart, and a dateline claiming you wrote somebody else's
            // paragraph is §83 in the loudest slot on the sheet.
            if thing.source == keptSource { return .kept }
            return .wrote
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
    /// Excludes the entry itself, its SIBLINGS, and every import receipt.
    ///
    /// "Sibling" is same source AND same kind since 2026-08-17 (prd §399), not
    /// same source. The old rule was written for a journal, where every row is a
    /// `.note` and so the two are identical — and it is wrong for the `You` room
    /// this pass widened the anatomy to, where the same source also holds that
    /// day's screenshots, saved links and voice notes. Those are exactly the
    /// rows worth showing beside something you wrote, and the source rule hid
    /// every one of them.
    ///
    /// The scan window is `limit * 6` rather than `limit + 2`: the exclusion now
    /// happens in Swift (a `#Predicate` on `kind` is the transformable-attribute
    /// class this project has a crash report for), so the fetch has to see past
    /// the siblings it is about to drop. A day holding more than that many rows
    /// of one kind shows fewer tiles — a stated ceiling, never a walk.
    @MainActor
    static func sameDay(as thing: Thing, context: ModelContext,
                        calendar: Calendar = .current, limit: Int = 6) -> [Thing] {
        let start = calendar.startOfDay(for: thing.capturedAt)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let id = thing.id
        let source = thing.source
        let kind = thing.kind
        var d = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.capturedAt >= start && $0.capturedAt < end },
            sortBy: [SortDescriptor(\.capturedAt, order: .forward)])
        d.fetchLimit = limit * 6
        let found = ((try? context.fetch(d)) ?? []).live
        return Array(found.lazy
            .filter { $0.id != id && !Corpus.isImportReceipt($0)
                      && !($0.source == source && $0.kind == kind) }
            .prefix(limit))
    }

    // MARK: - The same date, in other years

    /// What you wrote on this date in the other years you kept this journal
    /// (prd §399, 2026-08-17).
    ///
    /// The ROOM's anniversary answers today's date. This answers the ENTRY's,
    /// which is the reading a journal is actually opened for and the one thing
    /// a corpus can do that a chronological list cannot: you are reading 14 May
    /// 2021, and 14 May exists in six other years, all of them already here.
    ///
    /// **Bounded by construction, one small fetch per year.** There is no way to
    /// ask SwiftData for "same month and day" — a predicate cannot call a
    /// calendar — so the alternative is fetching the room and filtering, which
    /// for a decade-deep journal is the corpus walk this project forbids. Each
    /// year is a narrow date-range read with `fetchLimit = 1`, the same shape
    /// `sameDay` above already uses, and the year list is capped at `yearSpan`.
    ///
    /// Scoped to ONE source: "what I wrote in this journal on this date" is a
    /// question with an answer, and merging two exports of the same years would
    /// produce two rows for one day with no way to tell which journal was which.
    static let yearSpan = 12

    @MainActor
    static func otherYears(of thing: Thing, context: ModelContext,
                           calendar: Calendar = .current, now: Date = .now,
                           limit: Int = 6) -> [Thing] {
        let source = thing.source
        let parts = calendar.dateComponents([.year, .month, .day], from: thing.capturedAt)
        guard let year = parts.year, let month = parts.month, let day = parts.day
        else { return [] }
        // Years around this one, never past today: a journal has no future, and
        // asking for one is `yearSpan` fetches guaranteed to answer nothing.
        let newest = calendar.component(.year, from: now)
        let lower = max(year - yearSpan, newest - yearSpan)
        var out: [Thing] = []
        for candidate in stride(from: newest, through: lower, by: -1) where candidate != year {
            var components = DateComponents()
            components.year = candidate; components.month = month; components.day = day
            guard let start = calendar.date(from: components),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else { continue }
            var d = FetchDescriptor<Thing>(
                predicate: #Predicate {
                    $0.source == source && $0.capturedAt >= start && $0.capturedAt < end
                },
                sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
            d.fetchLimit = 1
            // `.live` at the boundary (corollary 4) — this array is handed to a
            // view, so the guarantee is made here rather than promised downstream.
            if let match = ((try? context.fetch(d)) ?? []).live.first {
                out.append(match)
                if out.count >= limit { break }
            }
        }
        return out
    }

    // MARK: - The entry before and the entry after

    /// The neighbouring entries in the same journal, in the order they were
    /// written (prd §399, 2026-08-17).
    ///
    /// A journal is a SEQUENCE and the sheet dead-ended: reading three
    /// consecutive days meant sheet, close, scroll, sheet, three times. Two
    /// bounded reads — the newest row before this one and the oldest after it,
    /// each `fetchLimit = 1`.
    ///
    /// Same source only, and `.entry` shapes only at the call site: a vault
    /// note's `capturedAt` is a file's modification time, so its "next" would be
    /// whatever you happened to edit afterwards, which is a fact about your
    /// editor rather than about the writing.
    @MainActor
    static func neighbours(of thing: Thing, context: ModelContext)
        -> (previous: Thing?, next: Thing?) {
        let source = thing.source
        let when = thing.capturedAt
        let id = thing.id
        func one(_ before: Bool) -> Thing? {
            var d = FetchDescriptor<Thing>(
                predicate: before
                    ? #Predicate { $0.source == source && $0.capturedAt < when }
                    : #Predicate { $0.source == source && $0.capturedAt > when },
                sortBy: [SortDescriptor(\.capturedAt, order: before ? .reverse : .forward)])
            // Two, not one: an import receipt shares the room and would
            // otherwise be offered as the next entry — a door onto our own note
            // about a sync, from inside somebody's diary.
            d.fetchLimit = 2
            return ((try? context.fetch(d)) ?? []).live
                .first { $0.id != id && !Corpus.isImportReceipt($0) }
        }
        return (one(true), one(false))
    }
}
