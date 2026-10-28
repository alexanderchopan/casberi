import Foundation
import Observation

/// **A THREAT YOU HAVE SEEN STOPS COUNTING (prd §1587).** The Threats door's
/// red figure was every flagged transfer ever, so it only grew. Opening one,
/// or holding it for Mark as seen, keeps its id here; the door counts what
/// is left, and the page keeps the seen ones in grey. On this device only.
@MainActor @Observable
final class ThreatsSeen {
    static let shared = ThreatsSeen()
    static let defaultsKey = "wallet.threats.seen.v1"

    private(set) var ids: Set<String>

    private init() {
        let data = UserDefaults.standard.data(forKey: Self.defaultsKey)
        ids = data.flatMap { try? JSONDecoder().decode(Set<String>.self, from: $0) } ?? []
    }

    func contains(_ id: UUID) -> Bool { ids.contains(id.uuidString) }

    func mark(_ id: UUID) {
        guard !ids.contains(id.uuidString) else { return }
        ids.insert(id.uuidString)
        if let data = try? JSONEncoder().encode(ids) { DefaultsWrite.set(data, forKey: Self.defaultsKey) }
    }
}
