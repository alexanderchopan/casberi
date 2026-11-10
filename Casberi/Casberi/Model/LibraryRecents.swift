import Foundation

/// **THE APPS YOU LAST OPENED FROM LIBRARY (prd §1733).** Library's Recent
/// row: the five apps of yours last opened here, newest first, so the rooms
/// you use are one tap away and not a folder and a hunt.
///
/// Names only, in this device's defaults, written behind
/// (`DefaultsWrite`, §721). An app no longer yours is dropped where the row
/// is drawn, never here: this keeps what was opened, not what you have.
enum LibraryRecents {
    static let key = "library.recentApps"
    static let keep = 5

    static func load() -> [String] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    /// The list with the app first, kept to `keep`, written behind.
    static func add(_ name: String, to list: [String]) -> [String] {
        var out = list.filter { $0 != name }
        out.insert(name, at: 0)
        out = Array(out.prefix(keep))
        if let data = try? JSONEncoder().encode(out) { DefaultsWrite.set(data, forKey: key) }
        return out
    }

    /// Where a first run starts (prd §1733, the six of §1741): apps across
    /// the categories that are quick to add, A–Z so none is the first step
    /// (§1314's rule). Two take one permission tap (Calendar, Photos), Files
    /// is the folder picker, and GitHub left because it is harder to add
    /// (user, 2026-11-09). The empty Feed's box and Library's row both read
    /// this list.
    static let starts = ["Calendar", "Files", "Photos", "Spotify", "Telegram", "X"]
}
