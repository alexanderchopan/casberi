import SwiftUI
import SwiftData
import Observation

/// The iPad layer (2026-07-25). Everything here is gated on the REGULAR
/// horizontal size class and is a no-op on iPhone.
///
/// Why the size class alone is a sound gate: the app ships portrait-only on
/// iPhone (`INFOPLIST_KEY_UISupportedInterfaceOrientations`), so no iPhone
/// this app can run on ever reports regular width — the one case that would
/// otherwise blur the two (a Pro Max in landscape) can't occur. iPad in Slide
/// Over reports COMPACT and therefore correctly gets the phone shell back,
/// which is the right answer for a 320pt column.
///
/// The shape (user rulings, 2026-07-25):
///   • The source chips become a fixed vertical RAIL down the leading edge —
///     same 56pt Stories circles (2026-07-10 ruling), same avatar/catalogue
///     doors at its head, turned 90°. The horizontal strip is untouched on
///     iPhone.
///   • The feed becomes LIST + DETAIL. A row tap fills a trailing pane
///     instead of throwing a sheet over the whole screen.
///
/// Both are width-gated, not idiom-gated: an iPad mini in portrait is a real
/// iPad and still gets the rail, but 744pt cannot hold a list AND a pane, so
/// it keeps the sheet. `minWidthForPane` is where that line sits.
enum PadLayout {

    /// The source rail's width — a 56pt chip plus the air either side of it,
    /// matching the horizontal strip's own `s4` leading inset.
    static let railWidth: CGFloat = 88

    /// Below this total width the detail pane is not offered and a row tap
    /// falls back to the sheet. Chosen so the narrowest configuration that
    /// DOES get a pane (iPad Pro 13" portrait, 1032pt) still leaves the list
    /// column ~540pt — wide enough to read as a list, not a sidebar.
    static let minWidthForPane: CGFloat = 980

    /// The detail pane's width for a given total. Proportional so a 13" in
    /// landscape gives the pane real room, clamped so it can never crush the
    /// list beside it or stretch into a second full screen.
    static func paneWidth(for total: CGFloat) -> CGFloat {
        min(max(total * 0.38, 400), 560)
    }

    /// The reading column — a single file of rows or form fields (Settings,
    /// every bridge setup screen, the feed itself). This is the value
    /// `dsAdaptiveContentWidth()` uses by default. It was 900, which is why
    /// a row's title and its trailing metadata sat ~700pt apart and the app
    /// read as a phone screen stretched to fit.
    static let readingMaxWidth: CGFloat = 700

    /// The wide column — grids and catalogs, which genuinely earn the width
    /// because they answer it with more columns rather than longer rows.
    static let wideMaxWidth: CGFloat = 1040

    /// The floating agent bar's cap. A capsule holding one placeholder line
    /// has no business being 1376pt wide.
    static let agentBarMaxWidth: CGFloat = 680
}

/// The shell's two iPad columns, restated for a layer that sits OUTSIDE
/// `MainSurface`'s safe-area insets and therefore can't inherit them — today
/// that is `RootShell`'s floating agent cluster (ruling 6: the bar rides every
/// screen the app can push, so it cannot live inside the feed's own insets).
/// One type so the rail/pane arithmetic exists in exactly one place.
struct PadShellInsets {
    let isRegular: Bool
    /// Space the source rail occupies on the leading edge.
    let railInset: CGFloat
    /// Space the detail pane occupies on the trailing edge — zero whenever
    /// the shell is too narrow to render one.
    let paneInset: CGFloat

    init(regular: Bool, width: CGFloat) {
        isRegular = regular
        railInset = regular ? PadLayout.railWidth : 0
        paneInset = regular && width >= PadLayout.minWidthForPane
            ? PadLayout.paneWidth(for: width) : 0
    }
}

/// The detail pane's selection (2026-07-25) — the iPad half of "a row tap
/// opens a thing".
///
/// A singleton for the same reason `HomeRoute` is one: the row that sets it
/// (`FeedScreen`, deep inside a paged `TabView`) and the view that renders it
/// (`MainSurface`, the pager's own container) are siblings with no binding
/// between them, and threading one through every shape branch would put a
/// binding on rows that don't open things at all.
///
/// `thing` is a HELD `@Model` reference, so it falls squarely under the
/// 2026-07-24 crash class (CLAUDE.md): a foreground bridge heal or a
/// CloudKit-propagated delete can remove it while the pane is open. Every
/// read guards with `isLive`, and `pruneIfDead()` drops it rather than
/// letting the pane trap on a stored property.
@Observable
final class PadDetailSelection {
    static let shared = PadDetailSelection()
    private init() {}

    /// What the pane is showing. nil = the pane's own resting state.
    var thing: Thing?

    /// True only while the shell is ACTUALLY rendering a pane. Written by
    /// `MainSurface` from its measured width; read by every row-tap site, so
    /// no caller has to know the breakpoint or re-derive the size class.
    var paneActive = false

    /// Routes a row tap. Returns true when the pane took it — a caller that
    /// gets false must present its own sheet exactly as it always did, which
    /// is what keeps iPhone (and a narrow iPad) on the original path.
    @discardableResult
    func present(_ thing: Thing) -> Bool {
        guard paneActive, thing.isLive else { return false }
        withAnimation(DS.Motion.standard) { self.thing = thing }
        return true
    }

    func clear() {
        withAnimation(DS.Motion.standard) { thing = nil }
    }

    /// Drops a selection whose model died under us (see the class note).
    func pruneIfDead() {
        if let t = thing, !t.isLive { thing = nil }
    }
}
