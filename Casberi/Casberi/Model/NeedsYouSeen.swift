import Foundation
import Observation

/// **A ROW IN NEEDS YOU CAN BE MARKED AS SEEN.** Holding a row there offers
/// Mark as seen; its id and its due date are kept here, and the Wallet's
/// Needs you (`FeedScreen.walletUpcoming`) leaves it out. The date is part of
/// the key: a deadline that moves (a name renewed, then near again) is a new
/// ask and comes back. On this device only, as `ThreatsSeen` is. It writes
/// nothing to the row, so a seat's next read cannot revert it.
@MainActor @Observable
final class NeedsYouSeen {
    static let shared = NeedsYouSeen()
    static let defaultsKey = "wallet.needsYou.seen.v1"

    private(set) var keys: Set<String>

    private init() {
        let data = UserDefaults.standard.data(forKey: Self.defaultsKey)
        keys = data.flatMap { try? JSONDecoder().decode(Set<String>.self, from: $0) } ?? []
    }

    nonisolated static func key(_ id: UUID, due: Date?) -> String {
        "\(id.uuidString)|\(due.map { Int($0.timeIntervalSince1970) } ?? 0)"
    }

    func contains(_ id: UUID, due: Date?) -> Bool { keys.contains(Self.key(id, due: due)) }

    func mark(_ id: UUID, due: Date?) {
        guard keys.insert(Self.key(id, due: due)).inserted else { return }
        if let data = try? JSONEncoder().encode(keys) { DefaultsWrite.set(data, forKey: Self.defaultsKey) }
    }
}
