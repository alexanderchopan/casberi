import SwiftUI

/// The dock's shared metrics (prd §591, 2026-09-03).
///
/// The source strip sits against the bottom edge now and the agent bar stands
/// in its leading corner — but they are two views on two layers, not one
/// object: the strip is a `.safeAreaInset` inside `MainSurface`'s
/// `NavigationStack`, and the bar is hosted on `RootShell`'s own ZStack so it
/// survives into Settings, a bridge form and every pushed room, which that
/// inset does not. Both need the same number and neither can read it off the
/// other, so it lives here.
///
/// **Spelled once because the failure is asymmetric and neither half is
/// visible from the other.** Too small and the leading source scrolls under
/// the bar and becomes a room you can see and cannot tap — which is the exact
/// objection that took the bar off the top of the sources panel on 2026-08-16.
/// Too large and the dock opens with a hole in it that reads as a missing
/// chip. A constant in each file would drift the moment either one moved.
enum DSDock {
    /// **THE FOLD IS CONTINUOUS (2026-09-05).** Every metric below has a
    /// `fold:` form — the dock's position between rest (0) and folded (1),
    /// straight off `ShellChrome.fold` — and the `minimized:` form is its two
    /// endpoints, kept because those endpoints are where the numbers are
    /// spelled and where the self-test reads them. The fold forms interpolate
    /// between the endpoints and nothing else, so the two can never disagree
    /// at either end.
    static func lerp(_ rest: CGFloat, _ folded: CGFloat, _ fold: CGFloat) -> CGFloat {
        rest + (folded - rest) * min(1, max(0, fold))
    }

    /// The bar's drawn size — **the same as a chip's own mark** (user,
    /// 2026-09-04: "why not just make it the same size as the All chip next to
    /// it").
    ///
    /// It was a flat 44, which is `DS.Hit.min` and was the right number while
    /// the bar was a floating pill in a corner answering to nothing. In the
    /// rail it is the first item in a row of marks, and a 44 among 46s reads as
    /// a slightly shrunken one — the kind of near-miss that looks like a bug
    /// rather than a distinction. It also had to FOLD, since the chips shrink
    /// 46→40 on scroll and a bar that did not would grow relatively larger
    /// exactly when the row got tighter.
    ///
    /// Mirrors `SourceChips.iconSize`, which cannot be read from here (that
    /// value is private to a view in another module-level file); the dock
    /// self-test pins the two together.
    static func agentSize(minimized: Bool) -> CGFloat { minimized ? 40 : 46 }
    static func agentSize(fold: CGFloat) -> CGFloat {
        lerp(agentSize(minimized: false), agentSize(minimized: true), fold)
    }

    /// **THE LEADING SEAT HOLDS ONE DOOR — YOUR FACE (2026-09-11, prd §700).**
    /// §697 seated two marks here, the face and the catalogue grid, and the
    /// grid moved the same day to the TAIL of the strip (user: "have the app
    /// icon not be fixed on the tab bar. only make the avatar be fixed"): the
    /// face is the one thing in the dock that is about you; the catalogue is
    /// a place, and the places scroll. So the cluster is one mark wide again
    /// — still spelled as a WIDTH rather than folded into `agentSeat`,
    /// because the strip's melt, the bar's own frame and the self-test all
    /// read it and cannot see each other; a seat that still counted two
    /// marks would leave 54pt of air between the face and "All".
    static func clusterWidth(fold: CGFloat) -> CGFloat { agentSize(fold: fold) }
    static func clusterWidth(minimized: Bool) -> CGFloat { agentSize(minimized: minimized) }

    /// The chip's own FRAME, which is bigger than its mark — it carries the
    /// active ring's room. Centring the bar on the row means centring on this,
    /// not on the mark.
    static func chipFrame(minimized: Bool) -> CGFloat { minimized ? 48 : 56 }
    static func chipFrame(fold: CGFloat) -> CGFloat {
        lerp(chipFrame(minimized: false), chipFrame(minimized: true), fold)
    }

    /// How much taller the chip under a POINTER stands
    /// than its neighbours at rest — the Mac dock's magnification, as a share
    /// of the chip (2026-09-09). Read by the strip's wave
    /// (`SourceChips.wave(for:)`, pointer only since prd §662h); the caption that once named the lifted
    /// chip is deleted (prd §662b), so nothing else keys on it.
    static let scrubLift: CGFloat = 0.4

    /// The air between the bar's trailing edge and the first chip.
    ///
    /// `s2` rather than the strip's own `chipGap`: this gap separates two
    /// DIFFERENT objects (a glass pill and a run of marks) where the chip gap
    /// separates peers, and a seam that matches the pitch inside the run reads
    /// as the bar being the first chip — which it deliberately is not, since
    /// tapping it does not change the room.
    static let seam: CGFloat = DS.Space.s2

    /// Where the bar's leading edge sits, measured from the window.
    ///
    /// **`slabInset + railLead`, not `slabInset` (§591d).** The bar and the glass
    /// bar behind it were both inset by `DS.Space.s4` and therefore landed on
    /// the SAME line — measured on the simulator at slab 18.0pt against pill
    /// 18.3pt, so the octopus sat flush against the rail's edge with no air at
    /// all (user: "the octopus still touches the slab edge"). Insetting it by the rail's own
    /// leading air gives the bar the same seat every chip inside the rail gets,
    /// which is what it is: the rail's first item, not something laid on top of
    /// its border.
    static let clusterInset: CGFloat = slabInset + railLead

    /// Where the bar's trailing edge sits, measured from the window — what the
    /// strip's melt is aligned against so chips dissolve UNDER the bar rather
    /// than beside it.
    ///
    /// **The first cut counted the width and the seam and NOTHING ELSE, and it
    /// shipped an overlap** — measured on the simulator at 9pt of the "All"
    /// chip sitting under the bar's glass. The reasoning was that the cluster's
    /// inset and the strip's own cancel; they do not, because the chips are
    /// inside a `ScrollView` whose leading padding is the melt's ramp rather
    /// than a margin. Spelled from the window edge outward instead, which is
    /// the only frame of reference both sides share.
    static func agentSeat(minimized: Bool) -> CGFloat {
        clusterInset + clusterWidth(minimized: minimized) + seam
    }
    static func agentSeat(fold: CGFloat) -> CGFloat {
        clusterInset + clusterWidth(fold: fold) + seam
    }

    /// How far the bar sits off the bottom edge so its centre lands on the
    /// chips' centre.
    ///
    /// **The bar and the chips are the same distance off the bottom and are
    /// still not aligned, which is why this exists** (user, 2026-09-03: "the
    /// octopus and the category chips need to be aligned. right now octopus is
    /// lower"). Both wear the strip's bottom padding, but a chip is 56pt tall
    /// and the bar is 44 — so bottom-aligning them puts the bar's centre 6pt
    /// below the row it is supposed to be the first seat of. The gap is
    /// exactly half the height difference, and it CHANGES when the strip folds
    /// on scroll (the chip goes 56 → 48 and the strip's own bottom padding
    /// `s2` → `s1`), so a constant would be right at rest and wrong the moment
    /// anybody scrolled.
    ///
    /// Both halves of the sum are the strip's own numbers, restated here
    /// because `RootShell` hosts the bar and cannot see inside `SourceChips`.
    /// They are the one thing in this file that must be re-derived if the chip
    /// ramp moves; the drift guard in `dock-selftest.sh` pins them together.
    /// The air inside the dock's glass slab, above and below the chips (§591d).
    /// Named here rather than spelled at the strip, because the bar's own
    /// alignment is measured from it and the two must move together — adding
    /// this padding without updating the inset is exactly what dropped the bar
    /// 5pt below the slab's bottom edge on its first run (user: "the octopus is
    /// falling off the dock and doesn't share the same middle axis as the other
    /// chips").
    static let slabPad: CGFloat = 5

    /// How far the glass bar is inset from the window's edges (§591d).
    ///
    /// The bar needs edges to be separate FROM — full bleed is what made it
    /// invisible — and the CHIPS SCROLL INSIDE IT, so this is also the scroll
    /// viewport's own leading offset and therefore a term in the melt's
    /// arithmetic. `SourceChips` subtracts it from `agentSeat` to convert the
    /// bar's window-space trailing edge into viewport space; spelled here so
    /// the inset and that conversion cannot drift.
    static let slabInset: CGFloat = DS.Space.s4

    /// The air INSIDE the rail's leading edge, before its first item.
    ///
    /// **`s2`, the same as every gap in the row, and separate from `slabPad`
    /// for a measured reason** (user, 2026-09-04: "should we make the chips on
    /// the nav bar closer to each other? then the octopus wouldn't be so close
    /// to the rail edge?"). Measured first, which changed the answer: the chip
    /// gap and the seam after the octopus are BOTH `s2` already, so the chips
    /// were not loose — the rail's own edge padding was the only number out of
    /// step, at `slabPad`'s 5 against everything else's 10. Tightening the
    /// chips would not have moved the octopus at all, since its distance from
    /// the edge is this padding and nothing else.
    ///
    /// It cannot simply BE `slabPad`, because that value is also the rail's
    /// vertical air and raising it to 10 would make the whole bar 10pt taller
    /// to fix a horizontal gap. One axis, one number.
    static let railLead: CGFloat = DS.Space.s2

    /// How far the strip's chips sit off the band's bottom edge.
    static func chipBottomInset(minimized: Bool) -> CGFloat {
        slabPad + (minimized ? DS.Space.s1 : DS.Space.s2)
    }
    static func chipBottomInset(fold: CGFloat) -> CGFloat {
        lerp(chipBottomInset(minimized: false), chipBottomInset(minimized: true), fold)
    }

    /// The air under the glass slab — the strip's bottom padding, the part of
    /// `chipBottomInset` that is not the slab's own vertical pad.
    static func slabBottomInset(fold: CGFloat) -> CGFloat {
        chipBottomInset(fold: fold) - slabPad
    }

    static func agentBottomInset(minimized: Bool) -> CGFloat {
        // Centre on centre, not edge on edge: the bar's mark and the chip's
        // mark are the same size now, but the chip's FRAME is larger (it
        // carries the ring's room), so bottom-aligning still leaves the bar
        // half the difference too low — and that difference changes with the
        // fold.
        return chipBottomInset(minimized: minimized)
            + (chipFrame(minimized: minimized) - agentSize(minimized: minimized)) / 2
    }
    static func agentBottomInset(fold: CGFloat) -> CGFloat {
        chipBottomInset(fold: fold) + (chipFrame(fold: fold) - agentSize(fold: fold)) / 2
    }

    /// The slab's bottom air, following the fold — a modifier of its own so
    /// the ONLY body that re-evaluates on a scroll tick is this one, not
    /// `MainSurface`'s (see `ShellChrome.fold`).
    struct SlabInset: ViewModifier {
        @Environment(ShellChrome.self) private var chrome
        func body(content: Content) -> some View {
            content.padding(.bottom, DSDock.slabBottomInset(fold: chrome.fold))
        }
    }

    /// The bar's seat off the bottom edge, following the fold — the same
    /// reason, for `RootShell`'s body.
    struct SeatInset: ViewModifier {
        @Environment(ShellChrome.self) private var chrome
        func body(content: Content) -> some View {
            content.padding(.bottom, DSDock.agentBottomInset(fold: chrome.fold))
        }
    }

    /// **What a PUSHED screen leaves clear at its bottom edge, so nothing
    /// comes to REST under the seat** (user report, 2026-09-19: *"the back
    /// button is directly over disconnect for me… I'm afraid I'll
    /// accidentally disconnect"*, iOS 27 / iPhone 17 Pro Max, on a bridge's
    /// account page).
    ///
    /// The seat survives into every pushed screen on purpose — it is the face
    /// on the root and the back door above it (prd §767, §796) — and it is
    /// hosted on `RootShell`'s ZStack, which is OUTSIDE the stack's safe
    /// area. So a pushed screen reserved nothing for it: the root feed pays
    /// for the whole band with `MainSurface`'s bottom `safeAreaInset`, and
    /// that inset is applied inside the stack, where a push covers it. Three
    /// screens had noticed and each spelled its own `ShellMetrics.bottomInset`
    /// by hand; every other pushed screen — every account page among them —
    /// ended its last row under the seat's glass.
    ///
    /// That is the honesty law's own failure mode from the other side (§83):
    /// not a dead control, but a live one hidden under a floating one, and the
    /// row underneath here is `Disconnect`. Scrolling UNDER the seat is the
    /// whole point of the glass and is untouched — this is about where the
    /// content stops.
    ///
    /// **Derived from the seat, never a literal**, for the reason the rest of
    /// this file exists: `agentSize` moved 44 → 46 once already, and a
    /// hand-kept clearance drifts the moment it moves again.
    ///
    /// **Pinned to the UNFOLDED seat rather than following `fold`, and that is
    /// prd §674 rather than laziness.** This is a scroll view's bottom
    /// content inset; a height that tracked the fold would re-inset the scroll
    /// view on every scroll tick, which is the bouncing screen §674 fixed. The
    /// unfolded seat is the larger of the two, so the folded one clears too.
    static var seatClearance: CGFloat {
        agentBottomInset(minimized: false) + agentSize(minimized: false) + DS.Space.s3
    }
}

extension View {
    /// Leaves `DSDock.seatClearance` at the bottom edge — every pushed
    /// screen, one line, applied where the push is resolved rather than
    /// remembered screen by screen (see `DSDock.seatClearance`).
    func dsSeatClearance() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: DSDock.seatClearance)
        }
    }

    /// **THE KEYBOARD COVERS THE DOCK; IT NEVER LIFTS IT** (prd §865,
    /// 2026-09-21, user: *"you can barely see what you're entering"*, on an
    /// agent room's Chat page — **amended 2026-09-21 after the first run on a
    /// simulator, which the original was written without**).
    ///
    /// The dock was not drawn over the entry field by a stacking mistake. It
    /// was LIFTED onto it: SwiftUI inflates the bottom safe area for the
    /// keyboard, every layer in the window rises by default, and this app
    /// opted out nowhere.
    ///
    /// **This is the SEAT's half, and it is the half a modifier can carry.**
    /// The seat cluster is a layer of `RootShell`'s `ZStack(alignment:
    /// .bottom)`, so two things have to be true for it to stay put, and the
    /// first shipped without the second:
    ///
    ///   * it must not inherit the keyboard's safe area — `ignoresSafeArea`;
    ///   * it must be laid out against the TRUE bottom — the full-height
    ///     frame. Without it the ZStack's own bounds have already been
    ///     compressed by the keyboard and bottom-alignment places the cluster
    ///     at the compressed bottom, which is the top of the keyboard. **A
    ///     child opting out does not undo a parent whose bounds already
    ///     shrank**, which is why the first version of this changed nothing
    ///     measurable on any of the four fields it was written for.
    ///
    /// The frame adds no background and no `contentShape`, so the empty column
    /// above the seat takes no touch — the feed under it scrolls and its rows
    /// tap as before.
    ///
    /// **`.bottom` alone, and `.container` is deliberately not touched**: the
    /// scroll view above must still rise, or the field this exists to reveal
    /// goes under the keyboard instead of under the dock. Measured, not
    /// assumed — applied one layer wider, at the band's `.safeAreaInset`
    /// mount, it dropped the chat entry's baseline under the keyboard.
    ///
    /// **The BAND's half is not here and cannot be**: that layer is a
    /// `safeAreaInset`, whose reserved HEIGHT is what has to yield, so it
    /// collapses on `ShellChrome.keyboardUp` instead. Both halves still end up
    /// invisible under a keyboard, which is the whole ruling; see
    /// `ShellChrome.keyboardUp` for why one fact could not serve both.
    func dsStaysUnderKeyboard() -> some View {
        frame(maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}
