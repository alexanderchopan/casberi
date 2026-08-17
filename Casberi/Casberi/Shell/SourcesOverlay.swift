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
    /// Grown to `naturalPanelHeight` by an upward drag. The detent `.sheet`
    /// gave us free, rebuilt — but only ONE step, resting or full, because a
    /// ladder of stops on a hand-rolled gesture is where this starts costing
    /// more than the sheet ever did.
    @State private var expanded = false

    /// Past this fraction of its own height, or on a flick, the release lets
    /// go. A fraction rather than a fixed distance because the panel's height
    /// varies with the corpus — a third of a short panel and a third of a tall
    /// one feel the same, where 120pt would feel decisive on one and
    /// unreachable on the other.
    private static let dismissFraction: CGFloat = 0.33
    private static let flickVelocity: CGFloat = 600
    /// The grabber's own height — its capsule plus the padding above it.
    ///
    /// It is counted in the panel's frame, and NOT counting it was a real bug
    /// on the first overlay build: the grabber was stacked above the tray
    /// inside a frame sized to the tray alone, so the content was squeezed by
    /// 13pt and scrolled — with the first group's eyebrow cut off the top —
    /// on a corpus small enough to fit twice over. Reported as "it scrolls
    /// within the panel instead of the panel moving".
    /// The strip, not just the capsule: the drag lives HERE and nowhere else,
    /// so it needs a real target. 24pt of chrome reading as a handle.
    private static let grabberHeight: CGFloat = 24
    /// How much of the screen the panel may ever take. Not the whole thing:
    /// a panel with no page left above it is a screen, and this one's whole
    /// claim is that it floats over the feed.
    private static let maxScreenFraction: CGFloat = 0.88
    /// Drag up past this and it grows. Shorter than the dismiss threshold on
    /// purpose — expanding is cheap and reversible, dismissing throws the
    /// panel away.
    private static let expandDistance: CGFloat = 60

    var body: some View {
        let panel = SourcesTray(labels: labels, active: active,
                                onPick: onPick, onDismiss: onDismiss)

        GeometryReader { geo in
            // The ceiling is the screen, not the corpus — a 40-source tray
            // still scrolls, it just does so at full height instead of at
            // resting height.
            let ceiling = geo.size.height * Self.maxScreenFraction
            // `grabberHeight` is ADDED, not absorbed: the grabber sits above
            // the tray inside this frame, so a frame sized to the tray alone
            // squeezes the content by exactly its height. That shipped in the
            // first overlay build and made a three-row tray scroll.
            let resting = min(panel.panelHeight + Self.grabberHeight, ceiling)
            let full = min(panel.naturalPanelHeight + Self.grabberHeight, ceiling)
            let canGrow = full > resting + 1
            let height = expanded && canGrow ? full : resting

            ZStack(alignment: .bottom) {
                // The catcher — paints nothing, closes on a tap. See the doc.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { onDismiss() }
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    // THE DRAG LIVES ON THE GRABBER, not on the panel.
                    //
                    // It was on the whole panel for one build and did nothing:
                    // the tray's own `ScrollView` wins that arbitration, so an
                    // upward drag scrolled the grid and never reached this
                    // gesture. Measured in the simulator — the panel did not
                    // move a pixel. Scoping the gesture to chrome that does
                    // not scroll removes the conflict rather than fighting it
                    // with `simultaneousGesture`, which would have let both
                    // fire and made a drag scroll AND resize.
                    grabber
                        .gesture(dragGesture(height: height, canGrow: canGrow))
                    panel
                }
                .frame(height: height)
                .background { glass }
                .clipShape(shape)
                // Downward only. An upward drag changes the HEIGHT on release
                // rather than offsetting the panel — lifting it would open a
                // gap under a surface that is anchored to the bottom edge.
                .offset(y: max(0, drag))
                .accessibilityAddTraits(.isModal)
                .accessibilityAction(.escape) { onDismiss() }
                .accessibilityAction(named: Text(expanded ? "Collapse" : "Expand")) {
                    if canGrow { withAnimation(DS.Motion.standard) { expanded.toggle() } }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
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
            .frame(maxWidth: .infinity)
            .frame(height: Self.grabberHeight)
            // The whole strip is the target, not the 36×5 capsule — a 5pt
            // drag handle is a 5pt drag handle however well it is drawn.
            .contentShape(Rectangle())
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

    /// One gesture, three outcomes: grow, collapse, or let go.
    ///
    /// Up expands (when there is anything left to show), down collapses a
    /// grown panel and dismisses a resting one. Collapsing before dismissing
    /// matters — a drag down from full height should give back what the drag
    /// up asked for, not throw the whole panel away.
    private func dragGesture(height: CGFloat, canGrow: Bool) -> some Gesture {
        // `.global`, NOT the default `.local` — and this is the difference
        // between a gesture that works and one that silently does nothing.
        //
        // The panel offsets ITSELF as the drag proceeds (`offset(y:)` below),
        // so in local space the gesture's own frame slides out from under the
        // finger and the translation it reports collapses. Measured in the
        // simulator: dragging UP worked (`max(0, drag)` means no offset, so
        // nothing moved) while dragging DOWN did nothing at all — neither
        // collapse nor dismiss ever fired. A global coordinate space is
        // immune to the view's own movement.
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in drag = max(0, value.translation.height) }
            .onEnded { value in
                let travel = value.translation.height
                let flick = value.predictedEndTranslation.height - travel
                if travel < -Self.expandDistance, canGrow {
                    withAnimation(DS.Motion.standard) { expanded = true; drag = 0 }
                    return
                }
                let far = travel > height * Self.dismissFraction
                let fast = flick > Self.flickVelocity
                guard far || fast else {
                    withAnimation(DS.Motion.standard) { drag = 0 }
                    return
                }
                if expanded {
                    withAnimation(DS.Motion.standard) { expanded = false; drag = 0 }
                } else {
                    onDismiss()
                    // Reset AFTER the close so the panel does not snap back up
                    // through its own exit transition.
                    drag = 0
                }
            }
    }
}
