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
/// One-shot: after the first signal, both observers unregister.
enum CloudSyncGuard {
    static func begin() {
        // Two observers on potentially different queues (the mirror's setup
        // queue and the main thread background hop), racing to clear once —
        // funnel both onto main so the token array is only ever touched
        // there.
        let center = NotificationCenter.default
        var tokens: [NSObjectProtocol] = []
        let clear: @Sendable () -> Void = {
            DispatchQueue.main.async {
                UserDefaults.standard.removeObject(forKey: SharedStore.cloudAttemptMarkerKey)
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
    }
}
