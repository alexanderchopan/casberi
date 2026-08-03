import SwiftUI

/// The one tray scaffold — the design-system rule for every bottom sheet.
///
/// RULE (brief §8): trays are not hand-rolled. A tray is `DSTray(title:height:)`
/// wrapping its content. It owns:
///   • the grabber (drag indicator),
///   • a left-aligned `heading22` title with top clearance so it never crowds
///     the grabber or "flows over" the top edge,
///   • uniform horizontal + bottom padding,
///   • the sheet surface, the height detent, and the color scheme,
///   • the overflow contract below.
/// Content flows below the title; the caller attaches its own `.onAppear`,
/// `.fileImporter`, `.confirmationDialog`, etc. to the `DSTray`.
///
/// OVERFLOW (2026-08-03, user report: "can see the words in the bring your own
/// agent header"). A tray's content is laid out against a FIXED detent, and
/// content taller than that detent does not compress — a `Text` with
/// `fixedSize`, a 44pt field, a list of seven rows all report their ideal
/// height. Until this date the oversized stack was centred in the sheet with
/// nothing clipping it, so it overflowed BOTH ways: the title and the first
/// paragraphs floated ABOVE the sheet's rounded top edge, drawn over the
/// screen behind it and crossed by the grabber, while the bottom ran off
/// under the home indicator. It reads as a rendering bug, because it is one.
///
/// So every tray now anchors its content to the TOP and clips to the sheet's
/// own bounds. A tray that overflows anyway degrades honestly — the title and
/// the summary stay put, the tail is cut off at the bottom edge where "there
/// is more here" is the obvious reading — instead of bleeding over the app.
/// This is a floor, not a licence: content that can outgrow its detent still
/// belongs in a `ScrollView` (the house pattern, `DSTray { ScrollView { … } }`),
/// with a `detents` set that can be dragged open.
struct DSTray<Content: View>: View {
    let title: String
    let height: CGFloat
    /// Paint `dsInk()` (pure black, forced dark) instead of the theme-
    /// adaptive default — for a tray that IS or precedes a black "detail"
    /// surface (`SocialProfileCard`, `WalletWorthALookTray`), so it reads as
    /// one continuous ink sheet instead of a shade off beside it. See
    /// `dsInk()` in `ThemeStore.swift` for the full rationale.
    var ink: Bool = false
    /// The detent set. Defaults to the single computed `height` every other
    /// tray already ships — pass a wider set (e.g. `[.height(height), .large]`)
    /// to let a tray with unpredictable content length be dragged open past
    /// its natural size instead of clipping at a hard ceiling.
    var detents: Set<PresentationDetent>?
    @ViewBuilder var content: () -> Content

    var body: some View {
        let tray = VStack(alignment: .leading, spacing: DS.Space.s4) {
            // The title doubles as its own catalog key — a title that isn't a
            // key just renders verbatim, so dynamic titles stay safe.
            Text(LocalizedStringKey(title))
                .dsText(.heading22)
                .foregroundStyle(DS.textPrimary)
            content()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Space.s4)
        // The title clears the grabber — this is the fix for titles crowding
        // the top edge; every tray inherits it.
        .padding(.top, DS.Space.s6)
        .padding(.bottom, DS.Space.s6)
        // The overflow contract (see the type doc): top-anchored, then clipped
        // to the sheet. The frame resolves to the detent's height, so an
        // oversized stack hangs off the BOTTOM only, and `clipped` keeps it
        // inside the sheet instead of over the screen behind it.
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
        .presentationDetents(detents ?? [.height(height)])
        .presentationDragIndicator(.visible)
        // Feel, re-declared for this presentation (2026-08-01, user: the
        // sources tray's cells were silent). `DSHaptic` is a counter bump on a
        // shared bus, and the mapping from counter to feedback is a VIEW
        // modifier — so it plays only where it is attached. It was attached in
        // exactly one place, `RootShell`'s body, and a sheet covers that: every
        // haptic fired from inside a tray bumped its counter and nothing was
        // listening. A tray is its own hosting environment, the same reason
        // `RootShell.rootPresented` has to re-inject the shell's environment
        // objects rather than let a sheet inherit them.
        //
        // It cannot double up with the root's copy — that copy is precisely
        // what doesn't fire under a sheet, which is the bug. And it belongs
        // HERE rather than at each call site because design law already says
        // every tray in this app is a `DSTray`, so one line covers all of them
        // and a tray built tomorrow can't be born silent.
        .dsSensoryFeedback()

        if ink {
            tray.dsInk()
        } else {
            tray.presentationBackground(DS.surfaceSheet).dsColorScheme()
        }
    }
}
