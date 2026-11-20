import Foundation
import Observation

/// **A THREAT YOU HAVE SEEN STOPS COUNTING (prd §1587).** The Threats door's
/// red figure was every flagged transfer ever, so it only grew. Opening one,
/// or holding it for Mark as seen, keeps its id here; the door counts what
/// is left, and a seen one leaves the page for the Seen row at its foot
/// (prd §1919, over §1587's grey row). On this device only.
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

    /// Every finding on the page at once (prd §1849): Risks' "Mark all as
    /// seen".
    func markAll(_ all: [UUID]) {
        let fresh = all.map(\.uuidString).filter { !ids.contains($0) }
        guard !fresh.isEmpty else { return }
        ids.formUnion(fresh)
        if let data = try? JSONEncoder().encode(ids) { DefaultsWrite.set(data, forKey: Self.defaultsKey) }
    }

    /// Undo of a Mark all as seen (prd §1919): the findings come back as new.
    func unmark(_ all: [UUID]) {
        let back = all.map(\.uuidString).filter { ids.contains($0) }
        guard !back.isEmpty else { return }
        ids.subtract(back)
        if let data = try? JSONEncoder().encode(ids) { DefaultsWrite.set(data, forKey: Self.defaultsKey) }
    }

    func mark(_ id: UUID) {
        guard !ids.contains(id.uuidString) else { return }
        ids.insert(id.uuidString)
        if let data = try? JSONEncoder().encode(ids) { DefaultsWrite.set(data, forKey: Self.defaultsKey) }
    }
}
