import Foundation

/// EXPORT NOTES AS MARKDOWN (the note-export ruling, 2026-09-29) — every note
/// you wrote, as a folder of `.md` files you save to Files: an Obsidian vault,
/// iCloud Drive, anywhere.
///
/// **Why.** A note is kept in `- [ ]` and `[[links]]` already (§982), the
/// vault's own syntax, so the only thing between these notes and every other
/// notes app was a way out. A way out is also what makes writing here safe.
///
/// **The shape.** One file per note, named by its title; a folder of yours
/// (§980) is a directory; a note's picture sits beside it as a `.jpg` and a
/// voice note's audio as a `.m4a`, each embedded the way Obsidian embeds
/// (`![[name]]`). A front matter line says when it was written. A locked note
/// is NOT exported — its words are sealed (§982) and a plain file of them
/// would undo the lock — and the count of those left out is returned, so the
/// door can say so.
///
/// Foundation-only: `note-checklist-selftest.sh` compiles it whole. The bytes
/// are joined in by the caller (`NoteExportDocument`).
enum NoteExport {

    struct Note: Equatable {
        var title: String
        var content: String
        var folder: String?
        var created: Date
        var isVoice = false
        var isLocked = false
        var hasPicture = false
        var hasAudio = false
        /// Pictures after the first (the note-pictures ruling).
        var morePictures = 0
    }

    /// One file to write: its path under the export folder, and what goes in
    /// it — text, or the index of the note whose picture or audio it holds.
    struct File: Equatable {
        enum Body: Equatable {
            case markdown(String)
            /// The note's `index`-th picture, 0 the first.
            case picture(note: Int, index: Int = 0)
            case audio(note: Int)
        }
        var path: [String]
        var body: Body
    }

    struct Plan: Equatable {
        var files: [File]
        var lockedLeftOut: Int
    }

    static func plan(_ notes: [Note]) -> Plan {
        var files: [File] = []
        var taken: [String: Set<String>] = [:]   // directory key → names used
        // One directory per folder, spelled as its first note spells it: a
        // folder is one folder whatever the case it was typed in (§980).
        var spelled: [String: String] = [:]
        var locked = 0
        for (index, note) in notes.enumerated() {
            if note.isLocked { locked += 1; continue }
            let typed = note.folder.map(fileName).flatMap { $0.isEmpty ? nil : $0 }
            let dirKey = typed.map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) } ?? ""
            let dir = typed.map { spelled[dirKey, default: $0] }
            if let dir { spelled[dirKey] = dir }
            let base = unique(fileName(note.title).isEmpty ? String(localized: "Untitled") : fileName(note.title),
                              in: &taken[dirKey, default: []])
            let prefix = dir.map { [$0] } ?? []
            var embeds: [String] = []
            if note.hasPicture {
                files.append(File(path: prefix + [base + ".jpg"], body: .picture(note: index)))
                embeds.append("![[\(base).jpg]]")
                for n in 0..<max(0, note.morePictures) {
                    let name = "\(base) \(n + 2).jpg"
                    files.append(File(path: prefix + [name], body: .picture(note: index, index: n + 1)))
                    embeds.append("![[\(name)]]")
                }
            }
            if note.hasAudio {
                files.append(File(path: prefix + [base + ".m4a"], body: .audio(note: index)))
                embeds.append("![[\(base).m4a]]")
            }
            files.append(File(path: prefix + [base + ".md"],
                              body: .markdown(markdown(note, embeds: embeds))))
        }
        return Plan(files: files, lockedLeftOut: locked)
    }

    /// The note's file: a front matter with its date, then its words — the
    /// title's line as a heading when the words do not open with it — then
    /// what it embeds.
    static func markdown(_ note: Note, embeds: [String]) -> String {
        let stamp = ISO8601DateFormatter.string(from: note.created, timeZone: .current,
                                                formatOptions: [.withInternetDateTime])
        var out = "---\ncreated: \(stamp)\n---\n\n"
        let words = note.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = words.components(separatedBy: "\n").first ?? ""
        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let named = title.trimmingCharacters(in: CharacterSet(charactersIn: "… "))
        if !title.isEmpty, named.isEmpty || !firstLine.contains(named) {
            out += "# \(title)\n\n"
        }
        if !words.isEmpty { out += words + "\n" }
        if !embeds.isEmpty { out += (words.isEmpty ? "" : "\n") + embeds.joined(separator: "\n") + "\n" }
        return out
    }

    /// A title as a file name: no path separators or the characters Files,
    /// Windows and Obsidian refuse, no leading dot, at most 80 characters.
    static func fileName(_ title: String) -> String {
        let refused = CharacterSet(charactersIn: "/\\:*?\"<>|#^[]\n\r\t")
        let cleaned = title.unicodeScalars.map { refused.contains($0) ? " " : String($0) }.joined()
        let squeezed = cleaned.split(whereSeparator: { $0 == " " }).joined(separator: " ")
        var name = String(squeezed.prefix(80)).trimmingCharacters(in: .whitespaces)
        while name.hasPrefix(".") { name.removeFirst() }
        return name.trimmingCharacters(in: .whitespaces)
    }

    /// `name`, or `name 2`, `name 3`… — the first not yet used in its
    /// directory, compared without case (Files is case-insensitive).
    static func unique(_ name: String, in used: inout Set<String>) -> String {
        var candidate = name
        var n = 2
        while used.contains(candidate.lowercased()) {
            candidate = "\(name) \(n)"
            n += 1
        }
        used.insert(candidate.lowercased())
        return candidate
    }
}
