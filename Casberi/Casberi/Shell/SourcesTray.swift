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
/// # Grouped by catalog category (2026-08-06, user)
///
/// The grid is now packed into the categories `BridgeCatalog.categories`
/// already uses, so the tray reads like the catalog you connected these from
/// instead of being a flat wall of twenty marks.
///
/// **The name sits ABOVE its group, never beside it.** Three layouts were
/// mocked (`prototype/sources-tray-categories-v1…v3.html`) and the first two
/// died on height, which is the only currency a picker has — you are in this
/// tray for two seconds and a scroll is the worst tax it can charge:
///
/// - Banded headers, one category per band: ~1,250pt against today's 572pt.
/// - A left rail with the name holding column one: ~964pt. It paid twice — the
///   marker ate a column (four chips per row instead of five) AND every
///   category opened a row, so four single-app categories burned four rows on
///   four chips.
/// - This: the name is an 11pt overline over its own cells, so nothing is
///   reserved, chips run five across again, and small categories SHARE a row.
///   Twenty sources land in four rows — **570pt, inside the 620pt resting cap
///   and a whisker under the flat grid it replaces.** Categories at no cost.
///
/// **Groups pack greedily and a group may start mid-row** (user ruling
/// 2026-08-06, "why not just start the next category after it"). The earlier
/// mock kept a wrapped category alone on its rows to keep it unmistakable;
/// that was over-cautious and cost a row. An overline marks a group's START,
/// so a group beginning at column three is already labelled — and the ONLY
/// unlabelled cells are continuations of the group named above them, which is
/// a rule read once and never again. Packing is also what lets catalog order
/// stay strict: nothing has to float out of sequence to fill a row.
///
/// **Alphabetising was considered and refused.** It would hold the height,
/// but this tray is the STRIP's map — its whole job is teaching the positions
/// of an icon-only row that has no labels. An alphabetical tray teaches
/// positions the strip does not have. So the strip's frozen order survives
/// inside every group, exactly as `ShellChrome.chipOrder` hands it over; only
/// the grouping is new, and a group's members keep their relative order.
///
/// **"All" no longer has a cell** (user, 2026-08-06). It belongs to no
/// category, so in a grouped grid it could only ever be an ungrouped orphan
/// taking a row of its own — ~100pt for one chip. It remains the first chip in
/// the strip behind this tray, so the everything-room is one dismiss and one
/// tap away. Known cost, stated rather than hidden: from INSIDE the tray there
/// is now no way back to All.
struct SourcesTray: View {
    /// The strip's own ordered labels — "All" first, then sources.
    let labels: [String]
    let active: String
    let onPick: (String) -> Void

    @Environment(BridgeStore.self) private var bridges
    @Environment(\.dismiss) private var dismiss

    private static let columns = 5
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
    /// Aligns the overline's first character with the left edge of the chip
    /// ring beneath it — the chip is `chipSize` centred in a slot, so this is
    /// half that difference at the phone's own column width. Deliberately a
    /// constant rather than a measured inset: it is a nudge, not a layout, and
    /// a `GeometryReader` here would buy a fraction of a point on the iPad in
    /// exchange for a measurement pass on every source pick.
    private static let overlineInset: CGFloat = 7

    /// One chip in the grid. It carries its own category rather than the row
    /// carrying a parallel array of names: the category is what VoiceOver
    /// speaks and what the overline draws, and keeping both on the cell means
    /// a continuation cell can never disagree with the band above it.
    private struct Cell {
        let label: String
        let category: String
        /// The first member of its group, wherever the packing put it — the
        /// one cell that draws an overline.
        let startsGroup: Bool
    }

    /// One packed row: up to `columns` cells. A row draws a name band when any
    /// of its cells starts a group; a row of pure continuations draws none.
    private struct PackedRow: Identifiable {
        let id: Int
        let cells: [Cell]
        var hasOverlines: Bool { cells.contains(where: \.startsGroup) }
    }

    /// Group the labels by catalog category in catalog order, then pack the
    /// cells into rows of `columns` without regard for group boundaries.
    ///
    /// Pure and self-contained on purpose — the whole layout is decided here
    /// and the body just draws it, so the packing can be reasoned about (and
    /// one day tested) without mounting a view.
    ///
    /// A source the catalog can't place keeps its cell rather than vanishing:
    /// unplaceable labels collect in a trailing "Other" group. A tray that
    /// silently dropped a source would be the worst possible failure here,
    /// since this is the one screen that claims to show every source.
    private var packed: [PackedRow] {
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

        // Catalog order, and inside a category the strip's frozen order, which
        // `sources` already carries.
        var groups: [(name: String, labels: [String])] = BridgeCatalog.categories
            .compactMap { category in
                guard let members = byCategory[category.name], !members.isEmpty else { return nil }
                return (name: category.name, labels: members)
            }
        if !unplaced.isEmpty { groups.append((name: "Other", labels: unplaced)) }

        var rows: [PackedRow] = []
        var cells: [Cell] = []
        func flush() {
            guard !cells.isEmpty else { return }
            rows.append(PackedRow(id: rows.count, cells: cells))
            cells = []
        }
        for group in groups {
            for (index, label) in group.labels.enumerated() {
                if cells.count == Self.columns { flush() }
                // Only the group's FIRST cell is named; everything after it is
                // a continuation, wherever the row break happens to land.
                cells.append(Cell(label: label, category: group.name, startsGroup: index == 0))
            }
        }
        flush()
        return rows
    }

    private func height(of row: PackedRow) -> CGFloat {
        let cell = Self.chipSize + DS.Space.s1 + Self.nameHeight
        // A row where no group starts carries no band at all — there is
        // nothing to name, and reserving the space would pay for a label that
        // is never drawn.
        return row.hasOverlines ? Self.overlineHeight + Self.overlineGap + cell : cell
    }

    /// Natural height, capped. Past the cap the grid scrolls and `.large` is
    /// draggable — a 40-source corpus must not clip silently (the "Worth a
    /// look" tray's own 2026-07-24 lesson).
    private var trayHeight: CGFloat {
        let rows = packed
        let grid = rows.reduce(0) { $0 + height(of: $1) }
            + CGFloat(max(0, rows.count - 1)) * DS.Space.s4
        // DSTray's own chrome: top clearance, the title, its gap, bottom pad.
        let chrome = DS.Space.s6 + 30 + DS.Space.s4 + DS.Space.s6
        return min(grid + chrome, 620)
    }

    var body: some View {
        DSTray(title: String(localized: "Your sources"),
               height: trayHeight,
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
                    VStack(alignment: .leading, spacing: DS.Space.s4) {
                        ForEach(rows) { row in
                            VStack(alignment: .leading, spacing: 0) {
                                if row.hasOverlines { overlineBand(row) }
                                cellRow(row)
                            }
                        }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    /// The names, drawn as their own `columns`-wide row above the chips.
    ///
    /// Five equal slots rather than one span per group: the slots are the same
    /// flexible widths the cell row below uses, so a name and the chip it
    /// belongs to line up with no measurement anywhere. A span-per-group
    /// layout would need the cell width to compute its own, which is the
    /// `GeometryReader` this deliberately avoids.
    private func overlineBand(_ row: PackedRow) -> some View {
        HStack(spacing: DS.Space.s2) {
            ForEach(0..<Self.columns, id: \.self) { column in
                Text(column < row.cells.count && row.cells[column].startsGroup
                     ? row.cells[column].category : "")
                    .dsText(.label11)
                    .fontWeight(.semibold)
                    .foregroundStyle(DS.textTertiary)
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
        // The band names the row beneath it; VoiceOver reads each chip's own
        // category on the cell instead, so this is decoration to it.
        .accessibilityHidden(true)
    }

    private func cellRow(_ row: PackedRow) -> some View {
        HStack(spacing: DS.Space.s2) {
            ForEach(0..<Self.columns, id: \.self) { column in
                if column < row.cells.count {
                    cell(row.cells[column])
                } else {
                    // Holds the column so a short last row keeps every chip
                    // above it on its own vertical.
                    Color.clear.frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ cell: Cell) -> some View {
        let label = cell.label
        let isActive = label == active
        // Same read as the strip's: one ring, two exclusive states. Solid tint
        // is selection; DASHED orange is "this connection needs you" (the
        // 2026-07-21 ruling — the two must not be the same ring in two hues).
        let broken = bridges.bridges.contains {
            $0.name == label && $0.status == .attention
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
        // The grouping is drawn, so it must also be SPOKEN — an overline band
        // hidden from VoiceOver would otherwise take the category away from
        // the one reader who can't see the layout that carries it.
        .accessibilityLabel(label + ", \(cell.category)"
            + (broken ? String(localized: ", needs reconnecting") : ""))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
