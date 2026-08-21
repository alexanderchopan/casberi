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
        /// A note that arrived under `You` — the share sheet, a drop, a
        /// capture (prd §399, 2026-08-17).
        ///
        /// It exists because the anatomy could not honestly be widened to
        /// `You` without it. §366 left that source out and said why: the sheet
        /// would first need "an answer to what `You` means (wrote it, or merely
        /// brought it)", and a note shared out of Apple Notes lands there
        /// indistinguishably from one typed here. The answer is that we cannot
        /// know, and the fix is a verb that does not need to: **you kept it**,
        /// at that time, on this device, which is true of both and claims
        /// authorship of neither.
        case kept

        /// Past tense, second person, as it appears mid-sentence.
        var verb: String {
            switch self {
            case .wrote:    return String(localized: "written")
            case .recorded: return String(localized: "recorded")
            case .marked:   return String(localized: "marked")
            case .kept:     return String(localized: "kept")
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

    // MARK: - The body's own structure

    /// One block of a note's body (prd §399, 2026-08-17).
    ///
    /// `NoteProse` set the whole body as ONE `Text`, so a Day One or Obsidian
    /// note — both of which really are markdown — drew its own punctuation:
    /// `# Monday` as a hash and a word, `**finally**` with the asterisks in,
    /// `- milk` as a hyphen. The importer already proves the format is
    /// markdown; `DayOneImport.unescapeMarkdown` exists precisely because Day
    /// One backslash-escapes markdown punctuation on the way out.
    ///
    /// Deliberately SMALL. Headings, lists, quotes and paragraphs are the four
    /// shapes a person writing prose actually uses; tables, footnotes, HTML
    /// blocks and embeds are not, and each one added is a way for a body to
    /// render as something other than what it says.
    enum Block: Equatable {
        /// `# …` through `###### …`, level clamped to 1...6.
        case heading(level: Int, text: String)
        case bullet(String)
        /// The index is the one WRITTEN in the source, never a re-count: a list
        /// starting at 3 was started at 3 on purpose, and renumbering somebody's
        /// note is editing it.
        case numbered(index: Int, text: String)
        case quote(String)
        case paragraph(String)
        /// A fenced block, verbatim (2026-08-20). `language` is whatever
        /// followed the opening fence, or nil — it is a LABEL, never used to
        /// choose a parser, so an unknown word costs nothing.
        ///
        /// Added for the agent rooms rather than the notes room, and it is the
        /// fifth shape only because it is the one an LLM answer cannot do
        /// without: ChatGPT, Claude and Claude Code write fenced code
        /// constantly, and without this the fence markers drew as prose and —
        /// far worse — every marker rule below applied INSIDE the code, so a
        /// Python `# TODO` became a heading and a shell `- flag` became a
        /// bullet. A vault note gains the same fix for free, which is the
        /// argument for extending this splitter instead of writing a second
        /// one next to it.
        case code(language: String?, text: String)

        /// The characters this block will draw, for the fold's arithmetic.
        var length: Int {
            switch self {
            case .heading(_, let t), .bullet(let t), .quote(let t), .paragraph(let t):
                return t.count
            case .numbered(_, let t):
                return t.count
            case .code(_, let t):
                return t.count
            }
        }
    }

    /// Is this line a ``` fence, and what language did it name?
    ///
    /// Three backticks minimum, so an inline `` `code` `` span never opens a
    /// block. The info string is taken whole and trimmed; a fence with nothing
    /// after it is an unlabelled block.
    static func fence(_ line: String) -> (isFence: Bool, language: String?) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("```") else { return (false, nil) }
        let info = trimmed.drop(while: { $0 == "`" }).trimmingCharacters(in: .whitespaces)
        return (true, info.isEmpty ? nil : info)
    }

    /// A body, split into blocks.
    ///
    /// **`markdown` is a per-source FACT, not a preference.** Day One and
    /// Obsidian store markdown. Apple Journal's body is HTML run through
    /// `plainText(fromHTML:)`, and a `You` note is whatever somebody typed or
    /// shared — neither is markdown, and parsing them as if they were would
    /// eat a literal asterisk somebody meant, or promote a line starting "- "
    /// into a bullet that was a dash.
    ///
    /// Blank lines separate blocks; single newlines INSIDE a paragraph are
    /// kept rather than joined, which is where this departs from strict
    /// markdown and does so knowingly: a journal entry's line breaks are the
    /// writer's, and CommonMark would run them together into one wall.
    ///
    /// **THE FLAG GOVERNS MARKERS, NOT SPLITTING (2026-08-21).** It used to do
    /// both — a non-markdown body returned as ONE paragraph — and the two are
    /// different facts. Whether `- ` is a bullet or a dash depends on who wrote
    /// the file; whether a blank line ends a paragraph does not, because nobody
    /// writing anything means a blank line literally. Conflating them cost the
    /// fold: `folded` cuts between blocks, so a single-block body can never
    /// fold, and every non-markdown source was left with the twelve-line clamp
    /// this whole pass exists to replace. Markers, fences and thematic breaks
    /// stay gated; paragraph breaks are universal.
    static func blocks(_ text: String, markdown: Bool) -> [Block] {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return [] }

        var out: [Block] = []
        var para: [String] = []
        func flush() {
            let joined = para.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { out.append(.paragraph(joined)) }
            para = []
        }
        // A fence in progress. While it is open NOTHING below applies — that
        // suspension is the whole point of the case, not a detail of it: inside
        // a code block a `#` is a comment, a `- ` is a flag, a `> ` is a shell
        // prompt and a blank line is part of the program.
        var fenceLines: [String]?
        var fenceLanguage: String?
        func closeFence() {
            guard let lines = fenceLines else { return }
            // Trailing blank lines go, leading indentation stays: the shape of
            // a program is its content.
            let text = lines.joined(separator: "\n")
                .trimmingCharacters(in: .newlines)
            if !text.isEmpty { out.append(.code(language: fenceLanguage, text: text)) }
            fenceLines = nil
            fenceLanguage = nil
        }

        // The per-source half, named so it reads as the fact it is — and so the
        // harness has ONE anchor for "markers are gated" rather than gating the
        // two blocks below under a bare `markdown` a mutation can't tell apart.
        let takesMarkers = markdown

        for raw in body.components(separatedBy: .newlines) {
            if takesMarkers {
                let fenced = fence(raw)
                if fenceLines != nil {
                    // Only a fence closes a fence.
                    if fenced.isFence { closeFence() } else { fenceLines?.append(raw) }
                    continue
                }
                if fenced.isFence {
                    flush()
                    fenceLines = []
                    fenceLanguage = fenced.language
                    continue
                }
            }
            let line = raw.trimmingCharacters(in: .whitespaces)
            // The one rule that applies to every source: a blank line ends a
            // paragraph. See the type doc — this is deliberately OUTSIDE the
            // `markdown` gate.
            if line.isEmpty { flush(); continue }
            if takesMarkers {
                // A thematic break draws nothing — the design system has no
                // hairlines — so it acts as the paragraph break it already is
                // rather than printing "---" as a line of prose.
                if line.allSatisfy({ $0 == "-" }) && line.count >= 3 { flush(); continue }
                if line.allSatisfy({ $0 == "*" }) && line.count >= 3 { flush(); continue }
                if let block = leader(line) { flush(); out.append(block); continue }
            }
            para.append(line)
        }
        // An UNCLOSED fence still yields its code. This is not an edge case
        // here, it is the common one: an agent transcript is stored under an
        // 8,000-character clamp, so a long answer's last fence is routinely cut
        // mid-program. Dropping it would delete exactly the part of the answer
        // somebody opened the sheet to read.
        closeFence()
        flush()
        return out
    }

    /// One line's own block, or nil when it is ordinary prose.
    ///
    /// Every marker requires a SPACE after it, which is the whole of its
    /// correctness: `#hashtag` is a tag somebody wrote (Obsidian's inline tag
    /// syntax, landed by its own ingest), `#Monday` is not a heading, and
    /// `-5 degrees` is not a bullet.
    static func leader(_ line: String) -> Block? {
        if line.hasPrefix("#") {
            let hashes = line.prefix(while: { $0 == "#" }).count
            let rest = line.dropFirst(hashes)
            if hashes <= 6, rest.hasPrefix(" ") {
                let text = rest.trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { return .heading(level: hashes, text: text) }
            }
            return nil
        }
        for mark in ["- ", "* ", "+ "] where line.hasPrefix(mark) {
            let text = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : .bullet(text)
        }
        if line.hasPrefix(">") {
            let text = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : .quote(text)
        }
        let digits = line.prefix(while: { $0.isNumber })
        if !digits.isEmpty, digits.count <= 3, let index = Int(digits) {
            let rest = line.dropFirst(digits.count)
            if rest.hasPrefix(". ") || rest.hasPrefix(") ") {
                let text = String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { return .numbered(index: index, text: text) }
            }
        }
        return nil
    }

    /// Past this many characters the body folds. Roughly a screenful at
    /// `reading20` on a phone: short enough that a fold is rare on an ordinary
    /// entry, long enough that the fold means something when it happens.
    static let foldLength = 900

    /// The blocks shown before the fold — whole blocks only.
    ///
    /// It cuts at a BLOCK boundary and always keeps at least one, so a fold can
    /// never leave a heading standing alone over nothing, and never shows an
    /// empty opening. The old fold was `lineLimit(12)` on one `Text`, which cut
    /// mid-sentence at whatever width the device happened to be.
    static func folded(_ blocks: [Block], limit: Int = foldLength) -> [Block] {
        var out: [Block] = []
        var used = 0
        for block in blocks {
            if !out.isEmpty && used >= limit { break }
            out.append(block)
            used += block.length
        }
        return out
    }

    // MARK: - Wikilinks

    /// The URL scheme an inline `[[wikilink]]` becomes, so the renderer can
    /// tell OUR links from a real one somebody wrote in their note.
    ///
    /// Deliberately not `casberi://` — that is the app's real deep-link scheme
    /// and `RootShell.route` acts on it, so a note containing a crafted link
    /// could otherwise reach a router. This scheme is claimed by nothing,
    /// registered nowhere, and is intercepted by the one view that renders it.
    static let wikiScheme = "casberi-note"

    /// Rewrites `[[Target]]`, `[[Target|Alias]]` and `[[Target#Heading]]` into
    /// ordinary markdown links, so the inline renderer draws them and the
    /// sheet can walk them (prd §399).
    ///
    /// The vault's own syntax has been extracted at ingest since 2026-07-28
    /// and resolved into a list UNDER the note — but in the body itself it
    /// still read as literal double brackets, which is the one place a vault
    /// user expects a link to work because it works everywhere else they see
    /// that note.
    ///
    /// Alias rules mirror `NoteLinks.extract` exactly, and must: the list below
    /// the note is built from that function, so a different split here would
    /// draw a link the shelf doesn't list, or list one the body doesn't draw.
    static func markdownWithWikilinks(_ text: String) -> String {
        guard text.contains("[["),
              let regex = try? NSRegularExpression(pattern: #"\[\[([^\]]+)\]\]"#)
        else { return text }
        let ns = text as NSString
        var out = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard match.numberOfRanges > 1 else { continue }
            out += ns.substring(with: NSRange(location: cursor,
                                              length: match.range.location - cursor))
            cursor = match.range.location + match.range.length
            let inner = ns.substring(with: match.range(at: 1))
            // `Target|Alias` and `Target#Heading` — the target is everything
            // before the first of either, exactly as `NoteLinks.extract` cuts it.
            let target = inner
                .split(whereSeparator: { $0 == "|" || $0 == "#" })
                .first.map(String.init)?
                .trimmingCharacters(in: .whitespaces) ?? ""
            let alias = inner.contains("|")
                ? inner.split(separator: "|", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)
                : target
            guard !target.isEmpty, !alias.isEmpty,
                  let encoded = target.addingPercentEncoding(
                    withAllowedCharacters: .alphanumerics) else {
                out += ns.substring(with: match.range)
                continue
            }
            // The alias is somebody's own text and may hold `]` or `)`, either
            // of which ends a markdown link early and spills the rest of the
            // URL into the note as visible prose.
            let safe = alias
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "[", with: "\\[")
                .replacingOccurrences(of: "]", with: "\\]")
            out += "[\(safe)](\(wikiScheme)://\(encoded))"
        }
        out += ns.substring(from: cursor)
        return out
    }

    /// The note title an intercepted wikilink URL names, or nil.
    ///
    /// The inverse of the encoding above, and the ONLY way a tapped link
    /// becomes a destination — so a URL that is not ours, or carries no host,
    /// resolves to nothing rather than to a guess.
    static func wikiTarget(_ url: URL) -> String? {
        guard url.scheme == wikiScheme else { return nil }
        let host = url.host(percentEncoded: false) ?? ""
        return host.isEmpty ? nil : host
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
        /// What the person did. It reaches the sentence only for a `.device`
        /// origin, where "Recorded here" and "Kept here" are the difference
        /// between a claim we can make and one we can't (prd §399).
        var act: NoteSheet.Act = .wrote
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
            // A voice note really was recorded here. A `You` note may have been
            // typed here or shared in from somewhere else, and nothing in the
            // record can tell the two apart — so it says the one thing that is
            // true either way (§399).
            return i.act == .recorded
                ? String(localized: "Recorded here, on this device.")
                : String(localized: "Kept here, on this device.")
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
