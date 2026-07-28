import Foundation
import CoreData

/// The other half of `CloudSyncGuard`'s notification. `CloudSyncGuard`
/// listens for ONE event just to prove the launch survived, then unregisters
/// — it never looks at what the event actually says, so a broken mirror
/// (missing production schema, revoked entitlement, quota) and a working one
/// looked identical from inside the app; the Data tray's "Synced to your
/// iCloud" row was pure INTENT (the toggle's own state), never a measured
/// fact. Found 2026-07-27 diagnosing a sync outage: the production CloudKit
/// schema had never been deployed (`CD_Thing` didn't exist there), so every
/// write since M1 had been silently failing, and nothing in the app could
/// have said so.
///
/// This is a LONG-LIVED observer (never unregisters, unlike the guard's
/// one-shot) — a sync failure can arrive any time in the session (an export
/// retried after a network hiccup, a quota hit), not only at launch. State is
/// UserDefaults-backed so the Data tray can read the last real outcome even
/// on a launch where nothing has synced yet.
enum CloudSyncStatus {
    private static let lastErrorKey = "icloud.sync.lastError"
    private static let lastErrorDateKey = "icloud.sync.lastErrorDate"
    private static let lastSuccessDateKey = "icloud.sync.lastSuccessDate"

    static func begin() {
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil, queue: .main
        ) { note in
            guard let event = note.userInfo?[
                NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            ] as? NSPersistentCloudKitContainer.Event else { return }
            record(event)
        }
    }

    private static func record(_ event: NSPersistentCloudKitContainer.Event) {
        // `endDate` is nil while an event is still in flight — only a
        // finished event carries a real verdict.
        guard event.endDate != nil else { return }
        let defaults = UserDefaults.standard
        if event.succeeded {
            defaults.set(Date.now, forKey: lastSuccessDateKey)
            defaults.removeObject(forKey: lastErrorKey)
            defaults.removeObject(forKey: lastErrorDateKey)
        } else if let error = event.error {
            NSLog("[Casberi] CloudKit \(String(describing: event.type)) failed: \(error)")
            defaults.set(error.localizedDescription, forKey: lastErrorKey)
            defaults.set(Date.now, forKey: lastErrorDateKey)
        }
    }

    static var lastError: String? { UserDefaults.standard.string(forKey: lastErrorKey) }
    static var lastErrorDate: Date? { UserDefaults.standard.object(forKey: lastErrorDateKey) as? Date }
    static var lastSuccessDate: Date? { UserDefaults.standard.object(forKey: lastSuccessDateKey) as? Date }

    /// A remembered error only means something if nothing has succeeded
    /// SINCE it — CloudKit retries on its own, so a stale failure from
    /// launches ago shouldn't keep reading as a live problem once a later
    /// event has gone through clean.
    static var hasLiveError: Bool {
        guard let errorDate = lastErrorDate else { return false }
        guard let successDate = lastSuccessDate else { return true }
        return errorDate > successDate
    }

    /// Delete-everything already purges the CloudKit zone; the remembered
    /// status should go with it rather than showing a stale error or a stale
    /// success timestamp for a corpus that no longer exists.
    static func reset() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: lastErrorKey)
        defaults.removeObject(forKey: lastErrorDateKey)
        defaults.removeObject(forKey: lastSuccessDateKey)
    }
}
