import SwiftUI

/// The grid itself — one cell per class, a count and the class's own sentence.
///
/// **A cell is a WELL, and an absence is an OUTLINE and a dash.** Vibenet's
/// census reasoned this out in 2026-09-02 and it generalises without change: a
/// zero drawn in the same well as a count reads as a measurement — the same
/// object, a smaller number — when what it means is that this permission is
/// not in play at all. Wallet's four bare numerals adopt the well here; that
/// is the one visible change the merge makes to a room that already had this
/// scope.
///
/// **Every dimension derives from `DSRoomChassis.figureSlot`** (§665), so the
/// figure grows with the slot and a device that gives it more room spends it
/// on the cells rather than on air.
struct RoomPermissionsFigure: View {
    let kinds: [RoomPermissions.Kind]
    var lead: RoomPermissions.Lead? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var drawn: [RoomPermissions.Kind] {
        Array(kinds.prefix(RoomPermissions.cellsShown(kinds)))
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: DS.Space.s2, alignment: .topLeading),
              count: RoomPermissions.columns(kinds))
    }

    /// Rows the grid actually needs — one where a room has two kinds, two
    /// where it has more. The cell height follows, so a one-row grid is not a
    /// two-row grid with an empty half.
    private var rows: CGFloat {
        CGFloat(max(1, Int(ceil(Double(drawn.count) / Double(RoomPermissions.columns(kinds))))))
    }

    /// A lead line costs the grid its own height, so it is subtracted here
    /// rather than left to clip (`censusCell`'s lesson, which had no lead to
    /// account for).
    private var cellHeight: CGFloat {
        let leadCost: CGFloat = lead == nil ? 0 : 28 + DS.Space.s2
        let slot = DSRoomChassis.figureSlot - leadCost
        return (slot - DS.Space.s2 * (rows - 1)) / rows - DS.Space.s2 * 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let lead {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    Text(lead.figure)
                        .dsText(.stat24).foregroundStyle(DS.textPrimary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                    if let caption = lead.caption {
                        Text(caption)
                            .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    }
                }
                .padding(.bottom, DS.Space.s2)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: DS.Space.s2) {
                ForEach(Array(drawn.enumerated()), id: \.element.id) { index, kind in
                    cell(kind)
                        .chartArrival(index: index, reduceMotion: reduceMotion)
                }
            }
            if let folded = RoomPermissions.folded(kinds) {
                Text(String(localized: "and \(folded) more"))
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(RoomPermissions.spoken(kinds, lead: lead)))
    }

    @ViewBuilder
    private func cell(_ kind: RoomPermissions.Kind) -> some View {
        let held = kind.count > 0
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                Text(held ? "\(kind.count)" : "—")
                    .dsText(.price16)
                    .foregroundStyle(held ? (kind.unbounded ? DS.attention : DS.textPrimary)
                                          : DS.textTertiary)
                    .monospacedDigit()
                if held, let aside = kind.aside {
                    Text(aside)
                        .dsText(.label11).foregroundStyle(DS.textTertiary)
                        .lineLimit(1).minimumScaleFactor(0.85)
                }
            }
            Text(kind.label)
                .dsText(.label12)
                .foregroundStyle(held ? DS.textTertiary : DS.textQuaternary.opacity(0.6))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .minimumScaleFactor(0.9)
            Spacer(minLength: 0)
        }
        // PINNED, not floored: a floor is what a label's own wrapping walks
        // straight through, and the grid it grows is clipped rather than
        // scrolled. Two modifiers because SwiftUI has no `maxWidth:`+`height:`
        // overload.
        .frame(height: cellHeight, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, DS.Space.s2)
        .padding(.vertical, DS.Space.s2)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(held ? DS.surfaceWell : Color.clear)
        }
        .overlay {
            if !held {
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .strokeBorder(DS.fillLine, lineWidth: 1)
            }
        }
    }
}

/// A captioned block of rows — one kind of thing, named above it.
///
/// **TWO KINDS OF ROW, SAID TO BE TWO** (user, 2026-09-02, on Frames' sponsor
/// list: *"sponsors list also is messy"*). A person and a grant have different
/// anatomies, and stacked under one caption at one spacing they read as a
/// single list that keeps changing shape. Each block names its kind; `s6`
/// between blocks is the gap the app already uses for "these are different
/// things".
struct RoomListBlock<Content: View>: View {
    let caption: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text(caption)
                .dsText(.label12).foregroundStyle(DS.textTertiary)
            content()
        }
    }
}
