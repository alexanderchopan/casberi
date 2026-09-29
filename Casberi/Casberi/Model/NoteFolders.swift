import Foundation

/// THE NOTES ROOM'S FOLDERS — the rule for a folder's NAME and the room's
/// folder list (prd §980, 2026-09-29).
///
/// A folder is a name. A thing is filed by writing that name to
/// `Thing.folder` (one folder at most — user: "one folder"), and a pin files
/// the same way a note does (user: "anything in the room"). The list of
/// folders is what `NoteFolderStore` holds UNION every name a row carries:
/// the store keeps an EMPTY folder alive, and the rows keep a folder alive on
/// a device whose key-value mirror has not landed yet — the row rides
/// CloudKit, the list rides the key-value store, and either may arrive first.
///
/// Foundation-only, so `note-folders-selftest.sh` compiles it whole.
enum NoteFolderName {

    /// The longest name kept: a folder row is one line in the rows' column.
    static let maxLength = 40

    /// A typed name, made storable: whitespace trimmed, inner runs collapsed
    /// to one space, clamped to `maxLength`. Nothing left is no folder.
    static func clean(_ raw: String) -> String? {
        let words = raw.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        let joined = words.joined(separator: " ")
        let clamped = String(joined.prefix(maxLength))
            .trimmingCharacters(in: .whitespaces)
        return clamped.isEmpty ? nil : clamped
    }

    /// The identity two spellings share — "Recipes" and "recipes" are one
    /// folder, as they are in Notes and Finder.
    static func key(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// The folder `name` already is, spelled as it was first made, or nil
    /// when it is new — so "recipes" typed later files into "Recipes".
    static func existing(_ name: String, in names: [String]) -> String? {
        let k = key(name)
        return names.first { key($0) == k }
    }

    /// The room's folder list: the stored names, then any name a row carries
    /// that the store has not heard of, one per `key`, in Finder's order.
    /// The stored spelling wins a clash.
    static func list(stored: [String], filed: [String?]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for name in stored + filed.compactMap({ $0 }) {
            guard let clean = clean(name), seen.insert(key(clean)).inserted else { continue }
            out.append(clean)
        }
        return out.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// How many rows each folder holds, by `key`.
    static func counts(filed: [String?]) -> [String: Int] {
        var out: [String: Int] = [:]
        for case let name? in filed { out[key(name), default: 0] += 1 }
        return out
    }
}
