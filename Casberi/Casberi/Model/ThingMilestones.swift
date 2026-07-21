import Foundation

/// A quiet count-up, not a celebration screen (prd §36v's ruling, generalized
/// per-source 2026-07-21): crossing a round number of things from ONE source
/// flashes "N things banked from Source." once per threshold, ever. No
/// streaks, no goals — a fact the corpus can prove, said once.
enum ThingMilestones {
    private static let thresholds = [50, 100, 500, 1000, 5000, 10000]

    /// `count` is that source's OWN total, not the whole corpus. Fires at
    /// most one flash per call — the highest threshold just crossed.
    @MainActor
    static func check(source: String, count: Int, chrome: ShellChrome) {
        guard let hit = thresholds.last(where: { count >= $0 }) else { return }
        let key = "milestone.\(source).\(hit)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        chrome.flash(String(localized: "\(hit.formatted()) things banked from \(source)."))
    }
}
