import Foundation

/// FIND IN NOTES (the Find-in-Notes ruling, 2026-09-29) — the Notes room's
/// own filter, Apple Notes' search field over its list.
///
/// The composer's Find (§215) searches everything you keep; a note you wrote
/// last spring is one row among thousands there. This narrows the room you
/// are standing in, as you type, and only it.
///
/// **Every word typed must match**, in any order, in the title, the words or
/// the folder's name — case, accents and width folded
/// (`localizedStandardContains`, the app's one text-match rule). A locked
/// note matches only by title and folder, because its record holds nothing
/// else (§982): the filter cannot find what no screen may show.
///
/// Foundation-only, so `note-checklist-selftest.sh` compiles it whole.
enum NoteFind {

    /// The typed words, split on white space; an empty query is no filter.
    static func words(_ query: String) -> [String] {
        query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    static func matches(title: String, content: String, folder: String?,
                        query: String) -> Bool {
        let wanted = words(query)
        guard !wanted.isEmpty else { return true }
        return wanted.allSatisfy { word in
            title.localizedStandardContains(word)
                || content.localizedStandardContains(word)
                || (folder?.localizedStandardContains(word) ?? false)
        }
    }
}
