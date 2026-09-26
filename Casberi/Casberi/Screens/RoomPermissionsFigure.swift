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
    /// The scope: one account's name, or how many you follow — the crown's
    /// own caption (prd §924).
    var caption: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// **THE PRESSED KEY (prd §924)** — a kind's id and the holder's index.
    /// While set, the reading names the holder and every other key goes
    /// quiet; a tap toggles, so the figure is never stuck lit.
    @State private var lit: Lit?

    private struct Lit: Equatable {
        let kind: String
        let index: Int
    }

    /// How many keys a class draws before it says "+N" (prd §924): six is
    /// two rows of three at the mark's size in a three-column grid.
    static let keysShown = 6
    static let mark: CGFloat = 26

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: DS.Space.s3, alignment: .topLeading),
              count: RoomPermissions.columns(kinds))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            reading
            // **THE PERMISSIONS THEMSELVES (prd §924).** One key per
            // permission under its class — amber where it has no limit, blue
            // where it is capped, the colours the numerals wore — the money
            // beside a class whose keys carry one, and no plate: the label
            // takes the column's whole width and stops truncating. A class
            // with none keeps one quiet key and its word, so the absence
            // still reads (§83's outline-and-dash, in the figure's own marks).
            LazyVGrid(columns: columns, alignment: .leading, spacing: DS.Space.s3) {
                ForEach(Array(kinds.enumerated()), id: \.element.id) { index, kind in
                    classBlock(kind)
                        .chartArrival(index: index, reduceMotion: reduceMotion)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? nil : DS.Motion.standard, value: lit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(RoomPermissions.spoken(kinds, lead: lead)))
    }

    // MARK: - The reading

    private var unboundedCount: Int {
        kinds.filter(\.unbounded).reduce(0) { $0 + $1.count }
    }

    private var permissionsPhrase: String {
        let n = RoomPermissions.total(kinds)
        return n == 1 ? String(localized: "1 permission") : String(localized: "\(String(n)) permissions")
    }

    private var pressed: (kind: RoomPermissions.Kind, holder: RoomPermissions.Holder)? {
        guard let lit, let kind = kinds.first(where: { $0.id == lit.kind }),
              kind.holders.indices.contains(lit.index) else { return nil }
        return (kind, kind.holders[lit.index])
    }

    /// **THE CROWN'S READING (prd §924)** — caption, a figure at `stat24`,
    /// one line. The Wallet's reach leads ("$6,704" · "in reach · 5
    /// permissions · 4 with no limit"); a room with no lead leads with the
    /// count. Only the reading clears the gear (§920's rule).
    @ViewBuilder
    private var reading: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let caption {
                Text(caption)
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
            }
            Text(pressed?.holder.name ?? lead?.figure ?? permissionsPhrase)
                .dsText(.stat24)
                .foregroundStyle(DS.textPrimary)
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
            line
                .dsText(.body17)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, DSRoomChassis.gearColumn)
    }

    private static func joined(_ parts: [Text]) -> Text {
        guard let first = parts.first else { return Text(verbatim: "") }
        return parts.dropFirst().reduce(first) {
            $0 + Text(verbatim: " · ").foregroundStyle(DS.textTertiary) + $1
        }
    }

    private var line: Text {
        if let (kind, holder) = pressed {
            var parts: [Text] = []
            if let usd = holder.usd {
                parts.append(Text(WalletApprovalExposure.money(usd))
                    .foregroundStyle(kind.unbounded ? DS.attention : DS.textSecondary))
            }
            if let note = holder.note { parts.append(Text(note).foregroundStyle(DS.textSecondary)) }
            parts.append(Text(kind.label).foregroundStyle(DS.textSecondary))
            return Self.joined(parts)
        }
        var parts: [Text] = []
        if let caption = lead?.caption { parts.append(Text(caption).foregroundStyle(DS.textSecondary)) }
        if lead != nil { parts.append(Text(permissionsPhrase).foregroundStyle(DS.textSecondary)) }
        if unboundedCount > 0 {
            parts.append(Text(unboundedCount == 1 ? String(localized: "1 with no limit")
                                                  : String(localized: "\(String(unboundedCount)) with no limit"))
                .foregroundStyle(DS.attention))
        }
        if parts.isEmpty {
            parts.append(Text(String(localized: "on the accounts you follow")).foregroundStyle(DS.textSecondary))
        }
        return Self.joined(parts)
    }

    // MARK: - The keys

    @ViewBuilder
    private func classBlock(_ kind: RoomPermissions.Kind) -> some View {
        let held = kind.count > 0
        let shown = min(kind.count, Self.keysShown)
        let quietClass = lit != nil && lit?.kind != kind.id
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 4) {
                if held {
                    ForEach(0..<shown, id: \.self) { i in
                        key(kind, index: i, quiet: quietClass || (lit?.kind == kind.id && lit?.index != i))
                    }
                    if kind.count > shown {
                        Text(verbatim: "+\(kind.count - shown)")
                            .dsText(.label12).foregroundStyle(DS.textTertiary)
                    }
                    if let aside = kind.aside {
                        Text(aside)
                            .dsText(.label12).foregroundStyle(DS.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                } else {
                    Circle().fill(DS.fillFaint).frame(width: Self.mark, height: Self.mark)
                }
            }
            .opacity(held && quietClass ? 0.35 : 1)
            Text(held ? kind.label : String(localized: "\(kind.label) · none"))
                .dsText(.label12)
                .foregroundStyle(held ? (lit?.kind == kind.id ? DS.textPrimary : DS.textTertiary)
                                      : DS.textQuaternary)
                // Three lines, because a class is a clause ("Can spend
                // without a signature") and two clipped it at the third
                // word in a three-column grid — seen on the first build —
                // while the rows below the grid had the room to spare.
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(held && quietClass ? 0.35 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func key(_ kind: RoomPermissions.Kind, index: Int, quiet: Bool) -> some View {
        let face = Circle()
            .fill(kind.unbounded ? DS.attention : DS.tint)
            .frame(width: Self.mark, height: Self.mark)
            .overlay {
                Image(systemName: "key.fill")
                    .dsGlyph(.caption, weight: .semibold)
                    .foregroundStyle(kind.unbounded ? Color.black.opacity(0.75) : Color.white)
                    .accessibilityHidden(true)
            }
            .opacity(quiet ? 0.35 : 1)
        if kind.holders.indices.contains(index) {
            Button {
                DSHaptic.selection()
                let next = Lit(kind: kind.id, index: index)
                lit = lit == next ? nil : next
            } label: {
                face.contentShape(Circle())
            }
            .buttonStyle(PressSpring())
            .accessibilityLabel(Text(kind.holders[index].name))
            .accessibilityAddTraits(lit == Lit(kind: kind.id, index: index) ? .isSelected : [])
        } else {
            face
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
