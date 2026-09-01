import SwiftUI

/// THE ROOM CHASSIS — the geometry Wallet and Vibenet share (prd §491).
///
/// Both rooms are the same machine: one fixed box holding a figure, an account
/// rail under it, a scope switcher under that, then content. Both already share
/// the PARTS — `FaceScopeRail` draws the faces in both, `DSSectionSwitcher` the
/// chips — and until this file they shared none of the SPACING between them.
///
/// **That is why they drifted, and why measuring was the wrong fix.** Wallet
/// lays its chassis out as `List` sections with `listRowInsets`; Vibenet as a
/// `VStack` with padding, inheriting `stackedRoom`'s `s6` card separation. Two
/// hand-tuned stacks cannot stay equal — reported three times in one session
/// ("the toggle bar is in the wrong place", then "they are NOT the same"), and
/// each time the fix was another measurement rather than a shared number. A
/// room that has to be re-measured to match is a room that will drift again the
/// next time either side is touched.
///
/// So the numbers live here, once, and both call sites read them. Nothing about
/// how each room COMPOSES its chassis changes — Wallet keeps its sections and
/// Vibenet its stack, because those are load-bearing for other reasons — but
/// the distances between the three pieces can no longer disagree.
///
/// **What this deliberately does NOT own**: the figures themselves, the rail's
/// own internals, and the switcher's. Those are already one component each. It
/// owns exactly the gaps, which were the only thing with two owners.
enum DSRoomChassis {

    /// The fixed box every scope's figure draws into.
    ///
    /// FIXED, never fitted, and spelled rather than measured — a measured
    /// height settles the bar a frame LATE, which is the same walk arriving
    /// slower. The box holds the crown OR the scope's figure, never both
    /// stacked: Wallet's Positions scope opens "Deposited $61,000" in place of
    /// the wallet total, and a room that draws its crown AND a figure is a room
    /// whose bar sits a third of a screen lower than the one it copied.
    static let visualSlot: CGFloat = 210

    // **THE THREE GAPS WERE TIGHTENED ONE RUNG (prd §495, user: "should we
    // move the silouhette rail and the toggle rail higher on both vibenet and
    // wallet to let more of the lists show" → "just a tiny bit higher… so
    // maybe one more row of lists shows").**
    //
    // MEASURED FIRST, because the answer to "one more row" is a number: the
    // chrome above the first row is 535pt of an 874pt screen — 61% — and a
    // two-line event row is ~90pt. So a whole extra row costs ~85pt, and the
    // only place that much slack exists is `visualSlot`, which every scope's
    // drawing was just made to fill.
    //
    // What is FREE is the air: these three gaps plus the switcher's own
    // vertical padding come to ~22pt with nothing behind them. That is a
    // quarter of a row, and it reads as more than it measures because four
    // separate gaps close at once. The slot is deliberately untouched.
    //
    // Worth knowing when reading any screenshot of this: the 48pt demo banner
    // is not in a real install, so a shipping room already shows half a row
    // more than the demo does.

    /// Figure → account rail.
    static let railGap: CGFloat = DS.Space.s1

    /// Account rail → scope switcher.
    ///
    /// Tighter than `railGap` on purpose: the rail and the switcher are two
    /// controls that scope the same room, and they read as a pair rather than
    /// as two unrelated strips.
    ///
    /// It stays EQUAL to `railGap` rather than smaller: at `s1` the two are
    /// already as close as the ramp goes, and the pairing it exists to state
    /// is carried by both being the tightest gap on the page while
    /// `contentGap` below them is the widest.
    static let switcherGap: CGFloat = DS.Space.s1

    /// Scope switcher → the first thing it scopes.
    ///
    /// The widest of the three, and the only one that is a SEPARATION rather
    /// than a grouping: everything above it is chrome about the room, and
    /// everything below is the room.
    ///
    /// It keeps its rung while the two above drop one, so the separation it
    /// states gets STRONGER rather than weaker as the group tightens — which
    /// is the whole point of tightening a group rather than the page.
    static let contentGap: CGFloat = DS.Space.s2

    /// The page inset the chassis and its figures share.
    static let inset: CGFloat = DS.Space.s4

    // MARK: - The fused rail (prd §547, 2026-09-01)

    /// **THE RAIL AND THE SWITCHER ARE ONE OBJECT NOW** (user, 2026-09-01:
    /// *"what if we made the silouheet row and the scope rail seem like more of
    /// a component together"*).
    ///
    /// `railGap`/`switcherGap` above are what remains of the old answer: two
    /// strips, tuned closer and closer together in the hope that proximity
    /// would read as pairing. It never did, and measuring was the wrong fix for
    /// the same reason it was the wrong fix for the chassis itself — the two
    /// controls disagreed on all three things that make a component read as
    /// one, and no gap can settle that. They had different BLEED (the rail full
    /// bleed at `leading: 0`, the switcher inset 18), different SHAPE (circles
    /// with captions against a glass capsule of pills), and different
    /// SELECTION (a 0.7 recession plus a semibold caption against a travelling
    /// tint capsule) — stacked directly on top of each other, four points
    /// apart.
    ///
    /// So they share a container, an inset and one selection shape. What each
    /// deck DOES is untouched: the rail still scopes by address, the switcher
    /// still scopes by reading, and both keep their own scroll.
    ///
    /// **The padding is `s1` and that is a borrowed number, not a new one** —
    /// `DSSectionSwitcher` has always drawn `.padding(4)` inside its own glass
    /// capsule, so the slab is packed exactly as the control it absorbs was.
    /// It also happens to be what keeps the fused object at the height the two
    /// separate strips came to, which is the honest result stated plainly:
    /// this ruling fuses, it does not shrink. How much chrome stands above the
    /// first row is a different question and stays open.
    static let slabPadding: CGFloat = DS.Space.s1

    /// Rail deck → switcher deck. Equal to the padding around them on purpose:
    /// a container whose inner gap matches its own margin reads as one evenly
    /// packed object, where a wider inner gap reads as two things sharing a box.
    static let slabDeckGap: CGFloat = DS.Space.s1

    /// The slab's own corner — `DS.Radius.widget`, because that is the rung for
    /// an object of this size and this is not a new kind of thing.
    static let slabRadius: CGFloat = DS.Radius.widget

    /// **The one selection shape, in BOTH decks** — a face slot and a scope chip
    /// are filled by the same rounded rect at the same radius, so "this is the
    /// pick" is one mark in a control that used to carry two.
    ///
    /// CONCENTRIC, never typed: `DS.Radius.nested` is what keeps the fill's arc
    /// parallel to the slab's own the whole way round, and it is why this reads
    /// as inset rather than as a second box that happens to overlap. It also
    /// tracks the platform for free — Mac's tighter `s1`… does not differ, but
    /// the derivation costs nothing and the day either term is re-tuned the two
    /// stay concentric by construction.
    static var slabInnerRadius: CGFloat {
        DS.Radius.nested(parent: slabRadius, inset: slabPadding)
    }

    /// **THE INSET INSIDE THE ROOM CARD'S OWN ROOT** — the one that makes a
    /// card's content land on the same leading as a feed ROW (prd §495).
    ///
    /// Derived, never typed, and the derivation is the whole point. A shaped
    /// feed row leads at `DS.Space.s4 + DS.Space.s3` (27pt), and the room card
    /// already carries `DS.Space.s4` at its root — so `s3` is what closes the
    /// gap, and if either term is ever re-tuned the two stay equal by
    /// construction rather than by somebody remembering.
    ///
    /// **This corrects a fix made in the wrong direction earlier the same
    /// night.** The card's figures had been applying `inset` INSIDE that root
    /// (30pt total) while `VibenetAccountDetail` applied nothing (15pt), and
    /// removing the double took the figures to 15 — which aligned them with
    /// the detail and pulled BOTH 12pt away from the rows they sit above. The
    /// doubling was real; 15 was not the number to land on. Measured, not
    /// eyeballed: the pixel scan was too noisy to settle it and the row's own
    /// `listRowInsets` was exact.
    static let contentInset: CGFloat = DS.Space.s3
}

/// THE SLOT ITSELF — one definition of the box every room scope draws into
/// (prd §495, user: *"Wallet and Vibenet should use same template"*, then
/// *"one template"*).
///
/// **Shared COMPONENTS were never a shared TEMPLATE, and that is what kept
/// breaking.** `DSRoomChassis` owned four distances and `DSSectionSwitcher`
/// owned a control; neither owned the COMPOSITION. So Wallet built its
/// chassis from `List` sections with `listRowInsets` and vibenet from a
/// `VStack` with negative paddings, and inside vibenet alone five scopes
/// filled the same fixed box five different ways — one drawing its own
/// headline, one passing it to the chassis, one passing nil and faking the
/// settings-gear clearance with 44pt of padding. The box never moved, so
/// every screenshot said the toggle bar was where it should be; what moved
/// was the drawing INSIDE the box, which reshapes the whole region above the
/// bar and is indistinguishable from the bar moving. Reported three times.
///
/// This is the box: fixed height, one horizontal inset, top-aligned, clipped,
/// and a headline row that is RESERVED whether or not a headline is drawn.
///
/// **Reserving the row unconditionally is the load-bearing part.** It makes
/// every scope's drawing begin at the same y, and it earns the settings
/// gear's clearance for free — that control overlays this corner, and a
/// headline-height gap is exactly what it needs, which is why the 44pt hack
/// that used to buy it could be deleted rather than moved.
struct DSRoomSlot<Figure: View>: View {
    /// The scope's own headline, or nil where the drawing names itself. The
    /// ROW is reserved either way — see the type's own note.
    let headline: String?
    /// Whether to reserve the headline row at all.
    ///
    /// **True for a figure that draws below a heading; FALSE for one that IS
    /// the heading** (prd §495). Both rooms' Home scopes lead with the crown —
    /// a `price48` figure that occupies exactly the role a headline plays —
    /// so reserving a blank row above it pushes the crown 30pt down the screen
    /// and misaligns it with every other scope's headline, which is the
    /// opposite of what reserving the row is for.
    ///
    /// The guarantee the row exists to give is that every scope's FIRST PIXEL
    /// lands at the same y. A crown honours that by standing in the row, not
    /// by standing under it.
    ///
    /// **THE RULE: reserve the row only where the CHASSIS draws the
    /// headline.** Vibenet's figures pass theirs in, so the chassis owns that
    /// line and must keep room for it. Wallet's name themselves inside their
    /// own drawing, so reserving a row above them leaves a blank band AND
    /// takes 42pt from a figure sized for the whole slot — which clipped the
    /// holdings treemap and the NFT quad along their bottom edge the first
    /// time this shipped, because the quad derives its cell size from
    /// `DSRoomChassis.visualSlot` directly rather than from what it is
    /// offered.
    var reservesHeadline: Bool = true
    @ViewBuilder let figure: () -> Figure

    /// `stat24`'s line height, spelled from the ramp rather than measured:
    /// a measured height settles the frame a frame late, which is the same
    /// walk arriving slower (`visualSlot`'s own reasoning).
    static var headlineRow: CGFloat { 30 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if reservesHeadline {
                headlineRowView
            }
            figure()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, DSRoomChassis.contentInset)
        .frame(minHeight: DSRoomChassis.visualSlot,
               maxHeight: DSRoomChassis.visualSlot,
               alignment: .top)
        .clipped()
    }

    @ViewBuilder
    private var headlineRowView: some View {
            Group {
                if let headline {
                    Text(headline)
                        .dsText(.stat24)
                        .foregroundStyle(DS.textPrimary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    // `Color.clear`, not an empty `Text`: the reserved height
                    // must be the ramp's line height rather than whatever an
                    // empty string happens to measure.
                    Color.clear
                }
            }
            .frame(height: Self.headlineRow, alignment: .leading)
            .padding(.bottom, DS.Space.s3)
    }
}
