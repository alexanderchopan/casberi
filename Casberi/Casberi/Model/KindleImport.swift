import Foundation
import SwiftData

/// The Kindle bridge (2026-07-12) — a one-time import of the Kindle's own
/// `My Clippings.txt`, the file the device writes every highlight, note, and
/// bookmark into. No account, no API (Amazon offers neither): plug the Kindle
/// in, copy the file to Files, pick it here. Highlights land as notes, grouped
/// by book, the way Readwise's do. Re-importing adds only what's new — a
/// highlight's ref is a stable hash of its book and text, since the file
/// carries no ids.
///
/// ## The passage used to be destroyed at import (prd §366, 2026-08-12)
///
/// From 2026-07-12 until §366 this landed `title = titleLine(body)` — an
/// 80-character clamp with an ellipsis — and `content = "Book — Author"`. The
/// rest of the highlight was stored NOWHERE: not on `content`, not on
/// `enrichedText`, not on the row it came from. So the sheet drew a truncated
/// quotation at display size as though it were a headline, the book's name in
/// gray underneath as though it were the body, and **the words you marked the
/// passage for were gone**. It rendered perfectly and nothing in a build, an
/// audit or a screen sweep could see it.
///
/// The record is right way round now: the passage on `content`, the work on
/// `authorHandle` (where a room can rank it), the locator on `summary`. The
/// title stays a clamp, because the title is the feed row's label and
/// `titleLine` is exactly what a row wants.
///
/// **The re-import heals.** A highlight already in the corpus dedupes OUT of
/// the landing path, so without a heal on the dedupe hit the fix would reach
/// only files imported from today on and every existing row would stay
/// truncated forever — the social-bridge pattern (2026-07-16), and the reason
/// this walks `thingsByRef` rather than a ref Set. The heal is the ONLY thing
/// that can restore the words, since they exist only in the file.
enum KindleImport {

    struct Summary {
        var imported = 0
        var skipped = 0
        /// Rows already here that this pass repaired — passages restored from
        /// the file, books moved off `content`. Reported rather than folded
        /// into `skipped`: "nothing new" and "nothing new, and I gave you back
        /// 300 passages" are different outcomes, and the second is the whole
        /// reason to run the import again.
        var healed = 0
        var failed = false
    }

    @MainActor
    static func run(data: Data, context: ModelContext) -> Summary {
        guard var text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
            return Summary(failed: true)
        }
        // The Kindle writes a BOM and CRLF line endings. Normalize CRLF → LF
        // up front: splitting on CharacterSet.newlines instead would break
        // each "\r\n" into TWO separators, inserting a phantom empty line that
        // shifts every entry's metadata and body off by one.
        text = text.replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // Entries are separated by a line of ten equals signs.
        let blocks = text.components(separatedBy: "==========")
        var summary = Summary()
        // The MAP, not the ref set: a highlight already here must be reachable
        // so the pass can repair it (see the type's own note). `seen` still
        // guards against a file that lists the same passage twice.
        var landed = IngestSupport.thingsByRef(context, source: "Kindle")
        var seen = Set(landed.keys)
        var parsedAny = false
        var added = 0
        var healed = 0

        for raw in blocks {
            let lines = raw.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            let entry = Array(lines.drop(while: \.isEmpty))
            guard entry.count >= 2, !entry[0].isEmpty else { continue }
            let titleLine = entry[0]
            // Line 2 is the metadata ("- Your Highlight … | Added on …"); the
            // text follows, after the blank line the format inserts.
            let body = entry.dropFirst(2).joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }   // bookmarks carry no text — nothing to keep
            parsedAny = true

            let (book, author) = splitTitle(titleLine)
            let ref = "kindle:\(stableHash(book + "|" + body))"
            let work = author.isEmpty ? book : "\(book) — \(author)"
            let locator = parseLocator(entry[1])
            if seen.contains(ref) {
                summary.skipped += 1
                // The heal (prd §366). Only a row that is actually wrong is
                // touched — an unchanged row must cost a comparison, not a
                // write, or every re-import re-dates the whole corpus through
                // SwiftData's change tracking and mirrors all of it to
                // CloudKit.
                if let existing = landed[ref], heal(existing, passage: body,
                                                    work: work, locator: locator) {
                    healed += 1
                }
                continue
            }
            seen.insert(ref)

            let thing = Thing(
                kind: .note,
                // The row's label, and only the row's label. The passage
                // itself now lives on `content`, so this clamp costs nothing.
                title: IngestSupport.titleLine(body),
                content: body,
                source: "Kindle",
                capturedAt: parseDate(entry[1]) ?? .now,
                sourceRef: ref
            )
            // The work, where a room can group and rank by it. The same string
            // the pre-§366 importer wrote into `content`, deliberately — the
            // sheet reads both eras and must get one grouping key from them.
            thing.authorHandle = work
            // "page 42" / "location 611-612" — display copy about this
            // excerpt, which is what `summary` is for (the Trello card-back
            // rule; its own doc already names "the rest of a clamped Readwise
            // highlight"). nil on a Kindle whose file isn't in English, which
            // is a missing line rather than a wrong one.
            thing.summary = locator
            context.insert(thing)
            landed[ref] = thing
            SpotlightIndex.index([thing])
            added += 1
        }

        summary.healed = healed
        summary.imported = added
        // A file with no parseable entries isn't a Kindle export — say so.
        summary.failed = !parsedAny && added == 0
        // A pass that only healed still wrote — saving on `added` alone was
        // the shape that would have silently discarded every restored passage.
        if added > 0 || healed > 0 { context.saveHonestly() }
        return summary
    }

    /// Repairs one already-landed highlight against the file it came from.
    /// Returns whether anything actually changed.
    ///
    /// Three separate repairs, each guarded by its own comparison so a row
    /// that is already right is never written:
    ///
    /// 1. **The passage.** Pre-§366 rows hold the WORK in `content`; rows from
    ///    a file re-read after an edit could hold an older passage. Either way
    ///    the file is the authority — it is where these words exist.
    /// 2. **The work.** Moved off `content` onto `authorHandle`.
    /// 3. **The locator.** Never stored before at all.
    ///
    /// The TITLE is deliberately left alone. It is the row's label, it is a
    /// clamp of these same words, and rewriting it on every device that ever
    /// re-imports would churn the feed for no reading gained.
    @MainActor
    private static func heal(_ thing: Thing, passage: String,
                             work: String, locator: String?) -> Bool {
        var changed = false
        if thing.content != passage { thing.content = passage; changed = true }
        if thing.authorHandle != work { thing.authorHandle = work; changed = true }
        if let locator, thing.summary != locator { thing.summary = locator; changed = true }
        // The words are what the retriever reads, so a row whose passage was
        // just restored has to be re-indexed or it stays findable only by its
        // clamped title — which is the state this whole repair exists to end.
        if changed { SpotlightIndex.index([thing]) }
        return changed
    }

    /// "page 42", or "location 611-612" where the book has no pages.
    ///
    /// The Kindle writes a metadata line like
    /// `- Your Highlight on page 42 | Location 611-612 | Added on Sunday, …`.
    /// Page leads because it is the number a person can act on — it is what is
    /// printed in the paper copy and what you would quote — and location is
    /// the fallback for the many books that have no page numbers at all.
    ///
    /// **Both are shown, never together.** "page 42 · location 611-612" is two
    /// spellings of one fact, and the second one means nothing to a reader.
    ///
    /// English-only, and it fails to nil: a Kindle set to German writes
    /// "Seite", and a missing locator line is a fact we don't have rather than
    /// a wrong one. Same shape as `parseDate` above, which has always keyed on
    /// "Added on".
    static func parseLocator(_ meta: String) -> String? {
        for segment in meta.components(separatedBy: "|") {
            let s = segment.trimmingCharacters(in: .whitespaces)
            if let page = value(in: s, after: "page") { return "page \(page)" }
        }
        for segment in meta.components(separatedBy: "|") {
            let s = segment.trimmingCharacters(in: .whitespaces)
            if let loc = value(in: s, after: "location") { return "location \(loc)" }
        }
        return nil
    }

    /// The digits (and hyphens — a highlight spans a location RANGE) directly
    /// following a keyword, case-insensitively. nil when the keyword isn't
    /// there or nothing numeric follows it.
    private static func value(in segment: String, after keyword: String) -> String? {
        guard let r = segment.range(of: keyword, options: .caseInsensitive) else { return nil }
        let rest = segment[r.upperBound...].drop(while: { $0 == " " })
        let digits = rest.prefix(while: { $0.isNumber || $0 == "-" })
        guard let first = digits.first, first.isNumber else { return nil }
        // A trailing hyphen ("611-") is a range whose end we never read; the
        // number alone is the honest half.
        return String(digits).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// "Book Title (Author Name)" → the book and its author. A title with no
    /// trailing parenthetical keeps the whole line as the book.
    private static func splitTitle(_ s: String) -> (book: String, author: String) {
        guard s.hasSuffix(")"), let open = s.lastIndex(of: "(") else { return (s, "") }
        let book = String(s[..<open]).trimmingCharacters(in: .whitespaces)
        let author = String(s[s.index(after: open)..<s.index(before: s.endIndex)])
            .trimmingCharacters(in: .whitespaces)
        return book.isEmpty ? (s, "") : (book, author)
    }

    private static let clippingDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEEE, MMMM d, yyyy h:mm:ss a"
        return f
    }()

    private static func parseDate(_ meta: String) -> Date? {
        guard let r = meta.range(of: "Added on ") else { return nil }
        return clippingDate.date(from: String(meta[r.upperBound...]).trimmingCharacters(in: .whitespaces))
    }

    /// A launch-stable hash (FNV-1a) — Swift's own hashValue is seeded per
    /// process, so it can't dedupe across re-imports; this can.
    private static func stableHash(_ s: String) -> String {
        var hash: UInt64 = 1469598103934665603
        for byte in s.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return String(hash, radix: 16)
    }
}
