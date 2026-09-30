import SwiftUI

/// THE CALENDAR ROOM'S LEAD (prd §994): six weeks from the start of this one,
/// in the lead box every room shares, lighting the span the picked tile shows
/// — one cell for Today, a week's run for Week, the month for Month.
///
/// One drawing for every pick (user: "leave it as a monthly view only"): the
/// box never changes shape and never fits its content (§904), and the tile
/// says what the list below holds by what it lights here.
///
/// A dot under a day says Calendar holds an event on it — read off every
/// occurrence (`CalendarBusyDays`), so a weekly meeting marks every week it
/// meets. A day outside the room's reach (before today, past the month) is
/// drawn faint and never dotted: nothing there is held, so nothing there is
/// claimed (§83).
///
/// Display only. A day is not a control — the tiles are the room's one pick.
struct CalendarMonthLead: View {
    let scope: CalendarScope
    let busy: Set<String>
    var now: Date = .now

    private var calendar: Calendar { .current }

    /// The line the title takes, and the weekday letters' row, out of the
    /// box; the six weeks share what is left.
    private static let titleRow: CGFloat = 30
    private static let weekdayRow: CGFloat = 16

    @MainActor private var rowHeight: CGFloat {
        let rest = DSRoomChassis.leadBox - Self.titleRow - DS.Space.s2 - Self.weekdayRow
        return max(28, floor(rest / CGFloat(CalendarGrid.weeks)))
    }

    var body: some View {
        let days = CalendarGrid.days(now: now, calendar: calendar)
        let runs = CalendarGrid.runs(days, span: scope.span(now: now, calendar: calendar))
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            // The day dividers' rung (prd §999, user: "the month should be same
            // size font as Today Thursday Friday dates"), which is `heading20`
            // since §1006.
            Text(CalendarGrid.title(days, calendar: calendar))
                .dsText(.heading20)
                .foregroundStyle(DS.textPrimary)
                .frame(height: Self.titleRow)
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(Array(CalendarGrid.weekdaySymbols(calendar: calendar).enumerated()),
                            id: \.offset) { _, symbol in
                        Text(symbol)
                            .dsText(.label12)
                            .foregroundStyle(DS.textTertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: Self.weekdayRow)
                ForEach(0..<CalendarGrid.weeks, id: \.self) { row in
                    let start = row * 7
                    if days.count >= start + 7 {
                        week(Array(days[start..<start + 7]), run: runs[row])
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(days))
    }

    private func week(_ days: [CalendarGrid.Day], run: ClosedRange<Int>?) -> some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                cell(day)
            }
        }
        .frame(height: rowHeight)
        .background(alignment: .topLeading) {
            GeometryReader { geo in
                let column = geo.size.width / 7
                if let run {
                    Capsule(style: .continuous)
                        .fill(DS.tint.opacity(0.16))
                        .frame(width: column * CGFloat(run.count), height: rowHeight - 4)
                        .offset(x: column * CGFloat(run.lowerBound), y: 2)
                        .transition(.opacity)
                }
            }
        }
        .animation(DS.Motion.standard, value: run)
    }

    private func cell(_ day: CalendarGrid.Day) -> some View {
        let dotted = day.reachable && busy.contains(CalendarBusyDays.key(day.date, calendar: calendar))
        return VStack(spacing: 2) {
            Text(day.number, format: .number)
                .dsText(.body17)
                .fontWeight(day.isToday ? .semibold : .regular)
                .monospacedDigit()
                .foregroundStyle(day.isToday ? Color.white
                                 : day.reachable ? DS.textPrimary : DS.textTertiary)
                .frame(width: 30, height: 26)
                .background {
                    // Today wears the day divider's pink, the one other place
                    // the room names today (prd §742).
                    if day.isToday { Circle().fill(DS.brandInk) }
                }
            Circle()
                .fill(DS.textSecondary)
                .frame(width: 4, height: 4)
                .opacity(dotted ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
    }

    private func accessibilityText(_ days: [CalendarGrid.Day]) -> String {
        let count = days.filter {
            $0.reachable && busy.contains(CalendarBusyDays.key($0.date, calendar: calendar))
        }.count
        let title = CalendarGrid.title(days, calendar: calendar)
        return String(localized: "\(title). Events on \(count) days ahead. Showing \(scope.label).")
    }
}
