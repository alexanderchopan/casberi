import Foundation

/// The Notes room's second line (prd §983) — what a note of yours SAYS, under
/// its title, the way Apple Notes previews a note in its list.
///
/// A list says how far along it is and what is next ("2 of 3 done · bread"),
/// a locked note says only that it is locked (its record holds nothing else,
/// §982), a voice note says how long it runs and the words after its title
/// ("0:42 · then the courtyards", prd §1099) — "Voice note" only when it has
/// neither, because the waveform lead already says what it is — a one-line
/// note draws no second line,
/// and anything else shows the first line after the one its title was made from
/// — never the title twice (§398's defect, in a new room).
///
/// Foundation-only, so `note-checklist-selftest.sh` compiles it whole beside
/// `NoteChecklist` and `NoteSheet`.
enum NotePreview {

    static func line(title: String, content: String, isVoice: Bool,
                     isLocked: Bool, from origin: String? = nil,
                     length: String? = nil) -> String? {
        if isLocked { return String(localized: "Locked") }
        if isVoice {
            let words = voiceRest(title: title, content: content)
            switch (length, words) {
            case let (length?, words?): return "\(length) · \(words)"
            case let (length?, nil):    return length
            case let (nil, words?):     return words
            case (nil, nil):            return String(localized: "Voice note")
            }
        }
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
            // A bullet keeps its dot on the cover (prd §1099).
            if NoteChecklist.bullet(line) != nil { return NoteChecklist.bulletMark + plain(line) }
            guard let item = NoteChecklist.task(line) else { return plain(line) }
            return (item.done ? NoteChecklist.doneEditorMark : NoteChecklist.editorMark)
                + plain(item.text)
        }
        .joined(separator: "\n")
    }

    /// A voice note's words past its title. A recording is one line and its
    /// title the first 80 characters of it (`IngestSupport.titleLine`), so a
    /// cut title has nothing under it but the middle of a word — the line is
    /// then the length alone. A transcript corrected into lines reads as any
    /// note does.
    private static func voiceRest(title: String, content: String) -> String? {
        guard !title.hasSuffix("…") else { return nil }
        return underTitle(title: title, content: content).first.map(plain)
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
        readableLinks(titledLinks(NoteEditing.inlinePlain(NoteChecklist.plain(line)))
            .replacingOccurrences(of: "[[", with: "")
            .replacingOccurrences(of: "]]", with: ""))
    }

    /// A pasted link the editor titled, `[title](address)` (prd §1100),
    /// reads as its title.
    static func titledLinks(_ line: String) -> String {
        guard line.contains("]("),
              let rx = try? NSRegularExpression(pattern: #"\[([^\[\]\n]+)\]\((https?://[^\s)]+)\)"#)
        else { return line }
        let ns = line as NSString
        return rx.stringByReplacingMatches(in: line, range: NSRange(location: 0, length: ns.length),
                                           withTemplate: "$1")
    }

    /// A bare address, as the room reads it (prd §1099): its site and the
    /// last part of its path — "en.wikipedia.org › Bauhaus Archive" — never
    /// the scheme and the slashes, which filled the Notes box with
    /// "https://en.wikipedia.org/wiki/". Only the address's own words: no
    /// page title is fetched or guessed. The page keeps the address whole.
    static func readableLinks(_ line: String) -> String {
        guard line.contains("://") else { return line }
        let trailing = CharacterSet(charactersIn: ".,;:!?)\"'")
        return line.split(separator: " ", omittingEmptySubsequences: false).map { word -> String in
            let token = String(word)
            guard token.hasPrefix("http://") || token.hasPrefix("https://") else { return token }
            var address = token
            var tail = ""
            while let last = address.unicodeScalars.last, trailing.contains(last) {
                tail = String(address.removeLast()) + tail
            }
            guard let url = URL(string: address), var host = url.host, !host.isEmpty else { return token }
            if host.hasPrefix("www.") { host.removeFirst(4) }
            let page = url.pathComponents.last { $0 != "/" }
                .map { ($0.removingPercentEncoding ?? $0)
                    .replacingOccurrences(of: "_", with: " ")
                    .replacingOccurrences(of: "-", with: " ") }
            return (page.map { "\(host) › \($0)" } ?? host) + tail
        }
        .joined(separator: " ")
    }
}
