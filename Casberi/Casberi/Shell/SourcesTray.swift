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
/// **The grouping is carried by the eyebrow's INK.** With no container it is the
/// only thing left doing that job, so it moved `textTertiary` → `textPrimary` at
/// the same size and weight (`prototype/sources-tray-eyebrow-v1.html`, four
/// treatments). Two consequences accepted knowingly: the label now sits brighter
/// than the chip NAMES it labels (survivable — the saturated marks take the
/// first glance regardless, and the names are support), and 12pt was refused
/// because ink alone stays subordinate to the 22pt title while ink AND size
/// makes the grid read as eight lists rather than one tray.
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
/// # The packing rule is BIGGEST FIRST, and that is measured
///
/// Placing whole categories into five-slot rows is bin packing, so the order
/// they are offered in decides the row count. Three rules were compared against
/// the exact optimum (subset DP) over **39,237 random corpora** — 3–12
/// categories, up to 45 sources:
///
/// - **biggest first: 0 losses.** It tied the exact optimum every single time.
/// - catalog order: worse on **7.76%**, by up to **two rows** — 236pt here,
///   which is the difference between resting and scrolling.
///
/// So the whole optimisation is `sorted(by: count)` and the DP was thrown away:
/// it never once won, and it would have cost a scrambled order to run. Do not
/// "improve" this into a smarter packer without re-running that comparison —
/// there is no room above it to win.
///
/// The cost, stated rather than hidden: **group order is size order, not
/// catalog order.** That is a smaller loss than it sounds, because the tray's
/// order was never the STRIP's either (the strip is recency-and-taps, the tray
/// was already catalog), so nothing the tray teaches gets untaught; the strip's
/// frozen order still survives inside every card, exactly as
/// `ShellChrome.chipOrder` hands it over. Ties break on catalog position, so
/// the packing is deterministic for a given corpus.
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

    /// Mirrors `SourceRowPacking.columns` — the view needs it for its own slot
    /// loops, and a drift guard in `source-packing-selftest.sh` ties the two.
    fileprivate static let columns = SourceRowPacking.columns
    /// The chip's icon; the slot around it leaves room for the ring, exactly
    /// as `SourceChips` does at its own scale.
    private static let iconSize: CGFloat = 44
    private static let chipSize: CGFloat = 52
    /// Two lines of `label12` plus its own leading — the same fixed name box
    /// `AppsScreen.appTile` uses, so a one-word and a two-word name sit on the
    /// same baseline instead of the row jittering per cell.
    private static let nameHeight: CGFloat = 28
    /// One line of `label11` (its own `lineHeight`), and the gap under it.
    private static let overlineHeight: CGFloat = 15
    private static let overlineGap: CGFloat = 5
    /// Aligns the category name's first character with the left edge of the
    /// chip ring beneath it — the chip is `chipSize` centred in a slot, so this
    /// is half that difference at the phone's own column width, and inside a
    /// card it reads as the card's own padding. Deliberately a constant rather
    /// than a measured inset: it is a nudge, not a layout, and a
    /// `GeometryReader` here would buy a fraction of a point on the iPad in
    /// exchange for a measurement pass on every source pick.
    private static let overlineInset: CGFloat = 7
    /// A group's own top and bottom air — the card's padding, kept after the
    /// card (2026-08-16). Tuned against the resting cap, not chosen: at 8/6 a
    /// four-row tray lands at 610pt (598 before `rowGap` went s2 → s3 later the
    /// same day), and every point above that is a point closer to a scroll the
    /// packing exists to prevent. 10/8 was measured and refused for exactly
    /// that — it lands at 626, past the cap; see `rowGap`.
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
    /// Budget, since every point here is spent against that cap: four rows go
    /// **598 → 610pt**, and the row that fits at rest is unchanged (a five-row
    /// corpus was 726 and is now 742 — over either way, so it still rests at
    /// four and scrolls).
    private static let rowGap: CGFloat = DS.Space.s3

    /// DSTray's own chrome: top clearance, the title, its gap, bottom pad.
    private static let chromeHeight: CGFloat = DS.Space.s6 + 30 + DS.Space.s4 + DS.Space.s6
    private static let restingCap: CGFloat = 620

    /// Natural height, capped. Past the cap the grid scrolls and `.large` is
    /// draggable — a 40-source corpus must not clip silently (the "Worth a
    /// look" tray's own 2026-07-24 lesson).
    ///
    /// The cap SNAPS DOWN to a whole number of rows. A raw `min(…, cap)` cuts
    /// wherever the arithmetic lands, and the worst cut is the likeliest one:
    /// through a card, between its title and the chips it names. Measured on a
    /// 25-source corpus the tray rested showing three category names with
    /// NOTHING underneath them — which reads as a rendering bug, not as "there
    /// is more below". Snapping means the last visible card is always whole and
    /// the next fully hidden; the grabber and the `.large` detent carry the
    /// "there's more" signal, as they already did.
    private var trayHeight: CGFloat {
        let rows = packed
        func height(_ n: Int) -> CGFloat {
            guard n > 0 else { return Self.chromeHeight }
            let body = rows.prefix(n).reduce(CGFloat.zero) { $0 + Self.rowHeight(chipRows: $1.chipRows) }
            return body + CGFloat(n - 1) * Self.rowGap + Self.chromeHeight
        }
        let natural = height(rows.count)
        guard natural > Self.restingCap else { return natural }
        var fit = 1
        while fit < rows.count, height(fit + 1) <= Self.restingCap { fit += 1 }
        return height(fit)
    }

    var body: some View {
        DSTray(title: String(localized: "Your feeds"),
               height: trayHeight,
               glass: true,
               detents: [.height(trayHeight), .large]) {
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
                            rowView(row)
                        }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func rowView(_ row: PackedRow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            nameBand(row)
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                ForEach(0..<row.chipRows, id: \.self) { chipRow in
                    cellRow(row, chipRow: chipRow)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, Self.cardPadTop)
        .frame(height: Self.rowHeight(chipRows: row.chipRows))
    }

    // MARK: - Which block owns which column

    /// The block index (within the row) owning each column, or nil for a column
    /// no card reaches. Blocks fill left to right in packed order; an oversized
    /// block spans every column, which is the same rule and needs no special
    /// case here.
    private func owners(_ row: PackedRow) -> [Int?] {
        var out = [Int?](repeating: nil, count: Self.columns)
        var column = 0
        for (index, block) in row.blocks.enumerated() {
            for _ in 0..<block.span where column < Self.columns {
                out[column] = index
                column += 1
            }
        }
        return out
    }

    /// The chip at a given position, with the category VoiceOver should speak.
    private func member(_ row: PackedRow, chipRow: Int, column: Int) -> (label: String, category: String)? {
        // The oversized case wraps inside one card, so its second chip row
        // continues the same block rather than starting a new one.
        if let only = row.blocks.first, row.blocks.count == 1, only.members.count > Self.columns {
            let index = chipRow * Self.columns + column
            guard index < only.members.count else { return nil }
            return (only.members[index], only.name)
        }
        guard chipRow == 0 else { return nil }
        var start = 0
        for block in row.blocks {
            if column < start + block.members.count {
                return (block.members[column - start], block.name)
            }
            start += block.members.count
        }
        return nil
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

    /// The category names, one per card, at the column its card starts in.
    ///
    /// Five equal slots rather than one span per block: the slots are the same
    /// flexible widths the cell row below uses, so a name and the chip it
    /// belongs to line up with no measurement anywhere.
    ///
    /// Every name is a START now — cards are whole, so there is no such thing
    /// as a continuation and the old repeat-with-an-interpunct cue is gone with
    /// the shape that needed it.
    private func nameBand(_ row: PackedRow) -> some View {
        var starts = [Int: String]()
        var column = 0
        for block in row.blocks {
            starts[column] = block.name
            column += block.span
        }
        return HStack(spacing: DS.Space.s2) {
            ForEach(0..<Self.columns, id: \.self) { column in
                Text(starts[column] ?? "")
                    .dsText(.label11)
                    .fontWeight(.semibold)
                    // textPrimary since 2026-08-16 — with the card gone this ink
                    // IS the grouping. See the type doc for why not tint and why
                    // not a size bump as well.
                    .foregroundStyle(DS.textPrimary)
                    // Names never truncate (prd §201) — the app-tile rule. A
                    // category name is one word, and the longest in the
                    // catalog ("Shopping") clears a phone column at this size,
                    // so the scale factor is a floor for accessibility sizes
                    // rather than something the shipped catalog ever reaches.
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.leading, Self.overlineInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(height: Self.overlineHeight, alignment: .bottom)
        .padding(.bottom, Self.overlineGap)
        // The band names the card beneath it; VoiceOver reads each chip's own
        // category on the cell instead, so this is decoration to it.
        .accessibilityHidden(true)
    }

    private func cellRow(_ row: PackedRow, chipRow: Int) -> some View {
        HStack(spacing: DS.Space.s2) {
            ForEach(0..<Self.columns, id: \.self) { column in
                if let found = member(row, chipRow: chipRow, column: column) {
                    cell(label: found.label, category: found.category)
                } else {
                    // Holds the column so a short last row keeps every chip
                    // above it on its own vertical.
                    Color.clear.frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private func cell(label: String, category: String) -> some View {
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
            .frame(maxWidth: .infinity)
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
