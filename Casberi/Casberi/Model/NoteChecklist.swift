import Foundation

/// A note's CHECKLIST (prd §982, 2026-09-28) — the one piece of structure the
/// note sheet writes, because a list of things to do is the most common note
/// anybody jots, and Apple Notes' checklist is the one format people reach for
/// in it.
///
/// **Two spellings, one list.** While the note is being written the field
/// shows each item as `○ milk` — the circle Apple Notes draws, typed as a
/// character because a `TextField` draws characters and nothing else. The
/// note KEEPS it as markdown, `- [ ] milk`, which is what Obsidian, GitHub and
/// every markdown reader already call a task; a note shared out, or read by
/// the agent, says what it is in the one syntax everybody reads.
///
/// **Ticking an item is the one write a kept note takes.** §26 rules that a
/// note is captured whole and never edited. A tick is not an edit of the
/// words — it is the state of the list, the way a pin is the state of a row —
/// and a checklist you cannot tick is a list with its only verb missing
/// (§83). `toggled(_:ordinal:)` flips exactly one marker and leaves every
/// character of the words where it was.
///
/// Foundation-only, so `note-checklist-selftest.sh` compiles it whole.
enum NoteChecklist {

    /// The circle the field draws for an item (U+25CB), and a space.
    static let editorMark = "\u{25CB} "
    /// A ticked item in the field (U+25C9), when a kept list is opened to be
    /// edited (prd §981): its tick survives the edit.
    static let doneEditorMark = "\u{25C9} "
    static let openMark = "- [ ] "
    static let doneMark = "- [x] "

    // MARK: - Reading a kept note

    /// One line's task, or nil when it is not one — `NoteSheet.taskLine`,
    /// the renderer's own parser, so what draws as an item is what ticks.
    static func task(_ line: String) -> (done: Bool, text: String)? {
        NoteSheet.taskLine(line)
    }

    /// The text with its `ordinal`-th task (counted from 0, in reading order)
    /// ticked or unticked. Only the one character inside the brackets
    /// changes; an ordinal past the last task returns the text unchanged.
    static func toggled(_ text: String, ordinal: Int) -> String {
        var lines = text.components(separatedBy: "\n")
        var seen = 0
        for i in lines.indices {
            guard let found = task(lines[i]) else { continue }
            if seen == ordinal {
                let line = lines[i]
                guard let open = line.firstIndex(of: "[") else { return text }
                let inside = line.index(after: open)
                lines[i].replaceSubrange(inside...inside, with: found.done ? " " : "x")
                return lines.joined(separator: "\n")
            }
            seen += 1
        }
        return text
    }

    /// How much of the list is done, or nil when the text holds no list.
    static func progress(_ text: String) -> (done: Int, total: Int)? {
        var done = 0, total = 0
        for line in text.components(separatedBy: "\n") {
            guard let t = task(line) else { continue }
            total += 1
            if t.done { done += 1 }
        }
        return total == 0 ? nil : (done, total)
    }

    /// A line's words without its task marker — the title a list's first
    /// item makes, so a row never reads "- [ ] milk".
    static func plain(_ line: String) -> String {
        if let t = task(line) { return t.text }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix(editorMark) || trimmed.hasPrefix(doneEditorMark) {
            return String(trimmed.dropFirst(editorMark.count)).trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }

    // MARK: - Writing one

    /// The draft as the note keeps it: every `○ ` line becomes `- [ ] `, and
    /// an item left with no words is dropped rather than kept as an empty
    /// box.
    static func stored(_ draft: String) -> String {
        draft.components(separatedBy: "\n").compactMap { line -> String? in
            let lead = line.prefix(while: { $0 == " " })
            let body = line.dropFirst(lead.count)
            let done: Bool
            if body.hasPrefix(editorMark) || body == "\u{25CB}" { done = false }
            else if body.hasPrefix(doneEditorMark) || body == "\u{25C9}" { done = true }
            else { return line }
            let words = body.dropFirst(1).trimmingCharacters(in: .whitespaces)
            return words.isEmpty ? nil : lead + (done ? doneMark : openMark) + words
        }
        .joined(separator: "\n")
    }

    /// A kept note opened to be edited (prd §981): its `- [ ]` and `- [x]`
    /// items back into the field's circles, so the list reads as a list
    /// while it is changed and keeps its ticks when it is kept again.
    static func editable(_ text: String) -> String {
        text.components(separatedBy: "\n").map { line in
            guard let item = task(line) else { return line }
            let lead = line.prefix(while: { $0 == " " })
            return lead + (item.done ? doneEditorMark : editorMark) + item.text
        }
        .joined(separator: "\n")
    }

    /// The checklist key, pressed with no cursor to read (the title focused,
    /// or nothing): the LAST line becomes an item, or stops being one — a
    /// jot is written top to bottom. With a cursor, `toggleLine(_:at:)`.
    static func toggleLastLine(_ draft: String) -> String {
        guard !draft.isEmpty else { return editorMark }
        var lines = draft.components(separatedBy: "\n")
        let last = lines[lines.count - 1]
        if last.hasPrefix(editorMark) || last.hasPrefix(doneEditorMark) {
            lines[lines.count - 1] = String(last.dropFirst(editorMark.count))
            return lines.joined(separator: "\n")
        }
        if last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines[lines.count - 1] = editorMark
            return lines.joined(separator: "\n")
        }
        return draft + "\n" + editorMark
    }

    // MARK: - Where the cursor is (the note-editor ruling)

    /// The line holding character `offset` (counted in `Character`s from the
    /// start), as its start and end offsets. An offset past the end is the
    /// last line; a negative one the first.
    static func lineBounds(_ text: String, at offset: Int) -> (start: Int, end: Int) {
        let chars = Array(text)
        let at = min(max(offset, 0), chars.count)
        var start = at
        while start > 0, chars[start - 1] != "\n" { start -= 1 }
        var end = at
        while end < chars.count, chars[end] != "\n" { end += 1 }
        return (start, end)
    }

    /// Whether the line under the cursor is an item — the key's lit state
    /// once the field says where its cursor is.
    static func isItem(_ text: String, at offset: Int) -> Bool {
        let (start, end) = lineBounds(text, at: offset)
        let line = String(Array(text)[start..<end])
        return line.hasPrefix(editorMark) || line.hasPrefix(doneEditorMark)
    }

    /// The checklist key, pressed with the cursor at `offset`: THAT line
    /// becomes an item, or stops being one, and the cursor keeps its place
    /// in the words (two characters right when a circle went on, two left
    /// when one came off, never inside the circle). An empty text starts an
    /// item. This supersedes `toggleLastLine` wherever the field reports its
    /// cursor; `toggleLastLine` stays for a field that does not.
    static func toggleLine(_ text: String, at offset: Int) -> (text: String, cursor: Int) {
        guard !text.isEmpty else { return (editorMark, editorMark.count) }
        var chars = Array(text)
        let at = min(max(offset, 0), chars.count)
        let (start, end) = lineBounds(text, at: at)
        let line = String(chars[start..<end])
        let mark = editorMark.count
        if line.hasPrefix(editorMark) || line.hasPrefix(doneEditorMark) {
            chars.removeSubrange(start..<(start + mark))
            return (String(chars), max(start, at - mark))
        }
        chars.insert(contentsOf: Array(editorMark), at: start)
        return (String(chars), at + mark)
    }

    /// Return, inside a list, typed ANYWHERE in the words (§982's rule at
    /// the end of the words, carried to the cursor), with where the cursor
    /// lands.
    ///
    /// One newline inserted, nothing else changed — a paste, a deletion or
    /// two characters at once is left exactly as it arrived (nil). The text
    /// BEFORE the new line decides: an item with words (or with words after
    /// the cursor, a split) starts the next line as an item; an empty item
    /// with nothing after it ends the list, the newline and the circle both
    /// gone, as in Apple Notes. Anything else is nil.
    ///
    /// A newline typed beside another newline could have been typed at any
    /// place in that run — "○ a⏎" and "⏎" on the empty line under it make
    /// the same text. `hint`, the cursor before the key, says which; with no
    /// hint the earliest place is read, the end of the line above.
    static func continuedAt(old: String, new: String, hint: Int? = nil) -> (text: String, cursor: Int)? {
        let o = Array(old), n = Array(new)
        guard n.count == o.count + 1 else { return nil }
        var last = 0
        while last < o.count, o[last] == n[last] { last += 1 }
        guard n[last] == "\n", Array(n[(last + 1)...]) == Array(o[last...]) else { return nil }
        var first = last
        while first > 0, o[first - 1] == "\n" { first -= 1 }
        let p = hint.map { min(max($0, first), last) } ?? first
        // The line the Return was typed in, split at `p`.
        let (start, end) = lineBounds(old, at: p)
        let before = String(o[start..<p])
        let after = String(o[p..<end])
        guard before.hasPrefix(editorMark) || before.hasPrefix(doneEditorMark) else { return nil }
        let words = before.dropFirst(editorMark.count).trimmingCharacters(in: .whitespaces)
        if words.isEmpty && after.trimmingCharacters(in: .whitespaces).isEmpty {
            // Return on an empty item: the item goes, and the line stays empty.
            var kept = o
            kept.replaceSubrange(start..<end, with: [])
            return (String(kept), start)
        }
        var out = n
        out.insert(contentsOf: Array(editorMark), at: p + 1)
        return (String(out), p + 1 + editorMark.count)
    }

    /// Whether the last line is an item — the key's lit state.
    static func endsInItem(_ draft: String) -> Bool {
        let last = draft.components(separatedBy: "\n").last ?? ""
        return last.hasPrefix(editorMark) || last.hasPrefix(doneEditorMark)
    }
}
