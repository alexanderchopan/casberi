import SwiftUI
import SwiftData

// COMING UP (prd §1136 item 7, §1136c, user: "well 'day' aggregated could
// have aggregated calendar"): one calendar across every app, as Day's Coming
// up tile — Day is the category about time — with Home ending in a door to
// it. It reads what the rooms already date: an event's start, a deadline's
// `dueAt`, a renewal, a grant, a reminder, a calendar you subscribed to
// (§1137). It is the one tile in Day that reaches across categories.
extension FeedScreen {
    /// How far ahead Coming up looks: the week its strip draws, today and the
    /// six days after (prd §1136b, user: "1 week pls").
    static let comingUpDays = 7

    /// When a row happens: its deadline, else its own date (an event's start
    /// is `capturedAt`, `ScheduleIngest`'s rule).
    static func comingUpWhen(_ thing: Thing) -> Date { thing.dueAt ?? thing.capturedAt }

    /// The end of the week ahead: midnight after its seventh day.
    static func comingUpEnd(now: Date = .now) -> Date {
        let today = groupingCalendar.startOfDay(for: now)
        return groupingCalendar.date(byAdding: .day, value: comingUpDays, to: today)
            ?? now.addingTimeInterval(Double(comingUpDays) * 86_400)
    }

    /// Every app's rows ahead this week, soonest first. Two bounded fetches —
    /// what STARTS ahead (events), and what is DUE ahead (deadlines, bills,
    /// reminders, whose `capturedAt` is when they landed) — run from the
    /// tile's `.task`, on the main context, never from a body.
    @MainActor
    func loadDayComingUp() {
        let now = Date.now
        let end = Self.comingUpEnd(now: now)
        var starting = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.capturedAt > now && $0.capturedAt < end },
            sortBy: [SortDescriptor(\.capturedAt)])
        starting.fetchLimit = 300
        var due = FetchDescriptor<Thing>(predicate: #Predicate { $0.dueAt != nil })
        due.fetchLimit = 600
        let a = (try? modelContext.fetch(starting)) ?? []
        let b = (try? modelContext.fetch(due)) ?? []
        var seen = Set<UUID>()
        dayComingUp = (a + b)
            .filter { $0.isLive }
            .filter { let w = Self.comingUpWhen($0); return w > now && w < end }
            .filter { seen.insert($0.id).inserted }
            .sorted { Self.comingUpWhen($0) < Self.comingUpWhen($1) }
        #if DEBUG
        // `comingUp|` — how many rows Home's Later today and Day's week hold
        // (prd §1139), for a check that cannot scroll.
        let later = dayComingUp.filter { Self.groupingCalendar.isDateInToday(Self.comingUpWhen($0)) }
        NSLog("[Casberi] comingUp| laterToday=%d week=%d first=%@", later.count, dayComingUp.count,
              later.first.map { TitleSeam.split($0.title).name } ?? "-")
        #endif
    }

    /// The days ahead as groups: "Later today", "Tomorrow", then a weekday.
    func comingUpDays(_ rows: [Thing]) -> [(String, [Thing])] {
        var out: [(String, [Thing])] = []
        for thing in rows where thing.isLive {
            let when = Self.comingUpWhen(thing)
            let label = Self.groupingCalendar.isDateInToday(when)
                ? String(localized: "Later today") : Self.dayWord(when)
            if out.last?.0 == label { out[out.count - 1].1.append(thing) } else { out.append((label, [thing])) }
        }
        return out
    }

    /// Coming up's box: the week as seven days, a dot under a day with
    /// something on it, at the lead's one size (prd §760).
    var dayComingUpBox: some View {
        let days = Set(dayComingUp.filter(\.isLive).map {
            Self.groupingCalendar.startOfDay(for: Self.comingUpWhen($0))
        })
        return VStack(alignment: .leading, spacing: DS.Space.s3) {
            Text("This week")
                .dsText(.heading20)
                .foregroundStyle(DS.textPrimary)
            ComingUpWeek(days: days)
        }
        .padding(.horizontal, DS.Space.s2)
        .frame(maxWidth: .infinity, minHeight: DSRoomChassis.leadBox,
               maxHeight: DSRoomChassis.leadBox, alignment: .leading)
        .dsRoomHeadBlock()
        .task(id: chrome.dayScope) { loadDayComingUp() }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(.init(top: DS.Space.s2, leading: DSRoomChassis.inset,
                             bottom: DSRoomChassis.leadGap, trailing: DSRoomChassis.inset))
    }

    @ViewBuilder
    func dayComingUpSections(nextEventID: UUID?) -> some View {
        let groups = comingUpDays(dayComingUp)
        if groups.isEmpty {
            // Empty, it shows what would fill it (prd §769), as two doors
            // (prd §1137a): no calendar is added for you, because a default
            // would reach a host you never chose and fill the week with
            // dates you never asked for.
            Section {
                Text("Nothing on the calendar this week.")
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
                    .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DSRoomChassis.rowInset,
                                              bottom: DS.Space.s2, trailing: DSRoomChassis.rowInset))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                if !connectedSeatNames.contains("Calendar") {
                    DSDoorRow(icon: ScopeTileGlyph.calendars, label: "Connect Calendar") {
                        route.openSetup(forOffer: "Calendar")
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.rowInset,
                                              bottom: 0, trailing: DSRoomChassis.rowInset))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                DSDoorRow(icon: ScopeTileGlyph.new, label: "Subscribe to a calendar") {
                    feedSheet = .calendarSubscribe
                }
                .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.rowInset,
                                          bottom: DS.Space.s4, trailing: DSRoomChassis.rowInset))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        } else {
            groupedSections(groups, nextEventID: nextEventID)
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
        let week = (0..<FeedScreen.comingUpDays).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
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
