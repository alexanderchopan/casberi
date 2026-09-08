import Foundation

/// The row window a long list draws through — `windowRowTarget` rows, plus one
/// target per "Show older" tap, and a flag saying whether anything was held
/// back.
///
/// **A LIST'S ROW COUNT IS A COST A SHEET DRAG PAYS, AND BUILD 539 DIED OF IT
/// (crash report 2026-09-08, prd §657).** A `0x8BADF00D` scene-update watchdog
/// — "exhausted real (wall clock) time allowance of 10.00 seconds",
/// `ProcessVisibility: Background`, 10.358s of application CPU at **16%**. The
/// faulting stack is a finger:
///
///     -[_UISheetInteraction handlePan:]
///       → sheetInteraction:didChangeOffset:  → -[_UISheetLayoutInfo _layout]
///       → -[UIView layoutBelowIfNeeded]      → _UIHostingView.layoutSubviews
///       → UICollectionViewListCoordinatorBase.update(…performDiff:)
///       → ListCoreDataSource.visitContent(atRow:)
///       → ListDiffable.rowIndex(at:) → sectionIndex(atOffset:)
///       → BidirectionalCollection.index(_:offsetBy:) over ShadowSectionCollection
///
/// UIKit lays a sheet's hosting view out SYNCHRONOUSLY on every offset change,
/// so an interactive drag — dismissing one included — re-runs the whole
/// `List` content update. SwiftUI resolves each row's index by a LINEAR WALK of
/// its shadow collection, so that update is O(rows × sections): fine at thirty
/// rows, seconds of CPU at thousands. Backgrounded, the app gets ~16% of a core
/// — the same six-fold throttle §614 measured — so a render costing a second
/// and a half of CPU exceeds ten seconds of wall clock and the watchdog kills
/// it.
///
/// The lesson is `PrivacyCover`'s, one surface over: making the render faster
/// raises the row count at which this happens and does not change that it
/// happens. **Not drawing the rows does.**
///
/// Foundation-only on purpose, so `scripts/row-window-selftest.sh` compiles it
/// WHOLE AND UNMODIFIED. `FeedScreen` keeps its own `windowed(_:)` — that one
/// windows GROUPS, with a day's worth of rules this has no business knowing
/// (whole days wherever they fit, a single day bigger than the budget
/// truncated rather than allowed to unbound the room). This is the flat case:
/// one list, no sections to keep whole.
enum RowWindow {
    /// One screenful, and the feed's own number (`FeedScreen.windowRowTarget`).
    static let rowTarget = 30

    /// Linear, deliberately — the feed's ruling (user, 2026-08-01: "most people
    /// won't be scrolling back to previous history"). Geometric growth only
    /// helps somebody walking a long room to its beginning, which is the rare
    /// case, and the common case is what the bound is for.
    static func budget(steps: Int) -> Int { rowTarget * (max(0, steps) + 1) }

    /// The rows to draw, and whether any were held back. `more` is false when
    /// the list exactly fills the budget: there is nothing behind it, so an
    /// opener would be a control that reveals nothing (design law, §83).
    static func slice<T>(_ rows: [T], steps: Int) -> (shown: [T], more: Bool) {
        let budget = budget(steps: steps)
        guard rows.count > budget else { return (rows, false) }
        return (Array(rows.prefix(budget)), true)
    }
}
