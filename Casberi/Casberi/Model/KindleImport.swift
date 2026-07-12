import Foundation
import SwiftData

/// The Kindle bridge (2026-07-12) — a one-time import of the Kindle's own
/// `My Clippings.txt`, the file the device writes every highlight, note, and
/// bookmark into. No account, no API (Amazon offers neither): plug the Kindle
/// in, copy the file to Files, pick it here. Highlights land as notes, grouped
/// by book, the way Readwise's do. Re-importing adds only what's new — a
/// highlight's ref is a stable hash of its book and text, since the file
/// carries no ids.
enum KindleImport {

    struct Summary {
        var imported = 0
        var skipped = 0
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
        var seen = IngestSupport.existingSourceRefs(context)
        var parsedAny = false
        var added = 0

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
            if seen.contains(ref) { summary.skipped += 1; continue }
            seen.insert(ref)

            let source = author.isEmpty ? book : "\(book) — \(author)"
            let thing = Thing(
                kind: .note,
                title: IngestSupport.titleLine(body),
                content: source,
                source: "Kindle",
                capturedAt: parseDate(entry[1]) ?? .now,
                sourceRef: ref
            )
            context.insert(thing)
            SpotlightIndex.index([thing])
            added += 1
        }

        summary.imported = added
        // A file with no parseable entries isn't a Kindle export — say so.
        summary.failed = !parsedAny && added == 0
        if added > 0 { try? context.save() }
        return summary
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
