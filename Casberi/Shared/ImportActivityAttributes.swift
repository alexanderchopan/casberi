import Foundation
#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit

/// A bulk import, on the lock screen (2026-08-14, prd §382).
///
/// The app's longest single operation had no presence outside the screen that
/// started it. §307/§309 raised the import caps by more than an order of
/// magnitude — 10,000 posts, 5,000 likes — and §310 made those land in chunks
/// so the app keeps breathing, which together mean a real archive takes long
/// enough that a person will leave and come back. Until this, leaving meant
/// having no idea whether it finished.
///
/// THE COUNT IS WHAT IS ALREADY SAVED, and that is the whole reason this can be
/// honest. A Live Activity implies "still happening", and an import running on
/// the main actor is not guaranteed to survive backgrounding — so a frozen
/// progress bar would be a claim we can't keep. But `ImportCommit`'s own
/// doctrine is that A CHUNK IS A COMMIT: every number this activity has ever
/// shown describes rows that are really in the store and will still be there if
/// the run dies. So a display that stops moving is not lying, it is reporting
/// the last thing that actually happened — which is exactly what the copy says
/// ("9,000 saved"), never "9,000 of 12,000 in progress".
struct ImportActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Rows committed so far. Never an estimate.
        var landed: Int
        /// How many were built for this run. Zero means unknown, and the view
        /// shows no bar at all rather than a bar against a denominator it made
        /// up.
        var total: Int
        var finished: Bool
    }

    /// The app the archive came from ("X", "Instagram") — the same string its
    /// receipt lands under, so the activity and the row it produces agree.
    var source: String
}
#endif
