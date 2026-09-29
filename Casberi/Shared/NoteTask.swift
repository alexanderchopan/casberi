import Foundation

/// A note's checklist, as the note KEEPS it (prd §982): `- [ ] milk`,
/// `- [x] eggs` — the one parser and the two writes every target shares.
///
/// Here in `Shared/` (the note-widget ruling, 2026-09-29) because three
/// targets now write a kept note: the app (a tick on the note's page), the
/// widget (a tick on the Home Screen) and the intents (Add to note, from
/// Siri, Shortcuts and the share sheet). One parser, so what draws as an
/// item is what ticks, wherever it was ticked. `NoteSheet.taskLine` and
/// `NoteChecklist.toggled`/`progress` read through this.
///
/// Foundation-only: `note-checklist-selftest.sh` and `note-sheet-selftest.sh`
/// compile it whole.
enum NoteTask {

    /// One line's checklist item, or nil: `- [ ]`, `* [ ]` or `+ [ ]`, `x`
    /// or `X` for done, and words after it — an item with no words is not an
    /// item.
    static func line(_ line: String) -> (done: Bool, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let bullet = trimmed.first, bullet == "-" || bullet == "*" || bullet == "+"
        else { return nil }
        let rest = trimmed.dropFirst()
        guard rest.hasPrefix(" [") else { return nil }
        let box = rest.dropFirst(2)
        guard let mark = box.first, box.dropFirst().hasPrefix("]") else { return nil }
        let done: Bool
        switch mark {
        case " ": done = false
        case "x", "X": done = true
        default: return nil
        }
        let text = box.dropFirst(2).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (done, text)
    }

    /// Every item, in reading order.
    static func items(_ text: String) -> [(done: Bool, text: String)] {
        text.components(separatedBy: "\n").compactMap(line)
    }

    /// The text with its `ordinal`-th item (counted from 0, in reading order)
    /// ticked or unticked. Only the one character inside the brackets
    /// changes; an ordinal past the last item returns the text unchanged.
    static func toggled(_ text: String, ordinal: Int) -> String {
        var lines = text.components(separatedBy: "\n")
        var seen = 0
        for i in lines.indices {
            guard let found = line(lines[i]) else { continue }
            if seen == ordinal {
                let current = lines[i]
                guard let open = current.firstIndex(of: "[") else { return text }
                let inside = current.index(after: open)
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
        for l in text.components(separatedBy: "\n") {
            guard let t = line(l) else { continue }
            total += 1
            if t.done { done += 1 }
        }
        return total == 0 ? nil : (done, total)
    }

    /// ADD TO NOTE (the add-to-note ruling): `text` written under what the
    /// note already says. A note that ENDS in a list takes each line as the
    /// next open item — "add milk to Groceries" is an item, not a sentence
    /// under a list — and any other note takes the words on a new line.
    /// Blank lines in what is added are dropped from a list, kept in prose;
    /// nothing to add returns the note unchanged.
    static func appended(_ content: String, _ text: String) -> String {
        let added = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !added.isEmpty else { return content }
        let kept = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kept.isEmpty else { return added }
        let lastLine = kept.components(separatedBy: "\n").last ?? ""
        if line(lastLine) != nil {
            let items = added.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .map { line($0) != nil ? $0 : "- [ ] " + $0 }
            return kept + "\n" + items.joined(separator: "\n")
        }
        return kept + "\n" + added
    }

    /// One line of a note as the Note widget draws it (the note-widget
    /// ruling): an item with its place in the list, so its tick names it, or
    /// a line of words.
    enum PageLine: Equatable {
        case item(done: Bool, text: String, ordinal: Int)
        case words(String)
    }

    /// The note's words under its title, for a surface with no renderer: the
    /// title's own line dropped when it opens the words (never the title
    /// twice, §398), blank lines dropped, `[[links]]` read as their titles,
    /// items numbered in reading order so a tick names the right one.
    static func page(title: String, content: String) -> [PageLine] {
        var lines = content.components(separatedBy: "\n")
        // A title is its first line, cut short when the line is long — so a
        // first line the title opens is the title's, and goes. A list's first
        // item names its note too (§982), and stays: it is an item to tick.
        let named = unlinked(title).trimmingCharacters(in: CharacterSet(charactersIn: "… "))
        if let first = lines.first, line(first) == nil, !named.isEmpty,
           unlinked(first.trimmingCharacters(in: .whitespaces)).hasPrefix(named) {
            lines.removeFirst()
        }
        var ordinal = 0
        var out: [PageLine] = []
        for raw in lines {
            if let item = line(raw) {
                out.append(.item(done: item.done, text: unlinked(item.text), ordinal: ordinal))
                ordinal += 1
                continue
            }
            let words = raw.trimmingCharacters(in: .whitespaces)
            guard !words.isEmpty else { continue }
            out.append(.words(unlinked(words)))
        }
        return out
    }

    /// `[[Title]]` read as `Title`.
    static func unlinked(_ text: String) -> String {
        text.replacingOccurrences(of: "[[", with: "").replacingOccurrences(of: "]]", with: "")
    }
}
