import Foundation
import CoreData
import UIKit

/// Clears `SharedStore`'s "CloudKit attempt in flight" marker on proof of
/// survival, so a launch that actually made it past CloudKit setup doesn't
/// look like a trap on the next start. Two signals, either is enough:
///
/// 1. `NSPersistentCloudKitContainer.eventChangedNotification` — CoreData's
///    own event for the mirror lifecycle. Any `.setup` event (success OR
///    error) proves the setup queue returned instead of trapping; a normal
///    CloudKit error still leaves the process alive, so the marker isn't
///    doing its job any longer and should clear.
/// 2. `UIApplication.didEnterBackgroundNotification` — if we made it to a
///    clean background handoff, we weren't killed mid-setup.
///
/// 3. **Still running `survivalProof` seconds later (prd §607).** Both signals
///    above are EVENTS, and on a Mac neither is reliable. A Catalyst app whose
///    window stays open never backgrounds — a person can run it for days
///    without one — so signal 2 is effectively iOS-only in practice, and
///    signal 1 only ever fires while sync is switched ON and the mirror is
///    answering, which is exactly the case that needs no guard. What was left
///    was that any unrelated crash — a force-quit during a beachball, one of
///    the SwiftData `ForEach` traps this repo has a whole corollary chain
///    about — left the marker set with the mirror entirely innocent, and TWO
///    of those in a row silently switched the person's sync off.
///
///    Time is the honest signal because of what the marker actually guards:
///    `PFCloudKitSetupAssistant` traps DURING setup, on the mirror's own queue,
///    within a second or two of the container being created. A process still
///    alive twenty seconds later did not trap in setup — whatever happens to
///    it afterwards is some other bug, and counting that as CloudKit's is how
///    the two-strike rule came to need a workaround in the first place.
///
/// One-shot: after the first signal, every observer unregisters.
enum CloudSyncGuard {
    /// Well past the mirror's setup window (measured behaviour: setup begins
    /// with the container and resolves in seconds), and short enough that an
    /// ordinary session clears the marker long before it could be misread.
    static let survivalProof: Duration = .seconds(20)

    static func begin() {
        // Two observers on potentially different queues (the mirror's setup
        // queue and the main thread background hop), racing to clear once —
        // funnel both onto main so the token array is only ever touched
        // there.
        let center = NotificationCenter.default
        var tokens: [NSObjectProtocol] = []
        let clear: @Sendable () -> Void = {
            DispatchQueue.main.async {
                let defaults = UserDefaults.standard
                defaults.removeObject(forKey: SharedStore.cloudAttemptMarkerKey)
                // Proof of survival breaks any trap streak in progress — see
                // `SharedStore.containerWithFallback`'s two-in-a-row rule.
                defaults.set(0, forKey: SharedStore.cloudTrapStreakKey)
                tokens.forEach(center.removeObserver)
                tokens.removeAll()
            }
        }
        tokens.append(center.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil, queue: .main
        ) { _ in clear() })
        tokens.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main
        ) { _ in clear() })
        // Signal 3. Detached rather than hung off a view's `.task`, because
        // the marker is a fact about the PROCESS and must clear whether or not
        // anything ever mounted — a launch that shows no window at all (the
        // share extension's host, a background launch) is still a launch that
        // survived setup.
        Task { @MainActor in
            try? await Task.sleep(for: survivalProof)
            clear()
        }
    }
}
