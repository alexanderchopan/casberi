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
    /// The mirror's three event types, kept APART (prd §607).
    ///
    /// `lastSuccessDate` above is stamped by ANY succeeded event — and
    /// `.setup` is an event. So a launch that connected to CloudKit and then
    /// exchanged nothing at all stamped a fresh success, and the Data tray
    /// read "Synced just now" over a mirror that had never carried one row in
    /// either direction. An `.export` does the same one direction over: it
    /// says this device SENT, which is not the question anybody opens that
    /// tray to ask. The question is "is the thing I saved on my phone here",
    /// and only `.import` answers it.
    ///
    /// Kept as three keys rather than one because they fail independently and
    /// for different reasons: export works and import doesn't when the other
    /// device never pushed; import works and export doesn't when this device's
    /// schema is ahead of Production (the CloudKit deploy class this repo has
    /// a rule for). A single date cannot distinguish those, and the whole
    /// point of this file is that the tray stops guessing.
    private static let lastImportDateKey = "icloud.sync.lastImportDate"
    private static let lastExportDateKey = "icloud.sync.lastExportDate"
    private static let lastSetupDateKey = "icloud.sync.lastSetupDate"

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
            // …and again under the event's OWN type, so the tray can say which
            // direction actually moved (prd §607). A `switch` with no default:
            // a fourth event type Apple adds must be a compile error here
            // rather than silently stamping nothing, because the failure is a
            // tray that goes quiet with no way to tell it from a dead mirror.
            switch event.type {
            case .setup:  defaults.set(Date.now, forKey: lastSetupDateKey)
            case .import: defaults.set(Date.now, forKey: lastImportDateKey)
            case .export: defaults.set(Date.now, forKey: lastExportDateKey)
            @unknown default: break
            }
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
    /// The last time a row arrived FROM iCloud — the one that answers "is my
    /// other device's stuff here".
    static var lastImportDate: Date? { UserDefaults.standard.object(forKey: lastImportDateKey) as? Date }
    /// The last time this device SENT. Reported separately rather than merged:
    /// a mirror that only exports is a real and nameable state (nothing has
    /// been saved elsewhere yet), and merging it into one figure states that
    /// as an exchange that happened.
    static var lastExportDate: Date? { UserDefaults.standard.object(forKey: lastExportDateKey) as? Date }
    /// The mirror connected. Proves the account and the container are reachable
    /// and NOTHING about whether a row ever moved — which is exactly why it is
    /// no longer allowed to be the thing the tray shows.
    static var lastSetupDate: Date? { UserDefaults.standard.object(forKey: lastSetupDateKey) as? Date }

    /// Whether the mirror is failing RIGHT NOW, rather than having failed at
    /// some point. An error only counts while nothing has succeeded since —
    /// any succeeded event clears it, which is the one job `lastSuccessDate`
    /// still has and the reason it survives §607's split.
    static var hasLiveError: Bool {
        guard let errorDate = lastErrorDate else { return false }
        guard let successDate = lastSuccessDate else { return true }
        return errorDate > successDate
    }

    /// What the Data tray says. The DECISION lives in `CloudSyncReading`
    /// (Foundation-only, compiled whole by `scripts/cloud-sync-selftest.sh`);
    /// this only gathers what this process happens to know, so the sheet and
    /// the probe can never disagree and the ordering can be proven off-device.
    static func line(engaged: Bool, wantsSync: Bool,
                     deviceName: String, macIdiom: Bool) -> String {
        CloudSyncReading.line(
            state: CloudSyncReading.State(
                wantsSync: wantsSync, engaged: engaged,
                hasLiveError: hasLiveError,
                lastImport: lastImportDate, lastExport: lastExportDate,
                lastSetup: lastSetupDate),
            deviceName: deviceName, macIdiom: macIdiom)
    }

    /// Delete-everything already purges the CloudKit zone; the remembered
    /// status should go with it rather than showing a stale error or a stale
    /// success timestamp for a corpus that no longer exists.
    static func reset() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: lastErrorKey)
        defaults.removeObject(forKey: lastErrorDateKey)
        defaults.removeObject(forKey: lastSuccessDateKey)
        defaults.removeObject(forKey: lastImportDateKey)
        defaults.removeObject(forKey: lastExportDateKey)
        defaults.removeObject(forKey: lastSetupDateKey)
    }
}
