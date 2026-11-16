import Foundation
import Observation

/// **WHITE UNTIL SEEN (prd §1816, user: "if there are new ones there and they
/// all will have one item each, they should be white until seen").** Activity
/// draws one row per app, its newest thing. A row you have opened drops to
/// grey; the next thing that app lands is a different row and stands white.
///
/// Seen means OPENED, never scrolled past: a page that greys on a scroll is
/// grey whole on its first visit and says nothing.
///
/// On this device only, as `ChatSeen` is: it says what these eyes have read.
/// Bounded at `cap`, the oldest stamps dropped first; a dropped stamp turns an
/// old row white again, and Activity holds one row per app, far under the cap.
@MainActor
@Observable
final class ActivitySeen {
    static let shared = ActivitySeen()

    nonisolated static let defaultsKey = "activity.seen.v1"
    nonisolated static let cap = 400

    private var stamps: [String: Double]

    private init() {
        let data = UserDefaults.standard.data(forKey: Self.defaultsKey)
        stamps = data.flatMap { try? JSONDecoder().decode([String: Double].self, from: $0) } ?? [:]
    }

    func has(_ id: UUID) -> Bool { stamps[id.uuidString] != nil }

    func mark(_ id: UUID, at now: Date = .now) {
        guard stamps[id.uuidString] == nil else { return }
        let next = Self.adding(id.uuidString, at: now.timeIntervalSince1970, to: stamps)
        stamps = next
        if let data = try? JSONEncoder().encode(next) { DefaultsWrite.set(data, forKey: Self.defaultsKey) }
    }

    /// The stamps with one more, the oldest dropped past `cap`.
    nonisolated static func adding(_ key: String, at time: Double, to stamps: [String: Double],
                                   cap: Int = ActivitySeen.cap) -> [String: Double] {
        var next = stamps
        next[key] = time
        if next.count > cap {
            for old in next.sorted(by: { ($0.value, $0.key) < ($1.value, $1.key) })
                .prefix(next.count - cap).map(\.key) {
                next[old] = nil
            }
        }
        return next
    }
}
