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
/// **THE CONSENT RECORD BEHIND THE UNLOCK NOTIFICATION (2026-08-29, prd §522).**
///
/// §473's ruling is that tracking a timelock is a CONTROL and never automatic,
/// and the notification inherits it whole: the only accounts that may reach a
/// lock screen when their delay ends are the ones somebody turned tracking on
/// for. That fact lived in `VibenetUnlockActivityDriver.live`, an in-memory
/// dictionary — so it died with the process, and the sweep that runs on the
/// next foreground had no way to know what had been consented to.
///
/// Foundation-only and OUTSIDE the `#if`, deliberately: the book is the record
/// of a decision, not a piece of ActivityKit, and a Mac Catalyst build that
/// cannot show a Live Activity must still be able to forget one.
///
/// **Small by construction** — at most one entry per watched account, capped at
/// five by `VibenetWatch` itself, and pruned once an entry can no longer be
/// news.
enum VibenetUnlockBook {
    struct Entry: Codable, Equatable, Sendable {
        var address: String
        var name: String
        var unlocksAt: Date
    }

    private static let key = "vibenet.unlock.tracked.v1"

    /// Addresses are keyed LOWERCASED, the rule every hex compare in this
    /// feature keeps: an RPC's casing is not a promise, and an entry that
    /// cannot be found again is one nothing can forget.
    private static func normalize(_ address: String) -> String { address.lowercased() }

    static func all() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        return saved
    }

    private static func write(_ entries: [Entry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func isTracked(_ address: String) -> Bool {
        let want = normalize(address)
        return all().contains { normalize($0.address) == want }
    }

    /// Replaces any entry for the same address — a second unlock started after
    /// a re-lock is a new instant, and two entries for one account would
    /// announce it twice.
    static func record(address: String, name: String, unlocksAt: Date) {
        let want = normalize(address)
        var entries = all().filter { normalize($0.address) != want }
        entries.append(Entry(address: address, name: name, unlocksAt: unlocksAt))
        write(entries)
    }

    static func forget(address: String) {
        let want = normalize(address)
        write(all().filter { normalize($0.address) != want })
    }

    /// Forget an entry ONLY while its delay is still running.
    ///
    /// **The distinction `reconcile` cannot make on its own, and the trap it
    /// would otherwise be.** A room read stops reporting an account as
    /// "unlocking" for two opposite reasons: it was RE-LOCKED, in which case no
    /// window will open and the consent is moot — or it FINISHED, which is the
    /// exact moment the notification exists for. Forgetting on both would let a
    /// reconcile that happens to run before the notify sweep silently delete
    /// the one thing that pass was going to announce, on the pass where it
    /// mattered, with nothing anywhere to say so.
    static func forgetIfPending(address: String, now: Date = .now) {
        let want = normalize(address)
        guard all().contains(where: { normalize($0.address) == want && $0.unlocksAt > now })
        else { return }
        forget(address: address)
    }

    /// Drop what can never be news again — an unlock further past than
    /// `NotifyDevnet.newsWindow`, which is the point the plan itself starts
    /// refusing. Called by the sweep AFTER it has composed, so an entry is
    /// never pruned in the same pass that would have announced it.
    static func prune(now: Date = .now) {
        write(all().filter { now.timeIntervalSince($0.unlocksAt) <= NotifyDevnet.newsWindow })
    }
}

@MainActor
enum VibenetUnlockActivityDriver {

    #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
    private static var live: [String: Activity<VibenetUnlockActivityAttributes>] = [:]

    /// Whether this account is already tracked — what the control reads to
    /// decide whether it offers to start or to stop, so it is never a button
    /// that does nothing (§83).
    static func isTracking(_ address: String) -> Bool {
        rehydrate()
        return live[key(address)] != nil
    }

    /// **PICK UP ACTIVITIES THAT OUTLIVED THE PROCESS (prd §522).**
    ///
    /// A Live Activity survives the app being killed; `live` did not, so after
    /// a relaunch every tracked account read as untracked — the control offered
    /// "Track" for a countdown already on the lock screen, and taking it
    /// requested a SECOND activity for the same account, while the first had no
    /// handle left to end it with. Once per process, and free where there is
    /// nothing to pick up.
    private static var rehydrated = false
    private static func rehydrate() {
        guard !rehydrated else { return }
        rehydrated = true
        for activity in Activity<VibenetUnlockActivityAttributes>.activities {
            live[key(activity.attributes.address)] = activity
        }
    }

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
        rehydrate()
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
        // The BOOK is written only on a real start (prd §522) — it is the
        // record of a consent that was actually given, so a request iOS refused
        // must never leave one behind. It outlives the process, which the
        // dictionary above does not.
        VibenetUnlockBook.record(address: address, name: name, unlocksAt: unlocksAt)
        return true
    }

    /// The delay ended, or the account stopped unlocking. Ends the activity
    /// rather than leaving it to expire, so a RE-LOCKED account does not go on
    /// counting down to a moment that stopped meaning anything.
    ///
    /// Called by the person (the control's off state) and by the room read,
    /// which is why it must be safe to call for an address nobody tracked.
    /// `withdrawingConsent` is true for the PERSON's tap and false for a room
    /// read — see `VibenetUnlockBook.forgetIfPending` for why those are not the
    /// same act.
    static func finish(address: String, withdrawingConsent: Bool = true) {
        rehydrate()
        // Forgotten FIRST, before any early return: the book records consent,
        // and consent is withdrawn whether or not there is still an activity
        // handle to end. Returning early on a missing handle would leave a
        // lock-screen notification armed for an account somebody has just
        // stopped tracking.
        if withdrawingConsent {
            VibenetUnlockBook.forget(address: address)
        } else {
            VibenetUnlockBook.forgetIfPending(address: address)
        }
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
            // NOT a withdrawal of consent (prd §522): a room that has stopped
            // calling an account "unlocking" may be describing a re-lock or a
            // finished delay, and only the person's own tap means "stop telling
            // me". NOTE this function has no caller today; wiring it with the
            // default would silently disable the unlock notification.
            finish(address: address, withdrawingConsent: false)
        }
    }

    /// Addresses are compared lowercased for the reason every hex compare in
    /// this feature is: an RPC's casing is not a promise, and a tracked
    /// account that cannot be found again is an activity nothing can end.
    private static func key(_ address: String) -> String { address.lowercased() }

    #else
    // The book is Foundation-only and reads the same on every platform, so a
    // Catalyst build still answers honestly about a consent given on a phone.
    // Nothing can start one here (`available` is false), so in practice it is
    // empty — which is the right answer rather than a hardcoded one.
    static func isTracking(_ address: String) -> Bool { VibenetUnlockBook.isTracked(address) }
    static var available: Bool { false }
    @discardableResult
    static func start(address: String, name: String, unlocksAt: Date) -> Bool { false }
    static func finish(address: String, withdrawingConsent: Bool = true) {
        if withdrawingConsent { VibenetUnlockBook.forget(address: address) }
        else { VibenetUnlockBook.forgetIfPending(address: address) }
    }
    static func reconcile(stillUnlocking: Set<String>, reached: Set<String>) {}
    #endif
}
