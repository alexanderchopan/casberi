import SwiftUI

/// The folded Markets room's one control (2026-08-10) — see `MarketsRoom`.
///
/// `PredictionVenueSwitcher`'s shape, widened from two venues to every present
/// market seat: glass capsule, a selection fill traveling on matched geometry,
/// brand mark beside each name. Two things differ, both forced by there being
/// up to seven scopes instead of three.
///
/// **It scrolls, and it names its venues in words.** A row of seven marks is
/// the strip's own hunt problem reproduced one layer down, and market seats are
/// the worst marks in the catalog to hunt through — several are a letter in a
/// circle and two of them are the same letter. The mark stays as recognition;
/// the word is what you read.
///
/// **It centers the active scope on appear**, the `SourceChips` rule: a
/// selection you cannot see reads as no selection, and with seven scopes the
/// one you are standing in can easily start off-screen.
///
/// No "All" scope, deliberately. A merged list is the one thing this aggregate
/// must not offer — a token's 24h percent, a stock's session percent and a
/// market's probability points do not convert, so a single ranked list across
/// them would be this app's first invented number. Cross-venue comparison
/// survives where it is real: two prediction venues pricing the SAME question
/// draw each other's bar on the card itself (`PredictionBrowseSection`'s twin).
struct MarketsVenueSwitcher: View {
    /// Present market seats, in catalog order (`ShellChrome.categoryVenues["Markets"]`).
    let venues: [String]
    /// The seat currently showing — a real source, always.
    let active: String
    let onPick: (String) -> Void

    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(venues, id: \.self) { venue in
                        chip(venue)
                    }
                }
                .padding(4)
            }
            .scrollBounceBehavior(.basedOnSize)
            .dsGlass(cornerRadius: 999)
            .onAppear { proxy.scrollTo(active, anchor: .center) }
            .onChange(of: active) { _, now in
                withAnimation(DS.Motion.standard) { proxy.scrollTo(now, anchor: .center) }
            }
        }
        // The capsule sizes to its content up to the width available, so a
        // two-venue fold draws a short capsule rather than a full-width bar
        // with five empty inches in it.
        .frame(maxWidth: .infinity, alignment: .leading)
        // NO container `accessibilityLabel` here, deliberately. A label on a
        // view that is not itself an accessibility element either does nothing
        // or propagates down and makes every venue button announce the same
        // word instead of its brand — and neither existing switcher in this app
        // carries one. Each chip already names itself and reports `.isSelected`,
        // which is the whole content of this control.
    }

    private func chip(_ venue: String) -> some View {
        let isOn = venue == active
        return Button {
            guard !isOn else { return }
            DSHaptic.selection()
            onPick(venue)
        } label: {
            HStack(spacing: 5) {
                BridgeIcon(name: venue, size: 14, circular: true)
                Text(venue)
                    .dsText(.subhead13)
                    .fontWeight(isOn ? .semibold : .regular)
                    .foregroundStyle(isOn ? DS.textPrimary : DS.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, DS.Space.s3)
            .padding(.vertical, DS.Space.s2)
            .background {
                ZStack {
                    Capsule(style: .continuous).fill(DS.fillFaint)
                    if isOn {
                        Capsule(style: .continuous).fill(DS.tint.opacity(0.18))
                            .matchedGeometryEffect(id: "marketsVenueSelection", in: ns)
                    }
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .dsHover()
        // The source strip's own grammar, one tier down — the same edge-ease
        // `walletSwitcherChip` took on 2026-08-04. Under Reduce Motion only
        // the fade remains.
        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
            content
                .scaleEffect(reduceMotion || phase.isIdentity ? 1 : 0.9)
                .opacity(phase.isIdentity ? 1 : 0.6)
        }
        .id(venue)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
