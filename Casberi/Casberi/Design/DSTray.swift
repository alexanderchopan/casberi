import SwiftUI

/// The one tray scaffold — the design-system rule for every bottom sheet.
///
/// RULE (brief §8): trays are not hand-rolled. A tray is `DSTray(title:height:)`
/// wrapping its content. It owns:
///   • the grabber (drag indicator),
///   • a left-aligned `heading22` title with top clearance so it never crowds
///     the grabber or "flows over" the top edge,
///   • uniform horizontal + bottom padding,
///   • the sheet surface, the height detent, and the color scheme.
/// Content flows below the title; the caller attaches its own `.onAppear`,
/// `.fileImporter`, `.confirmationDialog`, etc. to the `DSTray`.
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
        .presentationDetents(detents ?? [.height(height)])
        .presentationDragIndicator(.visible)

        if ink {
            tray.dsInk()
        } else {
            tray.presentationBackground(DS.surfaceSheet).dsColorScheme()
        }
    }
}
