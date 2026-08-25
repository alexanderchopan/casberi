import Foundation
#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit
#endif

/// Starts and ends the timelock's Live Activity (prd §473).
///
/// `MoneyActivityDriver`'s shape exactly — the whole ActivityKit surface
/// behind one `#if`, empty bodies on Mac Catalyst, and no permission spent
/// (Live Activities are a Settings switch, not a prompt, so none of §306's
/// notification rationing applies).
///
/// **A CONTROL, NEVER AUTOMATIC.** `ImportActivityDriver` starts itself
/// because an import IS something the person just did; an unlock delay is
/// something that happened on the chain, possibly to an account they merely
/// watch and do not own. Putting that on somebody's lock screen because we
/// noticed it would be spending the most personal surface the OS has on a
/// devnet account nobody asked to be interrupted about. So the account detail
/// offers it and this refuses to start otherwise — `MoneyActivityDriver`'s own
/// precedent, which is offered from the receipt rather than fired by the
/// sweep.
///
/// **KEYED BY ADDRESS**, so the sweep can blindly offer every account it
/// re-read without knowing which ones anybody chose to track: `start` refuses
/// a second activity for an address that already has one, and `finish` is a
/// no-op for an address that doesn't.
@MainActor
enum VibenetUnlockActivityDriver {

    #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
    private static var live: [String: Activity<VibenetUnlockActivityAttributes>] = [:]

    /// Whether this account is already tracked — what the control reads to
    /// decide whether it offers to start or to stop, so it is never a button
    /// that does nothing (§83).
    static func isTracking(_ address: String) -> Bool { live[key(address)] != nil }

    static var available: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// Begin tracking a running delay.
    ///
    /// Returns false when nothing started, so the caller can say so rather
    /// than leaving a control that looks like it worked. The commonest false
    /// is Live Activities being switched off for the app, which is not an
    /// error and not something to nag about.
    ///
    /// **An unlock already in the past never starts one.** A delay that has
    /// elapsed is not a countdown, and `Text(timerInterval:)` handed a past
    /// date renders a stopped clock at zero — an activity that arrives dead.
    @discardableResult
    static func start(address: String, name: String, unlocksAt: Date) -> Bool {
        guard available, live[key(address)] == nil, unlocksAt > .now else { return false }
        let activity = try? Activity.request(
            attributes: VibenetUnlockActivityAttributes(accountName: name, address: address),
            // `staleDate` IS the unlock instant, not an interval past it: the
            // moment the delay ends this activity has said everything it can
            // say, and iOS greying it out by itself is more honest than a
            // countdown sitting at zero waiting for the app to be opened.
            content: .init(state: .init(unlocksAt: unlocksAt, finished: false),
                           staleDate: unlocksAt))
        guard let activity else { return false }
        live[key(address)] = activity
        return true
    }

    /// The delay ended, or the account stopped unlocking. Ends the activity
    /// rather than leaving it to expire, so a RE-LOCKED account does not go on
    /// counting down to a moment that stopped meaning anything.
    ///
    /// Called by the person (the control's off state) and by the room read,
    /// which is why it must be safe to call for an address nobody tracked.
    static func finish(address: String) {
        guard let activity = live.removeValue(forKey: key(address)) else { return }
        Task {
            await activity.end(.init(state: .init(unlocksAt: .now, finished: true),
                                     staleDate: nil),
                               dismissalPolicy: .immediate)
        }
    }

    /// Every tracked account the room no longer reports as unlocking — the
    /// sweep's one call. Takes the addresses that ARE still unlocking rather
    /// than the ones that stopped, because the caller knows the first and
    /// would have to derive the second from a list this type owns.
    ///
    /// **Never acts on an unread room.** An account whose read failed is
    /// absent from `stillUnlocking` for a reason that has nothing to do with
    /// its lock, and ending the activity on that would take the countdown off
    /// the lock screen because the network hiccuped — `ScreenshotIngest
    /// .pruneDeleted`'s rule, on a surface where the person is watching.
    static func reconcile(stillUnlocking: Set<String>, reached: Set<String>) {
        for address in live.keys where reached.contains(address) && !stillUnlocking.contains(address) {
            finish(address: address)
        }
    }

    /// Addresses are compared lowercased for the reason every hex compare in
    /// this feature is: an RPC's casing is not a promise, and a tracked
    /// account that cannot be found again is an activity nothing can end.
    private static func key(_ address: String) -> String { address.lowercased() }

    #else
    static func isTracking(_ address: String) -> Bool { false }
    static var available: Bool { false }
    @discardableResult
    static func start(address: String, name: String, unlocksAt: Date) -> Bool { false }
    static func finish(address: String) {}
    static func reconcile(stillUnlocking: Set<String>, reached: Set<String>) {}
    #endif
}
