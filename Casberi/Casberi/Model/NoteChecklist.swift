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

    /// Whether this tick finished the list (prd §1193): every item of a list
    /// of two or more is done now, and was not before. One tick, one moment.
    static func finished(before: String, after: String) -> Bool {
        guard let now = progress(after), now.total >= 2, now.done == now.total else { return false }
        guard let was = progress(before) else { return true }
        return was.done < was.total
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
        // A heading's or a quote's mark is markdown's, not its words (§1100).
        let opened = line.trimmingCharacters(in: .whitespaces)
        for mark in ["# ", "> "] where opened.hasPrefix(mark) {
            return String(opened.dropFirst(mark.count)).trimmingCharacters(in: .whitespaces)
        }
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

/// THE EDITOR'S LIST RULES, AT THE CURSOR (prd §1100). `NoteChecklist`'s
/// writing half acts on the LAST line, because a SwiftUI `TextField` never
/// says where its cursor is; the note's editor is a `UITextView` now, so each
/// rule here takes the text and the cursor (a UTF-16 offset, as UIKit counts)
/// and answers the text and the cursor after. Foundation-only, compiled whole
/// by `note-checklist-selftest.sh` with the rest of this file.
///
/// The field's spellings are `NoteChecklist`'s: `○ `/`◉ ` items, `• `
/// bullets, `N. ` numbers, and markdown's `> ` quote and `# ` heading, which
/// are kept as typed.
enum NoteEditing {
    struct Edit: Equatable {
        var text: String
        var cursor: Int
        /// The selection's length after the edit (a wrapped selection stays
        /// selected), 0 for a bare cursor.
        var length: Int = 0
    }

    // MARK: - Formatting, for someone who never types markdown (prd §1101)

    /// The inline marks the Aa key writes: markdown's, so the note reads the
    /// same in Obsidian, a share and the agent.
    enum Inline: String, CaseIterable {
        case bold = "**", italic = "_", strike = "~~"
    }

    /// The line styles the Aa key sets.
    enum LineStyle: CaseIterable {
        case body, heading, bullet, number, quote
        var mark: String {
            switch self {
            case .body: return ""
            case .heading: return NoteEditing.headingMark
            case .bullet: return NoteChecklist.bulletMark
            case .number: return "1. "
            case .quote: return NoteEditing.quoteMark
            }
        }
    }

    /// Bold, italic or strikethrough over the selection — or off, when the
    /// selection already sits inside that mark. With nothing selected the
    /// marks go in around the cursor, which stands between them, so what you
    /// type next is in that style.
    static func wrap(_ text: String, selection: NSRange, in style: Inline) -> Edit {
        let ns = text as NSString
        let m = style.rawValue
        let ml = (m as NSString).length
        let start = selection.location, end = selection.location + selection.length
        // Already wrapped: the marks stand right outside the selection.
        if start >= ml, end + ml <= ns.length,
           ns.substring(with: NSRange(location: start - ml, length: ml)) == m,
           ns.substring(with: NSRange(location: end, length: ml)) == m {
            let inner = ns.substring(with: selection)
            let out = ns.replacingCharacters(in: NSRange(location: start - ml, length: selection.length + 2 * ml),
                                             with: inner)
            return Edit(text: out, cursor: start - ml, length: selection.length)
        }
        // The selection holds its own marks: take them off.
        let inner = ns.substring(with: selection)
        if selection.length > 2 * ml, inner.hasPrefix(m), inner.hasSuffix(m) {
            let bare = String(inner.dropFirst(m.count).dropLast(m.count))
            let out = ns.replacingCharacters(in: selection, with: bare)
            return Edit(text: out, cursor: start, length: (bare as NSString).length)
        }
        let out = ns.replacingCharacters(in: selection, with: m + inner + m)
        return Edit(text: out, cursor: start + ml, length: selection.length)
    }

    /// The line at the cursor takes a style: its mark (heading, bullet,
    /// number, quote — or an item's circle) is replaced by the new one, and
    /// the style it already has turns back to plain words.
    static func setLineStyle(_ text: String, cursor: Int, to style: LineStyle) -> Edit {
        let range = lineRange(text, at: cursor)
        let current = (text as NSString).substring(with: range).trimmingCharacters(in: .newlines)
        let lead = current.prefix(while: { $0 == " " })
        let body = String(current.dropFirst(lead.count))
        var old = ""
        if body.hasPrefix(headingMark) { old = headingMark }
        else if let found = mark(of: current) { old = found.mark }
        let same = (style == .number && NoteChecklist.numbered(body) != nil) || (!old.isEmpty && old == style.mark)
        let new = same ? "" : style.mark
        let start = range.location + lead.count
        let oldLength = (old as NSString).length
        let out = (text as NSString).replacingCharacters(in: NSRange(location: start, length: oldLength), with: new)
        let delta = (new as NSString).length - oldLength
        return Edit(text: out, cursor: max(start, cursor + delta))
    }

    /// The inline marks' runs in a text, for drawing: each run's whole range
    /// (marks included) and its words' range, by style. A mark is only a mark
    /// around words — `**` alone, or `_` inside a word, is a character.
    static func inlineRuns(_ text: String) -> [(style: Inline, whole: NSRange, words: NSRange)] {
        let patterns: [(Inline, String)] = [
            (.bold, #"\*\*(?=\S)(.+?)(?<=\S)\*\*"#),
            (.strike, #"~~(?=\S)(.+?)(?<=\S)~~"#),
            (.italic, #"(?<![\w_])_(?=\S)(.+?)(?<=\S)_(?![\w_])"#),
        ]
        let full = NSRange(location: 0, length: (text as NSString).length)
        var out: [(Inline, NSRange, NSRange)] = []
        for (style, pattern) in patterns {
            guard let rx = try? NSRegularExpression(pattern: pattern) else { continue }
            for m in rx.matches(in: text, range: full) { out.append((style, m.range, m.range(at: 1))) }
        }
        return out
    }

    /// A line's words without the Aa key's inline marks — the title a note
    /// makes and the room's preview never read `**`.
    static func inlinePlain(_ line: String) -> String {
        var out = line
        for run in inlineRuns(line).sorted(by: { $0.whole.location > $1.whole.location }) {
            let ns = out as NSString
            guard run.whole.upperBound <= ns.length else { continue }
            out = ns.replacingCharacters(in: run.whole, with: (line as NSString).substring(with: run.words))
        }
        return out
    }

    static let quoteMark = "> "
    static let headingMark = "# "

    /// The line holding a UTF-16 offset: its range in the text.
    static func lineRange(_ text: String, at offset: Int) -> NSRange {
        let ns = text as NSString
        let safe = max(0, min(offset, ns.length))
        return ns.lineRange(for: NSRange(location: safe, length: 0))
    }

    /// A line's own words, without its line break.
    private static func line(_ text: String, _ range: NSRange) -> String {
        (text as NSString).substring(with: range).trimmingCharacters(in: .newlines)
    }

    /// A line's lead (its spaces) and the list mark after it, or nil.
    static func mark(of line: String) -> (lead: String, mark: String)? {
        let lead = String(line.prefix(while: { $0 == " " }))
        let body = line.dropFirst(lead.count)
        for m in [NoteChecklist.editorMark, NoteChecklist.doneEditorMark, NoteChecklist.bulletMark, quoteMark]
            where body.hasPrefix(m) { return (lead, m) }
        if let n = NoteChecklist.numbered(String(body)) { return (lead, "\(n.number). ") }
        return nil
    }

    /// Return at the cursor. Inside a list line with words, the next line
    /// takes the next mark (an open item, a bullet, the next number, a
    /// quote); on a line that is only its mark, the mark goes and the list
    /// ends — Apple Notes' rule. Nil: let the newline through as typed.
    static func returnKey(_ text: String, cursor: Int) -> Edit? {
        let range = lineRange(text, at: cursor)
        let current = line(text, range)
        guard let (lead, mark) = mark(of: current) else { return nil }
        let words = current.dropFirst(lead.count + mark.count).trimmingCharacters(in: .whitespaces)
        let ns = text as NSString
        if words.isEmpty {
            // End the list: the line keeps its lead only.
            let lineEnd = range.location + (current as NSString).length
            let cleared = ns.replacingCharacters(in: NSRange(location: range.location,
                                                             length: lineEnd - range.location),
                                                 with: "")
            return Edit(text: cleared, cursor: range.location)
        }
        var next = mark
        if mark == NoteChecklist.doneEditorMark { next = NoteChecklist.editorMark }
        if let n = NoteChecklist.numbered(String(current.dropFirst(lead.count))) { next = "\(n.number + 1). " }
        let insert = "\n" + lead + next
        let out = ns.replacingCharacters(in: NSRange(location: cursor, length: 0), with: insert)
        return Edit(text: out, cursor: cursor + (insert as NSString).length)
    }

    /// A space typed at the cursor: `- ` or `* ` opening a line becomes a
    /// bullet. Nil: let the space through.
    static func space(_ text: String, cursor: Int) -> Edit? {
        let range = lineRange(text, at: cursor)
        let before = (text as NSString).substring(with: NSRange(location: range.location,
                                                                length: cursor - range.location))
        let lead = before.prefix(while: { $0 == " " })
        let body = before.dropFirst(lead.count)
        guard body == "-" || body == "*" else { return nil }
        let out = (text as NSString).replacingCharacters(
            in: NSRange(location: range.location + lead.count, length: 1),
            with: NoteChecklist.bulletMark)
        return Edit(text: out, cursor: cursor + (NoteChecklist.bulletMark as NSString).length - 1)
    }

    /// The checklist key at the cursor: the line becomes an item, or stops
    /// being one (a bullet becomes an item too).
    static func toggleChecklist(_ text: String, cursor: Int) -> Edit {
        let range = lineRange(text, at: cursor)
        let current = line(text, range)
        let ns = text as NSString
        let lead = current.prefix(while: { $0 == " " })
        let start = range.location + lead.count
        if let found = mark(of: current) {
            let markLength = (found.mark as NSString).length
            let isItem = found.mark == NoteChecklist.editorMark || found.mark == NoteChecklist.doneEditorMark
            let replacement = isItem ? "" : NoteChecklist.editorMark
            let out = ns.replacingCharacters(in: NSRange(location: start, length: markLength), with: replacement)
            let delta = (replacement as NSString).length - markLength
            return Edit(text: out, cursor: max(start, cursor + delta))
        }
        let out = ns.replacingCharacters(in: NSRange(location: start, length: 0), with: NoteChecklist.editorMark)
        return Edit(text: out, cursor: cursor + (NoteChecklist.editorMark as NSString).length)
    }

    /// Indent (+1) or outdent (−1) the line at the cursor by two spaces.
    static func indent(_ text: String, cursor: Int, by step: Int) -> Edit? {
        let range = lineRange(text, at: cursor)
        let current = line(text, range)
        let ns = text as NSString
        if step > 0 {
            guard current.prefix(while: { $0 == " " }).count < 8 else { return nil }
            return Edit(text: ns.replacingCharacters(in: NSRange(location: range.location, length: 0), with: "  "),
                        cursor: cursor + 2)
        }
        let spaces = min(2, current.prefix(while: { $0 == " " }).count)
        guard spaces > 0 else { return nil }
        return Edit(text: ns.replacingCharacters(in: NSRange(location: range.location, length: spaces), with: ""),
                    cursor: max(range.location, cursor - spaces))
    }

    /// Move the line at the cursor up (−1) or down (+1), past its neighbour.
    static func moveLine(_ text: String, cursor: Int, by step: Int) -> Edit? {
        var lines = text.components(separatedBy: "\n")
        let index = lineIndex(text, at: cursor)
        let target = index + step
        guard lines.indices.contains(index), lines.indices.contains(target) else { return nil }
        let column = cursor - offset(ofLine: index, in: lines)
        lines.swapAt(index, target)
        let out = lines.joined(separator: "\n")
        return Edit(text: out, cursor: offset(ofLine: target, in: lines) + column)
    }

    /// The tick on an item at a line (by index): flip it, then the TICKED
    /// SINK — a ticked item moves to the foot of its run of items, and an
    /// unticked one rises to stand above the run's first ticked item (Apple
    /// Notes' "sort checked items"). Works in either spelling: the field's
    /// circles or a kept note's boxes.
    static func tick(lines: [String], at index: Int) -> [String] {
        guard lines.indices.contains(index), let done = isDone(lines[index]) else { return lines }
        var out = lines
        out[index] = flipped(lines[index])
        // The run of items around it.
        var top = index, bottom = index
        while top > 0, isDone(out[top - 1]) != nil { top -= 1 }
        while bottom < out.count - 1, isDone(out[bottom + 1]) != nil { bottom += 1 }
        let item = out.remove(at: index)
        bottom -= 1
        if !done {
            // Now ticked: the foot of the run.
            out.insert(item, at: bottom + 1)
        } else {
            // Now open: above the first ticked item in the run.
            var at = top
            while at <= bottom, isDone(out[at]) == false { at += 1 }
            out.insert(item, at: at)
        }
        return out
    }

    /// nil when a line is no item; else whether it is ticked.
    static func isDone(_ line: String) -> Bool? {
        let body = line.drop(while: { $0 == " " })
        if body.hasPrefix(NoteChecklist.editorMark) { return false }
        if body.hasPrefix(NoteChecklist.doneEditorMark) { return true }
        return NoteChecklist.task(line)?.done
    }

    private static func flipped(_ line: String) -> String {
        let lead = String(line.prefix(while: { $0 == " " }))
        let body = line.dropFirst(lead.count)
        if body.hasPrefix(NoteChecklist.editorMark) {
            return lead + NoteChecklist.doneEditorMark + body.dropFirst(NoteChecklist.editorMark.count)
        }
        if body.hasPrefix(NoteChecklist.doneEditorMark) {
            return lead + NoteChecklist.editorMark + body.dropFirst(NoteChecklist.doneEditorMark.count)
        }
        return NoteChecklist.toggled(line, ordinal: 0)
    }

    /// The index of the line holding a UTF-16 offset.
    static func lineIndex(_ text: String, at offset: Int) -> Int {
        let ns = text as NSString
        let safe = max(0, min(offset, ns.length))
        return ns.substring(to: safe).components(separatedBy: "\n").count - 1
    }

    private static func offset(ofLine index: Int, in lines: [String]) -> Int {
        lines.prefix(index).reduce(0) { $0 + ($1 as NSString).length + 1 }
    }
}

extension NoteChecklist {
    /// A kept note's `ordinal`-th task ticked or unticked, then sunk to the
    /// foot of its run (or raised above the run's first ticked item) — the
    /// box's tick (prd §1100), the same rule the editor's tick keeps.
    static func toggledSinking(_ text: String, ordinal: Int) -> String {
        let lines = text.components(separatedBy: "\n")
        var seen = 0
        for i in lines.indices where task(lines[i]) != nil {
            if seen == ordinal { return NoteEditing.tick(lines: lines, at: i).joined(separator: "\n") }
            seen += 1
        }
        return text
    }
}
