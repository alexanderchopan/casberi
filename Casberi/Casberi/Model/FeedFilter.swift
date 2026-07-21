import Foundation
import Observation

/// Feed's filter state, shared — Home's kind bar sets it (a segment tap
/// lands you in the filtered feed), Feed's chips read and write it, and the
/// casberi://feed/type/<Tag> route drives it from anywhere.
@Observable
final class FeedFilter {
    static let shared = FeedFilter()

    private static let lastSourceKey = "feed.lastSource"

    /// Persists on every change (amends §131's content-first landing): the
    /// app now opens on whichever chip you were last standing on, not always
    /// "All". Persisting on every write rather than only at background is
    /// what makes this exactly "where you left off" — whatever `source` last
    /// held when the process died IS what's on disk, no lifecycle hook
    /// needed. RootShell's launch `onAppear` no longer resets this to "All";
    /// a fresh install (no stored value yet) still opens on "All" naturally.
    var source: String {
        didSet { UserDefaults.standard.set(source, forKey: Self.lastSourceKey) }
    }
    var tag = "All"

    private init() {
        source = UserDefaults.standard.string(forKey: Self.lastSourceKey) ?? "All"
    }

    func clear() { source = "All"; tag = "All" }

    #if DEBUG
    /// `-landingChip <source>` (or `clear`) seeds the persisted landing
    /// directly, without navigating THIS launch — so a two-launch probe
    /// (seed, relaunch) verifies the next-launch landing headlessly, the
    /// same two-launch shape the empty-feed staging already uses.
    static func seedLandingFromLaunchArgs() {
        guard let spec = UserDefaults.standard.string(forKey: "landingChip"),
              !spec.isEmpty else { return }
        if spec == "clear" {
            UserDefaults.standard.removeObject(forKey: lastSourceKey)
        } else {
            UserDefaults.standard.set(spec, forKey: lastSourceKey)
        }
    }
    #endif
}
