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
    ///
    /// Then what the app dates without storing (prd §1327 item 3): each
    /// plan's next renewal off the Wallet's own reading (`SubscriptionsReading`)
    /// and each card's payment date off Home's (`SpendingReading`), read here
    /// because Day may open before the Wallet has, turned into entries by
    /// `DayDated` and never re-dated. A Rocket Money bill is a plan there, so
    /// once the plans have read, its stored row steps aside and the plan
    /// stands for it: one bill, one row (§1105).
    @MainActor
    func loadDayComingUp() async {
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
        let stored = (a + b)
            .filter { $0.isLive }
            .filter { let w = Self.comingUpWhen($0); return w > now && w < end }
            .filter { seen.insert($0.id).inserted }
            .sorted { Self.comingUpWhen($0) < Self.comingUpWhen($1) }
        let plans = SubscriptionsReading.shared
        // The plan stands for a bill only once the plans have read.
        func kept() -> [Thing] {
            plans.read ? stored.filter { $0.isLive && !SubscriptionsSource.isBill($0, now: now) } : stored
        }
        dayComingUp = kept()

        await plans.refresh(modelContext, now: now)
        guard !Task.isCancelled else { return }
        await SpendingReading.shared.refresh(modelContext, now: now)
        guard !Task.isCancelled else { return }
        let cal = Self.groupingCalendar
        let dated = DayDated.entries([
            DayDated.renewals(plans.items, now: now, end: end, calendar: cal),
            DayDated.cardDues(SpendingReading.shared.cards, now: now, end: end, calendar: cal),
        ])
        let rows = kept()
        if rows.map(\.id) != dayComingUp.map(\.id) { dayComingUp = rows }
        if dated != dayComingUpDated { dayComingUpDated = dated }
        #if DEBUG
        // `comingUp|` — how many rows Home's Later today and Day's week hold
        // (prd §1139), for a check that cannot scroll; `dated=` what the
        // places computed (prd §1327 item 3), then by place.
        let later = rows.filter { $0.isLive && Self.groupingCalendar.isDateInToday(Self.comingUpWhen($0)) }
        NSLog("[Casberi] comingUp| laterToday=%d week=%d dated=%d plans=%d cards=%d first=%@",
              later.count, rows.count, dated.count,
              dated.filter { $0.place == .subscription }.count, dated.filter { $0.place == .card }.count,
              later.first.map { TitleSeam.split($0.title).name } ?? "-")
        #endif
    }

    /// What re-reads Coming up: a pick of the tile, and every refresh the
    /// Wallet's readings take (`walletSpendingKey` carries the pulse and the
    /// hand-tracked list).
    var dayComingUpKey: String { "\(chrome.dayScope.rawValue)|\(walletSpendingKey)" }

    /// The days ahead as groups: "Later today", "Tomorrow", then a weekday;
    /// each day's stored rows, and by its label the entries computed for it
    /// (`DayDated.days`), so a day only a renewal stands on is a day too.
    func comingUpDays(_ rows: [Thing], dated: [DayDated.Entry])
        -> (groups: [(String, [Thing])], entries: [String: [DayDated.Entry]]) {
        let live = rows.filter(\.isLive)
        let byID = Dictionary(live.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let days = DayDated.days(stored: live.map { (id: $0.id, when: Self.comingUpWhen($0)) },
                                 dated: dated, calendar: Self.groupingCalendar)
        var groups: [(String, [Thing])] = []
        var entries: [String: [DayDated.Entry]] = [:]
        for day in days {
            let label = Self.groupingCalendar.isDateInToday(day.start)
                ? String(localized: "Later today") : Self.dayWord(day.start)
            groups.append((label, day.stored.compactMap { byID[$0] }))
            if !day.dated.isEmpty { entries[label] = day.dated }
        }
        return (groups, entries)
    }

    /// Coming up's box: the week as seven days, a dot under a day with
    /// something on it, at the lead's one size (prd §760).
    var dayComingUpBox: some View {
        let days = Set(dayComingUp.filter(\.isLive).map {
            Self.groupingCalendar.startOfDay(for: Self.comingUpWhen($0))
        } + dayComingUpDated.map { Self.groupingCalendar.startOfDay(for: $0.when) })
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
        .task(id: dayComingUpKey) { await loadDayComingUp() }
        .feedRowBackground()
        .listRowSeparator(.hidden)
        .listRowInsets(.init(top: DS.Space.s2, leading: DSRoomChassis.inset,
                             bottom: DSRoomChassis.leadGap, trailing: DSRoomChassis.inset))
    }

    @ViewBuilder
    func dayComingUpSections(nextEventID: UUID?) -> some View {
        let (groups, entries) = comingUpDays(dayComingUp, dated: dayComingUpDated)
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
                    .feedRowBackground()
                    .listRowSeparator(.hidden)
                if !connectedSeatNames.contains("Calendar") {
                    DSDoorRow(icon: ScopeTileGlyph.calendars, label: "Connect Calendar") {
                        route.openSetup(forOffer: "Calendar")
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.rowInset,
                                              bottom: 0, trailing: DSRoomChassis.rowInset))
                    .feedRowBackground()
                    .listRowSeparator(.hidden)
                }
                DSDoorRow(icon: ScopeTileGlyph.new, label: "Subscribe to a calendar") {
                    feedSheet = .calendarSubscribe
                }
                .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.rowInset,
                                          bottom: DS.Space.s4, trailing: DSRoomChassis.rowInset))
                .feedRowBackground()
                .listRowSeparator(.hidden)
            }
        } else {
            groupedSections(groups, nextEventID: nextEventID, entries: entries)
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
