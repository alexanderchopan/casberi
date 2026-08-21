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
    /// The catalog door the EMPTY tray offers — threaded straight through to
    /// `SourcesTray`, which is the only thing that draws it.
    let onOpenCatalog: () -> Void
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
    /// A fraction of the panel, CAPPED — and the cap is the half that was
    /// missing. At 33% of height alone, a short panel (three rows, ~450pt)
    /// demanded ~150pt of travel before it let go, so a normal pull did
    /// nothing at all and read as a dead handle. The cap makes a big panel
    /// cheap to dismiss without making a small one impossible.
    private static let dismissFraction: CGFloat = 0.33
    private static let dismissCeiling: CGFloat = 90
    /// Also lowered, for the same report: 600 asked for a hard flick.
    private static let flickVelocity: CGFloat = 350
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
    /// The whole header — grabber, its clearance, the title and the gap below
    /// it. THIS is the drag region (2026-08-16, user: "the grabber doesn't
    /// work to pull it down, you have to tap outside the panel to close it").
    ///
    /// The gesture was on the 24pt grabber strip alone, which is a target you
    /// have to aim at with a thumb you cannot see past. A sheet lets you drag
    /// its whole header, and so does this now — full width, everything above
    /// the scrolling grid.
    ///
    /// **93 → 107 on 2026-08-18**, when the title band gained the All capsule
    /// beside it: the band is the taller of the title's own line and a 44pt
    /// control, and 44 wins. Stated because this height is spent, not free —
    /// it is 14pt less feed above the panel. What it does NOT touch is how
    /// many rows rest: `restingCap` governs the tray's CONTENT and this sits
    /// outside it, so a four-row corpus still rests at four (634 + 107 = 741,
    /// under the 769 ceiling a 874pt phone allows). On a phone small enough
    /// for the ceiling to bite, the panel was already clamped and already
    /// scrolling, so the 14pt changes nothing there either.
    private static let titleBandHeight: CGFloat = DS.Hit.min
    private static let headerHeight: CGFloat =
        grabberHeight + DS.Space.s6 + titleBandHeight + DS.Space.s4
    /// How much of the screen the panel may ever take. Not the whole thing:
    /// a panel with no page left above it is a screen, and this one's whole
    /// claim is that it floats over the feed.
    private static let maxScreenFraction: CGFloat = 0.88
    /// Drag up past this and it grows. Shorter than the dismiss threshold on
    /// purpose — expanding is cheap and reversible, dismissing throws the
    /// panel away.
    private static let expandDistance: CGFloat = 60

    /// **On Mac this is a floating panel beside the rail, not a bottom sheet
    /// (2026-08-20).**
    ///
    /// The move off `.sheet` (above) already made this a view in the app's own
    /// hierarchy, and everything it bought applies on a Mac too. What did NOT
    /// travel is the SHAPE: full-bleed to the window's bottom edge, square
    /// bottom corners because they sit off-screen, and a rise-from-the-bottom
    /// transition are all statements about a phone — a surface pinned to the
    /// edge your thumb reaches from. A desktop window has no such edge, and a
    /// 2000pt-wide panel holding a grid of 56pt marks is the "made for mobile"
    /// reading in its purest form.
    ///
    /// So on Mac it floats: a stated width, clear of every edge, all four
    /// corners rounded because all four are visible, anchored beside the rail
    /// — which is both where it is opened from (the catalogue door at the
    /// rail's head) and what it is a bigger map of.
    ///
    /// Everything else is deliberately unchanged, including the drag: a
    /// trackpad drives it fine, and Escape and click-outside were always the
    /// primary dismissals here.
    private var macPanel: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }

    /// Wide enough for the grid's own columns, far short of a window. Paired
    /// with `PadLayout.railWidth` below so the panel sits beside the rail
    /// rather than over it.
    private static let macPanelWidth: CGFloat = 460

    var body: some View {
        let panel = SourcesTray(labels: labels, active: active,
                                onPick: onPick, onDismiss: onDismiss,
                                onOpenCatalog: onOpenCatalog)

        GeometryReader { geo in
            // The ceiling is the screen, not the corpus — a 40-source tray
            // still scrolls, it just does so at full height instead of at
            // resting height.
            let ceiling = geo.size.height * Self.maxScreenFraction
            // `grabberHeight` is ADDED, not absorbed: the grabber sits above
            // the tray inside this frame, so a frame sized to the tray alone
            // squeezes the content by exactly its height. That shipped in the
            // first overlay build and made a three-row tray scroll.
            let resting = min(panel.panelHeight + Self.headerHeight, ceiling)
            let full = min(panel.naturalPanelHeight + Self.headerHeight, ceiling)
            let canGrow = full > resting + 1
            let height = expanded && canGrow ? full : resting

            ZStack(alignment: macPanel ? .bottomLeading : .bottom) {
                // The catcher — paints nothing, closes on a tap. See the doc.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { onDismiss() }
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    // THE DRAG LIVES ON THE HEADER, not on the panel and not
                    // on the grabber alone.
                    //
                    // Not the panel: the tray's own `ScrollView` wins that
                    // arbitration, so the gesture never fired at all (measured
                    // — the panel did not move a pixel). Not the grabber
                    // alone: 24pt is a target you must aim at, and it was
                    // reported dead on a real device. The header is chrome, it
                    // does not scroll, and it is the region a sheet lets you
                    // drag.
                    header
                        .gesture(dragGesture(height: height, canGrow: canGrow))
                    panel
                }
                .frame(width: macPanel ? Self.macPanelWidth : nil, height: height)
                .background { glass }
                .clipShape(shape)
                // Clear of the window's edges, and clear of the rail — AFTER
                // the clip, so it insets the panel rather than its glass.
                .padding(.leading, macPanel ? PadLayout.railWidth + DS.Space.s4 : 0)
                .padding(.bottom, macPanel ? DS.Space.s4 : 0)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: macPanel ? .bottomLeading : .bottom)
        }
        .ignoresSafeArea()
        .transition(transition)
    }

    /// A phone panel RISES from the edge it is pinned to. A floating one has no
    /// edge to rise from, so it arrives where it will sit — the standard Mac
    /// reading, and the same anchor it is scaled about.
    private var transition: AnyTransition {
        if reduceMotion { return .opacity }
        if macPanel {
            return .opacity.combined(with: .scale(scale: 0.96, anchor: .bottomLeading))
        }
        return .move(edge: .bottom)
    }

    /// Top corners only on touch: the panel is anchored to the bottom edge, and
    /// rounding the two corners that sit off-screen would be a radius nobody
    /// can see costing a clip everybody pays for. On Mac it floats clear of
    /// every edge, so all four corners are visible and all four are rounded —
    /// the square pair would read as a sheet that had been cut off.
    private var shape: UnevenRoundedRectangle {
        let bottom = macPanel ? DS.Radius.sheet : 0
        return UnevenRoundedRectangle(topLeadingRadius: DS.Radius.sheet,
                                      bottomLeadingRadius: bottom,
                                      bottomTrailingRadius: bottom,
                                      topTrailingRadius: DS.Radius.sheet,
                                      style: .continuous)
    }

    /// Grabber + title + the All capsule: the panel's chrome, and its drag
    /// region.
    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            grabber
            HStack(spacing: DS.Space.s2) {
                Text("Your feeds")
                    .dsText(.heading22)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: DS.Space.s2)
                allChip
            }
            .frame(height: Self.titleBandHeight)
            .padding(.top, DS.Space.s6)
            .padding(.bottom, DS.Space.s4)
            .padding(.horizontal, DS.Space.s4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.headerHeight)
        // The whole band is the target, title included.
        .contentShape(Rectangle())
    }

    /// The way back to All, from inside the tray (2026-08-18).
    ///
    /// **The known cost §391 restated and §407 pays.** "All has no cell" (user,
    /// 2026-08-06) is a ruling about the GRID, and it stands: All belongs to
    /// no category, so as a cell it could only be an ungrouped orphan taking a
    /// row of its own out of a layout whose whole discipline is whole groups
    /// on shared columns. `SourcesTray`'s own doc then recorded the
    /// consequence rather than hiding it — "from INSIDE the tray there is now
    /// no way back to All" — and the panel is the surface that most invites
    /// you to try: it is the map of every room, opened by the gesture that
    /// means "where can I go", and the everything-room was the one
    /// destination it refused. A word capsule in the header costs the grid
    /// nothing, costs the packer nothing, and touches no ruling: it is not a
    /// cell.
    ///
    /// **It also fixes a second thing, which is the stronger argument.** Open
    /// this panel while you are IN All — which is where the app opens, so it
    /// is the common case — and until today no cell anywhere wore the
    /// selection ring. A map of your rooms showing no you-are-here reads as
    /// broken, and `revealActive`'s whole job (jump so the active cell is
    /// visible) was silently a no-op in exactly that state because there was
    /// nothing to jump to.
    ///
    /// **Why not `wordChipFill`**, the strip's own shared word-chip paint: it
    /// carries `dsGlass`, i.e. a second material, and this capsule sits ON the
    /// panel's glass rather than on the crown. Stacking material inside the
    /// panel is §391's lesson wearing a translucent coat. Its travelling
    /// `matchedGeometryEffect` has nowhere to travel to besides — there is one
    /// word chip here, not five — so the only thing sharing that modifier
    /// would buy is a shape this surface renders differently anyway. What IS
    /// shared is the reading: tint means selection here exactly as it does on
    /// the strip and on a cell's ring, and the resting state is `fillStrong`,
    /// the same wash the grabber above it already wears.
    ///
    /// **The one open question, stated rather than discovered later, and
    /// UNMEASURED on device:** how the header's `.gesture` and this button
    /// arbitrate a drag that STARTS on the capsule. Either SwiftUI gives the
    /// drag priority once it passes its 8pt minimum (the capsule taps and the
    /// panel still drags, nothing to fix) or it gives the nested button
    /// priority (those ~55×44pt become a dead zone for the pull-to-dismiss
    /// the rest of the band carries). The TAP works in both, so neither is a
    /// broken control — this is worth a device check, not a redesign.
    ///
    /// What is NOT the fix if it turns out to be the dead zone:
    /// `.simultaneousGesture`. A short pull that stays inside the capsule's
    /// own bounds would then move the panel AND fire the button on release,
    /// so a hesitant drag would land you in All — a wrong destination is a
    /// worse failure than a corner of a full-width header that does not drag.
    /// Move the drag onto the grabber-plus-title region instead, which gives
    /// the capsule its own space without handing one gesture two meanings.
    private var allChip: some View {
        let isOn = active == "All"
        return Button {
            DSHaptic.selection()
            onPick("All")
            onDismiss()
        } label: {
            Text("All")
                .dsText(.label12)
                .fontWeight(.semibold)
                // `.white` on the tint for the same reason the strip's active
                // word chip is white on it: the accent is a dark blue in both
                // themes, so this pairing does not flip with the theme.
                .foregroundStyle(isOn ? .white : DS.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, DS.Space.s3)
                .frame(height: DS.Hit.min)
                .background {
                    if isOn {
                        Capsule(style: .continuous).fill(DS.tint)
                    } else {
                        Capsule(style: .continuous).fill(DS.fillStrong)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(PressSpring())
        .dsHover()
        .accessibilityLabel(Text("All"))
        .accessibilityHint(Text("Show every source"))
        .accessibilityAddTraits(isOn ? .isSelected : [])
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
                let far = travel > min(height * Self.dismissFraction, Self.dismissCeiling)
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
