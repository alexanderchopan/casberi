import SwiftUI

// THE ACCOUNT MENU OF A MERGED ROOM THAT DRAWS NO SCREEN OF ITS OWN
// (prd §1049, §1050d, built §1052). Reading first; Agents, Media, Life, Day
// and Work follow. The Wallet keeps its own menu (addresses and apps), and
// Testnets crosses networks from each network's menu (§1050k). A pick
// narrows the list to that app (`selectedSeat`, through `walletScopeAllows`)
// and the box to that app's own head, or to its newest row.
extension FeedScreen {
    /// The apps the menu lists: the room's connected ones, and only once
    /// there are two to choose between.
    var mergedMenuSeats: [RoomAccounts.Seat] {
        guard source != CategoryFold.walletRoom, RoomAccounts.mergedRooms.contains(source)
        else { return [] }
        let seats = RoomAccounts.connected(in: source, names: connectedSeatNames)
            .filter { !$0.ownScreen && chrome.seatShows($0) }
        return seats.count > 1 ? seats : []
    }

    var mergedMenuDraws: Bool { !mergedMenuSeats.isEmpty }

    /// The menu, a glass pill in the title row (prd §1066), as the Wallet's is.
    @ViewBuilder
    var mergedAccountsPill: some View {
        let seats = mergedMenuSeats
        let all = DSAccountSlot(id: "", name: String(localized: "All apps"), sub: nil,
                                faces: seats.prefix(2).map { .mark(url: nil, source: $0.mark) })
        let slots = [all] + seats.map { seat in
            DSAccountSlot(id: RoomAccounts.scopeID(seat), name: seat.name, sub: nil,
                          faces: [.mark(url: nil, source: seat.mark)])
        }
        let picked = selectedSeat.map(RoomAccounts.scopeID)
        let showing = slots.first { !$0.id.isEmpty && $0.id == picked } ?? all
        let room = source
        DSScopeMenu(slots: slots, showing: showing,
                    spoken: { String(localized: "Showing: \($0)") },
                    onPick: { id in
                        withAnimation(DS.Motion.standard) {
                            chrome.mergedScope[room] = (id?.isEmpty ?? true) ? nil : id
                            // A person is picked from the app's faces; another
                            // app's row may not hold them (prd §1079).
                            if room == RoomAccounts.socialRoom { chrome.personScope = nil }
                        }
                    })
    }
}

// MARK: - Day (prd §1049, built §1056)

extension FeedScreen {
    /// When a Day row happens: a to-do's due date, else the thing's own time
    /// (an event's start, a mail's arrival).
    private static func dayWhen(_ thing: Thing) -> Date { thing.dueAt ?? thing.capturedAt }

    /// THE DAY READS FORWARD (Calendar's agenda, §994): today and the days
    /// ahead, soonest first, then what already happened, newest day first.
    /// One list, so a mail that arrived this morning stands in today beside
    /// the meeting after lunch.
    private func dayRoomGroups(_ visible: [Thing]) -> [(String, [Thing])] {
        let cal = Self.groupingCalendar
        let today = cal.startOfDay(for: .now)
        var buckets: [Date: [Thing]] = [:]
        for thing in visible where thing.isLive {
            buckets[cal.startOfDay(for: Self.dayWhen(thing)), default: []].append(thing)
        }
        let ahead = buckets.keys.filter { $0 >= today }.sorted()
        let past = buckets.keys.filter { $0 < today }.sorted(by: >)
        return (ahead + past).map { day in
            (dayLabel(day), (buckets[day] ?? []).sorted { Self.dayWhen($0) < Self.dayWhen($1) })
        }
    }

    /// What New can make: only what a connected seat makes, and only where
    /// its app answers (§83).
    var dayMakes: [DayMake] {
        let seats = Set(RoomAccounts.connected(in: RoomAccounts.dayRoom, names: connectedSeatNames)
            .map(\.name))
        return DayMake.allCases.filter { make in
            switch make {
            case .event:    return seats.contains("Calendar") && !DS.isMac
            case .reminder: return seats.contains("Reminders")
                                && HandOffState.answers("x-apple-reminderkit")
            case .email:    return dayCompose != nil
            }
        }
    }

    /// The connected mail seat's compose door, Gmail first.
    private var dayCompose: URL? {
        let seats = Set(RoomAccounts.connected(in: RoomAccounts.dayRoom, names: connectedSeatNames)
            .map(\.name))
        for mail in ["Gmail", "iCloud Mail"] where seats.contains(mail) {
            if let action = SourceActions.action(forSource: mail),
               case .openURL(let url) = action.run { return url }
        }
        return nil
    }

    func makeInDay(_ make: DayMake) {
        let url: URL? = {
            switch make {
            case .event:    return URL(string: "calshow://")
            case .reminder: return URL(string: "x-apple-reminderkit://")
            case .email:    return dayCompose
            }
        }()
        if let url { openExternal(url) }
    }

    /// The Day room: the cover (what is next, else the newest), All · New,
    /// the menu, then the days.
    @ViewBuilder
    func dayRoomSections(_ visible: [Thing], nextEventID: UUID?, heroShown: Bool) -> some View {
        let groups = dayRoomGroups(visible)
        let now = Date.now
        let next = visible.filter { $0.isLive && Self.dayWhen($0) >= now }
            .min { Self.dayWhen($0) < Self.dayWhen($1) }
        let cover = heroShown ? nil : (next ?? visible.first { $0.isLive })
        if let cover {
            Section { ledeListRow(cover) }
        } else if !heroShown {
            Section {
                emptyLeadRow(headline: DSProse.text("Nothing ahead"),
                             words: Text("Your calendar, to-dos and mail appear here"))
            }
        }
        let makes = dayMakes
        Section {
            DSScopeTiles(sections: DayScope.allCases.filter { !$0.isVerb || !makes.isEmpty },
                         active: .all, attention: [], verbs: [.new]) { picked in
                guard picked.isVerb else { return }
                if makes.count == 1 { makeInDay(makes[0]) } else { dayMakeOpen = true }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.inset,
                                      bottom: DSRoomChassis.leadGap,
                                      trailing: DSRoomChassis.inset))
        }
        roomScopeSection
        groupedSections(liftingCover(groups, id: cover?.id), nextEventID: nextEventID)
    }
}

// MARK: - Work (prd §1049, built §1057)

extension FeedScreen {
    /// The deadlines ahead, soonest first: a dispute's reply-by, a cert or
    /// token that expires, a ticket due, a build that lapses.
    private func workDeadlines(_ visible: [Thing]) -> [Thing] {
        let now = Date.now
        return visible.filter { thing in
            guard thing.isLive, let due = thing.dueAt else { return false }
            return due >= now
        }
        .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
    }

    /// What is waiting on the person now, newest first (`WorkAsk`, prd §1080).
    private func workAsks(_ visible: [Thing]) -> [Thing] {
        let now = Date.now
        return visible.filter { $0.isLive && WorkAsk.needsYou(WorkStage.Row($0), at: $0.capturedAt, now: now) }
            .sorted { $0.capturedAt > $1.capturedAt }
    }

    /// What Watch can follow: the connected seats that keep a watch.
    var workWatches: [WorkWatch] {
        let seats = Set(RoomAccounts.connected(in: RoomAccounts.workRoom, names: connectedSeatNames)
            .map(\.name))
        return WorkWatch.allCases.filter { seats.contains($0.rawValue) }
    }

    /// GitHub's own tray (§1031); the others' watch lists live on their
    /// account pages.
    func watchInWork(_ watch: WorkWatch) {
        if watch == .github {
            feedSheet = .githubWatch
        } else if let destination = BridgeRouter.destination(forOffer: watch.rawValue) {
            route.openAccount(destination)
        }
    }

    /// The Work room: the newest thing, All · Coming up · Watch, the menu,
    /// then the list — one row per PR, issue, ticket, incident, deployment or
    /// build, standing at its newest event (prd §1079).
    ///
    /// **The box is the newest event, not the nearest deadline** (prd §1079,
    /// user: "people like to see their PRs and that header card update to
    /// newest thing", amending §1057). Deadlines keep their own tile.
    @ViewBuilder
    func workRoomSections(_ allVisible: [Thing], nextEventID: UUID?, heroShown: Bool) -> some View {
        let visible = objectFolded(allVisible)
        let comingUp = chrome.workScope == .comingUp
        // What needs you now leads Coming up, then what is due (prd §1080);
        // a row that is both stands once, under the asks.
        let asks = comingUp ? workAsks(visible) : []
        let askIDs = Set(asks.map(\.id))
        let deadlines = workDeadlines(visible).filter { !askIDs.contains($0.id) }
        // Coming up leads with what needs you, else the soonest deadline.
        let cover = heroShown ? nil
            : (comingUp ? (asks.first ?? deadlines.first) : visible.first { $0.isLive })
        if let cover {
            Section { ledeListRow(cover) }
        } else if !heroShown {
            // A head already holds the box (a picked app's own, prd §1067):
            // a second, empty box under it pushed the tiles off the screen.
            Section {
                emptyLeadRow(headline: DSProse.text("Nothing yet"),
                             words: Text("What you build lands here"))
            }
        }
        let watches = workWatches
        Section {
            DSScopeTiles(sections: WorkScope.allCases.filter { !$0.isVerb || !watches.isEmpty },
                         active: chrome.workScope, attention: [], verbs: [.watch]) { picked in
                if picked.isVerb {
                    if watches.count == 1 { watchInWork(watches[0]) } else { workWatchOpen = true }
                    return
                }
                withAnimation(DS.Motion.standard) { chrome.workScope = picked }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.inset,
                                      bottom: DSRoomChassis.leadGap,
                                      trailing: DSRoomChassis.inset))
        }
        roomScopeSection
        if comingUp {
            let waiting = asks.filter { $0.id != cover?.id }
            let rest = deadlines.filter { $0.id != cover?.id }
            if waiting.isEmpty && rest.isEmpty && cover == nil {
                Section {
                    DSSkeletonRows(label: Text("Nothing needs you, and nothing is due."))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } else {
                // Named by what it is, not by a time (prd §740).
                if !waiting.isEmpty {
                    groupedSections([(String(localized: "Needs you"), waiting)],
                                    nextEventID: nextEventID, dated: false)
                }
                // Soonest first: the days in order, each due-ordered.
                let cal = Self.groupingCalendar
                let days = Dictionary(grouping: rest) { cal.startOfDay(for: $0.dueAt ?? .now) }
                groupedSections(days.keys.sorted().map { (dayLabel($0), days[$0] ?? []) },
                                nextEventID: nextEventID)
            }
        } else {
            let days = chronoDays(visible)
            groupedSections(liftingCover(days, id: cover?.id), nextEventID: nextEventID,
                            boundary: boundaryThingID(in: days))
        }
    }
}
