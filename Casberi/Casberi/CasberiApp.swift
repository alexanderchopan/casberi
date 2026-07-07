import SwiftUI
import SwiftData

/// Casberi — one home for a person's things.
///
/// M0: project scaffold, token layer, glass tab shell + composer, demo corpus.
/// SwiftData stays on-device for M0; CloudKit sync joins in M1 (brief §11).
@main
struct CasberiApp: App {
    let container: ModelContainer

    init() {
        do {
            // The store lives in the app group so the share extension writes
            // to the same corpus (S3: every capture surface routes here).
            container = try SharedStore.container()
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
        // The demo corpus seeds only in debug, never for a fresh user (real
        // users start empty — the empty states are the product too).
        if DemoState.seedsDemoData {
            DemoCorpus.seedIfNeeded(container.mainContext)
        }
        #if DEBUG
        // An explicit -fresh YES re-runs the first launch: onboarding shows.
        if DemoState.freshRequestedThisLaunch {
            UserDefaults.standard.removeObject(forKey: "onboarded")
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootShell()
        }
        .modelContainer(container)
    }
}
