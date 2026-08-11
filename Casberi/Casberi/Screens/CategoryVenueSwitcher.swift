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
/// **It carries the strip's attention state down to the seat** (2026-08-11) —
/// see `needsAttention`. This is the half that makes the folded chip's dashed
/// ring mean something specific rather than merely "something in here".
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
    /// For the attention state below — the strip's dashed ring, resolved to a
    /// seat one tier down.
    @Environment(BridgeStore.self) private var bridges

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

    /// The dashed attention ring, one tier down from the strip (2026-08-11).
    ///
    /// **The category chip's ring had nowhere to resolve to.** A folded chip
    /// lights its dashed ring when ANY seat behind it needs reconnecting
    /// (`SourceChips.attentionSeats`) — prd §351's own text promises that the
    /// switcher is then "one tap from naming which seat it is", and this
    /// control drew no attention state whatsoever, so the tap arrived at a row
    /// of identical capsules. VoiceOver was the only place the members were
    /// even named. The seat wears the same dashed orange here, so the drill-down
    /// actually ends somewhere.
    ///
    /// Resolved through `offer(forSource:)`, exactly as the strip and the
    /// Sources Tray do — the three must agree about which seats are in trouble,
    /// and the alias family (Privacy Pools against 0xBow Privacy Pools) is
    /// precisely where a raw name comparison silently answers no.
    private func needsAttention(_ venue: String) -> Bool {
        let seat = BridgeCatalog.offer(forSource: venue)?.name ?? venue
        return bridges.bridges.contains { $0.name == seat && $0.status == .attention }
    }

    private func chip(_ venue: String) -> some View {
        let isOn = venue == active
        let broken = needsAttention(venue)
        return Button {
            guard !isOn else { return }
            DSHaptic.selection()
            onPick(venue)
        } label: {
            HStack(spacing: 5) {
                BridgeIcon(name: venue, size: DS.Face.badge, circular: true)
                Text(CategoryFold.venueLabel(venue))
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
            // Unlike the strip, selection and attention are NOT exclusive here,
            // and that is a property of this control rather than a departure
            // from the 2026-07-21 ruling: selection is a FILL in this capsule
            // and a RING up in the strip, so the two cues never compete for the
            // same pixels. The seat you are standing in can be the broken one —
            // that is in fact the likeliest way to find yourself looking at it.
            .overlay {
                if broken {
                    Capsule(style: .continuous)
                        .strokeBorder(DS.attention,
                                      style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .dsHover()
        // The dashed ring is the only cue that a seat needs you, and it is
        // visual — so the label has to say it too, in the same words the strip
        // and the tray use.
        .accessibilityLabel(broken
                            ? String(localized: "\(venue), needs reconnecting")
                            : venue)
        .dsTooltip(broken
                   ? String(localized: "\(venue), needs reconnecting")
                   : venue)
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
