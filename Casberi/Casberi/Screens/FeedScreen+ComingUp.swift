import SwiftUI

// COMING UP (prd §1136 item 7, user: "i do feel some master list or calendar
// is lacking"): one calendar across every app, under Today on Home. It reads
// what the rooms already date — an event's start, a deadline's `dueAt`, a
// renewal, a grant, a reminder, a calendar you subscribed to (§1137) — so no
// room grows a calendar tile of its own.
extension FeedScreen {
    /// How far ahead Coming up looks: the five weeks the Calendar ingest and a
    /// subscribed calendar read.
    static let comingUpHorizon: TimeInterval = 35 * 86_400
    /// The most rows it draws; the rooms hold the rest.
    static let comingUpCap = 40

    /// When a row happens: its deadline, else its own date (an event's start
    /// is `capturedAt`, prd ScheduleIngest's rule).
    static func comingUpWhen(_ thing: Thing) -> Date { thing.dueAt ?? thing.capturedAt }

    /// What is ahead, soonest first: live rows whose date is after now and
    /// inside the horizon.
    func comingUp(_ visible: [Thing], now: Date = .now) -> [Thing] {
        let end = now.addingTimeInterval(Self.comingUpHorizon)
        return visible
            .filter { $0.isLive }
            .filter { let w = Self.comingUpWhen($0); return w > now && w <= end }
            .sorted { Self.comingUpWhen($0) < Self.comingUpWhen($1) }
            .prefix(Self.comingUpCap)
            .map { $0 }
    }

    /// The days ahead as groups: "Later today", "Tomorrow", then a weekday.
    func comingUpDays(_ rows: [Thing]) -> [(String, [Thing])] {
        var out: [(String, [Thing])] = []
        for thing in rows {
            let when = Self.comingUpWhen(thing)
            let label = Self.groupingCalendar.isDateInToday(when)
                ? String(localized: "Later today") : Self.dayWord(when)
            if out.last?.0 == label { out[out.count - 1].1.append(thing) } else { out.append((label, [thing])) }
        }
        return out
    }

    @ViewBuilder
    func comingUpSections(_ visible: [Thing], nextEventID: UUID?) -> some View {
        let rows = comingUp(visible)
        Section {
            FeedDayDivider(label: String(localized: "Coming up"), dated: false) { EmptyView() }
                .textCase(nil)
                .padding(.leading, DSRoomChassis.rowInset)
                .padding(.top, DS.Space.s4)
                .padding(.bottom, DS.Space.s1)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            ComingUpWeek(days: Set(rows.map { Self.groupingCalendar.startOfDay(for: Self.comingUpWhen($0)) }))
                .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.inset,
                                          bottom: DS.Space.s2, trailing: DSRoomChassis.inset))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            if rows.isEmpty {
                Text("Nothing on the calendar.")
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
                    .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.rowInset,
                                              bottom: DS.Space.s4, trailing: DSRoomChassis.rowInset))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        ForEach(comingUpDays(rows), id: \.0) { label, things in
            Section {
                FeedDayDivider(label: label) { EmptyView() }
                    .textCase(nil)
                    .padding(.leading, DSRoomChassis.rowInset)
                    .padding(.vertical, DS.Space.s1)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                ForEach(Array(things.enumerated()), id: \.element.id) { i, thing in
                    if thing.isLive {
                        shapedListRow(thing, index: i, nextEventID: nextEventID)
                    }
                }
            }
        }
    }
}

/// The week ahead as seven days, today first, a pink dot under a day with
/// something on it. A figure, not a control: it presses nothing (prd §83).
struct ComingUpWeek: View {
    let days: Set<Date>

    var body: some View {
        let cal = FeedScreen.groupingCalendar
        let today = cal.startOfDay(for: .now)
        let week = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
        HStack(spacing: DS.Space.s1) {
            ForEach(week, id: \.self) { day in
                let isToday = day == today
                VStack(spacing: 3) {
                    Text(day.formatted(.dateTime.weekday(.abbreviated)))
                        .dsText(.label12)
                        .foregroundStyle(isToday ? DS.textPrimary : DS.textSecondary)
                    Text(day.formatted(.dateTime.day()))
                        .dsText(.heading17)
                        .foregroundStyle(DS.textPrimary)
                    Circle()
                        .fill(days.contains(day) ? DS.brand : Color.clear)
                        .frame(width: 5, height: 5)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Space.s2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("The week ahead"))
    }
}
