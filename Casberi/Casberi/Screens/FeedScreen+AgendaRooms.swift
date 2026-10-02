import SwiftUI
import SwiftData

// Calendar, Reminders and Mail: the agenda, the state groups, the waiting
// section and their tiles, split out of
// FeedScreen.swift (prd §718). Nothing here changed but the file it lives
// in and, where another file reads a member, its access level.
extension FeedScreen {
    /// The Reminders room's tiles (prd §993): All · Today · Scheduled · New.
    /// New leaves for the Reminders app, where a reminder is made (ruling
    /// 2026-07-25), and is drawn only where that app answers its scheme — a
    /// tile that opens nothing is a dead control (§83).
    private var remindersTiles: DSScopeTiles<RemindersScope> {
        let canOpen = HandOffState.answers("x-apple-reminderkit")
        return DSScopeTiles(sections: RemindersScope.allCases.filter { !$0.isVerb || canOpen },
                            active: chrome.remindersScope,
                            attention: [],
                            verbs: [.new]) { picked in
            if picked.isVerb {
                if let url = URL(string: "x-apple-reminderkit://") { openExternal(url) }
            } else {
                withAnimation(DS.Motion.standard) { chrome.remindersScope = picked }
            }
        }
    }

    /// The mail rooms' tiles (prd §1019): All · Attachments · New, in Gmail
    /// and iCloud Mail alike. New composes in the app `SourceActions` names
    /// for the seat (Gmail's own when installed, else `mailto:`) and is drawn
    /// only where that action resolves — a tile that opens nothing is a dead
    /// control (§83).
    var mailTiles: DSScopeTiles<MailScope> {
        let compose = SourceActions.action(forSource: source)
        return DSScopeTiles(sections: MailScope.allCases.filter { !$0.isVerb || compose != nil },
                            active: chrome.mailScope,
                            attention: [],
                            verbs: [.new]) { picked in
            if picked.isVerb {
                if let compose, case .openURL(let url) = compose.run { openExternal(url) }
            } else {
                withAnimation(DS.Motion.standard) { chrome.mailScope = picked }
            }
        }
    }

    /// Calendar reads forward: Today and upcoming days ascending, event-time
    /// order within each day (mock C2) — and, separately, what's already
    /// happened, newest day first.
    ///
    /// Two lists, not one, since 2026-07-27 (user: "this calendar display feed
    /// with dates and different orders is awkward, can we hide past events?").
    /// The old shape concatenated them, so a single scroll ran forward then
    /// backward — Monday, Wednesday, then last Friday — and the reversal at
    /// the seam was invisible. An agenda is what's AHEAD; history is the All
    /// feed's job (a past event still sits in its own day there). So the room
    /// shows the upcoming days and keeps the past behind one disclosure at the
    /// foot, the way Reminders already keeps its stale to-dos.
    ///
    /// LIVE ONLY at the top of the derivation (COROLLARY 2, build 150): every
    /// caller below reads `capturedAt` — the split itself, the toggle's count,
    /// the day headers — and a heal pass can delete a row out from under any
    /// of them mid-update.
    private func agendaSplit(_ visible: [Thing]) -> (upcoming: [(String, [Thing])],
                                                     past: [(String, [Thing])]) {
        let cal = Self.groupingCalendar
        let today = cal.startOfDay(for: .now)
        var buckets: [Date: [Thing]] = [:]
        for thing in visible where thing.isLive {
            buckets[cal.startOfDay(for: thing.capturedAt), default: []].append(thing)
        }
        func groups(_ days: [Date]) -> [(String, [Thing])] {
            days.map { day in
                (dayLabel(day), (buckets[day] ?? []).sorted { $0.capturedAt < $1.capturedAt })
            }
        }
        return (groups(buckets.keys.filter { $0 >= today }.sorted()),
                groups(buckets.keys.filter { $0 < today }.sorted(by: >)))
    }

    /// True while the Calendar room is holding past events back — the closing
    /// "that's everything" line has to sit out then, the way it already does
    /// for Reminders and Wallet (both render a subset of `visible`). The
    /// disclosure row names the hidden count instead.
    func hidesPastEvents(_ visible: [Thing]) -> Bool {
        guard shape == .calendar, !pastEventsExpanded else { return false }
        let today = Self.groupingCalendar.startOfDay(for: .now)
        return visible.contains {
            $0.isLive && Self.groupingCalendar.startOfDay(for: $0.capturedAt) < today
        }
    }

    /// The Calendar room: the agenda ahead, then — only when asked for — what
    /// already happened, newest first. The disclosure sits in one place
    /// whichever way it's pointing, so expanding doesn't move the control out
    /// from under the finger that tapped it.
    @ViewBuilder
    func calendarSections(_ visible: [Thing], nextEventID: UUID?,
                                  heroShown: Bool) -> some View {
        // The month grid and its Today · Week · Month tiles are deleted:
        // Calendar folds into Day (prd §1056), which reads forward as this
        // agenda does.
        agendaSections(visible, nextEventID: nextEventID, heroShown: heroShown)
    }

    /// The agenda the Calendar shape drew before §994, and still draws for
    /// Cal.com and Calendly, and under a head.
    @ViewBuilder
    private func agendaSections(_ visible: [Thing], nextEventID: UUID?,
                                heroShown: Bool) -> some View {
        let split = agendaSplit(visible)
        let pastCount = split.past.reduce(0) { $0 + $1.1.count }
        // THE NEXT EVENT IS THE COVER (prd §911) — §908 drew it a date tile and
        // this shape had no cover path, so the room opened on a row. The
        // agenda is soonest-first, so the first row of the first day is what
        // is next; nothing ahead holds the lead as the room's empty state,
        // because the visible agenda IS empty and the past sits behind a door.
        // The NEXT event first — today's day group also holds this morning's
        // events, already over — then the first row ahead, then nothing.
        let nextAhead = nextEventID.flatMap { id in
            split.upcoming.contains { $0.1.contains { $0.isLive && $0.id == id } } ? id : nil
        }
        groupedSections(split.upcoming, nextEventID: nextEventID,
                        cover: heroShown ? nil : (nextAhead ?? ledeThingID(in: split.upcoming)))
        if split.upcoming.isEmpty {
            if heroShown {
                nothingAheadSection(String(localized: "Nothing coming up."))
            } else {
                Section {
                    emptyLeadRow(headline: DSProse.text("Nothing coming up."),
                                 words: Text("Past events sit one tap below."))
                }
            }
        }
        if pastCount > 0 {
            pastEventsToggle(count: pastCount)
            if pastEventsExpanded {
                groupedSections(split.past, nextEventID: nextEventID)
            }
        }
    }

    /// An agenda with nothing on it says so, rather than leaving the room
    /// looking like a load that never finished. Not `filteredEmptyState` —
    /// nothing is filtered out and there IS a corpus here; the past sits one
    /// tap below.
    private func nothingAheadSection(_ line: String) -> some View {
        Section {
            Text(line)
                .dsText(.body17)
                .foregroundStyle(DS.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, DS.Space.s4)
                .padding(.top, DS.Space.s6)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
        }
    }

    /// The past-events disclosure — a quiet inline door on the page itself,
    /// not a card (the same voice as the wallet's "See all transactions"):
    /// the agenda above is the content, this is where the record continues.
    private func pastEventsToggle(count: Int) -> some View {
        Section {
            Button {
                DSHaptic.selection()
                withAnimation(DS.Motion.standard) { pastEventsExpanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Text(pastEventsExpanded
                         ? String(localized: "Hide past events")
                         : (count == 1 ? String(localized: "Show 1 past event")
                                       : String(localized: "Show \(count) past events")))
                        .dsText(.body17)
                        .monospacedDigit()
                    Image(systemName: pastEventsExpanded ? "chevron.up" : "chevron.down")
                        .dsGlyph(.caption)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(DS.tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Space.s1)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPress())
            .padding(.top, DS.Space.s6)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
        }
    }

    /// The next upcoming event — its ROW carries the emphasis (no hero).
    /// Events only: in the All shape other kinds share the list, and only
    /// an event's capture time means "starts at".
    func nextEventID(_ visible: [Thing]) -> UUID? {
        visible.filter { $0.isLive && $0.kind == .event && $0.capturedAt > .now }
            .min { $0.capturedAt < $1.capturedAt }?.id
    }

    /// Gmail: what's waiting on you, capped at two (mock G1). Doing-marked
    /// only (honesty fix 2026-07-13): the old `content.contains("?")` sniff
    /// promoted any newsletter with a question mark to "waiting on you" —
    /// fake status. The section now shows only what the person marked
    /// in motion, and earns back a smarter derivation later.
    @ViewBuilder
    func waitingSection(_ visible: [Thing], nextEventID: UUID?) -> some View {
        let waiting = visible.filter { $0.mark == .doing }.prefix(2).map { $0 }
        if !waiting.isEmpty {
            daySection("Waiting on you", waiting, nextEventID: nextEventID, dated: false)
        }
    }

    // Waiting mails stay in their day groups too (unlike agent approvals,
    // which ARE removed): a mail is a record, and excluding only the first
    // two doing-marked mails (the lede's cap) would punch order-dependent
    // holes in the day history. The lede highlights; the record stays whole.

    /// Reminders: state groups — Doing, To do (stale todos collapse), Done
    /// (same-day only).
    @ViewBuilder
    func reminderSections(_ visible: [Thing], nextEventID: UUID?,
                                  heroShown: Bool) -> some View {
        // THE NEWEST OPEN REMINDER IS THE COVER (prd §911): what you are doing
        // first, then what is to do — the room's own order — lifted out of its
        // group so it draws once. Done rows never cover.
        let open = visible.filter { $0.mark == .doing }
            + visible.filter { $0.mark == .todo || $0.mark == .none }
        let isRemindersRoom = source == "Reminders"
        // In the Reminders room the newest open reminder always covers, even
        // one `ledeThingID` would decline (prd §997), so the lead is held.
        let reminderCover = coverThing(heroShown ? nil : ledeThingID(in: [("", open)]), in: visible)
            ?? (isRemindersRoom && !heroShown ? open.first : nil)
        if isRemindersRoom {
            // The cover, then the tiles; with nothing OPEN, the lead box holds
            // the checklist drawn empty (prd §993). Open, not visible: a room
            // of done reminders drew no cover and no well, and its tiles rose
            // to the top of the screen (prd §997, §752).
            let scope = chrome.remindersScope
            standaloneLead(cover: reminderCover, tiles: remindersTiles, listEmpty: open.isEmpty,
                           emptyWords: Text(scope.summary),
                           emptyFigure: .checklist,
                           emptyHeadline: Text(scope.emptyHeadline))
        } else if let reminderCover { Section { ledeListRow(reminderCover) } }
        let doing = visible.filter { $0.mark == .doing && $0.id != reminderCover?.id }
        let todos = visible.filter { ($0.mark == .todo || $0.mark == .none) && $0.id != reminderCover?.id }
        let weekAgo = Date.now.addingTimeInterval(-7 * 86_400)
        let fresh = todos.filter { $0.capturedAt > weekAgo }
        let stale = todos.filter { $0.capturedAt <= weekAgo }
        let doneToday = visible.filter {
            $0.mark == .done && Calendar.current.isDateInToday($0.capturedAt)
        }
        if !doing.isEmpty { daySection("Doing", doing, nextEventID: nextEventID, dated: false) }
        if !fresh.isEmpty || !stale.isEmpty {
            // One To do card (2026-07-21): the Older toggle — or the stale
            // rows it expands into — continues the fresh rows' surface
            // instead of sitting under it as a flat band.
            let hasToggle = !stale.isEmpty && !staleExpanded
            let slots = fresh.count + (staleExpanded ? stale.count : 0) + (hasToggle ? 1 : 0)
            let positions = cardRunPositions(count: slots)
            Section {
                // UNPINNED (2026-08-29) — a ROW, not a `header:`; see the twin in
                // `bundledSections`. This is the one of the four whose spacing was
                // CHOSEN rather than carried over: it had no insets of its own, so
                // it took whatever the system gives a header slot. It sits in the
                // rows' own column now, with the micro pad every other quiet line
                // in this file wears.
                Text("To do").dsText(.heading17).foregroundStyle(DS.textPrimary).textCase(nil)
                    .padding(.vertical, DS.Space.s1)
                    .listRowInsets(.init(top: 0, leading: DSRoomChassis.rowInset,
                                         bottom: 0, trailing: DSRoomChassis.rowInset))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                ForEach(Array(keyed(fresh).enumerated()), id: \.element.id) { i, item in
                    // Corollary 3 (build 176) — see `ThingRowKeying`.
                    if let thing = item.live {
                        shapedListRow(thing, index: i, nextEventID: nextEventID,
                                      position: positions[i])
                    }
                }
                if !stale.isEmpty {
                    if staleExpanded {
                        ForEach(Array(keyed(stale).enumerated()), id: \.element.id) { i, item in
                            // Corollary 3 (build 176) — see `ThingRowKeying`.
                            if let thing = item.live {
                                shapedListRow(thing, index: i, nextEventID: nextEventID,
                                              position: positions[fresh.count + i])
                            }
                        }
                    } else {
                        HStack {
                            Text("Older").dsText(.body17).foregroundStyle(DS.textSecondary)
                            Text("\(stale.count)").dsText(.subhead12).foregroundStyle(DS.textTertiary)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .accessibilityHidden(true)
                                .dsGlyph(.caption)
                                .foregroundStyle(DS.textTertiary)
                        }
                        .padding(.vertical, DS.Space.s1)
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(DS.Motion.standard) { staleExpanded = true } }
                        .dsTapCard()
                        .listRowBackground(Color.clear)   // bare, like every row (prd §749)
                        .listRowInsets(.init(top: Self.rowAir,
                                             leading: DSRoomChassis.rowInset,
                                             bottom: Self.rowAir,
                                             trailing: DSRoomChassis.rowInset))
                        .listRowSeparator(.hidden)
                    }
                }
            }
        }
        if !doneToday.isEmpty { daySection("Done", doneToday, nextEventID: nextEventID, dated: false) }
    }
}
