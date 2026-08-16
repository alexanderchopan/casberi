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
    /// Present on GLASS instead of the opaque `surfaceSheet` (2026-08-16, user).
    ///
    /// The one tray that takes it is `SourcesTray`, and it takes it because its
    /// cells lost their opaque cards the same day: marks floating on an opaque
    /// sheet are the bare 2026-08-06 grid, marks floating on a panel of glass
    /// are a shelf. Everywhere else the opaque sheet stays right — a tray that
    /// carries text you READ has nothing to gain from a live backdrop and a
    /// contrast floor to lose.
    ///
    /// Deliberately NOT the default, and deliberately not `dsGlass`: that
    /// modifier is for the floating layer (composer, FAB, toasts) and carries a
    /// stroke, a shadow and a corner radius of its own — all three wrong for a
    /// surface the system already rounds, shadows and clips for us.
    var glass: Bool = false
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
        }
        // Top-aligned by FRAME, not by a trailing `Spacer(minLength: 0)`
        // (2026-08-11). A Spacer is a view, so the stack's own `spacing` was
        // inserted BEFORE it as well as before the content — every tray paid
        // `DS.Space.s4` twice while its caller's height arithmetic counted it
        // once.
        //
        // Reported as clipping in the sources tray: cards with no bottom edge.
        // `SourcesTray.chromeHeight` is `s6 + title + s4 + s6`, and it snaps
        // the resting height DOWN to a whole number of cards precisely so a
        // card is never cut in half — but the sheet was 15pt shorter than that
        // arithmetic believed, so the last card lost its 6pt of bottom padding
        // and a slice of its name row. The label survived and the card's
        // rounded bottom did not, which is why it read as a clipping bug
        // rather than as a height being wrong.
        //
        // Fixed HERE rather than by adding 15pt to the one tray that noticed:
        // every caller computes its height from the same "pad, title, gap,
        // content, pad" model this component documents, so the phantom gap was
        // wrong for all of them and merely invisible in trays with slack. A
        // deficit clips; slack does not, so this can only turn clipped trays
        // into correct ones.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, DS.Space.s4)
        // The title clears the grabber — this is the fix for titles crowding
        // the top edge; every tray inherits it.
        .padding(.top, DS.Space.s6)
        .padding(.bottom, DS.Space.s6)
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
        } else if glass {
            tray.presentationBackground { DSGlassSheet() }.dsColorScheme()
        } else {
            tray.presentationBackground(DS.surfaceSheet).dsColorScheme()
        }
    }
}

/// The sheet as a PANEL of glass rather than a blurred rectangle.
///
/// The material alone reads as FOG — measured against four alternatives in
/// `prototype/sources-tray-glass-v1.html`. What makes it read as a pane is the
/// SHEEN: a fall-off from the top-leading corner, i.e. the light the panel is
/// under. The mock also carried a 1pt lit rim along the top edge, which is the
/// single strongest cue of the two and is NOT here on purpose — brief §8's
/// no-hairlines rule has zero exceptions, and a lit rim is a hairline no matter
/// what it is standing in for. The gradient carries the same idea with no line.
///
/// No shape of its own: `presentationBackground` is already clipped to the
/// sheet, and an inner `RoundedRectangle` would draw its own corners inside the
/// system's — two radii, one of which is a guess at what iOS is doing this year.
private struct DSGlassSheet: View {
    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: DS.glassSheen, location: 0),
                        .init(color: DS.glassSheen.opacity(0.25), location: 0.22),
                        .init(color: .clear, location: 0.46)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea()
    }
}
