import Foundation

/// WHAT A NOTE THING SHEET IS — the shape decision and the "how it landed"
/// reading (prd §366, 2026-08-12).
///
/// The wallet sheets became receipts, the social sheets became posts, the work
/// sheets became statuses. Notes is the category where the sheet's whole job
/// is to show you words, and it was the one showing the fewest of them.
/// Measured off the shipped importers rather than guessed:
///
/// - **Kindle destroys the passage at import.** `title = titleLine(body)` cuts
///   at 80 characters and appends an ellipsis, and `content` holds `"Book —
///   Author"` instead. The rest of the highlight is stored NOWHERE. So the
///   sheet drew a truncated quotation at `heading34` as though it were a
///   headline, and the book's name in gray underneath as though it were the
///   body — exactly inverted, over a record that had already lost the thing
///   you opened it to read.
/// - **Four of six sources clamp the body at twelve lines.** Obsidian got an
///   `enrichedText` exception on 2026-08-09; Day One, Apple Journal, Kindle
///   and shared notes never did. The app will index a 900-word journal entry,
///   answer questions about it and surface it in search — then refuse to show
///   you more than a dozen lines of it, with no "more" and nothing to scroll.
/// - **Prose is set as a caption.** Every body here draws at `callout15` in
///   `textSecondary`, the tier the design system uses for footnotes UNDER a
///   fact. On these sources the body is not an annotation of the thing, it IS
///   the thing, and it was the quietest text on the screen.
/// - **A journal entry never states its date.** The only clock was the
///   eyebrow's relative age ("3y ago") — so the one fact that identifies an
///   entry, and the only fact every source here carries, was the one fact the
///   sheet withheld.
/// - **Tags are stamped and never drawn.** Obsidian lands frontmatter and
///   inline tags, Day One lands the export's own. The filter can reach them;
///   no note sheet renders `thing.tags` at all.
/// - **The spec table's one row.** On a note every gate fails but `hasFrom`,
///   so the whole table was `From · written by you` behind an 80pt label
///   column — the shape the wallet and social passes deleted, still standing.
///
/// ## The ruling: the gate is a DATA test, never a source list
///
/// Same ruling §363 made one category over, for the same reason: a source list
/// has to be remembered every time a seat lands a note, and a data test covers
/// the vault that ships next month for free. `shape(_:)` asks only about the
/// record — does it quote somebody else's work, and is its title a NAME the
/// person chose or a first line we derived from its own body.
///
/// ## Why this file is Foundation-only
///
/// So `scripts/note-sheet-selftest.sh` can compile it WHOLE and unmodified.
/// Every failure here is a SILENT WRONG ANSWER that renders perfectly: a word
/// count taken over a clamped body understates a note by thousands and looks
/// like a measurement; a passage classified as an entry draws a date hero over
/// somebody else's sentence; a read time on a twelve-word note is a claim
/// nobody can catch. Nothing in a build or a screen sweep can see any of it.
/// Everything touching `Thing` lives in `NoteSheetSource.swift`.
enum NoteSheet {

    // MARK: - Shape

    /// The anatomy a note thing wears. Three, and there is deliberately no
    /// fourth: a shape exists only where the sheet would otherwise draw the
    /// wrong noun. Voice is NOT a fourth — it is an entry whose body happens
    /// to have audio above it, and it already had the only working anatomy in
    /// the category.
    enum Shape: String, Equatable {
        /// A dated piece of writing you made. A journal entry, an exported
        /// day, a voice note. **The DATE is the identity** — the title was
        /// derived from the entry's own first line, so it names nothing the
        /// body doesn't already say, and leading with it printed that line
        /// twice.
        case entry
        /// A named thing in a graph. A vault note, whose title is a filename
        /// the person chose and whose neighbours are written in everybody
        /// else's text. The NAME is the identity, so it leads.
        case note
        /// Somebody else's words that you marked. A Kindle highlight. **The
        /// passage is the hero and the work is the identity** — today those
        /// two are swapped in the record itself.
        case passage
    }

    /// The facts the shape decision reads. A value type on purpose: the
    /// decision is the thing worth testing, and it must be testable without a
    /// `Thing`, a store, or a simulator.
    struct Facts: Equatable {
        /// Is this a notes-category source at all? A `false` here means "no
        /// note anatomy", never "draw it badly".
        var notes: Bool
        /// `ThingKind.rawValue`, so this file needs no SwiftData.
        var kind: String
        /// Does the record quote a work somebody else wrote — a book, with an
        /// author? Proven at the source layer off the citation field, and
        /// true only when a citation was actually read.
        var cited: Bool
        /// Is the title a NAME the person gave this thing, rather than a line
        /// we cut out of its own body? Proven, never guessed: the source layer
        /// answers yes only when the record carries a file path whose last
        /// component IS the title.
        var named: Bool
    }

    /// The anatomy, or nil for a notes-source thing that needs none (an import
    /// receipt is an event, not a note; a folder-picked PDF is a file).
    ///
    /// Order is load-bearing and each step earns its place:
    ///
    /// 1. **A citation outranks everything.** A marked passage is somebody
    ///    else's writing no matter what else the record carries, and it is the
    ///    one shape where leading with a date would put OUR clock on THEIR
    ///    sentence.
    /// 2. **Then a name.** A title that is a filename is an identity; a title
    ///    that is a first line is a repetition. Only the path test can tell
    ///    them apart, and it is a proof rather than a heuristic.
    /// 3. **Then, and only then, the kind decides.** Everything left that is
    ///    written text — a note or a voice note — is an entry, which is the
    ///    widening: Day One, Apple Journal and Voice all reach it on the
    ///    strength of their own record with no source named anywhere.
    static func shape(_ f: Facts) -> Shape? {
        guard f.notes else { return nil }
        if f.cited { return .passage }
        if f.named { return .note }
        if f.kind == "note" || f.kind == "voice" { return .entry }
        return nil
    }

    // MARK: - Words

    /// How many words the body we HOLD contains.
    ///
    /// Whitespace-separated tokens, which is the count every word processor
    /// means and the only one a reader can check by eye. Deliberately not
    /// characters: a character count is exact and answers a question nobody
    /// asks.
    static func words(in text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// Below this a read-time claim is noise — at 220 words a minute, 100
    /// words is under thirty seconds, and "1 min" on a two-line note reads as
    /// the app padding itself out.
    static let readTimeFloor = 100

    /// Words per minute. 220 is ordinary adult reading of ordinary prose; the
    /// number matters far less than that it is one number, stated once.
    static let wordsPerMinute = 220

    /// Minutes to read, or nil below the floor.
    static func readMinutes(words: Int) -> Int? {
        guard words >= readTimeFloor else { return nil }
        return max(1, Int((Double(words) / Double(wordsPerMinute)).rounded()))
    }

    // MARK: - The dateline

    /// The hero of an entry: the day it was written, which is what an entry
    /// IS. `headline` is the day, `detail` the year (when it isn't this one),
    /// the act and the time.
    struct Dateline: Equatable {
        var headline: String
        var detail: String
    }

    /// What the person did, which is the verb the dateline and the provenance
    /// sentence both turn on.
    enum Act: String, Equatable {
        case wrote, recorded, marked

        /// Past tense, second person, as it appears mid-sentence.
        var verb: String {
            switch self {
            case .wrote:    return String(localized: "written")
            case .recorded: return String(localized: "recorded")
            case .marked:   return String(localized: "marked")
            }
        }
    }

    /// "Tuesday, 14 May" / "2024 · written at 9:12 AM".
    ///
    /// **The year appears only when it isn't the current one**, which is why
    /// `now` is a parameter rather than a read of the clock: a hero that says
    /// "2026" on something you wrote this morning is stating the obvious in
    /// the loudest slot on the sheet, and a function that reads `Date.now`
    /// itself cannot be tested at a year boundary.
    static func dateline(_ when: Date, act: Act, now: Date,
                         calendar: Calendar = .current) -> Dateline {
        let headline = when.formatted(.dateTime.weekday(.wide).day().month(.wide))
        let time = when.formatted(date: .omitted, time: .shortened)
        let sameYear = calendar.component(.year, from: when)
            == calendar.component(.year, from: now)
        let clause = String(localized: "\(act.verb) at \(time)")
        guard !sameYear else { return Dateline(headline: headline, detail: clause) }
        let year = when.formatted(.dateTime.year())
        return Dateline(headline: headline, detail: "\(year) · \(clause)")
    }

    /// "4m", "3h", "6d", "5w" — how long since a vault note was edited.
    ///
    /// Spelled out here rather than borrowed from the row's own time text for
    /// the Foundation-only reason above, and deliberately COARSE: this is a
    /// reading of how live a note is, and a note edited eleven weeks ago and
    /// one edited twelve are the same answer.
    static func relative(_ then: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(then))
        let minutes = Int(seconds / 60)
        if minutes < 1 { return String(localized: "just now") }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        if days < 7 { return "\(days)d" }
        let weeks = days / 7
        if weeks < 52 { return "\(weeks)w" }
        return "\(weeks / 52)y"
    }
}

/// HOW IT LANDED — the block that replaces the spec table on a note sheet.
///
/// The spec table's whole contribution to a note was one row reading `From —
/// written by you`, in its own card, behind an 80pt label column. It said less
/// than the eyebrow directly above it, which already names the source. This
/// says where the thing came from in a sentence, and puts beside it the
/// readings the record already held and nobody drew.
///
/// ## What this is allowed to be, and what it must never become
///
/// §223's module doctrine bans a COUNT from being a *thing*. It does not ban a
/// state surface from stating one. This is a **reading of one note**, never
/// news: it updates in place, it is never a row, and it never says "+3 words
/// since yesterday". A reading the record cannot support has no cell at all —
/// an absent number and a measured zero are different facts, and that
/// distinction is the only reason any number here can be trusted.
struct NoteReception: Equatable {

    /// One reading and its noun.
    struct Reading: Equatable {
        var text: String
        var noun: String
    }

    /// Where this thing came from, decided at the source layer because it is a
    /// lookup, and worded here because the wording is what's worth testing.
    enum Origin: String, Equatable {
        /// A folder we read continuously — a vault. The sentence names the
        /// path, because on a vault "where is this really" is a live question.
        case vault
        /// A file the person brought here once. The sentence names the export,
        /// and the file itself when the source has exactly one.
        case export
        /// Made on this device. Nothing was brought and nothing is read.
        case device
    }

    /// What the record can be measured for, in a fixed order, absent excluded.
    var readings: [Reading] = []
    /// One sentence saying how this arrived. Replaces the `From` spec row.
    var provenance: String?
    /// What the record structurally cannot give us, said out loud, for the one
    /// shape where a short body reads as a broken import rather than a stated
    /// limit.
    var ceiling: String?

    var isEmpty: Bool {
        readings.isEmpty && provenance == nil && ceiling == nil
    }

    /// Everything the sentence and the readings are built from. One struct
    /// rather than a dozen arguments, so a new fact can be added without every
    /// call site and every fixture being rewritten.
    struct Input {
        var shape: NoteSheet.Shape
        var source: String
        var origin: Origin
        /// The one file this source's export IS, where naming it tells the
        /// person something they can act on ("My Clippings.txt"). nil where
        /// the export is a folder of many.
        var originFile: String?
        /// The vault-relative path, for a `.vault` origin.
        var path: String?
        /// Words in the body we HOLD. nil when there is no body to measure.
        var words: Int?
        /// Is that body clamped — i.e. is the real note longer than what we
        /// stored? Decides between "1,240 words" and "1,240+ words". THE field
        /// that keeps this card from stating a measurement it cannot make.
        var clamped: Bool = false
        /// A vault note's own modification time.
        var editedAt: Date?
        /// When the person marked a passage.
        var markedAt: Date?
        /// Other passages already landed from the same work.
        var siblings: Int?
        /// When the entry was written, and when the row was created here. The
        /// pair is what licenses the "imported on" clause: an export brought
        /// years of entries in one afternoon, and saying so is the difference
        /// between a date that describes the writing and one that describes
        /// the reading.
        var writtenAt: Date?
        var landedAt: Date?
        /// Was the passage stored under the pre-§366 importer, which kept only
        /// the first 80 characters? Proven at the source layer off the stored
        /// text, never assumed from a date.
        var truncatedPassage: Bool = false
        var now: Date
    }

    /// The reading, or nil when there is nothing honest to say.
    static func compose(_ i: Input) -> NoteReception? {
        var out = NoteReception()
        out.readings = readings(i)
        out.provenance = sentence(i)
        out.ceiling = ceiling(i)
        return out.isEmpty ? nil : out
    }

    // MARK: - The readings

    /// Fixed order, absent excluded, and each shape measures what it can.
    ///
    /// A `.passage` deliberately gets NO word count: a marked sentence is as
    /// long as it is, "24 words" says nothing about it, and the two facts
    /// worth stating are how many you have marked in that work and when.
    private static func readings(_ i: Input) -> [Reading] {
        var out: [Reading] = []
        if i.shape == .passage {
            // The count INCLUDES this one, so it reads as a position in a
            // collection ("12 marked in this book") rather than as a tally of
            // other things — which is also why a lone highlight still gets a
            // cell reading "1" instead of the section vanishing.
            if let siblings = i.siblings, siblings > 0 {
                out.append(Reading(text: siblings.formatted(.number),
                                   noun: String(localized: "marked in this book")))
            }
            if let marked = i.markedAt {
                out.append(Reading(text: shortDay(marked),
                                   noun: String(localized: "you marked it")))
            }
            return out
        }
        if let words = i.words, words > 0 {
            // The honesty valve, borrowed verbatim from `SocialCount`'s "97+":
            // a body we clamped is at LEAST this long, and a bare number over
            // a clamped body understates a real note by thousands while
            // looking exactly like a measurement.
            let text = i.clamped
                ? "\(words.formatted(.number))+"
                : words.formatted(.number)
            out.append(Reading(text: text, noun: String(localized: "words")))
            if let minutes = NoteSheet.readMinutes(words: words) {
                out.append(Reading(text: i.clamped ? "\(minutes)+ min" : "\(minutes) min",
                                   noun: String(localized: "to read")))
            }
        }
        // A vault note is a thing you keep editing, which is the one clock a
        // named note has and an entry does not — an entry's clock is its hero.
        if i.shape == .note, let edited = i.editedAt {
            out.append(Reading(text: NoteSheet.relative(edited, now: i.now),
                               noun: String(localized: "since you edited")))
        }
        return out
    }

    // MARK: - The sentence

    /// One sentence, three grammars, chosen by where the thing came from.
    ///
    /// The export grammar is the one that earns this function: it names the
    /// FILE as the origin and, where the dates license it, says the writing is
    /// older than its arrival here. "From your Day One export — imported 3
    /// August" is a complete answer to "why am I looking at this"; `From:
    /// written by you` was not an answer at all.
    private static func sentence(_ i: Input) -> String? {
        switch i.origin {
        case .vault:
            guard let path = i.path, !path.isEmpty else {
                return String(localized: "Read from your \(i.source) vault.")
            }
            return String(localized: "Read from your vault at \(path).")
        case .device:
            return String(localized: "Recorded here, on this device.")
        case .export:
            let head: String
            if let file = i.originFile, !file.isEmpty {
                head = String(localized: "From \(file), written by your \(i.source).")
            } else {
                head = String(localized: "From your \(i.source) export.")
            }
            guard let clause = importedClause(i) else { return head }
            return "\(head) \(clause)"
        }
    }

    /// "Imported 3 August." — but ONLY when the writing is meaningfully older
    /// than the row.
    ///
    /// An export brings years of entries in one afternoon, and the gap between
    /// the two dates is the fact worth stating. Where they agree — you wrote
    /// it today and it landed today — the clause says nothing and is dropped,
    /// because a sheet that reports both halves of the same moment reads as a
    /// form again.
    private static func importedClause(_ i: Input) -> String? {
        guard let landed = i.landedAt, let written = i.writtenAt else { return nil }
        guard landed.timeIntervalSince(written) > 86_400 else { return nil }
        return String(localized: "Imported \(day(landed)).")
    }

    // MARK: - The ceiling

    /// What the record cannot give us, for the one case where a short body
    /// reads as a bad import rather than a stated limit.
    ///
    /// Scoped to a passage stored under the pre-§366 Kindle importer, and only
    /// then: every other note in the corpus really does hold what it claims
    /// to, so saying this anywhere else would be inventing a limitation.
    private static func ceiling(_ i: Input) -> String? {
        guard i.shape == .passage, i.truncatedPassage else { return nil }
        return String(localized:
            "Stored before whole passages were kept — import My Clippings.txt again for the rest.")
    }

    // MARK: - Dates
    //
    // Spelled out rather than taken from a shared formatter: this file is
    // Foundation-only by design so the harness can compile it whole, and each
    // of these is a stable, locale-aware `Date.FormatStyle` read with no
    // dependency to import.

    /// "3 August" — a day without a year, for a clause that sits beside a
    /// sentence already naming the source. The year belongs on the hero.
    private static func day(_ d: Date) -> String {
        d.formatted(.dateTime.day().month(.wide))
    }

    /// "4 Aug" — the abbreviated form, for a reading where the cell is narrow
    /// and the noun beneath it carries the meaning.
    private static func shortDay(_ d: Date) -> String {
        d.formatted(.dateTime.day().month(.abbreviated))
    }
}
