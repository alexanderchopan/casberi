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

    /// UserDefaults key: set to `true` the instant we ask SwiftData for a
    /// CloudKit-backed container; cleared once we have proof this launch
    /// survived setup (see `CloudSyncGuard`). If it's still `true` at the top
    /// of the NEXT launch, the previous launch's CloudKit setup TRAPPED (a
    /// mirroring queue can `os_crash` from Apple's own code — see
    /// `Casberi-2026-07-24-233929.ips`, `PFCloudKitSetupAssistant` on
    /// `com.apple.coredata.cloudkit.queue`). `containerWithFallback`'s `try?`
    /// can't catch that — it happens after `container()` returns — so this
    /// out-of-band marker is the only way to break the crash-loop.
    static let cloudAttemptMarkerKey = "icloud.cloudAttemptInFlight"

    /// Consecutive-trap counter (RULE, 2026-07-27) — how many launches in a
    /// row stamped the marker above and never cleared it. `CloudSyncGuard`
    /// resets this to 0 the moment a launch actually survives, so it only
    /// ever counts an unbroken streak. Read alongside `cloudAttemptMarkerKey`
    /// in `containerWithFallback`.
    static let cloudTrapStreakKey = "icloud.cloudTrapStreak"

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
            // Stamp the in-flight marker BEFORE handing SwiftData the
            // CloudKit descriptor: the mirror's own setup queue can trap
            // inside Apple's code, and a marker written after that point
            // would never land. `CloudSyncGuard` (app-only) clears it on
            // any proof-of-survival (setup event, or clean background).
            UserDefaults.standard.set(true, forKey: cloudAttemptMarkerKey)
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
        // Never CREATE the store from an extension process (2026-08-01).
        // Opening a ModelContainer creates the file when it's missing, and a
        // widget timeline refresh can run in the window between an app update
        // landing and the app's own first launch. Every iOS build shipped
        // before 2026-08-01 lacked the app-group entitlement (the unsigned-
        // archive pipeline stripped it — see scripts/testflight.sh), so the
        // first entitled launch must ADOPT the legacy sandbox store into the
        // group container (`adoptLegacyStoreIfNeeded`); an extension-created
        // empty store in that window would read as "the group store already
        // exists" and the whole corpus would appear wiped. Every caller
        // `try?`s and degrades (widget placeholder, share reports failure),
        // so declining is honest — and the store exists on every install the
        // moment the app has launched once.
        guard let groupURL = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: appGroup),
              FileManager.default.fileExists(atPath: groupStoreURL(in: groupURL).path)
        else { throw StoreUnready() }
        return try make(cloudKit: .none)
    }

    /// Thrown by `extensionContainer` when the app hasn't created the shared
    /// store yet — see the comment there.
    struct StoreUnready: Error {}

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
        #if DEBUG
        // Harness hook (`-storeScratch YES`, scripts/verify-mac.sh): open an
        // on-disk store at a throwaway per-process temp path instead of the
        // real group container, CloudKit off. On the Mac there is no
        // simulator sandbox — a directly-launched DEBUG build shares the
        // REAL container with the person's installed app, so a probe run
        // whose schema is ahead of the installed build would forward-migrate
        // the daily driver's store out from under it. Scratch keeps the
        // harness hermetic: a real disk open (unlike in-memory, so the
        // container-open launch span stays measured), zero reads or writes
        // against the person's corpus, no CloudKit attempt, no trap-marker
        // bookkeeping (a scratch launch is not evidence about the mirror).
        // DEBUG-only and argument-domain-only — unreachable in any shipped
        // build.
        if UserDefaults.standard.bool(forKey: "storeScratch") {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("casberi-scratch-\(ProcessInfo.processInfo.processIdentifier)")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let config = ModelConfiguration(url: dir.appendingPathComponent("scratch.store"),
                                            cloudKitDatabase: .none)
            if let made = try? ModelContainer(for: Thing.self,
                                              migrationPlan: ThingMigrationPlan.self,
                                              configurations: config) {
                NSLog("[Casberi] storeScratch: opened %@", dir.path)
                return made
            }
            NSLog("[Casberi] storeScratch: on-disk open failed, using in-memory scratch")
            return ephemeralContainer()
        }
        #endif
        // If the last launch stamped the CloudKit attempt marker and never
        // cleared it, the mirror trapped mid-setup. RULE (2026-07-27, was a
        // single-launch trip before this): only auto-flip sync off after
        // TWO CONSECUTIVE trapped launches — an ordinary force-quit, or any
        // of the unrelated SwiftData `ForEach` crashes (CLAUDE.md's "never
        // key a ForEach on a derived array" class, builds 137/142/150) also
        // leaves this marker set with the mirror never at fault, and a
        // one-strike rule was silently disabling sync for users who hit
        // those, with no way to know it wasn't their choice. Two in a row
        // is still fast (worst case: the very next launch), but rules out a
        // single unrelated crash. `CloudSyncGuard` resets the streak to 0
        // the moment any later launch actually survives. Written to
        // `UserDefaults` directly so the AppStorage-backed toggle picks it
        // up on next read.
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: cloudAttemptMarkerKey) {
            let streak = defaults.integer(forKey: cloudTrapStreakKey) + 1
            defaults.set(streak, forKey: cloudTrapStreakKey)
            NSLog("[Casberi] previous launch trapped in CloudKit setup (streak \(streak))")
            if streak >= 2, defaults.bool(forKey: "icloud.sync") {
                NSLog("[Casberi] two consecutive trapped launches — turning sync off")
                defaults.set(false, forKey: "icloud.sync")
                degradeReason = "iCloud sync failed and was turned off — your things are safe here. Turn it back on in Data."
            }
        } else {
            // A launch that never even attempted CloudKit (sync off, or the
            // marker already clear) can't be part of a trap streak — reset
            // so a stale count from long ago doesn't disable sync the very
            // next time it's turned back on.
            defaults.set(0, forKey: cloudTrapStreakKey)
        }
        defaults.removeObject(forKey: cloudAttemptMarkerKey)
        do {
            return try container()
        } catch let primaryError {
            NSLog("[Casberi] primary store open failed, retrying without CloudKit: \(primaryError)")
            do {
                let made = try make(cloudKit: .none)
                degradeReason = "iCloud sync is off — your things are here."
                return made
            } catch let localError {
                NSLog("[Casberi] local fallback store open ALSO failed, using an ephemeral store: \(localError)")
                degradeReason = "Couldn't load your things — nothing was lost. Try relaunching."
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
        if let groupURL { adoptLegacyStoreIfNeeded(into: groupURL) }
        let config = groupURL != nil
            ? ModelConfiguration(groupContainer: .identifier(appGroup), cloudKitDatabase: cloudKit)
            : ModelConfiguration(cloudKitDatabase: cloudKit)
        return try ModelContainer(for: Thing.self, migrationPlan: ThingMigrationPlan.self, configurations: config)
    }

    /// Where SwiftData puts the store inside the group container (verified
    /// against a real container: `Library/Application Support/default.store`).
    private static func groupStoreURL(in groupURL: URL) -> URL {
        groupURL.appendingPathComponent("Library/Application Support/default.store")
    }

    /// One-time upgrade path (2026-08-01). Every iOS build shipped before this
    /// date carried NO app-group entitlement — the unsigned-archive ship
    /// pipeline stripped every entitlement from every TestFlight build (see
    /// scripts/testflight.sh) — so on real devices `make`'s nil-group fallback
    /// has been putting the corpus in the app sandbox's own Application
    /// Support all along. The first build with the entitlement restored
    /// suddenly sees a group container and would open a brand-new EMPTY store
    /// there: the whole corpus would appear wiped while sitting untouched one
    /// directory over. So before the group store first exists, copy the
    /// legacy store in — all four pieces: the store, -shm, -wal (committed
    /// rows not yet checkpointed live in the -wal), and `.default_SUPPORT`
    /// (externally-stored blobs — voice-note audio). COPY, not move: the
    /// sandbox originals stay behind as a backup. Idempotent by the group
    /// store's own existence — once it's there (adopted or freshly created)
    /// this never runs again; a missing -shm/-wal is a checkpointed store,
    /// not an error. On a copy failure every piece is removed so the NEXT
    /// launch retries, rather than this one opening a half-copied corpus.
    /// From an extension process the legacy path is the extension's OWN empty
    /// sandbox, so this is a structural no-op there.
    private static func adoptLegacyStoreIfNeeded(into groupURL: URL) {
        let fm = FileManager.default
        let groupSupport = groupURL.appendingPathComponent("Library/Application Support",
                                                           isDirectory: true)
        guard !fm.fileExists(atPath: groupStoreURL(in: groupURL).path),
              let legacySupport = fm.urls(for: .applicationSupportDirectory,
                                          in: .userDomainMask).first,
              fm.fileExists(atPath: legacySupport.appendingPathComponent("default.store").path)
        else { return }
        try? fm.createDirectory(at: groupSupport, withIntermediateDirectories: true)
        let pieces = ["default.store", "default.store-shm", "default.store-wal",
                      ".default_SUPPORT"]
        do {
            for name in pieces {
                let src = legacySupport.appendingPathComponent(name)
                guard fm.fileExists(atPath: src.path) else { continue }
                try fm.copyItem(at: src, to: groupSupport.appendingPathComponent(name))
            }
            NSLog("[Casberi] adopted the legacy sandbox store into the app-group container")
        } catch {
            NSLog("[Casberi] legacy store adoption failed (will retry next launch): \(error)")
            for name in pieces {
                try? fm.removeItem(at: groupSupport.appendingPathComponent(name))
            }
        }
    }
}
