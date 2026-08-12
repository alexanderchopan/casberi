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

    /// The Mac window's floor, stated ONCE (2026-08-02).
    ///
    /// It used to be stated twice and the two drifted the day the rail landed.
    /// `CasberiApp`'s `.frame(minWidth:)` gained `+ railWidth` with a comment
    /// explaining that 560 is a statement about the CONTENT column, so leaving
    /// it alone once a fixed 88pt rail moved in "would have quietly redefined
    /// it as 472". `RootShell`'s `UIWindowScene.sizeRestrictions` did not gain
    /// it — and that is the one that BINDS: RootShell's own note records, from
    /// a live measurement, that SwiftUI's `minWidth` does not constrain a
    /// Catalyst NSWindow at all. So the floor really was 560 with a 472pt
    /// column under it, i.e. precisely the outcome the other comment believed
    /// it had prevented. Both sites read this now, so a future rail-width
    /// change moves one number.
    static let macMinContentWidth: CGFloat = 560
    static var macMinWindowSize: CGSize {
        CGSize(width: macMinContentWidth + railWidth, height: 480)
    }

    /// The first-launch window size. Deliberately clear of `minWidthForPane`:
    /// it used to be exactly 980, so a fresh install opened ON the pane
    /// boundary and the first nudge of the resize handle collapsed the pane
    /// and fired the displaced-to-sheet hand-off. A default size should sit in
    /// the middle of a layout, never on its edge.
    static let macIdealWindowSize = CGSize(width: 1120, height: 760)

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

    /// The floating cluster's cap — today that is the whisper capsule alone.
    ///
    /// It was `agentBarMaxWidth` (680) and it capped the BAR, because the bar
    /// spanned the shell and a capsule holding one placeholder line has no
    /// business being 1376pt wide. Since 2026-08-07 the bar hugs its own two
    /// controls in the bottom-right corner and needs no cap at any width; the
    /// whisper above it still does, and wants a tighter one than the bar ever
    /// did — it is a title over a line of facts, not a row of chrome, so past
    /// a reading column's worth of width the words simply drift apart.
    ///
    /// Deliberately above any iPhone's usable width (the widest is ~430pt, less
    /// two `s4` insets), so this binds on iPad and Mac only and the phone keeps
    /// its whole column.
    static let floatingClusterMaxWidth: CGFloat = 420
}

extension View {
    /// Reserve the source rail's column (user ruling 2026-08-12: "the rail
    /// should be preserved and content not go behind it").
    ///
    /// **Why a padding and not the safe-area inset that is already there.**
    /// The rail rides `.safeAreaInset(edge: .leading)` applied to the
    /// NavigationStack, and that inset NEVER REACHES THE STACK'S CONTENT —
    /// measured on the Mac renderer 2026-08-12, the feed's own
    /// `safeAreaInsets.leading` reads **0** at every window width while the
    /// strip's `.top` inset (applied INSIDE the stack) reads its full 50. This
    /// is the same fact `MainSurface.topInset` already records for the demo
    /// banner — "an inset applied further out reserves space the strip simply
    /// ignores" — met a second time on a second edge, and it is why that band
    /// pads itself by hand rather than trusting the inset.
    ///
    /// So nothing was reserving the rail's 88pt, and what kept it looking
    /// right was arithmetic that only holds on a wide window: the feed is
    /// capped at `readingMaxWidth` and CENTRED, so it clears the rail only
    /// while the space it is centred in exceeds 700 + 2×88 = 876pt. Below
    /// that the column slides under the chips. The detail pane makes that the
    /// NORMAL case rather than an edge one, because its own trailing inset
    /// (applied inside the stack, so it does bind) takes 400–560pt off the
    /// width being centred in: at the shipped default 1120pt window the feed
    /// had 694pt and every row title was drawn beneath the rail, its first
    /// characters cut ("Calendar" → "alendar"). A window had to reach roughly
    /// 1600pt before the collision stopped.
    ///
    /// Applied to the stack's CONTENT — the root pager and each pushed room —
    /// rather than to `dsAdaptiveContentWidth`, which every screen wears: the
    /// same setup screens are also presented as `ConnectFormSheet`, and a
    /// sheet has no rail beside it, so reserving inside that modifier would
    /// shift every connect form 88pt off its own centre.
    ///
    /// What this gives up, stated plainly: rows no longer travel UNDER the
    /// rail, which was the reason the rail became an inset in the first place
    /// (2026-08-10 — "the material finally has something to blur"). That
    /// benefit was never actually being collected, since a capped, centred
    /// column only reaches the chips at the widths where it also reads as
    /// broken. The page photo and the crown pour still run the full width
    /// beneath it — they are painted by a `.background` that ignores the safe
    /// area — so the glass keeps a real backdrop to sample.
    func dsRailColumn(_ reserve: Bool) -> some View {
        padding(.leading, reserve ? PadLayout.railWidth : 0)
    }
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

    /// `paneVisible` is false while a pushed room covers the pane — the rail
    /// lives outside the navigation stack and survives a push, the pane lives
    /// inside it and does not.
    init(regular: Bool, width: CGFloat, paneVisible: Bool = true) {
        isRegular = regular
        railInset = regular ? PadLayout.railWidth : 0
        paneInset = regular && paneVisible && width >= PadLayout.minWidthForPane
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
    // `.shared` DELETED (multi-window, 2026-08-02) — per-window now, held by
    // `SceneState`. A pane selection is the most obviously per-window thing
    // in the app: two windows each open on their own record is the reason to
    // have two.

    /// What the pane is showing. nil = the pane's own resting state.
    var thing: Thing?

    /// True only while the shell is ACTUALLY rendering a pane. Written by
    /// `MainSurface` from its measured width; read by every row-tap site, so
    /// no caller has to know the breakpoint or re-derive the size class.
    var paneActive = false

    /// Set the first time the shell measures itself. `paneActive` starts
    /// false and only becomes true after a layout pass, so anything asking
    /// at LAUNCH (a deep link, a Spotlight hand-off, the `-openThing` probe)
    /// would otherwise read a settled-looking `false` that just means "not
    /// measured yet" and take the sheet on a device that has a pane.
    var layoutSettled = false

    /// Handoff when the pane disappears out from under an open thing (Mac
    /// polish, 2026-07-28): on iPad, losing the pane means a ROTATION — a
    /// deliberate act that changes the whole layout at once, so clearing
    /// `thing` outright reads fine. On Mac the same `showsPane` transition
    /// fires on a plain, continuous window drag past `minWidthForPane`, so
    /// silently discarding whatever was open reads as the app randomly
    /// closing what you were reading. `MainSurface` sets this instead of
    /// clearing `thing` directly; `RootShell` observes it and opens the
    /// same thing as a real sheet instead of dropping it.
    var displaced: Thing?

    /// Suspends until the shell has measured itself, so a launch-time route
    /// asks a question that has an answer. Bounded — a shell that never lays
    /// out (nothing on screen to route into) must not hang the caller, it
    /// falls through and the caller takes its normal path.
    func awaitLayout() async {
        for _ in 0..<60 where !layoutSettled {
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

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
