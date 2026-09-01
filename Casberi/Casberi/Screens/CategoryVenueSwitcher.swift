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
/// The mark is a full-bleed `DS.Face.list` (36) in a `DS.Hit.min` (44) slot —
/// the same circle the face rail beneath it draws, and the touch floor as the
/// chip's own footprint (prd §541; see `chip`, which carries the whole argument
/// and the two costs). It has been 20 (a badge beside text), then 26 (§358, when
/// the words went and the mark became the chip's entire content), then 26 inside
/// a 36pt seat (§483); this doc has been corrected each time rather than left to
/// contradict the code, per `SourceChips.horizontalStrip`'s own lesson about
/// what a confidently stale note costs the next session.
///
/// Every chip keeps its `accessibilityLabel` and `dsTooltip` naming the venue,
/// which with the words gone is the ONLY naming in this control and therefore a
/// harder requirement than before (guarded in `category-fold-selftest.sh`).
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
    /// The shell's fold state (`ShellChrome.minimized`), on the SAME expression
    /// both face rails take — `chrome.minimized && !showsRail` (prd §541).
    ///
    /// **This control was the one piece of room chrome that did not compress**,
    /// and that was invisible until §541 made its mark full-bleed. `SourceChips`
    /// folds 56→48 above it and `FaceScopeRail` folds its captioned faces 36→26
    /// directly below it, so a switcher pinned at 36 sat between two controls
    /// that both shrank — which is the failure `FaceScopeRail`'s own doc names
    /// for the iPad case it declines to fold in: "it does not read as a system
    /// compressing; it reads as one control twitching."
    ///
    /// It is also the half of §541 that was nearly shipped wrong. Before §541 the
    /// switcher drew a 26pt mark, so it matched the FOLDED rail by accident and
    /// mismatched the resting one; fixing only the resting size would have moved
    /// the drift rather than removed it — 36 above 26 on every scroll in a social
    /// room, which is the same defect wearing the other state. Both states have
    /// to agree, which means this control folds on the same signal or neither
    /// does.
    var compact: Bool = false
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

    /// `DS.Face.list` (36) at rest, `.row` (26) folded — `FaceScopeRail.faceSize`'s
    /// own two rungs, spelled the same way so the mark row and the face row under
    /// it can never step apart (prd §541). The ramp's tiers, not two literals
    /// invented here.
    private var markSize: CGFloat { compact ? DS.Face.row : DS.Face.list }

    // THE SEAT'S SIZE IS SPELLED `DS.Hit.min` AT THE FRAME, not lifted into a
    // `slotSize` property, and that is a deliberate reversal made during this
    // change (prd §541). The property read better and cost real safety:
    // `accessibility-audit.py` check 3 resolves a frame to a literal or to a
    // name in `NAMED_SIZES`, so hoisting the floor into a computed property
    // made this very chip report as an unhittable button minutes after the same
    // pass had widened that check to catch it. Adding `slotSize` to
    // `NAMED_SIZES` would have cleared it by blanket-exempting a generic
    // identifier anywhere in the app — buying tidiness in one file with a hole
    // in the lint for every other.
    //
    // The check catching its own author's refactor is the check working. Say
    // the floor where the frame is.

    private func chip(_ venue: String) -> some View {
        let isOn = venue == active
        let broken = needsAttention(venue)
        return Button {
            guard !isOn else { return }
            DSHaptic.selection()
            onPick(venue)
        } label: {
            // **THE MARK IS THE CIRCLE, FULL BLEED** (prd §541, 2026-09-01,
            // user: *"should the source strips icons be larger? … smaller than
            // the silhouette rail or social avatars"* — they were, and the tap
            // targets were under the floor besides). This COMPLETES §483 rather
            // than reversing it.
            //
            // §483 pinned this chip's SEAT to `DS.Face.list` (36) so "two
            // stacked rows of circles share one outer diameter", fixing a 46pt
            // circle sitting above the rail's 36pt faces. What it left behind is
            // that the seat and the MARK are not the same circle: the mark went
            // on drawing at `row` (26) inside that 36pt seat, while the rail
            // below draws its faces at a full-bleed 36 — and once §483 also made
            // those faces solid silhouette discs, the row above was 26pt of ink
            // against 36pt of ink. Matching diameters that carry different
            // amounts of ink is the SAME optical-weight finding `DS.Face.rowCircle`
            // records for the feed's mixed columns, running the other way: the
            // frame agreed and the eye did not.
            //
            // So the mark takes `markSize` — `FaceScopeRail.faceSize`'s own two
            // rungs, folding with it rather than merely matching it at rest (see
            // `compact`, and note that matching only at rest is how this fix was
            // nearly shipped as a relocation of the same defect). This is not a
            // new treatment: it is the exact call `FaceScopeRail.face` already
            // makes for a person with no avatar (`BridgeIcon(name:size:circular:)`
            // at `faceSize`), so the two rows are now drawing the same thing at
            // the same size rather than merely being framed alike. It is also
            // what `SourceChips` has always done one tier up: a brand mark fills
            // its chip, because "an icon IS content, and frosting one would only
            // muddy a mark the person recognizes".
            //
            // **The seat becomes `DS.Hit.min` (44) and never folds, and that is
            // one change with the above rather than two.** The chip's whole slot
            // is its tap target and it was 36 — under the floor `DS.Hit.min`
            // exists to stop controls drifting beneath, on a control that is the
            // ONLY way out of a folded category seat. It was invisible to
            // `accessibility-audit.py` check 3 because that check triggers on
            // `Image(systemName:)` and this button's label is a brand mark; §541
            // widens it, so this class cannot ship again.
            //
            // Growing the seat is also what KEEPS the cue split below working: a
            // full-bleed mark covers a fill drawn behind it, and the annulus
            // between mark and seat is where the selection tint now reads — 4pt
            // at rest against the 5pt it had at 36/26, and 9pt folded. The fill
            // did not have to become a ring, which matters, because a ring is
            // what attention already is (see the overlay).
            // **THE SEAT DOES NOT FOLD WITH THE MARK.** The slot IS the tap
            // target, so a fold that returned space by shrinking it would be
            // `dsTapTarget`'s ruling ("keeps the DRAWN size and grows only the
            // target") run backwards — the exact defect this section fixes.
            // `FaceScopeRail` makes the same split, flooring its own captionless
            // slot "on a control whose whole slot is the tap target". So the fold
            // buys WIDTH per chip and no height, the honest trade for a bar that
            // is one row tall either way, and the annulus selection reads in
            // grows 4pt → 9pt as a free consequence.
            BridgeIcon(name: venue, size: markSize, circular: true)
                .frame(width: DS.Hit.min, height: DS.Hit.min)
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
            // that is in fact the likeliest way to find yourself looking at it,
            // since the folded chip's dashed ring is what sent you here.
            //
            // **THIS IS WHY §541 GREW THE SEAT INSTEAD OF MAKING SELECTION A
            // RING.** Going full-bleed hides a fill drawn behind the mark, and
            // the obvious repair — promote selection to the strip's own solid
            // tint ring — was proposed and REFUSED on this paragraph: attention
            // is already a ring, so both cues would land on one 2–3pt band of
            // pixels and the active-and-broken seat could show only one of them.
            // Concentric rings were measured on paper and are not available
            // either: a 36pt mark in a 44pt slot leaves 1.5pt of radius between
            // a hugging ring and a slot-edge ring, so two 2pt strokes touch. The
            // fill stays a fill and simply moves outward into the annulus.
            //
            // The cost, stated: at rest `DS.fillFaint` is ~3–4% alpha, so the
            // resting row is bare 36pt marks matching the rail exactly, and only
            // the ACTIVE chip paints a 44pt tinted halo. That is a state on one
            // chip, not a second circle size in the resting rhythm — but it is a
            // 4pt halo where it used to be 5pt, and whether it still reads as
            // selected is a DEVICE question this pass could not answer.
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
