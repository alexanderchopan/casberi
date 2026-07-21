import Foundation
import SwiftData

/// The one store, shared between the app and the share extension through the
/// app group — capture routes here from every surface (S3), and the corpus
/// stays on device (goal 6). Falls back to the local default store when the
/// group container is unavailable (e.g. unsigned builds), so the app never
/// fails to launch over an entitlement.
enum SharedStore {
    static let appGroup = "group.com.casberi.app"
    /// The CloudKit container the synced store mirrors into (M1). Matches the
    /// iCloud capability added in Xcode; until that capability exists, opening a
    /// CloudKit-backed container throws and we fall back to a local store.
    static let cloudContainerID = "iCloud.com.casberi.app"

    /// The person's sync choice (the Data tray toggle). Off by default — the
    /// corpus stays on device until they opt in AND the capability is present.
    static var syncEnabled: Bool {
        UserDefaults.standard.bool(forKey: "icloud.sync")
    }

    /// The build's CloudKit readiness — the ship gate. CloudKit mirroring sets
    /// up on a background queue and *traps* (doesn't throw) when the iCloud
    /// container entitlement is absent, so `try?` can't guard it, and iOS has no
    /// reliable runtime entitlement read. So this is an explicit switch:
    ///
    ///   FLIP TO `true` ONCE the iCloud + CloudKit capability is added in Xcode
    ///   (target → Signing & Capabilities → + Capability → iCloud → CloudKit,
    ///   container `iCloud.com.casberi.app`). Until then it stays `false` and
    ///   the corpus is local no matter what the toggle says — no crash.
    ///
    /// Real bytes move only when BOTH this is true AND the person opted in.
    /// FLIPPED TRUE 2026-07-06 — the iCloud + CloudKit capability is now in the
    /// build (container `iCloud.com.casberi.app`, verified in Casberi.entitlements).
    static let cloudKitReady = true

    /// Whether THIS process is actually mirroring to CloudKit — set when the
    /// container engages it. The container binds once at launch, so a toggle
    /// flipped mid-session isn't live until the next launch; the Data sheet
    /// reads this to say so honestly.
    private(set) static var cloudSyncActive = false

    static func container() throws -> ModelContainer {
        // Engage CloudKit only when the person opted in AND the build carries
        // the capability. Missing either, stay local — the toggle is honest
        // final UI, and this is the ship gate that keeps a live toggle from
        // crashing (or lying) before the engine exists.
        if syncEnabled, cloudKitReady {
            let made = try make(cloudKit: .private(cloudContainerID))
            cloudSyncActive = true
            return made
        }
        return try make(cloudKit: .none)
    }

    /// The widget and share extension open the SAME store file but never
    /// engage CloudKit mirroring — one process syncs (the app); a second
    /// mirror on the same store fights the first. Extension writes reach
    /// iCloud the next time the app opens.
    static func extensionContainer() throws -> ModelContainer {
        try make(cloudKit: .none)
    }

    /// Non-nil once the app has fallen back from the real corpus (a bad open
    /// that survived retries). RootShell flashes this once at launch instead
    /// of the app crash-looping — see `CasberiApp.init`'s degrade ladder.
    /// Written before any SwiftUI view exists, so it's a static, not state.
    nonisolated(unsafe) private(set) static var degradeReason: String?

    /// The open-failure recovery ladder (S0: the app must always launch).
    /// A `ModelContainer(for:)` failure almost always means the on-disk store
    /// no longer matches the compiled schema — most commonly a non-lightweight
    /// `Thing` change shipped without a new `ThingSchemaVN` stage (see
    /// `ThingSchemaVersioning.swift`). Rather than `fatalError` (a crash-loop
    /// for every install until a fix ships), retry with CloudKit off — a
    /// CloudKit-specific mirroring fault shouldn't take down a local-only
    /// open — and if even that fails, open an ephemeral in-memory store so
    /// the app still launches (empty, but alive); the real store file is
    /// left untouched on disk for a future fixed build to recover.
    static func containerWithFallback() -> ModelContainer {
        do {
            return try container()
        } catch let primaryError {
            NSLog("[Casberi] primary store open failed, retrying without CloudKit: \(primaryError)")
            do {
                let made = try make(cloudKit: .none)
                degradeReason = "iCloud sync couldn't open — your things are here, but sync is off until the next update."
                return made
            } catch let localError {
                NSLog("[Casberi] local fallback store open ALSO failed, using an ephemeral store: \(localError)")
                degradeReason = "Your things couldn't load this launch — nothing was lost, but they won't show until the next update."
                return ephemeralContainer()
            }
        }
    }

    private static func ephemeralContainer() -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        // In-memory only, no disk/CloudKit/group container involved — this
        // is the guaranteed-success leaf of the ladder above, so force-try
        // is the honest signature (nothing left to fall back to).
        return try! ModelContainer(for: Thing.self, configurations: config)
    }

    private static func make(cloudKit: ModelConfiguration.CloudKitDatabase) throws -> ModelContainer {
        let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        let config = groupURL != nil
            ? ModelConfiguration(groupContainer: .identifier(appGroup), cloudKitDatabase: cloudKit)
            : ModelConfiguration(cloudKitDatabase: cloudKit)
        return try ModelContainer(for: Thing.self, migrationPlan: ThingMigrationPlan.self, configurations: config)
    }
}
