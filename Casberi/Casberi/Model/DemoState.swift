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

    /// Demo data seeds only in debug builds, and never in fresh mode.
    static var seedsDemoData: Bool {
        #if DEBUG
        return !isFresh
        #else
        return false
        #endif
    }
}
