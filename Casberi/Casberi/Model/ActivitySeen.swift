import Foundation
import UIKit
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
///
/// **ACTIVITY SHOWS WHAT IS NEW (prd §1831, user: "only unseen items show in
/// the feed", "I have this list of wallet activity that I've already seen
/// which gets in the way", "on screen counts").** Seen widens from opened to
/// ON SCREEN: a row Activity drew is seen once you leave Activity, and the
/// next visit leaves it out. A visit's list is fixed when it begins
/// (`hidden`), so nothing leaves while you are looking at it, and a trip
/// into an app's page from a row comes back to the same list.
@MainActor
@Observable
final class ActivitySeen {
    static let shared = ActivitySeen()

    nonisolated static let defaultsKey = "activity.seen.v1"
    nonisolated static let cap = 400

    private var stamps: [String: Double]

    /// What this visit leaves out: everything seen when it began.
    private(set) var hidden: Set<String>
    /// The rows this visit drew, stamped when it ends. Not observed: a row
    /// appearing must not redraw the list it is in.
    @ObservationIgnored private var shown: Set<UUID> = []
    /// A row or a word opened a page from Activity; coming back is the same
    /// visit, not a new one.
    @ObservationIgnored private var away = false

    private init() {
        let data = UserDefaults.standard.data(forKey: Self.defaultsKey)
        let loaded = data.flatMap { try? JSONDecoder().decode([String: Double].self, from: $0) } ?? [:]
        stamps = loaded
        hidden = Set(loaded.keys)
        // Leaving the app ends the visit, so what was on screen is seen on
        // the next open. A model write, never a view's state (prd §614).
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                               object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                ActivitySeen.shared.endVisit()
                ActivitySeen.shared.away = false
            }
        }
    }

    func has(_ id: UUID) -> Bool { stamps[id.uuidString] != nil }

    /// Whether this visit leaves the row out.
    func isHidden(_ id: UUID) -> Bool { hidden.contains(id.uuidString) }

    /// Activity drew this row.
    func noteShown(_ id: UUID) { shown.insert(id) }

    /// Activity is landed on: a new visit fixes its list, unless this is the
    /// way back from a page one of its rows opened.
    func beginVisit() {
        if away { away = false; return }
        let next = Set(stamps.keys)
        if next != hidden { hidden = next }
    }

    /// A row or a word is taking you to a page from Activity.
    func leavingForPage() { away = true }

    /// Activity is left: every row it drew is seen.
    func endVisit() {
        let drawn = shown
        shown = []
        for id in drawn { mark(id) }
    }

    func mark(_ id: UUID, at now: Date = .now) {
        guard stamps[id.uuidString] == nil else { return }
        let next = Self.adding(id.uuidString, at: now.timeIntervalSince1970, to: stamps)
        stamps = next
        if let data = try? JSONEncoder().encode(next) { DefaultsWrite.set(data, forKey: Self.defaultsKey) }
    }

    #if DEBUG
    /// `-activitySeenForget YES`: every row new again.
    func forget() {
        stamps = [:]
        hidden = []
        shown = []
        DefaultsWrite.remove(Self.defaultsKey)
    }
    #endif

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
