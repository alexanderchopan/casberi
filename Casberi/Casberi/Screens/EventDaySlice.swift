import SwiftUI

/// AN EVENT AS A SLICE OF ITS DAY (prd §1182, the design canvas "Thing
/// sheets, the Apple pass"): the box shows the event between what comes
/// before and after it, four hours of the day on a fixed grid, the event in
/// the tint and its neighbours on the quiet fill. The clock and the day lead.
///
/// Values only: the sheet hands over plain blocks, read off the store on its
/// task (§628), so nothing here touches a model.
struct EventDaySlice: View {
    struct Block: Identifiable, Equatable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        var isThis = false
        var place: String? = nil
    }

    let start: Date
    let end: Date?
    let allDay: Bool
    let blocks: [Block]

    /// Four rows of an hour each: the box's height, never more.
    private static let hours = 4
    private static let rowHeight: CGFloat = 38

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: clock)
                    .dsText(.heading24)
                    .monospacedDigit()
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: DS.Space.s2)
                Text(verbatim: FeedScreen.dayWord(start))
                    .dsText(.label12)
                    .foregroundStyle(DS.brandInk)
            }
            if allDay {
                Text("All day")
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
            } else {
                grid
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spoken))
    }

    private var windowStart: Date {
        let cal = Calendar.current
        let hour = cal.dateInterval(of: .hour, for: start)?.start ?? start
        return cal.date(byAdding: .hour, value: -1, to: hour) ?? hour
    }

    private var grid: some View {
        let origin = windowStart
        let total = CGFloat(Self.hours) * Self.rowHeight
        return HStack(alignment: .top, spacing: DS.Space.s2) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<Self.hours, id: \.self) { i in
                    let hour = Calendar.current.date(byAdding: .hour, value: i, to: origin) ?? origin
                    Text(verbatim: hour.formatted(.dateTime.hour()))
                        .dsText(.dockCaption10)
                        .foregroundStyle(i == 1 ? DS.textPrimary : DS.textTertiary)
                        .frame(height: Self.rowHeight, alignment: .top)
                }
            }
            .frame(width: 36, alignment: .leading)
            ZStack(alignment: .topLeading) {
                Color.clear.frame(height: total)
                ForEach(blocks) { block in
                    let top = max(0, CGFloat(block.start.timeIntervalSince(origin) / 3600) * Self.rowHeight)
                    let bottom = min(total, CGFloat(block.end.timeIntervalSince(origin) / 3600) * Self.rowHeight)
                    if bottom > top {
                        HStack(spacing: DS.Space.s2) {
                            Text(verbatim: block.title)
                                .dsText(.label12)
                                .fontWeight(block.isThis ? .bold : .regular)
                                .lineLimit(1)
                            if block.isThis, let place = block.place {
                                Text(verbatim: place)
                                    .dsText(.label12)
                                    .lineLimit(1)
                                    .opacity(0.8)
                            }
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(block.isThis ? DS.inkGround : DS.textSecondary)
                        .padding(.horizontal, DS.Space.s2)
                        .frame(height: max(22, bottom - top - 4), alignment: .center)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(block.isThis ? DS.tint : DS.fillFaint))
                        .offset(y: top + 2)
                    }
                }
            }
            .frame(height: total)
            .clipped()
        }
    }

    private var clock: String {
        if allDay { return FeedScreen.dayWord(start) }
        let from = start.formatted(date: .omitted, time: .shortened)
        guard let end else { return from }
        return "\(from) – \(end.formatted(date: .omitted, time: .shortened))"
    }

    private var spoken: String {
        let others = blocks.filter { !$0.isThis }.map(\.title)
        let around = others.isEmpty ? "" : ". " + String(localized: "Also: \(others.joined(separator: ", "))")
        return "\(clock), \(FeedScreen.dayWord(start))" + around
    }
}
