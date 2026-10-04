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
    /// A bullet in the field (prd §1099): `- ` or `* ` typed at the start of
    /// a line becomes `• `, as Apple Notes turns a dash into a list. The note
    /// keeps it as markdown's `- `.
    static let bulletMark = "\u{2022} "
    static let keptBullet = "- "

    // MARK: - Bullets and numbers (prd §1099)

    /// A line's bullet words, or nil when it is not a bullet — in either
    /// spelling (`• ` in the field, `- ` / `* ` kept), never a task.
    static func bullet(_ line: String) -> String? {
        let trimmed = line.drop(while: { $0 == " " })
        guard task(line) == nil else { return nil }
        for mark in [bulletMark, "- ", "* "] where trimmed.hasPrefix(mark) {
            return String(trimmed.dropFirst(mark.count))
        }
        return nil
    }

    /// A numbered line's number and words ("2. eggs" → 2, "eggs"), or nil.
    static func numbered(_ line: String) -> (number: Int, text: String)? {
        let trimmed = line.drop(while: { $0 == " " })
        let digits = trimmed.prefix(while: \.isNumber)
        guard !digits.isEmpty, digits.count <= 3, let n = Int(digits) else { return nil }
        let rest = trimmed.dropFirst(digits.count)
        guard rest.hasPrefix(". ") else { return nil }
        return (n, String(rest.dropFirst(2)))
    }

    /// The space after a dash, typed at the start of the LAST line (where the
    /// writing happens — a `TextField` does not say where its cursor is):
    /// `- ` or `* ` becomes `• `. Nil when nothing changes.
    static func bulleted(old: String, new: String) -> String? {
        guard new.count == old.count + 1, new.hasPrefix(old), new.hasSuffix(" ") else { return nil }
        var lines = new.components(separatedBy: "\n")
        let last = lines[lines.count - 1]
        let lead = last.prefix(while: { $0 == " " })
        let body = last.dropFirst(lead.count)
        guard body == "- " || body == "* " else { return nil }
        lines[lines.count - 1] = lead + bulletMark
        return lines.joined(separator: "\n")
    }

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
        if let words = bullet(line) { return words.trimmingCharacters(in: .whitespaces) }
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
            // A bullet keeps as markdown's dash (prd §1099); an empty one is
            // dropped, like an empty item.
            if body.hasPrefix(bulletMark) || body == "\u{2022}" {
                let words = body.dropFirst(1).trimmingCharacters(in: .whitespaces)
                return words.isEmpty ? nil : lead + keptBullet + words
            }
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
            if let words = bullet(line) {
                return line.prefix(while: { $0 == " " }) + bulletMark + words
            }
            guard let item = task(line) else { return line }
            let lead = line.prefix(while: { $0 == " " })
            return lead + (item.done ? doneEditorMark : editorMark) + item.text
        }
        .joined(separator: "\n")
    }

    /// The checklist key, pressed: the LAST line becomes an item, or stops
    /// being one. The field is a `TextField`, which does not tell anyone
    /// where its cursor is, and a jot is written top to bottom — so the key
    /// acts where the writing is happening, at the end.
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

    /// The page's tick (prd §1099): a note opened on its page draws its items
    /// as circles you tick before you type, and the tick flips the
    /// `ordinal`-th item of the DRAFT (counted from 0) between `○ ` and `◉ `,
    /// every other character left where it was. The draft is kept the way
    /// every edit is (`stored`), so the tick lands as `- [x]`.
    static func toggledEditor(_ draft: String, ordinal: Int) -> String {
        var lines = draft.components(separatedBy: "\n")
        var seen = 0
        for i in lines.indices {
            let lead = lines[i].prefix(while: { $0 == " " })
            let body = lines[i].dropFirst(lead.count)
            let open = body.hasPrefix(editorMark)
            guard open || body.hasPrefix(doneEditorMark) else { continue }
            if seen == ordinal {
                lines[i] = lead + (open ? doneEditorMark : editorMark) + body.dropFirst(editorMark.count)
                return lines.joined(separator: "\n")
            }
            seen += 1
        }
        return draft
    }

    /// Whether the last line is an item — the key's lit state.
    static func endsInItem(_ draft: String) -> Bool {
        let last = draft.components(separatedBy: "\n").last ?? ""
        return last.hasPrefix(editorMark) || last.hasPrefix(doneEditorMark)
    }

    /// Return, inside a list: a new line after an item with words starts the
    /// next item; a new line after an EMPTY item ends the list, as it does in
    /// Apple Notes. Anything else — a paste, a deletion, a line typed in the
    /// middle — is left exactly as it arrived. Returns nil when there is
    /// nothing to change.
    static func continued(old: String, new: String) -> String? {
        guard new.count == old.count + 1, new.hasSuffix("\n"), new.hasPrefix(old) else { return nil }
        let lines = old.components(separatedBy: "\n")
        // A bullet or a numbered line continues the same way (prd §1099):
        // the next line takes the next mark, and Return on an empty one ends
        // the list.
        if let last = lines.last {
            let lead = String(last.prefix(while: { $0 == " " }))
            let body = last.dropFirst(lead.count)
            var nextMark: String?
            var words: String?
            if body.hasPrefix(bulletMark) {
                nextMark = bulletMark
                words = String(body.dropFirst(bulletMark.count))
            } else if let item = numbered(last) {
                nextMark = "\(item.number + 1). "
                words = item.text
            }
            if let nextMark, let words {
                if words.trimmingCharacters(in: .whitespaces).isEmpty {
                    var kept = lines
                    kept[kept.count - 1] = ""
                    return kept.joined(separator: "\n")
                }
                return new + lead + nextMark
            }
        }
        guard let last = lines.last,
              last.hasPrefix(editorMark) || last.hasPrefix(doneEditorMark) else { return nil }
        let words = last.dropFirst(editorMark.count).trimmingCharacters(in: .whitespaces)
        if words.isEmpty {
            // Return on an empty item: the item goes, and the line stays empty.
            var kept = lines
            kept[kept.count - 1] = ""
            return kept.joined(separator: "\n")
        }
        return new + editorMark
    }
}
