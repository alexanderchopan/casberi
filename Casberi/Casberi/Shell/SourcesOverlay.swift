import SwiftUI

/// The sources tray as a FLOATING PANEL, not a sheet (2026-08-16, user: "yes
/// lets move away from the sheet").
///
/// # Why the sheet had to go
///
/// The complaint that drove this was "still gray … it isn't clear like it is
/// on the sim", asked beside a screenshot of the App Store's iOS 26 tab bar
/// where the app name behind it is legible THROUGH the glass. Three builds
/// were spent on the material and none of them reached it (§393, §393a):
///
///   • the plate walked 0.82 → 0.55 → 0.45 → 0.35,
///   • `glassEffect(.clear)` was tried and reverted — on hardware it appears
///     not to sample a presented sheet's backdrop at all, while the simulator
///     renders the same build with the feed showing through,
///   • the sheet's own dimming layer was found and removed, which helped and
///     still did not get there.
///
/// What was left is the presentation itself. A `.sheet` renders in its own
/// context; Apple's Liquid Glass surfaces — bars, controls, that tab bar —
/// are views inside the app's own hierarchy, compositing directly over the
/// scroll behind them. So this hosts the panel in `RootShell`'s ZStack beside
/// the agent bar, where the material has the live feed behind it and no
/// presentation boundary in between.
///
/// # What the move cost, stated rather than discovered later
///
/// `.sheet` was carrying real behaviour for free, and every line of it is now
/// ours:
///
///   • **Detents.** The panel is one height — its natural resting height, the
///     same snapped-to-whole-rows number `SourcesTray` already computed. The
///     `.large` drag-to-expand is GONE; past the cap the grid scrolls inside
///     the panel, which is what the resting cap was always for.
///   • **Drag to dismiss**, rebuilt here: a downward drag tracks the finger
///     and releases past a third of the panel or on a fast flick.
///   • **The grabber**, drawn rather than requested.
///   • **Modal semantics.** `.accessibilityAddTraits(.isModal)` on the panel
///     tells VoiceOver the feed behind is not the subject; a sheet declared
///     that for us. The tap-catcher below is `.accessibilityHidden` so it is
///     not a stop of its own, and an Escape-equivalent lives on the panel's
///     own dismiss action.
///
/// # The backdrop is a CATCHER, not a scrim
///
/// It paints nothing — the whole point is that the feed stays visible — and
/// exists only so a tap outside the panel closes it. That is deliberately NOT
/// the pass-through behaviour `.presentationBackgroundInteraction` gave us for
/// one build: with the feed live, a tap on a row opened that row's sheet and
/// the tray vanished under it, which is a worse answer to "I tapped away from
/// this" than simply closing.
struct SourcesOverlay: View {
    let labels: [String]
    let active: String
    let onDismiss: () -> Void
    /// Last so the call site reads as a trailing closure, matching the shape
    /// the `.sheet` call it replaced already had.
    let onPick: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drag: CGFloat = 0

    /// Past this fraction of its own height, or on a flick, the release lets
    /// go. A fraction rather than a fixed distance because the panel's height
    /// varies with the corpus — a third of a short panel and a third of a tall
    /// one feel the same, where 120pt would feel decisive on one and
    /// unreachable on the other.
    private static let dismissFraction: CGFloat = 0.33
    private static let flickVelocity: CGFloat = 600

    var body: some View {
        let panel = SourcesTray(labels: labels, active: active,
                                onPick: onPick, onDismiss: onDismiss)
        let height = panel.panelHeight

        ZStack(alignment: .bottom) {
            // The catcher — paints nothing, closes on a tap. See the type doc.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                grabber
                panel
            }
            .frame(height: height)
            .background { glass }
            .clipShape(shape)
            .offset(y: max(0, drag))
            .gesture(dragToDismiss(height: height))
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape) { onDismiss() }
        }
        .ignoresSafeArea()
        .transition(reduceMotion ? .opacity : .move(edge: .bottom))
    }

    /// Top corners only: the panel is anchored to the bottom edge, and
    /// rounding the two corners that sit off-screen would be a radius nobody
    /// can see costing a clip everybody pays for.
    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: DS.Radius.sheet,
                               bottomLeadingRadius: 0,
                               bottomTrailingRadius: 0,
                               topTrailingRadius: DS.Radius.sheet,
                               style: .continuous)
    }

    private var grabber: some View {
        Capsule()
            .fill(DS.fillStrong)
            .frame(width: 36, height: 5)
            .padding(.top, DS.Space.s2)
            .accessibilityHidden(true)
    }

    /// The material. `glassEffect` is reachable HERE in a way it never was
    /// inside `presentationBackground` — this view is in the shell's own tree,
    /// which is the entire reason for the move — so the system's own Liquid
    /// Glass is the first choice again on iOS 26, with `DSGlassSheet`'s recipe
    /// carrying every device below it.
    /// **`.regular`, not `.clear`, and that is this app's own rule rather than
    /// a retreat** (2026-08-16). The first overlay build used `.clear` and the
    /// move worked — the feed read straight through the panel for the first
    /// time in four builds — and immediately overshot: the feed's own words
    /// competed with the tray's, a row title running through a category
    /// eyebrow. `DSGlassVariant`'s doc has said since 2026-08-06 that
    /// `.regular` is for chrome over CONTENT (rows, words, a feed) and
    /// `.clear` only for chrome over PIXELS, "deliberately NOT a taste
    /// option: `clear` withholds exactly the contrast `regular` provides".
    /// This tray sits over rows and words. The App Store tab bar it was
    /// compared against is `.regular` too — what made it read as glass was
    /// never the variant, it was being in the hierarchy at all.
    @ViewBuilder
    private var glass: some View {
        if #available(iOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.35)
                .overlay {
                    LinearGradient(
                        stops: [.init(color: DS.glassSheen, location: 0),
                                .init(color: DS.glassSheen.opacity(0.25), location: 0.12),
                                .init(color: .clear, location: 0.30)],
                        startPoint: .topLeading, endPoint: .bottom)
                }
                .overlay {
                    LinearGradient(
                        stops: [.init(color: .clear, location: 0.32),
                                .init(color: DS.glassDepth, location: 1)],
                        startPoint: .top, endPoint: .bottom)
                }
        }
    }

    private func dragToDismiss(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                // Downward only. An upward drag does nothing rather than
                // stretching the panel — there is no taller detent to reach,
                // so rubber-banding toward one would promise a state that
                // does not exist.
                drag = max(0, value.translation.height)
            }
            .onEnded { value in
                let far = value.translation.height > height * Self.dismissFraction
                let fast = value.predictedEndTranslation.height - value.translation.height
                    > Self.flickVelocity
                if far || fast {
                    onDismiss()
                    // Reset AFTER the close so the panel does not snap back up
                    // through its own exit transition.
                    drag = 0
                } else {
                    withAnimation(DS.Motion.standard) { drag = 0 }
                }
            }
    }
}
