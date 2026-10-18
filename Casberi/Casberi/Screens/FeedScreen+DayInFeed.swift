import SwiftUI
import SwiftData

// **DAY IS THE FEED'S FIRST SECTION (prd §1343, user: "we just make day a
// section, and we remove the 'coming up' filter bc we can have 'see more' in
// the card"; "A expands in place … if you click 'see all' in a section it
// expands in place, and also each category header has a + sign").** Not a
// tab: tabs are places you manage. **And it is dated rows like every section
// (prd §1413, user: "its like the odd man in the feed"; "i say we just get
// rid of the grid"; "that way we aren't conflating needs you w/ day").** The
// week strip, the five weeks that opened in place, the picked day, the
// next-thing row under the strip and the Needs you it gathered from every
// place are deleted: today and what follows under their day labels, in the
// Feed's grouped row, capped like every section, and More walks forward
// through the five weeks the rows are read for. Needs you lives in its place
// (`FeedScreen+WalletNeeds.swift`, Work's own section). Its + is in its
// header (`sectionAdds`): an event, a reminder, an email, a plan.
extension FeedScreen {

    /// `rows` is Day's room's own list on iPad and the Mac (prd §1344);
    /// in the Feed, nil: the section reads its own (`dayFeedRows`).
    @ViewBuilder
    func dayFeedSections(nextEventID: UUID?, rows: [Thing]? = nil) -> some View {
        let visible = (rows ?? dayFeedRows).live
        let window = dayFeedWindow(visible)
        // The window is the section's own (things and renewals counted
        // together); the days draw uncapped inside it, then More.
        let _ = { Self.sectionCapNow = (RoomAccounts.dayRoom, Int.max) }()
        groupedSections(window.days, nextEventID: nextEventID, renewals: window.renewals)
        let _ = { Self.sectionCapNow = (RoomAccounts.dayRoom, window.cap) }()
        if window.more { sectionMoreRow(RoomAccounts.dayRoom) }
    }

    /// **ONE CAP FOR THE WHOLE SECTION (prd §1343).** The days — their
    /// things and renewals together — while the cap lasts; More adds ten,
    /// as every section's does. The cap counts ROWS: a day fuller than what
    /// is left is cut at the cap, never drawn whole past it (2026-10-16,
    /// user: "it's also showing me more than five items"). Nothing but the
    /// cap bounds it (prd §1413): More reaches to the end of the five weeks
    /// the rows are read for, and no Needs you stands in the window.
    func dayFeedWindow(_ visible: [Thing])
        -> (days: [(String, [Thing])], renewals: [String: [Subscriptions.Item]], more: Bool, cap: Int) {
        let cap = sectionCaps[RoomAccounts.dayRoom] ?? Self.sectionFirstRows
        var budget = cap
        var more = false
        let renewals = dayRenewals()
        let rows = visible
        let byDay = Dictionary(grouping: renewals) {
            dayLabel(Self.groupingCalendar.startOfDay(for: $0.next ?? .now))
        }
        var days: [(String, [Thing])] = []
        var shown: [String: [Subscriptions.Item]] = [:]
        for (label, things) in dayRoomGroups(rows, renewals: renewals) {
            let live = things.filter(\.isLive)
            let plans = byDay[label] ?? []
            guard live.count + plans.count > 0 else { continue }
            guard budget > 0 else { more = true; break }
            let keptThings = Array(live.prefix(budget))
            let keptPlans = Array(plans.prefix(budget - keptThings.count))
            if keptThings.count + keptPlans.count < live.count + plans.count { more = true }
            days.append((label, keptThings))
            if !keptPlans.isEmpty { shown[label] = keptPlans }
            budget -= keptThings.count + keptPlans.count
        }
        return (days, shown, more, cap)
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

// **NOTES IS A FEED SECTION (prd §1347, user: "mock up what notes would look
// like in the feed", then "lets build it").** The reading half: your newest
// notes and the apps you write in, one plain list as the Notes page draws it
// (no day headers, the time at the row's edge), capped like every section,
// then More. The managing half — folders, voice, an old note — is the Notes
// page, reached from Library.
extension FeedScreen {
    @ViewBuilder
    func notesFeedSection(_ things: [Thing], nextEventID: UUID?) -> some View {
        let cap = sectionCaps[HomeScope.notesSection] ?? Self.sectionFirstRows
        let notes = things.filter(\.isLive).sorted { $0.capturedAt > $1.capturedAt }
        daySection("", Array(notes.prefix(cap)), nextEventID: nextEventID, dated: false, headed: false)
        if notes.count > cap { sectionMoreRow(HomeScope.notesSection) }
    }

    /// The section's rows: your notes and the apps you write in, newest
    /// first, one bounded fetch from the Feed's `.task`, never a body (§628).
    /// The sources are spelled into the predicate because it cannot read
    /// `Pinboard.writtenSources`; `Pinboard.inRoom` narrows "You" to the
    /// note and voice kinds after the fetch.
    @MainActor
    func loadNotesFeedRows() {
        let sources = ["You"] + Pinboard.writtenSources
        var newest = FetchDescriptor<Thing>(
            predicate: #Predicate { sources.contains($0.source) },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        newest.fetchLimit = Self.notesFeedFetchLimit
        let rows = ((try? modelContext.fetch(newest)) ?? []).filter { $0.isLive && Pinboard.inRoom($0) }
        guard rows.map(\.id) != notesFeedRows.map(\.id) else { return }
        notesFeedRows = rows
    }

    /// Past every cap More can reach in a sitting; the Notes page lists the rest.
    static let notesFeedFetchLimit = 200
}
