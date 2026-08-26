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
/// **It scrolls, and its venues are MARKS ONLY — no words (user ruling
/// 2026-08-11: "for the rooms why not just use ONLY the icon and not the name
/// with it. it would save space. the user already has the source tray with
/// names if they want to see it and they chose these apps so they know the
/// icons").** This overturns the first cut, which paired each mark with its
/// name on the theory that a row of marks reproduces the strip's own hunt
/// problem one layer down.
///
/// What makes the reversal right rather than a coin flip is that the two rows
/// are not the same problem. The STRIP is categories — synthetic groupings with
/// no brand of their own, which is exactly why §351 turned them into words. This
/// row is SEATS: every one is an app the person went and connected, wearing the
/// mark that app is known by. Recognition is already paid for, and the ceiling
/// here is ~7 members where the strip's is the whole catalog.
///
/// **The old ruling's one concrete objection was CHECKED, and it is false today**
/// — it claimed "two market seats are literally the same letter in a circle",
/// which was the whole evidential basis for keeping the words. Rendered on the
/// sim (2026-08-11, light theme, Markets room): all seven seats fit one row with
/// no scrolling and every mark is distinct — a green wordmark (Kalshi), a blue
/// geometric (Polymarket), a blue S (Stocktwits), a purple gecko
/// (GeckoTerminal), a ring (Circle x402), a sailboat (OpenSea), a green chart
/// (Tokens). Whatever pair that sentence described has since been re-marked. Had
/// it still been true the fix would have been THAT PAIR's mark, not every word
/// coming back.
///
/// The mark is 26pt (`DS.Mark.row`), up from the 20pt badge it wore beside text,
/// since it is now the chip's entire content; every chip keeps its
/// `accessibilityLabel` and `dsTooltip` naming the venue, which with the words
/// gone is the ONLY naming in this control and therefore a harder requirement
/// than before (guarded in `category-fold-selftest.sh`).
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
                // The selected mark's fill TRAVELS between seats on
                // `matchedGeometryEffect` — see `chip`, and note that this
                // container no longer has anything to do with it. It was added
                // to host a `glassEffectID` (which is inert outside a
                // `GlassEffectContainer`), and §360 removed that decoration
                // because it was equally inert INSIDE one, on a fill carrying no
                // `glassEffect` of its own. With no glass children left there is
                // nothing here to merge; it is kept only as the seam for when
                // these chips take real glass, and is safe to delete otherwise.
                // Stated rather than left implying it is load-bearing — this
                // file's neighbour just cost a session exactly that mistake.
                DSGlassContainer(spacing: 2) {
                    HStack(spacing: 2) {
                        ForEach(venues, id: \.self) { venue in
                            chip(venue)
                        }
                    }
                }
                .padding(4)
            }
            .scrollBounceBehavior(.basedOnSize)
            // **Clipped to the capsule, or a scrolling mark hangs OUTSIDE the
            // bar** (user, 2026-08-11: "is this an error how the next icon sits
            // outside the bar?" — it was). `dsGlass` paints a capsule-shaped
            // material behind the scroll view but does not bound its CONTENT, so
            // at the rounded ends a mark scrolled halfway out kept drawing past
            // the glass onto the page. Invisible until §358 made these marks
            // icon-only and dense enough that one is nearly always mid-exit.
            .clipShape(Capsule(style: .continuous))
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
            // `DS.Face.row`, not `DS.Mark.row` — the same 26, but a CIRCULAR
            // mark is sized off the face ramp (`face-ramp-audit.py` enforces it,
            // and caught this the first time it was written the other way).
            // **TWO ROWS OF CIRCLES STACKED SHARE ONE OUTER DIAMETER** (prd
            // §483, 2026-08-26, user: *"why don't we use the same size circles
            // for the source rooms and the account avatars, isn't it
            // disjointed"* — it was).
            //
            // The `DS.Face` ramp sizes the FACE by what it sits beside, and
            // says nothing about a mark row sitting directly above a face row —
            // which is what the wallet room became when the account rail came
            // down out of the pinned chrome. This chip was a 26pt mark in `s2`
            // padding, so it presented a **46pt** circle directly above the
            // rail's **36pt** faces: two adjacent rows of circles, ten points
            // apart, for no reason a reader could name.
            //
            // The seat is pinned to `DS.Face.list` (36) — the tier every avatar
            // in the app already wears — and the MARK stays at `row` (26), so
            // nothing gets harder to read. A frame rather than a smaller
            // padding, because the number that has to match is the outer one,
            // and deriving it from padding means it drifts the day the padding
            // is tuned for something else.
            BridgeIcon(name: venue, size: DS.Face.row, circular: true)
                .frame(width: DS.Face.list, height: DS.Face.list)
            .background {
                ZStack {
                    Capsule(style: .continuous).fill(DS.fillFaint)
                    if isOn {
                        let fill = Capsule(style: .continuous).fill(DS.tint.opacity(0.18))
                        // **`matchedGeometryEffect` on EVERY version, including
                        // 26 (prd §360, 2026-08-11).** This branched to
                        // `glassEffectID` on iOS 26 and that branch was inert:
                        // the decoration does nothing on a shape carrying no
                        // `glassEffect`, and this fill is a flat 18% tint, not a
                        // blob. So the shipped path had no travel at all while
                        // the pre-26 fallback did — the selection teleported on
                        // exactly the OS everyone runs, and looked correct in
                        // every still frame.
                        //
                        // It is the same swap `WordChipFill` made one tier up
                        // and reverted after frame-stepping at 60fps ("swapping
                        // `glassEffectID` in for `matchedGeometryEffect`
                        // silently deleted the travel it replaced"); this
                        // control was left on the losing side of that finding.
                        // Reduce Motion keeps the undecorated fill.
                        if reduceMotion {
                            fill
                        } else {
                            fill.matchedGeometryEffect(id: "venueActiveFill", in: ns)
                        }
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
