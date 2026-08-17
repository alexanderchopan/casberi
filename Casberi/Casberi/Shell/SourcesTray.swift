import SwiftUI

/// Every source at once (2026-07-31, user) — the long-press half of the agent
/// bar's two gestures: tap raises the agent, hold opens your places.
///
/// It exists because the strip can only ever show FOUR. Measured on a 402pt
/// phone: the two fixed doors plus the leading fade eat 135pt before the first
/// chip, and each chip is a 68pt pitch — four and a peek, out of a corpus that
/// routinely runs past twenty. Everything past the fourth cost a horizontal
/// scroll through icons with no names on them.
///
/// The two shapes considered and rejected first, so they aren't re-proposed:
/// a VERTICAL rail on the phone shows ~8 instead of 4 but costs 88pt of
/// permanent width (22% of the screen, against 8% of an iPad's — which is why
/// `SourceChips.verticalRail` is right THERE and wrong here), and it points the
/// wrong way besides: the feed is a `TabView(.page)` over these very labels, so
/// the strip is the map of a HORIZONTAL swipe. Stacked full-width rows are the
/// retired Home board wearing new clothes — a screen between you and the
/// content. This costs zero permanent chrome and shows all of them, not eight.
///
/// It carries the one thing the strip gave up: NAMES. Labels were dropped from
/// the chips on 2026-07-09 because they made the row scroll — true of a row,
/// free in a grid, so the icon-only strip finally has somewhere to send anyone
/// who doesn't recognise a mark.
///
/// # The tray is a PANEL OF GLASS, and the marks float on it (2026-08-16, user)
///
/// The grid has been grouped by `BridgeCatalog.categories` since 2026-08-06.
/// From 2026-08-10 to 2026-08-16 each category was a filled opaque card, which
/// was the right answer to "it still looks like just a bunch of icons" — a
/// filled container is SEEN rather than read — on an OPAQUE sheet. The sheet is
/// glass now (`DSTray(glass:)`), and on glass an opaque slab is the one thing
/// the material cannot do; see the "Where the card used to be" note below for
/// what it cost, measured. Seven treatments were compared as rendered pixels in
/// `prototype/sources-tray-glass-v1.html` — the marks floating directly on the
/// panel won.
///
/// **The grouping is carried by the eyebrow's INK — and, since later the same
/// day, by its SIZE.** With no container the eyebrow is the only thing doing
/// that job, so it first moved `textTertiary` → `textPrimary` at the same size
/// (`prototype/sources-tray-eyebrow-v1.html`), with 12pt refused on the theory
/// that ink AND size makes the grid read as eight lists. The user looked at
/// the shipped tray and overturned that: `subhead13` bold now (2026-08-16,
/// "make the eyebrows bold and larger") — on the more transparent panel the
/// 11pt ink alone was not holding the groups, and a heading that has to carry
/// structure by itself is allowed to look like a heading. The one consequence
/// kept from the first ruling: the eyebrow still sits well under the 22pt
/// title, so the tray reads as one surface with sections, not eight lists.
///
/// **It is still NOT tinted** (ruled 2026-08-11, re-asked and re-ruled
/// 2026-08-16). One of the original two reasons expired with the card — tinting
/// lost to the card, and there is no card — but the load-bearing one did not:
/// `DS.tint` means SELECTION in this tray (the active chip's ring), so eight
/// blue category names put selection's colour on eight unselected things. It
/// would also add a ninth hue to a tray that is already twenty saturated brand
/// marks. Colour is identity, state, or magnitude (brief §8); a heading is none
/// of the three.
///
/// **A group is still placed WHOLE, and rows alone are packed.** The card is
/// gone but its layout rule outlives it, for the reason that was never about the
/// fill: a group running past column five arrives on the next row as chips with
/// no name above them, and you have to look up and diagonally back to learn what
/// they are. There is no continuation, therefore no nameless run, therefore
/// nothing to explain.
///
/// # The grouping is drawn by PROXIMITY now, not only named (2026-08-16, user)
///
/// "It kinda still looks funky and like rows aren't even" — and it did, for a
/// nameable reason: the grid was five EQUAL slots, so the gap between two
/// groups sharing a row was byte-identical to the gap between two chips inside
/// a group. Proximity is the strongest grouping signal the eye has, and it
/// said "one row of five icons" while the eyebrows said "two groups" — a gap
/// is SEEN where a word is READ, so the gap won, the eyebrows looked like they
/// floated at random columns, and a four-chip row's phantom fifth slot read as
/// a hole. The deleted card used to carry the boundary; nothing had replaced
/// it. Four treatments were compared as rendered pixels in
/// `prototype/sources-tray-partition-v1.html`; whitespace won — it is the only
/// cue that adds zero chrome to a tray a same-day ruling just de-chromed.
///
/// So the grid is CLUSTERS now: chips at a fixed `slotWidth` pitch, the gap
/// inside a group stays `s2`, and the gap between two groups in a row is a
/// flexible `groupGapMin…groupGapMax` — wide enough that each group reads as a
/// discrete object before any word is read (cover the eyebrows and the
/// grouping survives). The bounds are why no `GeometryReader` is needed: a
/// full five-slot row with three blocks has exactly 2×20pt to give, a
/// two-block one 32pt, and the flexible spacer lands both without measuring
/// anything; a trailing `Spacer` absorbs what's left, so a short row's ragged
/// right edge reads as clusters ending rather than slots failing. The spacing
/// hierarchy this buys is the one grouping wants: ~26pt icon-to-icon inside a
/// group, ~40+pt between groups, ~80pt between rows (the eyebrow band inside
/// it) — and it fixes the axis imbalance the rowGap note below measured, since
/// the old grid was airier ACROSS (~31pt) than DOWN (26pt) while the cluster
/// pitch lands both at ~26. The cost, stated: chips in different rows no
/// longer share exact column verticals. That alignment was part of the
/// problem — it is what made the tray read as one table wearing misplaced
/// headings — so it is given up on purpose.
///
/// # The packing order: CATALOG WHEN IT'S FREE, biggest first when it pays
///
/// The bin packing itself lives in `SourceRowPacking` (see its doc for the
/// 39,237-corpus measurement). Until 2026-08-16 the order was pure biggest
/// first — optimal on height, but its cost was order churn in the one tray
/// whose job is teaching positions: connecting a single source could reorder
/// every group between opens. The same measurement bounds that cost: catalog
/// order TIES the optimum on ~92% of corpora, so both orders are packed and
/// catalog wins every tie. Most corpora keep the stable catalog order the
/// tray taught before the sort existed; the sort now runs only when it
/// genuinely saves a row. The strip's frozen order still survives inside
/// every group, exactly as `ShellChrome.chipOrder` hands it over.
///
/// **Alphabetising was considered and refused** (2026-08-06, still standing).
/// It would hold the height, but this tray is the STRIP's map — its whole job
/// is teaching the positions of an icon-only row that has no labels, and an
/// alphabetical tray teaches positions the strip does not have.
///
/// **"All" has no cell** (user, 2026-08-06). It belongs to no category, so in a
/// grouped grid it could only ever be an ungrouped orphan taking a row of its
/// own. It remains the first chip in the strip behind this tray, so the
/// everything-room is one dismiss and one tap away. Known cost, stated rather
/// than hidden: from INSIDE the tray there is now no way back to All.
struct SourcesTray: View {
    /// The strip's own ordered labels — "All" first, then sources.
    let labels: [String]
    let active: String
    let onPick: (String) -> Void

    @Environment(BridgeStore.self) private var bridges
    @Environment(\.dismiss) private var dismiss

    /// Mirrors `SourceRowPacking.columns` — the view needs it to wrap an
    /// oversized group's chips, and a drift guard in
    /// `source-packing-selftest.sh` ties the two.
    fileprivate static let columns = SourceRowPacking.columns
    /// The chip's icon; the slot around it leaves room for the ring, exactly
    /// as `SourceChips` does at its own scale.
    private static let iconSize: CGFloat = 44
    private static let chipSize: CGFloat = 52
    /// The cluster pitch and the group gap are COMPUTED per row from the
    /// row's own shape and the width it is given — `SourceRowPacking
    /// .rowMetrics`, which is where the reasoning and the harness live. A
    /// fixed pair of constants overflows the phone on a row of small
    /// categories; see that function's doc.
    /// Two lines of `label12` plus its own leading — the same fixed name box
    /// `AppsScreen.appTile` uses, so a one-word and a two-word name sit on the
    /// same baseline instead of the row jittering per cell.
    private static let nameHeight: CGFloat = 28
    /// One line of `subhead13` (its own `lineHeight`), and the gap under it.
    ///
    /// 15 → 21 on 2026-08-16 (user: "make the eyebrows bold and larger") —
    /// the eyebrow stepped `label11` semibold → `subhead13` bold. This
    /// OVERTURNS the same-day ruling below that refused a size bump: that
    /// ruling weighed ink-plus-size against the grid reading as eight lists,
    /// and the user looked at the shipped tray and ruled the other way — with
    /// no card and a more transparent panel, the ink alone was not holding.
    private static let overlineHeight: CGFloat = 21
    private static let overlineGap: CGFloat = 5
    /// Aligns the category name's first character with the left edge of the
    /// chip ring beneath it — the chip is `chipSize` centred in a `slotWidth`
    /// slot, so this is half that difference (was 7 when the slot was a
    /// flexible fifth). Deliberately a constant rather than a measured inset:
    /// it is a nudge, not a layout.
    private static let overlineInset: CGFloat = 5
    /// A group's own top and bottom air — the card's padding, kept after the
    /// card (2026-08-16). Tuned against the resting cap, not chosen: every
    /// point here is a point closer to a scroll the packing exists to prevent
    /// (the running four-row total lives on `rowGap`'s doc). 10/8 was measured
    /// in `prototype/sources-tray-glass-v2.html` and refused — it spent cap
    /// budget on air inside the group, where `rowGap` buys separation between
    /// them, which is the axis that was actually short.
    private static let cardPadTop: CGFloat = 8
    private static let cardPadBottom: CGFloat = 6

    /// One packed row: whole blocks totalling at most `columns` slots.
    ///
    /// The packing itself lives in `SourceRowPacking` — Foundation-only, so
    /// `scripts/source-packing-selftest.sh` can compile it whole and check it
    /// against an exact optimiser. This wrapper adds only what a view needs: a
    /// stable identity for `ForEach`.
    fileprivate struct PackedRow: Identifiable {
        let id: Int
        let blocks: [SourceRowPacking.Block]
        var chipRows: Int { blocks.map(\.chipRows).max() ?? 1 }
    }

    /// Group the labels by catalog category, then pack whole categories into
    /// rows — biggest first, ties by catalog position.
    ///
    /// Pure and self-contained on purpose: the whole layout is decided here and
    /// the body just draws it, so the packing can be reasoned about (and one
    /// day tested against the DP that proved it optimal) without mounting a
    /// view.
    ///
    /// A source the catalog can't place keeps its cell rather than vanishing:
    /// unplaceable labels collect in a trailing "Other" block. A tray that
    /// silently dropped a source would be the worst possible failure here,
    /// since this is the one screen that claims to show every source.
    fileprivate var packed: [PackedRow] {
        // "All" is the strip's, not the grid's — see the type doc.
        let sources = labels.filter { $0 != "All" }

        var byCategory: [String: [String]] = [:]
        var unplaced: [String] = []
        for label in sources {
            if let category = BridgeCatalog.category(forSource: label) {
                byCategory[category, default: []].append(label)
            } else {
                unplaced.append(label)
            }
        }

        // Catalog order first, so the size sort has a stable tiebreak; inside a
        // category the strip's frozen order, which `sources` already carries.
        var catalog: [SourceRowPacking.Block] = BridgeCatalog.categories
            .compactMap { category in
                guard let members = byCategory[category.name], !members.isEmpty else { return nil }
                return SourceRowPacking.Block(name: category.name, members: members)
            }
        if !unplaced.isEmpty {
            catalog.append(SourceRowPacking.Block(name: "Other", members: unplaced))
        }

        return SourceRowPacking.pack(catalog)
            .enumerated()
            .map { PackedRow(id: $0.offset, blocks: $0.element) }
    }

    /// A row's height, which varies: an oversized category wraps to two chip
    /// rows.
    fileprivate static func rowHeight(chipRows: Int) -> CGFloat {
        let unit = chipSize + DS.Space.s1 + nameHeight
        return cardPadTop + overlineHeight + overlineGap
            + CGFloat(chipRows) * unit
            + CGFloat(max(0, chipRows - 1)) * DS.Space.s2
            + cardPadBottom
    }

    /// Between rows. Tighter than the 2026-08-06 bare grid's `s4` because each
    /// group carries its own padding (`cardPadTop`/`Bottom`).
    ///
    /// **s2 → s3 on 2026-08-16** (user: "perhaps we can space the icons
    /// better"), and the interesting part is that the grid was never uniformly
    /// tight — it was tight in ONE axis. Measured on a 402pt phone: the content
    /// is 366pt over five flexible slots, so a 44pt mark sits in a ~65pt slot
    /// and the clear gap between two marks is **~31pt**. Vertically the same
    /// grid paid 8 + 6 of group padding and 10 between rows, i.e. 24pt from a
    /// name row to the next eyebrow — noticeably less than the air across, on a
    /// layout whose whole job is to read as groups.
    ///
    /// s3 is the ceiling here, not a first guess: the next variant
    /// (`prototype/sources-tray-glass-v2.html`, rail 2) also raised the group
    /// pads to 10/8 and looked marginally better, and it puts a four-row tray at
    /// **626pt against a 620 `restingCap`** — so it buys a little air by
    /// snapping a whole category off the resting height, which is the opposite
    /// of the trade. Loosening the chip's own icon→name gap was refused for a
    /// different reason: it detaches a name from its mark and reads as a caption
    /// rather than a label, while costing height in every chip row.
    ///
    /// Budget, since every point here is spent against that cap: four rows went
    /// **598 → 610pt** with this change, then **634** when the eyebrow stepped
    /// to `subhead13` the same day — which is what moved `restingCap` to 660.
    /// The row count that fits at rest is unchanged throughout: four rows rest,
    /// five (772) scroll.
    private static let rowGap: CGFloat = DS.Space.s3

    /// DSTray's own chrome: top clearance, the title, its gap, bottom pad.
    private static let chromeHeight: CGFloat = DS.Space.s6 + 30 + DS.Space.s4 + DS.Space.s6
    /// 620 → 660 on 2026-08-16, alongside the eyebrow's step to `subhead13`:
    /// four rows went 610 → 634pt, and a cap of 620 would have answered the
    /// user's "make the eyebrows larger" by snapping a whole category off the
    /// resting height. 660 keeps the same semantics on real corpora — anything
    /// from four rows (634) up to five (772) still rests at four — and a
    /// 660pt sheet leaves over 200pt of feed above it on the smallest phone
    /// this app targets.
    private static let restingCap: CGFloat = 660

    /// Natural height, capped — the cap SNAPS DOWN to a whole number of rows.
    /// A raw `min(…, cap)` cuts wherever the arithmetic lands, and the worst
    /// cut is the likeliest one: through a group, between its name and the
    /// chips it names. Measured on a 25-source corpus the tray rested showing
    /// three category names with NOTHING underneath them — which reads as a
    /// rendering bug, not as "there is more below". Snapping means the last
    /// visible group is always whole and the next fully hidden; the grabber
    /// and the `.large` detent carry the "there's more" signal.
    ///
    /// Also what decides whether the active source rests visible — see
    /// `revealActive`.
    private func restingRows(_ rows: [PackedRow]) -> Int {
        guard Self.height(of: rows.count, rows: rows) > Self.restingCap else { return rows.count }
        var fit = 1
        while fit < rows.count, Self.height(of: fit + 1, rows: rows) <= Self.restingCap { fit += 1 }
        return fit
    }

    private static func height(of n: Int, rows: [PackedRow]) -> CGFloat {
        guard n > 0 else { return chromeHeight }
        let body = rows.prefix(n).reduce(CGFloat.zero) { $0 + rowHeight(chipRows: $1.chipRows) }
        return body + CGFloat(n - 1) * rowGap + chromeHeight
    }

    /// Past the cap the grid scrolls and `.large` is draggable — a 40-source
    /// corpus must not clip silently (the "Worth a look" tray's 2026-07-24
    /// lesson).
    private var trayHeight: CGFloat {
        let rows = packed
        return Self.height(of: restingRows(rows), rows: rows)
    }

    var body: some View {
        DSTray(title: String(localized: "Your feeds"),
               height: trayHeight,
               glass: true,
               detents: [.height(trayHeight), .large]) {
            ScrollViewReader { proxy in
                ScrollView {
                    let rows = packed
                    if rows.isEmpty {
                        // Reachable on a brand-new install: the hold gesture works
                        // before anything is connected, and with All in the strip
                        // rather than the grid this would otherwise be a blank
                        // sheet with a title.
                        Text("Connect an app and it lands here.")
                            .dsText(.subhead13)
                            .foregroundStyle(DS.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(alignment: .leading, spacing: Self.rowGap) {
                            ForEach(rows) { row in
                                rowView(row).id(row.id)
                            }
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .onAppear { revealActive(proxy) }
            }
        }
    }

    /// The tray is the strip's map, and on a big corpus the snap-down cap can
    /// rest the one cell wearing the selection ring below the fold — you open
    /// "where am I?" and the answer is hidden with nothing saying so
    /// (2026-08-16). If the active source's row isn't among the resting rows,
    /// jump the scroll to it on mount. A JUMP, not an animation: the content
    /// simply appears already positioned, so there is no appear-triggered
    /// motion for Reduce Motion to honour.
    private func revealActive(_ proxy: ScrollViewProxy) {
        let rows = packed
        guard let index = rows.firstIndex(where: { row in
            row.blocks.contains { $0.members.contains(active) }
        }), index >= restingRows(rows) else { return }
        proxy.scrollTo(rows[index].id, anchor: .center)
    }

    /// One packed row of clusters. Blocks keep their packed order, separated by
    /// the computed group gap; a trailing spacer absorbs whatever the row
    /// doesn't use, so everything left-packs.
    ///
    /// The `GeometryReader` is a real layout measurement, unlike the one
    /// `overlineInset` refuses — the gap cannot be a constant without
    /// overflowing narrow phones (see `SourceRowPacking.rowMetrics`). It is
    /// safe here because the row's height is already a computed constant, so
    /// the reader's fill-all-space behaviour is bounded on both axes.
    private func rowView(_ row: PackedRow) -> some View {
        let slots = row.blocks.reduce(0) { $0 + $1.span }
        return GeometryReader { geo in
            let metrics = SourceRowPacking.rowMetrics(slots: slots,
                                                      blocks: row.blocks.count,
                                                      intraGap: Double(DS.Space.s2),
                                                      width: Double(geo.size.width))
            HStack(alignment: .top, spacing: CGFloat(metrics.gap)) {
                ForEach(Array(row.blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block, slot: CGFloat(metrics.slot))
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.top, Self.cardPadTop)
        .frame(height: Self.rowHeight(chipRows: row.chipRows), alignment: .top)
    }

    /// One category: its name, then its chips at the row's cluster pitch. An
    /// oversized category wraps inside its own cluster — packed alone in its
    /// row, so the wrap never collides with a neighbour.
    private func blockView(_ block: SourceRowPacking.Block, slot: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            nameBand(block, slot: slot)
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                ForEach(Array(stride(from: 0, to: block.members.count, by: Self.columns)),
                        id: \.self) { start in
                    HStack(spacing: DS.Space.s2) {
                        ForEach(block.members[start..<min(start + Self.columns, block.members.count)],
                                id: \.self) { label in
                            cell(label: label, category: block.name, slot: slot)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Where the card used to be

    /// Nothing. The category CARD was deleted on 2026-08-16 (user ruling) and
    /// this note is here so the deletion is a decision rather than a gap.
    ///
    /// From 2026-08-10 a category was a filled, raised, opaque card — the fix
    /// for "it still looks like just a bunch of icons", where a filled
    /// container is SEEN rather than read. That reasoning is intact and the
    /// card still lost, because the sheet under it changed: on a panel of glass
    /// an opaque slab is the one thing the material cannot do. It masked the
    /// blur over ~85% of the tray (so the glass survived only in the gutters,
    /// arriving as coloured stains from whatever row was behind), and worse,
    /// the sheet's local value now VARIES with the feed, so the same raised
    /// card read raised over a dark row and recessed over a bright one — a lift
    /// that is a property of somebody's feed is not a lift.
    ///
    /// The grouping is carried by the eyebrow's INK instead (see `nameBand`).
    /// Four treatments were compared as rendered pixels in
    /// `prototype/sources-tray-eyebrow-v1.html`; a carved recess in the glass
    /// (`t-carve` in `sources-tray-glass-v1.html`) was the runner-up and stays
    /// available if the ink alone stops holding at a larger corpus.

    // MARK: - Names and chips

    /// The category's name, sitting on its own cluster.
    ///
    /// Sized to the cluster's first chip row rather than left free: a name
    /// wider than its chips would widen the whole block and squeeze the group
    /// gap the layout exists to protect. The scale floor absorbs the loss —
    /// names never truncate (prd §201, the app-tile rule), and the longest
    /// catalog name over a single chip ("Shopping") lands around 0.93, which
    /// the eye doesn't register as a different size.
    private func nameBand(_ block: SourceRowPacking.Block, slot: CGFloat) -> some View {
        Text(block.name)
            .dsText(.subhead13)
            .fontWeight(.bold)
            // textPrimary since 2026-08-16 — this ink and the cluster gap ARE
            // the grouping. See the type doc for why not tint.
            .foregroundStyle(DS.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.leading, Self.overlineInset)
            .frame(width: CGFloat(block.span) * slot
                       + CGFloat(max(0, block.span - 1)) * DS.Space.s2,
                   height: Self.overlineHeight,
                   alignment: .bottomLeading)
            .padding(.bottom, Self.overlineGap)
            // The name sits on the cluster it names; VoiceOver reads each
            // chip's own category on the cell instead, so this is decoration
            // to it.
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func cell(label: String, category: String, slot: CGFloat) -> some View {
        let isActive = label == active
        // Same read as the strip's: one ring, two exclusive states. Solid tint
        // is selection; DASHED orange is "this connection needs you" (the
        // 2026-07-21 ruling — the two must not be the same ring in two hues).
        //
        // Resolved through the catalog rather than compared to the label
        // directly: a source name is not always its seat's name ("Privacy
        // Pools" against the "0xBow Privacy Pools" seat), and a bare `==` meant
        // that family could never show the ring at all. Falls back to the label
        // for a source the catalog has never heard of, which is what every
        // exactly-named seat already resolved to — so this changes nothing for
        // the seats that already worked.
        let seat = BridgeCatalog.offer(forSource: label)?.name ?? label
        let broken = bridges.bridges.contains {
            $0.name == seat && $0.status == .attention
        }
        Button {
            DSHaptic.selection()
            onPick(label)
            dismiss()
        } label: {
            VStack(spacing: DS.Space.s1) {
                ZStack {
                    BridgeIcon(name: label, size: Self.iconSize, circular: true)
                }
                .frame(width: Self.iconSize, height: Self.iconSize)
                .padding(2.5)
                .overlay {
                    if isActive {
                        Circle().strokeBorder(DS.tint, lineWidth: 2.5)
                    } else if broken {
                        Circle().strokeBorder(DS.attention,
                                              style: StrokeStyle(lineWidth: 2.5, dash: [3, 3]))
                    }
                }
                .frame(width: Self.chipSize, height: Self.chipSize)

                Text(label)
                    .dsText(.label12)
                    .fontWeight(isActive ? .semibold : .medium)
                    .foregroundStyle(isActive ? DS.textPrimary : DS.textSecondary)
                    .multilineTextAlignment(.center)
                    // Names never truncate (prd §201) — the app-tile rule,
                    // which is the whole reason this grid can carry names the
                    // strip couldn't.
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .frame(height: Self.nameHeight, alignment: .top)
            }
            // The row's cluster pitch — see `SourceRowPacking.rowMetrics`. An
            // explicit width rather than a flexible one because the whole
            // layout rests on the gap INSIDE a group being constant while the
            // gap BETWEEN groups carries the boundary.
            .frame(width: slot)
            .contentShape(Rectangle())
            .dsHover()
        }
        .buttonStyle(PressSpring())
        // The grouping is drawn, so it must also be SPOKEN — a name band
        // hidden from VoiceOver would otherwise take the category away from
        // the one reader who can't see the layout that carries it.
        .accessibilityLabel(label + ", \(category)"
            + (broken ? String(localized: ", needs reconnecting") : ""))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
