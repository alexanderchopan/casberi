import SwiftUI

/// The shell's one navigation strip (2026-07-13, drastic restructure): the app
/// is a single scrolling surface, and this chip row IS how you move through it.
/// The tab bar is gone — Pinned leads (your curated board), then All (the whole
/// feed), then every source most-recent-first. Tapping a chip swaps the surface
/// under a fixed header, so the strip never scrolls out of reach the way Feed's
/// old in-list chip row did.
///
/// Stories-sized (ruling 2026-07-10): 56pt icon-only circles — the brand logo
/// IS the chip. The active chip wears the blue ink ring; a source whose
/// connection needs you wears an orange one. No labels (labels made the row
/// scroll, ruling 2026-07-09) — Pinned wears a pin glyph, All keeps its word.
struct SourceChips: View {
    /// The full ordered label list — "Pinned", "All", then real sources.
    let labels: [String]
    let active: String
    /// Opens the app catalogue (user 2026-07-17: its door moved OUT of the
    /// top-right cluster and INTO the head of this strip — "add a source"
    /// belongs with your sources).
    var onApps: () -> Void = {}
    /// The zoom anchor the catalogue grows out of — the store still grows from
    /// its own door, that door just lives here now.
    var zoomNS: Namespace.ID? = nil
    let onTap: (String) -> Void

    @Environment(BridgeStore.self) private var bridges
    @Environment(ShellChrome.self) private var chrome
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The active chip's ink ring glides between chips instead of blinking
    /// (the old tab lozenge's grammar, motion pass 2026-07-11).
    @Namespace private var chipRingNS

    // Leading-dissolve geometry (user, 2026-07-19): the app icon sits at `s4`
    // and is 46 wide, so its right edge lands at 62. The strip runs UNDER it and
    // is masked — fully clear where the icon covers a chip, a short ramp back to
    // solid just past the icon, then solid the rest of the way. `stripInset` sets
    // the first chip to rest right where the ramp ends, so nothing is dimmed at
    // rest. Tune `fadeRamp` for a softer/tighter melt.
    private static let fadeClear: CGFloat = DS.Space.s4 + 46 - 8
    private static let fadeRamp: CGFloat = 24
    private static let stripInset: CGFloat = fadeClear + fadeRamp

    var body: some View {
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

            // The catalogue anchors the HEAD of the strip, FIXED outside the
            // scroll (user 2026-07-17): it's an action, not a filter, and it
            // must stay in reach as the active source chip re-centers below.
            // It rides ON TOP so chips vanish into it.
            catalogueChip
                .padding(.leading, DS.Space.s4)
        }
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
            DSHaptic.selection()
            onApps()
        } label: {
            ZStack {
                Circle().fill(DS.gray100)
                if let zoomNS {
                    AppsDoor().matchedTransitionSource(id: "appsDoor", in: zoomNS)
                } else {
                    AppsDoor()
                }
            }
            .frame(width: 46, height: 46)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Apps")
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
                case "Pinned":
                    // Your curated board — the literal gesture we ask for, so
                    // it wears the literal glyph (user, 2026-07-13).
                    Circle().fill(DS.gray100)
                    Image(systemName: "pin.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(DS.textPrimary)
                case "All":
                    Circle().fill(DS.gray100)
                    Text("All").dsText(.label12)
                        .foregroundStyle(DS.textPrimary)
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
                    Circle().strokeBorder(DS.attention, lineWidth: 2.5)
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
        }
        .buttonStyle(.plain)
        // Finger-driven, never idle: chips ease down as they leave the viewport
        // edges (Stories grammar). Under Reduce Motion only the fade remains.
        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
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
