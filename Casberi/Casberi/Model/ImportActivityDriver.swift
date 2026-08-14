import Foundation
#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit
#endif

/// Starts, moves and ends the import Live Activity (2026-08-14, prd §382).
///
/// Lives beside `ImportCommit` rather than inside it so the committer stays what
/// it is — a chunked save loop with no opinion about presentation — and so the
/// whole ActivityKit surface sits behind one `#if`. On Mac Catalyst every method
/// here is an empty body: Catalyst has no Live Activities and no Dynamic Island,
/// the same carve-out `VoiceRecordingActivity` already makes.
///
/// NO PERMISSION IS SPENT. Live Activities need no prompt — they are a Settings
/// switch the person either left on or turned off — which is why this can run
/// on an import without the §306 reasoning that keeps notifications rare. If
/// they are off, `start` returns nil and every later call is a no-op.
@MainActor
enum ImportActivityDriver {

    /// Below this an import finishes before anyone could look at the lock
    /// screen, and an activity that appears and vanishes reads as a glitch.
    /// A few hundred rows is the shape §310 was written for; a few thousand is
    /// where leaving the app becomes likely.
    static let floor = 1_500

    #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
    private static var live: Activity<ImportActivityAttributes>?

    static func start(source: String, total: Int) {
        guard total >= floor,
              ActivityAuthorizationInfo().areActivitiesEnabled,
              live == nil
        else { return }
        let state = ImportActivityAttributes.ContentState(landed: 0, total: total,
                                                          finished: false)
        live = try? Activity.request(
            attributes: ImportActivityAttributes(source: source),
            content: .init(state: state, staleDate: nil))
    }

    /// Called after every committed chunk. `landed` is rows really in the store
    /// — the attributes' own contract.
    static func advance(landed: Int, total: Int) async {
        guard let live else { return }
        await live.update(.init(state: .init(landed: landed, total: total,
                                             finished: false), staleDate: nil))
    }

    /// Ends with the final count still on screen for a moment.
    ///
    /// `.after` rather than `.immediate` because the last thing this activity
    /// says is the only part worth reading — how many things you now have — and
    /// dismissing at the instant of completion means the person who came back to
    /// check sees nothing and can't tell a finished import from one that never
    /// started.
    static func finish(landed: Int, total: Int) async {
        guard let activity = live else { return }
        live = nil
        await activity.end(.init(state: .init(landed: landed, total: total,
                                              finished: true), staleDate: nil),
                           dismissalPolicy: .after(.now + 8))
    }
    #else
    static func start(source: String, total: Int) {}
    static func advance(landed: Int, total: Int) async {}
    static func finish(landed: Int, total: Int) async {}
    #endif
}
