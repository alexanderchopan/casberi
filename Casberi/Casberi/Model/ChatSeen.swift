import Foundation

/// **WHEN YOU LAST OPENED A CHAT (prd §1635),** so its sheet can mark where
/// the messages you have not seen begin ("2 new"). One time per chat, kept on
/// this device only, the newest 200 chats; a chat never opened here marks
/// nothing, because "everything is new" says nothing.
@MainActor
enum ChatSeen {
    static let defaultsKey = "chat.seen.v1"
    static let cap = 200

    private static var cache: [String: Double]?

    private static var stamps: [String: Double] {
        if let cache { return cache }
        let data = UserDefaults.standard.data(forKey: defaultsKey)
        let read = data.flatMap { try? JSONDecoder().decode([String: Double].self, from: $0) } ?? [:]
        cache = read
        return read
    }

    /// The last time this chat was opened before now, nil when never.
    static func seen(_ id: UUID) -> Date? {
        stamps[id.uuidString].map { Date(timeIntervalSince1970: $0) }
    }

    /// Stamps this chat as opened now, dropping the oldest past the cap.
    static func mark(_ id: UUID, at now: Date = .now) {
        var next = stamps
        next[id.uuidString] = now.timeIntervalSince1970
        if next.count > cap {
            for key in next.sorted(by: { $0.value < $1.value }).prefix(next.count - cap).map(\.key) {
                next[key] = nil
            }
        }
        cache = next
        if let data = try? JSONEncoder().encode(next) { DefaultsWrite.set(data, forKey: defaultsKey) }
    }

    /// How many of the chat's newest messages came after `seen`: the times
    /// are aligned to the transcript's last lines, so the count is from the
    /// end. Zero when nothing is newer or nothing is timed.
    nonisolated static func newCount(times: [Date], since seen: Date?) -> Int {
        guard let seen else { return 0 }
        return times.reversed().prefix { $0 > seen }.count
    }
}
