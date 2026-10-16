import SwiftUI
import SwiftData

// **DAY IS THE FEED'S FIRST SECTION (prd §1343, user: "we just make day a
// section, and we remove the 'coming up' filter bc we can have 'see more' in
// the card"; "A expands in place … if you click 'see all' in a section it
// expands in place, and also each category header has a + sign").** Not a
// tab: tabs are places you manage. The section rests on this week as a strip
// of dots and the next thing; a tapped day opens the five weeks in place and
// stands in for the section's rows; Needs you leads the rows, by place; then
// today and what follows, capped like every section, with its More. Its + is
// in its header (`sectionAdds`): an event, a reminder, an email, a plan.
extension FeedScreen {

    @ViewBuilder
    func dayFeedSections(nextEventID: UUID?) -> some View {
        let all = dayFeedRows.live
        let visible = all
        let marks = dayCalendarMarks(all)
        let now = Date.now
        let next = all.filter { $0.isLive && Self.dayWhen($0) >= now }
            .min { Self.dayWhen($0) < Self.dayWhen($1) }
        dayFeedCalendarRow(marks: marks, next: next)
            // The renewals on the calendar read the Wallet's own reading, from
            // here, since the Feed may open before the Wallet has; the rows and
            // Needs you are read by the Feed's own list (prd §1343).
            .task(id: walletSubscriptionsKey) { await SubscriptionsReading.shared.refresh(modelContext) }
        if let picked = daySelected {
            dayPickedSection(picked, visible, nextEventID: nextEventID)
        } else {
            let window = dayFeedWindow(visible)
            dayNeedsRows(nextEventID: nextEventID, named: true, limit: window.needs)
            // The window is the section's own (needs and days counted
            // together); the days draw uncapped inside it, then More.
            let _ = { Self.sectionCapNow = (RoomAccounts.dayRoom, Int.max) }()
            groupedSections(window.days, nextEventID: nextEventID, renewals: window.renewals)
            let _ = { Self.sectionCapNow = (RoomAccounts.dayRoom, window.cap) }()
            if window.more { sectionMoreRow(RoomAccounts.dayRoom) }
        }
    }

    /// **ONE CAP FOR THE WHOLE SECTION (prd §1343).** Needs you first, then
    /// whole days — their things and renewals together — while the cap
    /// lasts; More adds ten, as every section's does. A month of renewals
    /// no longer runs the section past the screen.
    func dayFeedWindow(_ visible: [Thing])
        -> (needs: Int, days: [(String, [Thing])], renewals: [String: [Subscriptions.Item]], more: Bool, cap: Int) {
        let cap = sectionCaps[RoomAccounts.dayRoom] ?? Self.sectionFirstRows
        let waiting = dayNeeds.live.count
        // Needs you takes three on the first page, so today still shows
        // under it; More opens the rest.
        let needs = min(waiting, cap == Self.sectionFirstRows ? 3 : cap)
        // At least today, whole, whatever Needs you took.
        var budget = max(cap - needs, 1)
        var more = waiting > needs
        let renewals = dayRenewals()
        let byDay = Dictionary(grouping: renewals) {
            dayLabel(Self.groupingCalendar.startOfDay(for: $0.next ?? .now))
        }
        var days: [(String, [Thing])] = []
        var shown: [String: [Subscriptions.Item]] = [:]
        for (label, things) in dayRoomGroups(visible, renewals: renewals) {
            let plans = byDay[label] ?? []
            let count = things.filter(\.isLive).count + plans.count
            guard count > 0 else { continue }
            guard budget > 0 else { more = true; break }
            days.append((label, things))
            if !plans.isEmpty { shown[label] = plans }
            budget -= count
        }
        return (needs, days, shown, more, cap)
    }

    /// The week, its dots, and the next thing under it; open, all five
    /// weeks and the way back to today.
    private func dayFeedCalendarRow(marks: [WalletCalendar.Mark], next: Thing?) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            WalletCalendar(marks: marks, dots: true, selected: daySelected,
                           onDay: pickFeedDay,
                           shownWeeks: dayCalendarOpen ? WalletCalendar.weeks : 1)
            if dayCalendarOpen {
                Button {
                    DSHaptic.selection()
                    withAnimation(DS.Motion.standard) {
                        dayCalendarOpen = false
                        daySelected = nil
                    }
                } label: {
                    Text("Back to today")
                        .dsText(.body17)
                        .foregroundStyle(DS.tint)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: DS.Hit.min)
                        .contentShape(Rectangle())
                }
                .buttonStyle(RowPress())
            } else if let next {
                Button {
                    openThing(next)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                        Text(verbatim: next.title)
                            .dsText(.body17).fontWeight(.semibold)
                            .foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                        Text(verbatim: Self.dayFeedWhen(next))
                            .dsText(.subhead12)
                            .foregroundStyle(DS.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPress())
            }
        }
        .animation(DS.Motion.standard, value: dayCalendarOpen)
        .listRowInsets(EdgeInsets(top: DS.Space.s1, leading: DSRoomChassis.rowInset,
                                  bottom: DS.Space.s2, trailing: DSRoomChassis.rowInset))
        .feedRowBackground()
        .listRowSeparator(.hidden)
    }

    /// Day's rows for the section: its apps' events and due things from
    /// the start of today to the end of the calendar's five weeks, one
    /// bounded fetch from the section's `.task`, never a body (§628).
    @MainActor
    func loadDayFeedRows() {
        let cal = Self.groupingCalendar
        let start = cal.startOfDay(for: .now)
        let end = WalletCalendar.window(now: .now, calendar: cal).end
        let sources = RoomAccounts.roomSources(RoomAccounts.dayRoom)
        var starting = FetchDescriptor<Thing>(
            predicate: #Predicate { sources.contains($0.source) && $0.capturedAt >= start && $0.capturedAt < end },
            sortBy: [SortDescriptor(\.capturedAt)])
        starting.fetchLimit = 300
        var due = FetchDescriptor<Thing>(
            predicate: #Predicate { sources.contains($0.source) && $0.dueAt != nil })
        due.fetchLimit = 300
        var seen = Set<UUID>()
        let rows = (((try? modelContext.fetch(starting)) ?? []) + ((try? modelContext.fetch(due)) ?? []))
            .filter { $0.isLive }
            .filter { let w = Self.dayWhen($0); return w >= start && w < end }
            .filter { seen.insert($0.id).inserted }
        guard rows.map(\.id) != dayFeedRows.map(\.id) else { return }
        dayFeedRows = rows
    }

    /// A day tapped in the section: the calendar opens in place on it; the
    /// same day again lets it go, the calendar staying open.
    func pickFeedDay(_ day: Date) {
        let cal = Self.groupingCalendar
        withAnimation(DS.Motion.standard) {
            dayCalendarOpen = true
            if let picked = daySelected, cal.isDate(picked, inSameDayAs: day) {
                daySelected = nil
            } else {
                daySelected = cal.startOfDay(for: day)
            }
        }
    }

    /// "9:30 AM", "Tomorrow", "Oct 22" — when the next thing is, as its row
    /// would say it; an all-day thing has no clock (prd §1264).
    static func dayFeedWhen(_ thing: Thing) -> String {
        let start = dayWhen(thing)
        let cal = groupingCalendar
        let allDay = thing.factList.contains { $0.action == .allDay }
        if cal.isDateInToday(start) {
            return allDay ? String(localized: "Today") : start.formatted(date: .omitted, time: .shortened)
        }
        if cal.isDateInTomorrow(start) { return String(localized: "Tomorrow") }
        return start.formatted(.dateTime.month(.abbreviated).day())
    }

    /// The + menu's marks for Day's makes.
    static func dayMakeGlyph(_ make: DayMake) -> String {
        switch make {
        case .event:        return "calendar.badge.plus"
        case .reminder:     return "checklist"
        case .email:        return "envelope"
        case .subscription: return ScopeTileGlyph.subscriptions
        }
    }
}
