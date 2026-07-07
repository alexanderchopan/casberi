import Foundation

/// Whether this install simulates a brand-new user. Launch once with
/// `-fresh YES` and the mode sticks across relaunches (like a real new user's
/// empty install) until `-fresh NO` or reinstall. Release builds never seed
/// demo data regardless.
enum DemoState {
    static let isFresh: Bool = {
        let defaults = UserDefaults.standard
        // Launch arg present this run → adopt and persist it.
        if defaults.object(forKey: "fresh") != nil {
            let value = defaults.bool(forKey: "fresh")
            defaults.set(value, forKey: "fresh.sticky")
            return value
        }
        return defaults.bool(forKey: "fresh.sticky")
    }()

    /// True only when `-fresh YES` was passed on THIS launch — used to re-run
    /// first-launch behavior (onboarding) exactly once per explicit request.
    static var freshRequestedThisLaunch: Bool {
        UserDefaults.standard.object(forKey: "fresh") != nil
            && UserDefaults.standard.bool(forKey: "fresh")
    }

    /// Demo data seeds only in debug builds, never in fresh mode — and
    /// never on an install that went through onboarding (2026-07-07: the dev
    /// corpus was leaking into hand-tested onboarding runs, where its fake
    /// approvals read as real). The decision is made ONCE, at first launch:
    /// dev flows launch with `-onboarded YES` and keep the corpus; anything
    /// that starts at the Connect screen stays corpus-free forever.
    static var seedsDemoData: Bool {
        #if DEBUG
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "demo.corpusAllowed") == nil {
            defaults.set(defaults.bool(forKey: "onboarded"), forKey: "demo.corpusAllowed")
        }
        return !isFresh && defaults.bool(forKey: "demo.corpusAllowed")
        #else
        return false
        #endif
    }
}
