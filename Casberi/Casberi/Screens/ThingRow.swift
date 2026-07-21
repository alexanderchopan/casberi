import SwiftUI

/// A Feed / list row: source icon, title, tag, pin, time (brief §7 / Feed spec).
/// The verb line lives in the thing sheet, not here. Status shows in the title's
/// treatment (done strikes through). Rows carry status (principle 6).
struct ThingRow: View {
    let thing: Thing
    @Environment(\.modelContext) private var modelContext
    /// A quiet echo when this same link was already saved from another
    /// source — the source name it first landed from, or nil (delight pass
    /// 2026-07-21). Computed once per row identity, never on every redraw.
    @State private var echoSource: String?

    private var done: Bool { thing.mark == .done }

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            KindGlyph(kind: thing.kind, size: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(thing.title)
                    .dsText(.body17)
                    .foregroundStyle(done ? DS.textTertiary : DS.textPrimary)
                    .strikethrough(done, color: DS.textTertiary)
                    .lineLimit(1)
                if let echoSource {
                    Text("Also saved from \(echoSource)")
                        .dsText(.label12)
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            TagPill(thing.tags.first ?? thing.kind.typeTag)

            LiveTimeText(date: thing.capturedAt)
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s3)
        .task(id: thing.id) {
            echoSource = CrossSourceEcho.find(for: thing, context: modelContext)
        }
    }
}

/// A relative time ("3m", "2h", "5d") that stays true — it re-renders each
/// minute instead of going stale with the row (§9 polish).
struct LiveTimeText: View {
    let date: Date
    var color: Color = DS.textTertiary

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            let label = Self.short(date)
            // "2h" → "3h" rolls its digit (the Clock app's grammar) instead
            // of swapping — the change is the moment (motion pass 2026-07-11).
            Text(label)
                .dsText(.subhead13)
                .foregroundStyle(color)
                .contentTransition(.numericText())
                .animation(DS.Motion.standard, value: label)
        }
    }

    static func short(_ date: Date) -> String {
        let s = Date.now.timeIntervalSince(date)
        if s < 3600 { return "\(max(1, Int(s / 60)))m" }
        if s < 86_400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86_400))d"
    }
}

/// A small tag pill for list rows.
struct TagPill: View {
    let label: String
    init(_ label: String) { self.label = label }

    var body: some View {
        Text(label)
            .dsText(.label12)
            .foregroundStyle(DS.textPrimary)
            .padding(.horizontal, DS.Space.s2)
            .frame(height: 20)
            .background(DS.gray100, in: Capsule(style: .continuous))
    }
}

/// A section header for grouped lists.
struct SectionHeader: View {
    let title: String
    var count: String? = nil
    init(_ title: String, count: String? = nil) { self.title = title; self.count = count }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            Text(title).dsText(.heading17).foregroundStyle(DS.textPrimary)
            if let count {
                Text(count).dsText(.subhead13).foregroundStyle(DS.textTertiary)
            }
            Spacer()
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s4)
        .padding(.bottom, DS.Space.s1)
    }
}
