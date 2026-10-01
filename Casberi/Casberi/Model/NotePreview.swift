import Foundation

/// The Notes room's second line (prd §983) — what a note of yours SAYS, under
/// its title, the way Apple Notes previews a note in its list.
///
/// A list says how far along it is and what is next ("2 of 3 done · bread"),
/// a locked note says only that it is locked (its record holds nothing else,
/// §982), a voice note says it is one, a one-line note draws no second line,
/// and anything else shows the first line after the one its title was made from
/// — never the title twice (§398's defect, in a new room).
///
/// Foundation-only, so `note-checklist-selftest.sh` compiles it whole beside
/// `NoteChecklist` and `NoteSheet`.
enum NotePreview {

    static func line(title: String, content: String, isVoice: Bool,
                     isLocked: Bool, from origin: String? = nil) -> String? {
        if isLocked { return String(localized: "Locked") }
        if isVoice { return String(localized: "Voice note") }
        // A highlight's line names the page it was kept from (prd §1020).
        if let origin, !origin.isEmpty { return origin }
        if let list = NoteChecklist.progress(content) {
            let next = content.components(separatedBy: "\n")
                .compactMap(NoteChecklist.task)
                .first { !$0.done }?.text
            let head = String(localized: "\(list.done) of \(list.total) done")
            return next.map { "\(head) · \(plain($0))" } ?? head
        }
        return underTitle(title: title, content: content).first.map(plain)
    }

    /// What a note of yours reads on the Notes room's cover (§908's Notes
    /// face): the lines under its title, a list's items as the circles its
    /// sheet draws, a link as its title — never the title twice, never a
    /// box's markdown. The caller draws nothing for a locked or voice note.
    static func body(title: String, content: String) -> String {
        underTitle(title: title, content: content).map { line in
            guard let item = NoteChecklist.task(line) else { return plain(line) }
            return (item.done ? NoteChecklist.doneEditorMark : NoteChecklist.editorMark)
                + plain(item.text)
        }
        .joined(separator: "\n")
    }

    /// The note's non-empty lines after the one its title was made from.
    private static func underTitle(title: String, content: String) -> [String] {
        let lines = content.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let titleKey = plain(title).lowercased()
        // The first line is the title's own unless the title was cut from it.
        return Array(lines.drop { plain($0).lowercased() == titleKey
            || titleKey.hasSuffix("…") && plain($0).lowercased().hasPrefix(String(titleKey.dropLast())) })
    }

    /// A line's words, without the markers a note writes: a task's box and a
    /// link's brackets.
    static func plain(_ line: String) -> String {
        NoteChecklist.plain(line)
            .replacingOccurrences(of: "[[", with: "")
            .replacingOccurrences(of: "]]", with: "")
    }
}
