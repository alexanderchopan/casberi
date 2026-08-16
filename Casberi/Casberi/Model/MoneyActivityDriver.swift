import Foundation
import SwiftData
#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit
#endif

/// Starts, refreshes and ends the money receipt's Live Activity (prd §369
/// amendment, 2026-08-16). See `MoneyActivityAttributes` for the three rulings
/// that keep it honest.
///
/// Shaped after `ImportActivityDriver` — the whole ActivityKit surface behind
/// one `#if`, empty bodies on Mac Catalyst, and no permission spent (Live
/// Activities are a Settings switch, not a prompt, which is why this needs none
/// of §306's rationing).
///
/// **Keyed by `Thing.id`, and that is what makes it safe to call from anywhere.**
/// `start` refuses a second activity for a record that already has one, and
/// `refresh` is a no-op for a record that doesn't — so the bridge sweep can
/// blindly offer every row it re-read without knowing which ones anybody chose
/// to track.
@MainActor
enum MoneyActivityDriver {

    #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
    /// Live activities by `Thing.id`. A dictionary rather than a single slot
    /// (`ImportActivityDriver`'s shape): imports are one-at-a-time by nature,
    /// while somebody can perfectly reasonably be waiting on a card charge AND
    /// a Safe signature at once.
    private static var live: [String: Activity<MoneyActivityAttributes>] = [:]

    /// Whether this record is already being tracked — what the control reads to
    /// decide whether it offers to start or to stop.
    static func isTracking(_ id: String) -> Bool { live[id] != nil }

    static var available: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// Begin tracking. `stamp` is the receipt's own stamp word.
    ///
    /// Returns false when nothing started, so the caller can say so rather than
    /// leaving a control that looks like it worked (the honesty rule: no dead
    /// controls). The commonest false is Live Activities being switched off for
    /// the app, which is not an error and not something to nag about.
    @discardableResult
    static func start(id: String, title: String, stamp: String) -> Bool {
        guard available, live[id] == nil else { return false }
        let state = MoneyActivityAttributes.ContentState(
            stamp: stamp, checkedAt: .now, settled: false)
        let activity = try? Activity.request(
            attributes: MoneyActivityAttributes(title: title, thingID: id),
            // `staleDate` is the honesty rail in ActivityKit's own vocabulary:
            // past it, iOS greys the activity out by itself. A record we have
            // not re-read in six hours is one we can no longer speak for, and
            // without this the lock screen would keep stating yesterday's
            // status in today's present tense.
            content: .init(state: state, staleDate: .now + staleAfter))
        guard let activity else { return false }
        live[id] = activity
        return true
    }

    /// Six hours. Long enough that an overnight card authorization is still on
    /// the lock screen in the morning; short enough that "checked 2h ago" never
    /// silently becomes "checked two days ago" while still looking current.
    static let staleAfter: TimeInterval = 6 * 3600

    /// A sweep re-read this record and the state still stands. Moves
    /// `checkedAt` — which is the ONLY thing this call is for, and the reason
    /// it is worth making even when the stamp is unchanged: the age on screen
    /// is the claim, so leaving it stale while we do know better is the exact
    /// overclaim this feature is built to avoid.
    static func refresh(id: String, stamp: String) async {
        guard let activity = live[id] else { return }
        await activity.update(
            .init(state: .init(stamp: stamp, checkedAt: .now, settled: false),
                  staleDate: .now + staleAfter))
    }

    /// The record tore. Ends with the settled state briefly on screen.
    ///
    /// `.after` rather than `.immediate` for `ImportActivityDriver`'s reason:
    /// the last thing this activity says is the part worth reading, and
    /// dismissing at the instant of settlement means the person who came back
    /// to check finds nothing and cannot tell a settled record from an activity
    /// that never started.
    static func settle(id: String, stamp: String) async {
        guard let activity = live[id] else { return }
        live[id] = nil
        await activity.end(
            .init(state: .init(stamp: stamp, checkedAt: .now, settled: true),
                  staleDate: nil),
            dismissalPolicy: .after(.now + 8))
    }

    /// The person stopped tracking it themselves — no settled state, because
    /// nothing settled.
    static func stop(id: String) async {
        guard let activity = live[id] else { return }
        live[id] = nil
        await activity.end(nil, dismissalPolicy: .immediate)
    }

    /// Bring every tracked record up to date after a bridge sweep.
    ///
    /// **Call this after a sweep that really re-read the sources, and nowhere
    /// else.** `checkedAt` claims the app has current information about the
    /// record, so moving it because we re-read our OWN store would be the
    /// overclaim the whole feature is shaped to avoid — the background task
    /// (`WalletBackgroundRefresh.runNotifySweep`) deliberately does not drive a
    /// bridge refresh, which is exactly why it is not a caller. What covers the
    /// gap instead is `staleAfter`: iOS greys an activity out by itself once we
    /// have not genuinely checked in six hours.
    ///
    /// Every `Thing` is read BEFORE the first `await` and only values cross the
    /// suspension — the build-250 corollary, which reaches async model code
    /// that no view-layer guard can.
    static func sync(context: ModelContext) async {
        guard !live.isEmpty else { return }
        var standing: [(id: String, stamp: String, torn: Bool)] = []
        var gone: [String] = []
        for id in live.keys {
            guard let uuid = UUID(uuidString: id) else { gone.append(id); continue }
            var descriptor = FetchDescriptor<Thing>(
                predicate: #Predicate { $0.id == uuid })
            descriptor.fetchLimit = 1
            guard let thing = (try? context.fetch(descriptor))?.first,
                  thing.isLive,
                  let receipt = MoneyReceiptSource.receipt(for: thing) else {
                // The row was deleted, or stopped being a receipt at all. An
                // activity pointing at a record that no longer exists opens a
                // sheet onto nothing, so it ends rather than settles — nothing
                // settled, and saying so would be a claim we can't support.
                gone.append(id)
                continue
            }
            standing.append((id, receipt.stamp?.word ?? "",
                             receipt.finality == .torn))
        }
        for id in gone { await stop(id: id) }
        for row in standing {
            if row.torn {
                await settle(id: row.id, stamp: row.stamp)
            } else {
                await refresh(id: row.id, stamp: row.stamp)
            }
        }
    }
    #else
    static func isTracking(_ id: String) -> Bool { false }
    static var available: Bool { false }
    @discardableResult
    static func start(id: String, title: String, stamp: String) -> Bool { false }
    static let staleAfter: TimeInterval = 6 * 3600
    static func refresh(id: String, stamp: String) async {}
    static func settle(id: String, stamp: String) async {}
    static func stop(id: String) async {}
    static func sync(context: ModelContext) async {}
    #endif
}
