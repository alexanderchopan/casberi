import Foundation
import SwiftData

/// HIGHLIGHT (prd §1020): a passage you keep off a reading page.
///
/// Select words on an article, a mail or any body the app holds, and **Keep**
/// stands in the selection menu beside Copy (`KeepableText`). Keeping makes a
/// note of yours — `You`, `.note`, in the Notes room with everything a note
/// has (folders, the long press, the lock, the card) — whose words ARE the
/// passage, linked to the thing it came from the way a note links anything
/// you keep (§982.4): the origin's title in `wikilinks`, so the origin's
/// "Points at this" shelf lists the passage with no new query.
///
/// What marks it as a highlight is its `sourceRef` — `highlight:<origin id>`,
/// the stable door back to the page — and nothing else: no kind, no new
/// field, nothing CloudKit has to learn. The origin's link rides
/// `externalLink` so the card and the share carry the page.
enum Highlight {
    static let refPrefix = "highlight:"
    /// The kind tag beside `Note`, so the row and the sheet can say what it is.
    static let tag = "Highlight"

    static func isHighlight(_ thing: Thing) -> Bool {
        thing.source == NoteSheetSource.keptSource && thing.kind == .note
            && (thing.sourceRef ?? "").hasPrefix(refPrefix)
    }

    /// The origin's id, off the reference.
    static func originID(of thing: Thing) -> UUID? {
        guard let ref = thing.sourceRef, ref.hasPrefix(refPrefix) else { return nil }
        return UUID(uuidString: String(ref.dropFirst(refPrefix.count)))
    }

    /// The origin's title, as the note recorded it — the one wikilink.
    static func originTitle(of thing: Thing) -> String? {
        isHighlight(thing) ? thing.wikilinks.first : nil
    }

    /// A passage's title: its first line, clamped the way every ingest
    /// clamps a title, with the quote marks the card adds left off.
    static func title(for passage: String) -> String {
        let first = passage.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? passage
        return IngestSupport.titleLine(first)
    }

    /// Keep a passage from `origin`. The words are kept exactly as selected,
    /// trimmed; nothing is kept for an empty selection.
    @MainActor
    static func keep(_ passage: String, from origin: Thing, link: URL?,
                     context: ModelContext) -> Thing? {
        let words = passage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, origin.isLive else { return nil }
        let note = Thing(kind: .note, title: title(for: words), content: words,
                         source: NoteSheetSource.keptSource, tags: [tag],
                         sourceRef: refPrefix + origin.id.uuidString)
        note.wikilinks = [origin.title]
        note.externalLink = link?.absoluteString
        context.insert(note)
        context.saveHonestly()
        SpotlightIndex.index([note])
        CorpusSignal.shared.bump()
        return note
    }

    /// The thing the passage came from, when it is still kept.
    @MainActor
    static func origin(of thing: Thing, context: ModelContext) -> Thing? {
        guard let id = originID(of: thing) else { return nil }
        var fetch = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { $0.id == id })
        fetch.fetchLimit = 1
        return (try? context.fetch(fetch))?.first.flatMap { $0.isLive ? $0 : nil }
    }
}
