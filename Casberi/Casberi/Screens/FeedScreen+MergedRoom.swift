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

}

// MARK: - Day (prd §1049, built §1056)

extension FeedScreen {
    /// When a Day row happens: a to-do's due date, else the thing's own time
    /// (an event's start, a mail's arrival).
    static func dayWhen(_ thing: Thing) -> Date { thing.dueAt ?? thing.capturedAt }

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
        let subscriptions = chrome.dayScope == .subscriptions
        let comingUp = chrome.dayScope == .comingUp
        let anyCover = heroShown || subscriptions || comingUp ? nil : (next ?? visible.first { $0.isLive })
        // In the Feed's scroll (prd §1208c) only the timeline earns the box:
        // a plain cover stands down and its thing stays a row.
        let inFeed = Self.sectionCapNow != nil
        let timeline = anyCover.map { $0.id == next?.id && !(dayStrip?.isEmpty ?? true) } ?? false
        let cover = inFeed && !timeline ? nil : anyCover
        // Box B (prd §1087): the next thing over today's shape, while there
        // is a next thing and a day to draw; else the cover, as every room.
        // Subscriptions draws its own figure in the box (prd §1111).
        if subscriptions {
            Section { mailSubscriptionsBox }
        } else if comingUp {
            Section { dayComingUpBox }
        } else if let cover, cover.id == next?.id, let strip = dayStrip, !strip.isEmpty {
            Section { dayAheadRow(cover, strip: strip) }
        } else if let cover {
            Section { ledeListRow(cover) }
        } else if !heroShown && !inFeed {
            Section {
                emptyLeadRow(headline: DSProse.text("Nothing ahead"),
                             words: Text("Your calendar, to-dos and mail appear here"))
            }
        }
        let makes = dayMakes
        Section {
            DSScopeTiles(sections: DayScope.allCases.filter { !$0.isVerb || !makes.isEmpty },
                         active: chrome.dayScope, attention: [], verbs: [.new]) { picked in
                guard picked.isVerb else {
                    withAnimation(DS.Motion.standard) { chrome.dayScope = picked }
                    return
                }
                if makes.count == 1 { makeInDay(makes[0]) } else { dayMakeOpen = true }
            }
            // Today's strip, read off the main path's body (§628) and again
            // every five minutes while the room is open, so now moves.
            .task(id: visible.count) {
                while !Task.isCancelled {
                    loadDayStrip()
                    try? await Task.sleep(for: .seconds(300))
                }
            }
            .feedRowBackground()
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.inset,
                                      bottom: DSRoomChassis.leadGap,
                                      trailing: DSRoomChassis.inset))
        }
        roomScopeSection
        if subscriptions {
            mailSubscriptionsSections
        } else if comingUp {
            dayComingUpSections(nextEventID: nextEventID)
        } else {
            groupedSections(liftingCover(groups, id: cover?.id), nextEventID: nextEventID)
        }
    }
}

// MARK: - Day's Subscriptions (prd §1111)

extension FeedScreen {
    /// The mail seats a scoped Day reads lists from: every one on All, the
    /// picked app's on an app pick.
    var mailSubscriptionSources: Set<String>? {
        guard let seat = selectedSeat else { return nil }
        return seat.source.map { [$0] } ?? []
    }

    /// The box: the figure once there are lists, the empty state once the
    /// reading says there are none, and nothing before it lands. It starts
    /// the reading, its own fetch, on every refresh.
    @ViewBuilder
    var mailSubscriptionsBox: some View {
        let reading = MailSubscriptionsReading.shared
        let items = reading.items(in: mailSubscriptionSources)
        Group {
            if items.isEmpty {
                if reading.read {
                    DSEmptyState(headline: DSProse.text("No subscriptions yet"),
                                 words: Text("Newsletters and lists from your mail"),
                                 scale: .list(rows: 3))
                } else {
                    Color.clear
                }
            } else {
                MailSubscriptionsFigure(items: items)
            }
        }
        .frame(maxWidth: .infinity, minHeight: DSRoomChassis.leadBox, maxHeight: DSRoomChassis.leadBox)
        .dsRoomHeadBlock()
        .task(id: mailSubscriptionsKey) {
            // The tile's reading, and the doors to each service's plan,
            // which its rows name (prd §1117).
            await ServiceLinks.shared.refresh(modelContext, seats: bridges.bridges.map(\.name))
            mailSubscriptionProbe()
        }
        .feedRowBackground()
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DSRoomChassis.inset,
                                  bottom: DSRoomChassis.leadGap, trailing: DSRoomChassis.inset))
    }

    /// What re-reads the tile: a refresh, or a sender added or removed from a
    /// mail's sheet (prd §1115), `walletSubscriptionsKey`'s shape.
    var mailSubscriptionsKey: String {
        let added = MailSubscriptionStore.shared.entries
        let stamp = added.values.map(\.at).max()?.timeIntervalSince1970 ?? 0
        return "\(chrome.refreshPulse):\(added.count):\(stamp)"
    }

    /// `-mailSubscriptionSheet add|<name>` — raise Track a subscription's
    /// tray (prd §1117), or one mailing list's sheet by its name, once the tile has read (DEBUG; NSLogs
    /// `mailSubscriptionSheet:`), as `-subscriptionsSheet` does for a plan,
    /// because a `simctl`-launched capture has no tap.
    func mailSubscriptionProbe() {
        #if DEBUG
        guard !Self.mailSubscriptionProbed,
              let raw = UserDefaults.standard.string(forKey: "mailSubscriptionSheet"), !raw.isEmpty else { return }
        Self.mailSubscriptionProbed = true
        let items = MailSubscriptionsReading.shared.items
        NSLog("[Casberi] mailSubscriptionSheet: %@ (%d lists: %@)", raw, items.count,
              items.map(\.name).joined(separator: ", "))
        if raw == "add" {
            // Track a subscription's tray (prd §1117), as `-subscriptionsSheet add`.
            NSLog("[Casberi] mailSubscriptionSheet: add (%d senders: %@)",
                  MailSubscriptionsReading.shared.candidates.count,
                  MailSubscriptionsReading.shared.candidates.map { "\($0.name) \($0.count)" }.joined(separator: ", "))
            feedSheet = .mailSubscriptionAdd
        } else if let item = items.first(where: { $0.name.localizedCaseInsensitiveCompare(raw) == .orderedSame }) {
            feedSheet = .mailSubscription(item.id)
        }
        #endif
    }

    /// **DAY'S SUBSCRIPTIONS LIST, THE WALLET'S ORDER (prd §1117).** Track a
    /// subscription first (a sender whose mail carries no list header, picked
    /// from the ones that wrote this month), then the map of where the mail
    /// comes from, by the catalogue category of the app each list is (§1113's
    /// identity; a list it does not name is Other), then every list, the
    /// loudest first. A press on the map narrows the rows, as the Wallet's.
    @ViewBuilder
    var mailSubscriptionsSections: some View {
        let all = MailSubscriptionsReading.shared.items(in: mailSubscriptionSources)
        let reading = mailSubscriptionsReading(all)
        let tiles = FeedScreen.subscriptionsTiles(reading, width: mailSubscriptionsMapWidth)
        let drawn = tiles.map(\.id)
        let signature = all.map(\.id).sorted().joined(separator: "|")
        let pick = mailSubscriptionsPick.flatMap { $0.over == signature && !tiles.isEmpty ? $0.tile : nil }
        let items: [MailSubscriptions.Item] = {
            guard let pick else { return all }
            // The map measures what still writes, so a pick names only that.
            let keys = SubscriptionCategories.members(of: pick, drawn: drawn, slices: reading.slices)
            return all.filter { !$0.stopped && keys.contains(mailSubscriptionKey($0)) }
        }()
        let writing = items.filter { !$0.stopped }
        let stopped = items.filter(\.stopped)
        Section {
            DSDoorRow(icon: "plus", title: Text(SubscriptionWords.track)) {
                feedSheet = .mailSubscriptionAdd
            }
            .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.rowInset,
                                      bottom: 0, trailing: DSRoomChassis.rowInset))
            .feedRowBackground()
            .listRowSeparator(.hidden)
            if reading.counted > 0 {
                SubscriptionsSummary(reading: reading, tiles: tiles, pick: pick, mails: true) { tile in
                    mailSubscriptionsPick = tile.map { SubscriptionsPick(tile: $0, over: signature) }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { mailSubscriptionsMapWidth = $0 }
                .task(id: SubscriptionsSummary.logKey(reading, tiles: drawn) + "|\(mailSubscriptionsMapWidth > 0)") {
                    guard mailSubscriptionsMapWidth > 0 else { return }
                    SubscriptionsSummary.log(reading, tiles: tiles, mails: true)
                }
                .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DSRoomChassis.rowInset,
                                          bottom: DS.Space.s2, trailing: DSRoomChassis.rowInset))
                .feedRowBackground()
                .listRowSeparator(.hidden)
            }
            ForEach(writing) { item in mailSubscriptionRow(item) }
            // What went quiet stands last, under its own name (prd §1160):
            // still a door to its mail and its way out, counted in no figure.
            if !stopped.isEmpty {
                Text("Stopped")
                    .dsText(.heading20)
                    .foregroundStyle(DS.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .listRowInsets(EdgeInsets(top: DS.Space.s6, leading: DSRoomChassis.rowInset,
                                              bottom: DS.Space.s1, trailing: DSRoomChassis.rowInset))
                    .feedRowBackground()
                    .listRowSeparator(.hidden)
                ForEach(stopped) { item in mailSubscriptionRow(item) }
            }
        }
    }

    private func mailSubscriptionRow(_ item: MailSubscriptions.Item) -> some View {
        Button {
            feedSheet = .mailSubscription(item.id)
        } label: {
            MailSubscriptionRow(item: item, paid: mailSubscriptionIsPaid(item))
                .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .dsHover()
        .listRowInsets(EdgeInsets(top: Self.rowAir, leading: DSRoomChassis.rowInset,
                                  bottom: Self.rowAir, trailing: DSRoomChassis.rowInset))
        .feedRowBackground()
        .listRowSeparator(.hidden)
    }

    /// A list's place on Day's map: the category of the app §1113's identity
    /// names it, else Other.
    func mailSubscriptionKey(_ item: MailSubscriptions.Item) -> String {
        guard let offer = ServiceLinks.shared.byList[item.id]?.offer else { return SubscriptionCategories.otherKey }
        let category = BillersSource.category(ofMerchant: offer)
        return category == BillersSource.fallbackCategory ? SubscriptionCategories.otherKey : category
    }

    /// Lists → categories, measured in mails these thirty days; a quiet list
    /// stays in the rows and out of the map.
    func mailSubscriptionsReading(_ items: [MailSubscriptions.Item]) -> SubscriptionCategories.Reading {
        SubscriptionCategories.read(measured: items.compactMap { item -> (key: String, measure: Double)? in
            guard item.lastMonth > 0, !item.stopped else { return nil }
            return (key: mailSubscriptionKey(item), measure: Double(item.lastMonth))
        })
    }

    /// The service also has a plan in the Wallet (§1113), so its row says so.
    func mailSubscriptionIsPaid(_ item: MailSubscriptions.Item) -> Bool {
        guard let planID = ServiceLinks.shared.byList[item.id]?.planID else { return false }
        return SubscriptionsReading.shared.items.contains { $0.id == planID }
    }
}

extension FeedScreen {
    /// Today's events onto the strip (prd §1087).
    func loadDayStrip() {
        let connected = connectedSeatNames.contains("Calendar")
        let events = DayStripSource.events(context: modelContext, calendarConnected: connected)
        let strip = DayStrip.make(events, now: .now, calendar: .current)
        if strip != dayStrip { dayStrip = strip }
    }

    /// Box B's row: the cover's tap, press and long press, drawing the next
    /// thing over today's strip.
    func dayAheadRow(_ thing: Thing, strip: DayStrip) -> some View {
        let start = Self.dayWhen(thing)
        let minutes = Int(start.timeIntervalSinceNow / 60)
        let when: String = minutes <= 0 ? String(localized: "now")
            : minutes < 60 ? String(localized: "in \(minutes) min")
            : start.formatted(date: Calendar.current.isDateInToday(start) ? .omitted : .abbreviated,
                              time: .shortened)
        let clock = start.formatted(date: .omitted, time: .shortened)
        let line = [thing.endAt.map { "\(clock)–\($0.formatted(date: .omitted, time: .shortened))" } ?? clock,
                    thing.factList.first { $0.action == .map }?.value]
            .compactMap(\.self).joined(separator: " · ")
        return Button {
            openThing(thing)
        } label: {
            DayAheadCard(source: thing.source, title: thing.title, line: line, when: when, strip: strip,
                         selected: DS.isMac && chrome.walkSelected == thing.id.uuidString)
                .modifier(rowEntrance(0))
                .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .contextMenu {
            RowVerbMenu(thing: thing, room: source, run: { run($0, on: $1) }, onDelete: askDeleteNote,
                        onFile: fileThing, onNewFolder: { folderPrompt = .make(filing: $0) })
        }
        .dsHover()
        .macHoverLift()
        .id(thing.id.uuidString)
        .feedRowBackground()
        .listRowInsets(.init(top: DS.Space.s2, leading: DSRoomChassis.inset,
                             bottom: DSRoomChassis.leadGap, trailing: DSRoomChassis.inset))
        .listRowSeparator(.hidden)
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

    /// GitHub's own tray (§1031) once GitHub is connected, which a repo's
    /// lookup needs; else its page, where it connects.
    func watchOnGitHub() {
        if connectedSeatNames.contains("GitHub") {
            feedSheet = .githubWatch
        } else if let destination = BridgeRouter.destination(forOffer: "GitHub") {
            route.openAccount(destination)
        }
    }

    /// The Work room: the newest thing, All · Coming up · Watching, the menu,
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
        let watching = chrome.workScope == .watch
        // What needs you now leads Coming up, then what is due (prd §1080);
        // a row that is both stands once, under the asks.
        let asks = comingUp ? workAsks(visible) : []
        let askIDs = Set(asks.map(\.id))
        let deadlines = workDeadlines(visible).filter { !askIDs.contains($0.id) }
        // Coming up leads with what needs you, else the soonest deadline.
        let cover = heroShown ? nil
            : (comingUp ? (asks.first ?? deadlines.first) : visible.first { $0.isLive })
        if watching {
            Section { followingBox(.work) }
        } else if let cover {
            Section { ledeListRow(cover) }
        } else if !heroShown {
            // A head already holds the box (a picked app's own, prd §1067):
            // a second, empty box under it pushed the tiles off the screen.
            Section {
                emptyLeadRow(headline: DSProse.text("Nothing yet"),
                             words: Text("What you build lands here"))
            }
        }
        Section {
            DSScopeTiles(sections: WorkScope.allCases, active: chrome.workScope, attention: [], verbs: []) { picked in
                withAnimation(DS.Motion.standard) { chrome.workScope = picked }
            }
            .feedRowBackground()
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.inset,
                                      bottom: DSRoomChassis.leadGap,
                                      trailing: DSRoomChassis.inset))
        }
        roomScopeSection
        if watching {
            followingSections(.work)
        } else if comingUp {
            let waiting = asks.filter { $0.id != cover?.id }
            let rest = deadlines.filter { $0.id != cover?.id }
            if waiting.isEmpty && rest.isEmpty && cover == nil {
                Section {
                    DSSkeletonRows(label: Text("Nothing needs you, and nothing is due."))
                        .feedRowBackground()
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
