import SwiftUI

/// **The Permissions tile (prd §936): one bar per class, red only where the
/// class has no limit.** The keys (§924) — a column of key marks per class,
/// amber or blue, six before "+N" — are deleted; a class is a bar as long as
/// its count against the largest, labelled with the class's own noun
/// (`Power.word` in the Wallet, §931). A press lights one class and the
/// reading names it; the rows below still name every holder.
struct RoomPermissionsFigure: View {
    let kinds: [RoomPermissions.Kind]
    var lead: RoomPermissions.Lead? = nil
    /// The scope: one account's name, or how many you follow (prd §924).
    var caption: String? = nil
    @State private var lit: String?

    var body: some View {
        DSBarFigure(reading: { reading },
                    bars: DSBarList(bars: Self.bars(kinds), lit: lit) { picked in
                        lit = lit == picked ? nil : picked
                    })
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(RoomPermissions.spoken(kinds, lead: lead)))
    }

    /// Every class with something in it, in the model's order (most reach
    /// first); an empty class is not a bar.
    static func bars(_ kinds: [RoomPermissions.Kind]) -> [DSBarList.Bar] {
        let held = kinds.filter { $0.count > 0 }
        let peak = Double(held.map(\.count).max() ?? 1)
        return held.map { kind in
            DSBarList.Bar(id: kind.id, label: kind.label,
                          value: kind.aside.map { "\(kind.count) · \($0)" } ?? String(kind.count),
                          share: Double(kind.count) / peak,
                          alarm: kind.unbounded)
        }
    }

    private var unboundedCount: Int {
        kinds.filter(\.unbounded).reduce(0) { $0 + $1.count }
    }

    @ViewBuilder
    private var reading: some View {
        if let lit, let kind = kinds.first(where: { $0.id == lit }) {
            DSFigureReading(number: String(kind.count), caption: kind.phrase ?? kind.label)
        } else {
            let n = RoomPermissions.total(kinds)
            let noun = n == 1 ? String(localized: "permission") : String(localized: "permissions")
            DSFigureReading(
                number: lead?.figure ?? String(n),
                caption: lead?.figure == nil
                    ? [noun, caption].compactMap { $0 }.joined(separator: " · ")
                    : [lead?.caption, "\(n) \(noun)"].compactMap { $0 }.joined(separator: " · "),
                alarm: unboundedCount > 0 ? String(localized: "\(String(unboundedCount)) with no limit") : nil)
        }
    }
}

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
