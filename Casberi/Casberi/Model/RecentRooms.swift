import Foundation

/// The rooms tray's Recent line (prd §1013): the rooms you opened last,
/// newest first, one line long. Seat names only — the tray records a room
/// when `FeedFilter.source` lands on a connected seat, never a category, All
/// or the notes room — and it draws only the seats still connected.
///
/// It lives on this device and nowhere else. Readers read the in-memory
/// cache; the write rides `DefaultsWrite`, because a `UserDefaults` write on
/// the main thread can deadlock with every view body (§721).
@MainActor
enum RecentRooms {
    /// One line of the tray's five columns.
    static let cap = 5
    private static let key = "tray.recentRooms"
    private static var cache: [String]?

    static var list: [String] {
        if let cache { return cache }
        let stored = UserDefaults.standard.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        cache = stored
        return stored
    }

    static func record(_ source: String) {
        var next = list.filter { $0 != source }
        next.insert(source, at: 0)
        next = Array(next.prefix(cap))
        guard next != cache else { return }
        #if DEBUG
        NSLog("[Casberi] recentRooms: %@", next.joined(separator: ", "))
        #endif
        cache = next
        if let data = try? JSONEncoder().encode(next) {
            DefaultsWrite.set(data, forKey: key)
        }
    }
}
