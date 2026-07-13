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
    let onTap: (String) -> Void

    @Environment(BridgeStore.self) private var bridges
    @Environment(ShellChrome.self) private var chrome
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The active chip's ink ring glides between chips instead of blinking
    /// (the old tab lozenge's grammar, motion pass 2026-07-11).
    @Namespace private var chipRingNS

    var body: some View {
        // ScrollViewReader keeps the ACTIVE chip visible — a deep link
        // (casberi://feed/source/Zerion) can select a chip past the fold, and a
        // filter you can't see reads as no filter at all.
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s3) {
                    ForEach(labels, id: \.self) { label in
                        chip(label)
                    }
                }
                .padding(.horizontal, DS.Space.s4)
            }
            .onAppear {
                if active != "All" { proxy.scrollTo(active, anchor: .center) }
            }
            .onChange(of: active) { _, now in
                withAnimation(DS.Motion.standard) { proxy.scrollTo(now, anchor: .center) }
            }
        }
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
            // the one you're landing on flips in.
            .coinFlip(trigger: isActive)
            .padding(2.5)
            .overlay {
                // One ring, two exclusive states: tint = active (a single ring
                // that SLIDES from the old chip to the new — selection is an
                // object traveling, not two states blinking); orange = the
                // connection needs you (health lives where you live).
                if isActive {
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
