import SwiftUI

/// The shell's one navigation strip (2026-07-13, drastic restructure): the app
/// is a single scrolling surface, and this chip row IS how you move through it.
/// The tab bar is gone — All leads (the whole feed), then every source
/// most-recent-first. Tapping a chip swaps the surface under a fixed header,
/// so the strip never scrolls out of reach the way Feed's old in-list chip
/// row did. (The Pinned board that used to lead retired 2026-07-20,
/// docs/agent-brief.md rulings 11-12 — content-first, always.)
///
/// Stories-sized (ruling 2026-07-10): 56pt icon-only circles — the brand logo
/// IS the chip. The active chip wears the blue ink ring; a source whose
/// connection needs you wears an orange one. No labels (labels made the row
/// scroll, ruling 2026-07-09) — All keeps its word, every source wears its
/// own brand mark.
/// On iPad (regular width) the same strip turns 90° and becomes a fixed RAIL
/// down the leading edge (2026-07-25, user ruling) — same 56pt Stories
/// circles, same avatar-then-catalogue head, same rings, flips, catch bobs and
/// accessibility. It is ONE view with an `axis`, not two: every behaviour on a
/// chip (the sliding active ring, `ChipCatchBob`, the coin flip, the "All"
/// chip reporting its frame so the capture flight knows where to land) would
/// otherwise have to be kept in step across two copies, which is exactly how
/// the old Home/Feed split drifted.
struct SourceChips: View {
    /// The full ordered label list — "All", then real sources.
    let labels: [String]
    let active: String
    /// `.horizontal` is the iPhone strip; `.vertical` is the iPad rail.
    var axis: Axis = .horizontal
    /// Opens the app catalogue (user 2026-07-17: its door moved OUT of the
    /// top-right cluster and INTO the head of this strip — "add a source"
    /// belongs with your sources).
    var onApps: () -> Void = {}
    /// Opens Settings — the avatar joined this strip too (2026-07-20,
    /// Stories-style: your own face leads, fixed, ahead of the catalogue
    /// door). The system nav bar it used to live in alone is hidden now.
    var onSettings: () -> Void = {}
    /// Pull-to-refresh spin, threaded through to the avatar exactly as it
    /// was when it lived in the toolbar.
    var refreshSpin: Int = 0
    /// The zoom anchor BOTH fixed doors grow out of — the catalogue's
    /// "appsDoor" transition and the avatar's "settingsDoor" transition
    /// share one namespace under different ids, same as before the move.
    var zoomNS: Namespace.ID? = nil
    let onTap: (String) -> Void

    @Environment(BridgeStore.self) private var bridges
    @Environment(ShellChrome.self) private var chrome
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The active chip's ink ring glides between chips instead of blinking
    /// (the old tab lozenge's grammar, motion pass 2026-07-11).
    @Namespace private var chipRingNS
    /// Last time the catalogue door actually opened — see `openApps()`.
    @State private var lastAppsOpen: TimeInterval = 0

    // Leading-dissolve geometry (user, 2026-07-19; widened 2026-07-20 when
    // the avatar joined as a SECOND fixed leading icon ahead of the
    // catalogue door): avatar sits at `s4`, 46 wide; the catalogue door
    // sits `iconGap` past it, also 46 wide. The strip runs UNDER both and
    // is masked — fully clear where an icon covers a chip, a short ramp
    // back to solid just past the second icon, then solid the rest of the
    // way. `stripInset` sets the first chip to rest right where the ramp
    // ends, so nothing is dimmed at rest. Tune `fadeRamp` for a softer/
    // tighter melt.
    private static let avatarWidth: CGFloat = 46
    private static let catalogueWidth: CGFloat = 46
    private static let iconGap: CGFloat = DS.Space.s3
    private static let catalogueTrailingEdge: CGFloat =
        DS.Space.s4 + avatarWidth + iconGap + catalogueWidth
    private static let fadeClear: CGFloat = catalogueTrailingEdge - 8
    private static let fadeRamp: CGFloat = 24
    private static let stripInset: CGFloat = fadeClear + fadeRamp

    var body: some View {
        switch axis {
        case .horizontal: horizontalStrip
        case .vertical:   verticalRail
        }
    }

    /// The iPad rail. The two fixed doors sit at the HEAD, outside the scroll,
    /// exactly as they do horizontally — but there is no leading-fade mask
    /// here, because a rail has vertical room to spare and never has to run
    /// its chips underneath the doors to earn it. Chips below scroll on their
    /// own when a corpus grows past the rail's height.
    private var verticalRail: some View {
        VStack(spacing: Self.iconGap) {
            avatarChip
            catalogueChip
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: DS.Space.s1) {
                        ForEach(labels, id: \.self) { label in
                            chip(label)
                        }
                    }
                    .padding(.vertical, DS.Space.s2)
                }
                .scrollBounceBehavior(.basedOnSize)
                .onAppear {
                    if active != "All" { proxy.scrollTo(active, anchor: .center) }
                }
                .onChange(of: active) { _, now in
                    withAnimation(DS.Motion.standard) { proxy.scrollTo(now, anchor: .center) }
                }
            }
        }
        .padding(.top, DS.Space.s2)
        .frame(width: PadLayout.railWidth)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var horizontalStrip: some View {
        // The scroll strip runs the full width, UNDER the fixed app icon; the
        // leading fade mask dissolves each chip as it reaches the icon, so chips
        // melt INTO the catalogue button instead of being sheared off at a hard
        // clip line (user, 2026-07-19 — "disappear into it, not into a hard
        // line on the source chips").
        ZStack(alignment: .leading) {
            // ScrollViewReader keeps the ACTIVE chip visible — a deep link
            // (casberi://feed/source/Zerion) can select a chip past the fold,
            // and a filter you can't see reads as no filter at all.
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Space.s3) {
                        ForEach(labels, id: \.self) { label in
                            chip(label)
                        }
                    }
                    // Clears the fixed app icon at rest; the strip slides left
                    // beneath it — and through the fade — as you scroll.
                    .padding(.leading, Self.stripInset)
                    .padding(.trailing, DS.Space.s4)
                }
                .onAppear {
                    if active != "All" { proxy.scrollTo(active, anchor: .center) }
                }
                .onChange(of: active) { _, now in
                    withAnimation(DS.Motion.standard) { proxy.scrollTo(now, anchor: .center) }
                }
            }
            .mask(alignment: .leading) { leadingFade }

            // Avatar, then the catalogue — BOTH anchor the HEAD of the strip,
            // FIXED outside the scroll (avatar joined 2026-07-20; the
            // catalogue's own fixed placement dates to user 2026-07-17):
            // neither is a filter, and both must stay in reach as the active
            // source chip re-centers below. They ride ON TOP so chips vanish
            // into them.
            HStack(spacing: Self.iconGap) {
                avatarChip
                catalogueChip
            }
            .padding(.leading, DS.Space.s4)
        }
    }

    /// The avatar door — Settings. Stories-style: your own face leads the
    /// strip (2026-07-20), the same "add a source"-adjacent fixed placement
    /// the catalogue door already had. `AvatarChip` (`TopDoors.swift`) owns
    /// the actual door/bounce/spin — this just wires this screen's params.
    @ViewBuilder private var avatarChip: some View {
        AvatarChip(onSettings: onSettings, refreshSpin: refreshSpin, zoomNS: zoomNS)
    }

    /// The leading dissolve: transparent where the app icon sits, a soft ramp
    /// back to opaque just past it, opaque across the rest of the strip.
    private var leadingFade: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: Self.fadeClear)
            LinearGradient(colors: [.clear, .black],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: Self.fadeRamp)
            Rectangle().fill(.black)
        }
    }

    /// The app-catalogue door — the same `AppsDoor` grid glyph (and its
    /// attention state) it wore in the top-right, now the strip's first chip in
    /// the neutral circle Pinned/All share. The store still zooms out of it.
    @ViewBuilder private var catalogueChip: some View {
        Button {
            // A REAL action again (2026-07-26), not the no-op the
            // highPriorityGesture below was given sole ownership of: whichever
            // recognizer wins the press, the door opens. `openApps()`
            // coalesces, so the belt and the braces can never both fire.
            openApps()
        } label: {
            ZStack {
                if let zoomNS {
                    AppsDoor().matchedTransitionSource(id: "appsDoor", in: zoomNS)
                } else {
                    AppsDoor()
                }
            }
            .frame(width: 46, height: 46)
            // Glass on the NEUTRAL chips only (2026-07-20): this strip is
            // pinned chrome the feed scrolls under, so the doors and the "All"
            // chip wear the floating material. A source chip keeps its own app
            // icon — an icon IS content, and frosting one would only muddy a
            // mark the person recognizes.
            .dsGlass(cornerRadius: 23)
            // THE DOOR IS THE CIRCLE, not the glyph inside it (user, "you
            // press it and it doesn't respond, have to press it several
            // times", 2026-07-26 — the third report on this button). A
            // `.frame()` does not make its empty space hit-testable: the only
            // rendered content in here is a 21pt SF Symbol, so the press had
            // to land in roughly a 24×21pt box in the middle of a 46pt circle
            // that looks tappable everywhere. Near-center taps worked,
            // everything else fell through to the feed — which reads exactly
            // like a flaky button. A source chip never had this because
            // `BridgeIcon` fills its whole 46pt with a real image. Gesture
            // hit-testing reads the same shape, which is why last round's
            // `highPriorityGesture` couldn't fix it: the region was the bug,
            // not the arbitration.
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        // The door's glyph fills, colors and pulses when a bridge breaks —
        // all three cues are visual, so the label has to say it too.
        .accessibilityLabel(bridges.attentionCount > 0
                            ? Text("Apps, needs attention")
                            : Text("Apps"))
        // This strip rides `.safeAreaInset(edge: .top)` on the paged feed
        // TabView (`MainSurface`) — a plain Button's own tap gesture there
        // competes with the TabView(.page)'s internal pan recognizer for the
        // first touch (Apple's documented safeAreaInset-button bug, forums
        // thread 725366) and can take several presses to win the
        // arbitration (reported 2026-07-24: "requires pressing several
        // times before opening"). `highPriorityGesture` wins immediately.
        // Kept as the belt beside the Button's own braces above — it was
        // never the whole story, but it costs nothing to keep winning.
        .highPriorityGesture(TapGesture().onEnded { openApps() })
    }

    /// One entry point for the door's two possible tap deliveries (the
    /// Button's action and the high-priority tap). `highPriorityGesture`
    /// failing the Button's own gesture is the documented behaviour, so in
    /// practice only one arrives — the 0.4s coalesce is what makes relying on
    /// that unnecessary, and keeps a double haptic impossible either way.
    private func openApps() {
        let now = Date().timeIntervalSinceReferenceDate
        guard now - lastAppsOpen > 0.4 else { return }
        lastAppsOpen = now
        DSHaptic.selection()
        onApps()
    }

    @ViewBuilder
    private func chip(_ label: String) -> some View {
        let isActive = label == active
        let broken = bridges.bridges.contains {
            $0.name == label && $0.status == .attention
        }
        Button {
            DSHaptic.selection()
            withAnimation(DS.Motion.standard) { onTap(label) }
        } label: {
            ZStack {
                switch label {
                case "All":
                    // The one WORD in a strip of fixed 46pt icon chips, so it
                    // has to live inside that circle at every text size —
                    // at accessibility sizes it grew past the glass and
                    // collided with the catalogue door beside it (measured at
                    // accessibility-extra-large, 2026-07-21). It still scales;
                    // it just stops at the circle instead of spilling over the
                    // door. The neighbouring chips are app icons, which don't
                    // scale at all, so the strip's rhythm is fixed by design.
                    Text("All").dsText(.label12)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .frame(width: 46, height: 46)
                        .clipShape(Circle())
                        .dsGlass(cornerRadius: 23)
                default:
                    BridgeIcon(name: label, size: 46, circular: true)
                }
            }
            .frame(width: 46, height: 46)
            // The identity flip (2026-07-14, user): the chip is where
            // switching sources actually happens, so it's the one true flip
            // moment — the Feed source header dropped its own animated icon
            // in favor of this one, rather than two competing for the same
            // delight. Keyed to isActive: the chip you're leaving flips away,
            // the one you're landing on flips in. A first-ever thing from
            // this source flips it too (the bloom's beat, same vocabulary).
            .coinFlip(trigger: "\(isActive)-\(chrome.bloomTicks[label] ?? 0)")
            // The catch bob — a thing landing from this source while the
            // person watches bumps its chip once, the flight's landing
            // generalized to bridge arrivals (delight 2026-07-13).
            .modifier(ChipCatchBob(label: label,
                                   arrivedChip: chrome.arrivedChip,
                                   tick: chrome.arrivedTick,
                                   reduceMotion: reduceMotion))
            .padding(2.5)
            .overlay {
                // One ring, two exclusive states: tint = active (a single ring
                // that SLIDES from the old chip to the new — selection is an
                // object traveling, not two states blinking); orange = the
                // connection needs you (health lives where you live).
                if isActive {
                    // The active ring is always tint now — the feed sits on the
                    // neutral ink page (user ruling 2026-07-18: full ink), so
                    // there's no source-hue field for a tint ring to melt into.
                    let ring = Circle().strokeBorder(DS.tint, lineWidth: 2.5)
                    if reduceMotion {
                        ring
                    } else {
                        ring.matchedGeometryEffect(id: "chipRing", in: chipRingNS)
                    }
                } else if broken {
                    // DASHED, not merely orange (2026-07-21). "Selected" and
                    // "this connection is broken" were the same 2.5pt ring in
                    // two hues — indistinguishable to anyone who doesn't
                    // separate them by color. The solid ring now belongs to
                    // selection alone.
                    Circle().strokeBorder(DS.attention,
                                          style: StrokeStyle(lineWidth: 2.5, dash: [3, 3]))
                }
            }
            .frame(width: 56, height: 56)
            // The capture flight lands on "All" — the record that shows every
            // capture in place, the same target the old Feed tab was.
            .background {
                if label == "All" {
                    GeometryReader { g in
                        Color.clear
                            .onAppear { chrome.feedTabFrame = g.frame(in: .global) }
                            .onChange(of: g.frame(in: .global)) { _, f in chrome.feedTabFrame = f }
                    }
                }
            }
            // Same law as the catalogue door above: the chip is the circle.
            // A source chip was already whole (`BridgeIcon` fills its 46pt
            // with a real image), but "All" is a 12pt word inside a 56pt
            // frame — without this its press had to land on the letters.
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        // Finger-driven, never idle: chips ease down as they leave the viewport
        // edges (Stories grammar). Under Reduce Motion only the fade remains.
        // Follows `axis` so the rail's chips ease at its TOP and BOTTOM edges,
        // which is where its own viewport ends.
        .scrollTransition(.interactive, axis: axis) { content, phase in
            content
                .scaleEffect(reduceMotion || phase.isIdentity ? 1 : 0.88)
                .opacity(phase.isIdentity ? 1 : 0.6)
        }
        .id(label)
        .accessibilityLabel(chipAccessibilityLabel(label, broken: broken))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func chipAccessibilityLabel(_ label: String, broken: Bool) -> String {
        label + (broken ? ", needs reconnecting" : "")
    }
}

/// One catch bob: the chip springs up a touch and settles when its source
/// lands a thing while the person watches. Fires only for the arrived chip,
/// never loops, and sits out under Reduce Motion.
private struct ChipCatchBob: ViewModifier {
    let label: String
    let arrivedChip: String?
    let tick: Int
    let reduceMotion: Bool
    @State private var bob = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(bob ? 1.12 : 1)
            .onChange(of: tick) { _, _ in
                guard arrivedChip == label, !reduceMotion else { return }
                withAnimation(.spring(response: 0.28, dampingFraction: 0.5)) { bob = true }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(220))
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) { bob = false }
                }
            }
    }
}
