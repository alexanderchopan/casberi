import SwiftUI
import EventKit

// HOME'S DAY (prd §1141, user: "the home screen is supposed to SHOW the
// aggregated calendar for the day"): after Today's feeds, every event on your
// calendars today, the ones already over included and dimmed, in time order,
// then whatever else is dated today (a renewal, a deadline, a subscribed
// calendar's event). Calendar's stored rows keep only what is ahead and one
// occurrence per series (`ScheduleIngest`), so the day is read off EventKit
// directly, today only, on the screen's task, never in a body (§628).

/// One line of the day: an EventKit occurrence, or a dated row Casberi holds.
struct ScheduleItem: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date?
    let allDay: Bool
    /// The app it comes from, for its mark.
    let source: String
    /// The stored row it opens, when there is one.
    let thingID: UUID?

    /// Over: its end has passed (a timed event with no end, its start).
    func isOver(now: Date) -> Bool {
        if allDay { return false }
        return (end ?? start) < now
    }
}

enum TodaySchedule {
    /// Today's occurrences off EventKit, every one, past ones included; nil
    /// without full access, so the day can offer Connect Calendar instead.
    @MainActor
    static func calendarEvents(now: Date = .now) -> [ScheduleItem]? {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return nil }
        let cal = FeedScreen.groupingCalendar
        let start = cal.startOfDay(for: now)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        let store = EKEventStore()
        let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
        return events.compactMap { event in
            guard let begins = event.startDate else { return nil }
            let series = event.eventIdentifier ?? event.calendarItemIdentifier
            return ScheduleItem(id: "ek:\(series)@\(Int(begins.timeIntervalSince1970))",
                                title: event.title ?? String(localized: "Event"),
                                start: begins, end: event.endDate, allDay: event.isAllDay,
                                source: "Calendar", thingID: nil)
        }
    }

    /// The day in order: all-day first, then by start.
    static func ordered(_ items: [ScheduleItem]) -> [ScheduleItem] {
        items.sorted {
            if $0.allDay != $1.allDay { return $0.allDay }
            return $0.start < $1.start
        }
    }
}

extension FeedScreen {
    /// Reads the day: EventKit's occurrences today, then the dated rows
    /// Coming up holds for today that EventKit does not (a subscribed
    /// calendar, a renewal, a deadline). Called after `loadDayComingUp`.
    @MainActor
    func loadTodaySchedule() {
        let events = TodaySchedule.calendarEvents()
        calendarReadable = events != nil
        let held = dayComingUp.filter { thing in
            thing.isLive
                && Self.groupingCalendar.isDateInToday(Self.comingUpWhen(thing))
                && !(thing.sourceRef ?? "").hasPrefix("ekevent:")
        }.map { thing in
            ScheduleItem(id: thing.id.uuidString, title: TitleSeam.split(thing.title).name,
                         start: Self.comingUpWhen(thing), end: nil, allDay: false,
                         source: thing.source, thingID: thing.id)
        }
        todaySchedule = TodaySchedule.ordered((events ?? []) + held)
        #if DEBUG
        NSLog("[Casberi] todaySchedule| items=%d over=%d calendar=%@", todaySchedule.count,
              todaySchedule.filter { $0.isOver(now: .now) }.count, calendarReadable ? "yes" : "no")
        #endif
    }

    /// Home's day under Today's feeds: the header, every line of the day,
    /// and what is left. A free day says so; a day without Calendar offers it.
    @ViewBuilder
    func todayScheduleSections() -> some View {
        let now = Date.now
        let items = todaySchedule
        let ahead = items.filter { !$0.isOver(now: now) }
        Section {
            Text("Your day")
                .dsText(.heading20)
                .fontWeight(.semibold)
                .foregroundStyle(DS.brandInk)
                .padding(.leading, DSRoomChassis.rowInset)
                .padding(.top, DS.Space.s6)
                .padding(.bottom, DS.Space.s1)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            ForEach(items) { item in
                scheduleRow(item, over: item.isOver(now: now))
            }
            if ahead.isEmpty {
                if !calendarReadable && items.isEmpty {
                    DSDoorRow(icon: ScopeTileGlyph.calendars, label: "Connect Calendar") {
                        route.openSetup(forOffer: "Calendar")
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.rowInset,
                                              bottom: 0, trailing: DSRoomChassis.rowInset))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    Text(items.isEmpty ? "Nothing on your calendar today." : "Nothing else today.")
                        .dsText(.body17)
                        .foregroundStyle(DS.textSecondary)
                        .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DSRoomChassis.rowInset,
                                                  bottom: DS.Space.s2, trailing: DSRoomChassis.rowInset))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
        }
    }

    /// One line of the day: the app's mark, the title, the time trailing. It
    /// opens its row when Casberi holds one, else Calendar at that hour.
    private func scheduleRow(_ item: ScheduleItem, over: Bool) -> some View {
        let time: Text = item.allDay
            ? Text("All day")
            : Text(item.start.formatted(date: .omitted, time: .shortened))
        return DSPushRow(title: Text(verbatim: item.title), fact: time) {
            openScheduleItem(item)
        } leading: {
            BridgeIcon(name: item.source, size: DS.Face.row)
        }
        .opacity(over ? 0.45 : 1)
        .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.rowInset,
                                  bottom: 0, trailing: DSRoomChassis.rowInset))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func openScheduleItem(_ item: ScheduleItem) {
        if let id = item.thingID, let thing = dayComingUp.first(where: { $0.id == id && $0.isLive }) {
            openThing(thing)
            return
        }
        // Calendar at that hour: `calshow:` takes seconds since 2001.
        if let url = URL(string: "calshow:\(Int(item.start.timeIntervalSinceReferenceDate))") {
            openExternal(url)
        }
    }

    /// The week past today, for the Coming up door's count.
    var comingUpLaterCount: Int {
        dayComingUp.filter { $0.isLive && !Self.groupingCalendar.isDateInToday(Self.comingUpWhen($0)) }.count
    }
}
