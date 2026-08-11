import SwiftUI

/// Every folded category room's one control (prd §351, 2026-08-11 —
/// generalizes what was `MarketsVenueSwitcher`, built for Markets alone on
/// 2026-08-10; renamed rather than wrapped because nothing inside this file
/// was ever Markets-specific — only its name and the one call site were).
///
/// `PredictionVenueSwitcher`'s shape, widened from two venues to every present
/// member of a folded category: glass capsule, a selection fill traveling on
/// matched geometry, brand mark beside each name. Two things differ, both
/// forced by there being up to seven scopes instead of three.
///
/// **It scrolls, and it names its venues in words.** A row of seven marks is
/// the strip's own hunt problem reproduced one layer down, and several
/// catalog marks are the worst possible icons to hunt through on their own
/// (two market seats are literally the same letter in a circle). The mark
/// stays as recognition; the word is what you read.
///
/// **It centers the active scope on appear**, the `SourceChips` rule: a
/// selection you cannot see reads as no selection, and with seven scopes the
/// one you are standing in can easily start off-screen.
///
/// No "All" scope, deliberately, and this generalizes past Markets rather
/// than being Markets' own reasoning: a merged list across a folded
/// category's members is not this control's job for ANY category — Markets'
/// probability points and a stock's session percent don't convert, and
/// neither do a Peer fill's token amount and a Privacy Pools deposit's. Where
/// a merged reading is real it lives on the room itself (Wallet's own balance
/// composes across its riders; two prediction venues pricing the SAME
/// question draw each other's bar via `PredictionBrowseSection`'s twin) —
/// never invented here.
struct CategoryVenueSwitcher: View {
    /// Present members of one folded category, in catalog order
    /// (`ShellChrome.categoryVenues[category]`).
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
