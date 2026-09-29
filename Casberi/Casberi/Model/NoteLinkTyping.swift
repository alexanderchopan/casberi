import Foundation

/// A LINK TYPED into a note (the note-editor ruling, 2026-09-29) — `[[` at
/// the cursor offers what you keep by title, the way Apple Notes offers notes
/// after `>>`, and a pick writes `[[Exact title]]` exactly as the Link key's
/// picker does (`NoteLinkPicker`, prd §982). One syntax, two doors.
///
/// Counted in `Character`s, like `NoteChecklist`'s cursor functions, so a
/// harness can check it without a text field. Foundation-only:
/// `note-checklist-selftest.sh` compiles it whole.
enum NoteLinkTyping {

    /// The longest query read after `[[` — past it, the brackets were
    /// something else and the offer goes.
    static let maxQuery = 60

    /// The open link the cursor stands in: the offset of its `[[` and the
    /// words typed after it. Nil when the cursor is not inside an unclosed
    /// `[[` on its own line — a `]`, a `[` or a new line after the brackets
    /// closes the question.
    static func openQuery(in text: String, cursor: Int) -> (start: Int, query: String)? {
        let chars = Array(text)
        let at = min(max(cursor, 0), chars.count)
        var i = at
        while i >= 2 {
            let c = chars[i - 1]
            if c == "\n" || c == "]" { return nil }
            if c == "[" {
                guard chars[i - 2] == "[" else { return nil }
                let query = String(chars[i..<at])
                guard query.count <= maxQuery, !query.contains("[") else { return nil }
                return (i - 2, query)
            }
            i -= 1
        }
        return nil
    }

    /// The text with the open link at `start` completed to `[[title]]`, and
    /// the cursor after it. Whatever was typed after `[[` up to the cursor is
    /// replaced — it was the question, and the title is the answer — and a
    /// `]]` already standing at the cursor is taken rather than doubled.
    static func completed(_ text: String, start: Int, cursor: Int,
                          title: String) -> (text: String, cursor: Int) {
        var chars = Array(text)
        let from = min(max(start, 0), chars.count)
        var to = min(max(cursor, from), chars.count)
        if to + 2 <= chars.count, chars[to] == "]", chars[to + 1] == "]" {
            to += 2
        }
        let link = Array("[[\(title)]]")
        chars.replaceSubrange(from..<to, with: link)
        return (String(chars), from + link.count)
    }

    /// The titles offered for a query: the pool filtered by title, the
    /// pool's own order kept (newest first), at most `limit`. An empty query
    /// offers the newest.
    static func offers(_ query: String, in pool: [String], limit: Int = 3) -> [String] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let hits = q.isEmpty ? pool : pool.filter { $0.localizedStandardContains(q) }
        return Array(hits.prefix(limit))
    }
}
