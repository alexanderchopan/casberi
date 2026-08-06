import Foundation
import SwiftData

/// Obsidian's own wikilink graph, made walkable inside the sheet (2026-07-28)
/// — the delight a vault sync into Casberi didn't have. `[[Other note]]`
/// already means something inside Obsidian; reusing it costs nothing but
/// resolving a title against notes already landed. Extraction happens at
/// ingest, against the FULL body before `ObsidianIngest`'s 300-char `content`
/// clamp (a link past that point would otherwise be lost forever — see
/// `Thing.wikilinks`). Resolution happens at sheet-open time in
/// `ThingSheetView`, the same "read on open, never persisted" shape as
/// `replies`/`approvalCheck` there: a target note may not have synced yet, or
/// may never exist, so nothing here ever invents a destination.
enum NoteLinks {
    /// `[[Target]]`, `[[Target|Alias]]`, or `[[Target#Heading]]` — Obsidian's
    /// own link syntax. Only the note title before a `|` or `#` is kept (the
    /// alias/heading are display or block-scope details this graph doesn't
    /// need). De-duped case-insensitively, order kept, empty titles dropped.
    static func extract(from markdown: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\[\[([^\]|#]+)"#) else { return [] }
        let ns = markdown as NSString
        var seen = Set<String>()
        var out: [String] = []
        for match in regex.matches(in: markdown, range: NSRange(location: 0, length: ns.length)) {
            guard match.numberOfRanges > 1 else { continue }
            let title = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty, seen.insert(title.lowercased()).inserted else { continue }
            out.append(title)
        }
        return out
    }

    /// Resolves wikilink target titles against the vault's own landed notes
    /// — a case-insensitive exact title match. A target with no landed match
    /// (not yet synced, or renamed/deleted in the vault since) is simply
    /// omitted, honestly — nothing here invents a destination for a link
    /// that doesn't (yet) resolve.
    @MainActor
    static func resolve(_ targets: [String], context: ModelContext) -> [Thing] {
        guard !targets.isEmpty else { return [] }
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { $0.source == "Obsidian" })
        guard let notes = try? context.fetch(descriptor) else { return [] }
        var byTitle: [String: Thing] = [:]
        for note in notes { byTitle[note.title.lowercased()] = note }
        var seen = Set<String>()
        var out: [Thing] = []
        for target in targets {
            let key = target.lowercased()
            guard seen.insert(key).inserted, let match = byTitle[key] else { continue }
            out.append(match)
        }
        return out
    }

    /// The INVERSE graph (2026-08-06): which landed notes link TO this one.
    ///
    /// Obsidian's own most-used panel, and the half a note cannot carry
    /// itself — a note's outgoing links are written in its text, its incoming
    /// ones are written in everybody else's. So this is the one direction the
    /// vault's structure can only be seen from outside the file, which is
    /// exactly the thing a corpus is for.
    ///
    /// Deliberately the same shape as `resolve`: read at sheet-open time,
    /// never persisted, and honest about a link that doesn't resolve — the
    /// match is a note's own TITLE, which for this bridge is its filename, so
    /// a renamed note stops being linked-to the moment the vault says it is.
    /// Capped, because a daily-note vault has hub notes with hundreds of
    /// backlinks and a sheet is not a graph view.
    static let backlinkCap = 20

    @MainActor
    static func backlinks(to note: Thing, context: ModelContext) -> [Thing] {
        guard note.isLive, note.source == "Obsidian" else { return [] }
        let title = note.title.lowercased()
        guard !title.isEmpty else { return [] }
        let noteID = note.id
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { $0.source == "Obsidian" })
        guard let notes = try? context.fetch(descriptor) else { return [] }
        var out: [Thing] = []
        for candidate in notes where candidate.isLive && candidate.id != noteID {
            guard candidate.wikilinks.contains(where: { $0.lowercased() == title }) else { continue }
            out.append(candidate)
            if out.count == backlinkCap { break }
        }
        return out
    }
}
