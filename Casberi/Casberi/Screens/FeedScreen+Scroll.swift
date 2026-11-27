import SwiftData
import SwiftUI

// THE FEED IS ONE SCROLL (prd §1208, §1208a; user: "what if the feed was one
// continuous scroll but each section still had their same ui of the card and
// row of four buttons", "this way instead of swiping a user can scroll").
//
// On the phone the Feed stacks every category under its own box and tiles,
// in the dock's order: the pink name (a press folds it), the category's own
// box and tiles — each room's own sections, reused, so a tile switches in
// place exactly as it does in the room — then five rows and More. Nothing
// stops the scroll; nothing in it opens a screen of its own. iPad and Mac
// keep the rail and the rooms.

extension FeedScreen {
    /// Rows a section shows before More, and how many More adds.
    static let sectionFirstRows = 5
    static let sectionMoreRows = 10

    /// The section being drawn and its cap, read by `groupedSections` while
    /// that section's own sections are built (synchronously, inside this
    /// body), so every room's existing day-grouped list draws capped without
    /// each room learning about the scroll.
    @MainActor static var sectionCapNow: (category: String, rows: Int)?

    /// Whether this screen is the stacked Feed: the phone's All page.
    ///
    /// **WITH OR WITHOUT AN APP CONNECTED (prd §1809).** It waited for a
    /// connected app, so a new phone with your things already in iCloud and
    /// no app connected yet drew the older page: a "Newest" cover and large
    /// section names. One Activity for everyone; with nothing at all, the
    /// start box (`feedStarts`).
    var scrollsCategories: Bool {
        source == "All" && roomScopeInRoom && filter.tag == "All"
    }

    /// The categories the Feed stacks: every one with a room, in the dock's
    /// order, the Wallet (its own place) excepted.
    var scrollCategories: [String] {
        let all = HomeScope.feedCategories(chips: chrome.chipOrder)
        // THE PANE CARRIES DAY (prd §1403): beside a pane the Feed's Day
        // section — the week, the next thing, Needs you, the days — stands
        // under the Feed's box in the pane, and the list column lists the
        // rest; the pane's own instance draws Day and nothing else.
        switch roomBoxPlace {
        case .list: return all
        case .listWithoutBox: return all.filter { $0 != RoomAccounts.dayRoom }
        case .paneBox: return all.filter { $0 == RoomAccounts.dayRoom }
        }
    }

    /// **THE FEED'S ROW IS ITS CATEGORIES (prd §1328, user: "the fix isn't
    /// to close the gap its to add its row of stuff like the categories that
    /// are in the feed").** Day, Notes and the Wallet each stand a row under
    /// the box, so the Feed does too: its sections, in Feed order, on the
    /// strip their rows use. A tap lands on that section, as the pill's menu
    /// does (`feedJump`); nothing is ever lit, since the row jumps rather than
    /// narrows.
    @ViewBuilder
    var feedCategoryRow: some View {
        let tiles = scrollsCategories && !inSheet ? scrollCategories.map(FeedSectionTile.init) : []
        if tiles.count > 1 {
            Section {
                DSScopeTiles(sections: tiles + [.reorder], active: FeedSectionTile(name: ""),
                             scrollsColumns: true, verbs: [.reorder]) { picked in
                    DSHaptic.selection()
                    if picked.isReorder { feedSheet = .feedOrder; return }
                    chrome.feedJump = picked.name
                }
                .dsRoomTilesListRow()
            }
        }
    }

    /// The sections the pill names (prd §1208d): the Feed's categories, or
    /// the Wallet Home's lists (prd §1219).
    var pillSections: [String] {
        if scrollsCategories { return scrollCategories }
        if shape == .wallet, (chrome.walletSection ?? .home) == .home { return Self.walletHomeNames }
        return []
    }

    /// The section a thing stands in: its category, Reading's under Media
    /// (prd §1204), nil for anything with no category page (a note of yours).
    /// Day's apps stand in Day (prd §1343), which the catalogue files under
    /// Life. Asked once per source, never per row.
    @MainActor static func scrollCategory(ofSource source: String) -> String? {
        if RoomAccounts.host(ofSource: source)?.room == RoomAccounts.dayRoom { return RoomAccounts.dayRoom }
        guard let category = BridgeCatalog.category(forSource: source) else { return nil }
        return category == RoomAccounts.readingRoom ? RoomAccounts.mediaRoom : category
    }

    /// A section's identity in the Feed's list, apart from every other id
    /// (the contents' tiles are keyed by the same names).
    static let sectionPrefix = "feedSectionGroup:"
    static func sectionID(_ category: String) -> String { sectionPrefix + category }

    /// The id a section's name carries, so the tray can scroll to it.
    static func scrollAnchor(_ category: String) -> String { "feedSection:\(category)" }

    /// Each section's rows (prd §1343).
    func feedSectionRows(_ visible: [Thing], hiding shown: Set<UUID>) -> [String: [Thing]] {
        let live = visible.filter { $0.isLive && !shown.contains($0.id) }
        let sources = Set(live.map(\.source))
        // Each source's section once, not each row's (prd §1343): Day's apps
        // are Life's in the catalogue, and their rows stand in Day.
        var sectionOf: [String: String] = [:]
        for source in sources {
            sectionOf[source] = Self.scrollCategory(ofSource: source) ?? ""
        }
        // A note of yours, or an entry from an app you write in, stands in
        // Notes (prd §1347), whatever the app's category.
        // The Wallet's rows group under its name and no section draws them:
        // the Feed has no Wallet section (prd §1489).
        return Dictionary(grouping: live) {
            Pinboard.inRoom($0) ? HomeScope.notesSection : (sectionOf[$0.source] ?? "")
        }
    }

    /// What the Feed's own reads are keyed on (Day's rows, Notes' rows): any
    /// change to the corpus, on the Feed. Everywhere else `.idle`, so the
    /// task does nothing there.
    var feedSectionsKey: Corpus.Revision {
        guard source == "All" else { return .idle }
        return Corpus.revision(in: modelContext)
    }

    @ViewBuilder
    func feedScrollSections(_ visible: [Thing], hiding shown: Set<UUID>, nextEventID: UUID?) -> some View {
        let byCategory = feedSectionRows(visible, hiding: shown)
        // An app standing in Needs you stands only there (prd §1813): one
        // row per app on the whole of Activity. Its next-newest thing under
        // its category read as the same row twice (an alarm, then the alarm).
        let needs = quietActivity ? Set(activityNeedThings(visible).map(\.source)) : []
        // **NOTES LIVES IN ITS FOLDER (prd §1839, user: "Notes shouldn't be
        // there. that's just weird", "notes live in the folder").** On the
        // phone's Activity your notes are the Notes folder's first cell, on
        // Apps' panel; the word that stood here alone is gone.
        let categories = quietActivity ? scrollCategories.filter { $0 != HomeScope.notesSection } : scrollCategories
        ForEach(categories.map(Self.sectionID), id: \.self) { id in
            let category = String(id.dropFirst(Self.sectionPrefix.count))
            // Live again inside the closure: `List` may run it after a heal
            // deleted a row the body's own filter saw alive.
            // ONE ROW PER APP (prd §1807, user: "if someone is following
            // multiple socials … they wanna be able to scan list and know
            // what is most recent"): each app's newest thing, the newest app
            // first. Day and Notes are gathered, not one app's, and keep
            // their own rows.
            let rows = category == HomeScope.notesSection ? notesFeedRows.live : (byCategory[category] ?? []).live
            if quietActivity {
                // **ONE RULE (prd §1809)**: each app's newest thing; Day's
                // is each app's next.
                // **A CATEGORY IS A WORD, NOT A PAGE (prd §1813, user: "what
                // if there were no category pages. the only place categories
                // show is on activity").** Its name opens nothing; a row's
                // icon opens its app, one step from here. Notes is no
                // category: its word opens your notes, as before.
                let open: (() -> Void)? = category == HomeScope.notesSection ? {
                    chrome.activityReturn = category
                    ActivitySeen.shared.leavingForPage()
                    openCategory(category)
                } : nil
                // **WHAT IS NEW (prd §1831).** An app whose newest thing was
                // on screen when you last left Activity is left out. Day is
                // what is coming, not what came, and keeps every next thing;
                // Notes' word stays, as the Wallet's does, because it opens
                // a page.
                let isDay = category == RoomAccounts.dayRoom
                activitySection(category,
                                isDay ? Self.nextPerApp(dayFeedRows.live)
                                    : Self.newestPerApp(rows.filter { !needs.contains($0.source) })
                                        .filter { !ActivitySeen.shared.isHidden($0.id) },
                                nextEventID: nextEventID, open: open,
                                fades: !isDay, keepsWord: category == HomeScope.notesSection)
            } else {
                scrollSection(category,
                              category == HomeScope.notesSection || category == RoomAccounts.dayRoom
                                  ? rows : Self.newestPerApp(rows),
                              nextEventID: nextEventID)
            }
        }
    }

    /// **ACTIVITY IS QUIET (prd §1809, user: "feed still feels overwhelming
    /// b/c of sections, and b/c money has three rows while some others only
    /// have one").** On the phone's Activity every category is a small grey
    /// word over one row per app; beside a pane the sections keep their
    /// panels, where Day's week stands in the pane (§1403).
    var quietActivity: Bool { source == "All" && roomBoxPlace == .list && roomSizeClass == .compact }

    /// Day's rule (prd §1809): each app's next thing — an event's start, a
    /// to-do's due date — today or ahead, soonest first.
    static func nextPerApp(_ things: [Thing]) -> [Thing] {
        let today = groupingCalendar.startOfDay(for: .now)
        var seen = Set<String>()
        return things.filter { dayWhen($0) >= today }
            .sorted { dayWhen($0) < dayWhen($1) }
            .filter { seen.insert($0.source).inserted }
    }

    /// One category of Activity: its word, then one row per app, no day
    /// label, no More row. The word is a label (prd §1813; the Wallet's and
    /// Notes' open their own pages).
    @ViewBuilder
    func activitySection(_ name: String, _ rows: [Thing], nextEventID: UUID?,
                         open: (() -> Void)?, fades: Bool = true,
                         keepsWord: Bool = false, walletLead: Bool = false,
                         rowOpens: (() -> Void)? = nil) -> some View {
        let _ = { memo.sectionCounts[name] = rows.count }()
        // A category with nothing new leaves Activity; a word that opens a
        // page (the Wallet's, Notes') stays, alone (prd §1831).
        if !rows.isEmpty || keepsWord {
            SectionPanelGroup(anchor: Self.scrollAnchor(name), lit: landedSection == name) {
                ActivityWord(name: name, open: open)
            } rows: {
                // Rows the section itself owns, over its apps' rows (the
                // Wallet's watchlist and Spending, prd §1851, §1870). Rows,
                // never one `AnyView`: a `List` reads each as its own row.
                if walletLead { homeWalletLeadRows }
                ForEach(keyed(rows), id: \.id) { item in
                    if let thing = item.live { activityAppRow(thing, from: name, fades: fades, opens: rowOpens) }
                }
            }
            .environment(\.feedSectionPanelFilled, false)
            .environment(\.dsTitleOnly, true)
        }
    }

    /// **THE ROW IS THE APP (prd §1840, user: "if you press an app icon you
    /// go to the app page, but if you press the row you open the individual
    /// message. this isn't clear to anyone").** Activity is one row per app,
    /// so the row is the app's, and one tap
    /// anywhere opens the app's page, where that thing leads. It had two
    /// targets in one 44pt row, the icon to the app and the words to the
    /// thing, and nothing told them apart.
    ///
    /// White until seen (prd §1816): the newest thing is seen once its app's
    /// page has been opened over it, or once it was opened anywhere else.
    ///
    /// **THE ICON SAYS THE APP (prd §1864, user: "should we remove the app
    /// names from the feed writ large? i'd say so, then we don't even need
    /// subtext and its more minimal").** The row is the app's icon and its
    /// newest thing, on one line; the name stood over it and repeated down
    /// any list of one app's things. A thing with no words keeps the name,
    /// and VoiceOver still says it.
    /// The sources whose rows are your own money moving (prd §1987).
    static let actsInRoom: Set<String> = ["Wallet", RailgunBridge.sourceName, PrivacyPoolsBridge.sourceName]

    func activityAppRow(_ thing: Thing, from section: String, fades: Bool = true,
                        opens: (() -> Void)? = nil) -> some View {
        let seen = fades && ActivitySeen.shared.has(thing.id)
        let words = thing.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let app = Self.activityAppName(thing.source)
        // **AN OWN ACT READS AS IN ITS ROOM (prd §1987, user, of Home's
        // "Received 5.214713 USDC privately o…" under the old wallet mark:
        // "it should have new glyph and no verb right?"):** the act's glyph
        // leads, where or who is the name, the amount stands on the right.
        // Railgun's and Privacy Pools' own rows too (2026-11-27, user: "for
        // receive usdc from railgun it shows me the railgun icon ... it also
        // has a verb which we got rid of"): the glyph, the place, the amount.
        let acted = Self.actsInRoom.contains(thing.source) ? WalletRowWords.read(words).flatMap { $0.act == nil ? nil : $0 } : nil
        return DSPushRow(title: Text(verbatim: acted?.name ?? (words.isEmpty ? app : words)),
                         fact: acted?.figure.map { Text(verbatim: $0) },
                         factTone: seen ? DS.textSecondary : DS.textPrimary,
                         tint: seen ? DS.textSecondary : DS.textPrimary,
                         action: {
                             ActivitySeen.shared.mark(thing.id)
                             ActivitySeen.shared.leavingForPage()
                             // A section whose rows share one door (the
                             // Wallet's history, prd §1849).
                             if let opens { opens(); return }
                             chrome.activityReturn = section
                             chrome.openAppPage(thing.source)
                             // A money app's page is Money narrowed to it, the
                             // Wallet menu's own pick (prd §1840): eleven rows
                             // to one unnarrowed page told the apps apart by
                             // nothing.
                             if BridgeCatalog.category(forSource: thing.source) == CategoryFold.walletCategory,
                                let host = RoomAccounts.host(ofSource: thing.source),
                                host.room == CategoryFold.walletRoom {
                                 chrome.walletScope = RoomAccounts.scopeID(host.seat)
                             }
                         }) {
            // A thing by a person leads with their face, its app on the
            // corner (prd §1865, user: "show the users avatar w the x icon");
            // anything else keeps the app's icon.
            // A chat leads with whom it is with as its room draws them: a
            // photo by URL, a Telegram photo kept as bytes, else the name's
            // initial (`ChatFaceMark`).
            Group {
                if ChatFace.isPersonChat(thing) {
                    ChatFaceMark(thing: thing)
                        .frame(width: DS.Mark.row, height: DS.Mark.row)
                        .appCorner(thing.source, always: true)
                } else if let face = BandRow.personFace(thing) {
                    RemoteThumb(urlString: face, size: DS.Face.rowCircle,
                                fallback: thing.source, circular: true)
                        .frame(width: DS.Mark.row, height: DS.Mark.row)
                        .appCorner(thing.source, always: true)
                } else if let act = acted?.act {
                    WalletMarkView(mark: .kind(thing.kind, symbol: act.symbol, tint: Color(hex: act.hex)),
                                   size: DS.Face.rowCircle)
                        .frame(width: DS.Mark.row, height: DS.Mark.row)
                } else {
                    BridgeIcon(name: thing.source, size: DS.Mark.row)
                }
            }
            .opacity(seen ? 0.5 : 1)
            .accessibilityHidden(true)
        }
        .accessibilityLabel(Text(verbatim: words.isEmpty ? app : "\(app), \(words)"))
        // On screen is seen, once you leave (prd §1831); Day's rows are what
        // is coming and are never left out.
        .onAppear { if fades { ActivitySeen.shared.noteShown(thing.id) } }
        .feedRowBackground()
        .listRowInsets(.init(top: Self.rowAir, leading: DSRoomChassis.rowInset,
                             bottom: Self.rowAir, trailing: DSRoomChassis.rowInset))
        .listRowSeparator(.hidden)
    }

    /// **NEVER "WALLET" UNDER "WALLET" (prd §1839, user: "we can't have it
    /// say 'wallet wallet' twice").** The wallets you follow land under the
    /// seat named Wallet, the word over them; the row says whose they are:
    /// "Your account" when the only one is yours, "Accounts" when you follow
    /// others too. Every other app keeps its seat's name.
    @MainActor static func activityAppName(_ source: String) -> String {
        let name = BridgeCatalog.seatName(forSource: source)
        guard name == CategoryFold.walletRoom else { return name }
        let onlyYours = WalletStore.shared.addresses.allSatisfy { YourAccountDemo.isYours($0.address) }
        return onlyYours ? String(localized: "Your account") : String(localized: "Accounts")
    }

    /// Each app's newest thing, the newest app first (prd §1807).
    static func newestPerApp(_ things: [Thing]) -> [Thing] {
        var seen = Set<String>()
        return things.sorted { $0.capturedAt > $1.capturedAt }.filter { seen.insert($0.source).inserted }
    }

    // MARK: - Activity's own sections (prd §1807)

    /// The Wallet's rows in the Feed's corpus. The scroll draws no Wallet
    /// category (prd §1489); Activity's Needs you and Money read them.
    ///
    /// **THEIR OWN FETCH AS WELL (2026-11-15).** The list's window is every
    /// app's newest things together, so the Wallet's rows could all fall
    /// outside it; `walletFeedRows` is the Wallet's newest by itself. The
    /// list's rows lead, so a move that has just landed shows before the
    /// task reads again.
    func activityMoneyRows(_ visible: [Thing]) -> [Thing] {
        let listed = visible.filter { $0.isLive && Self.scrollCategory(ofSource: $0.source) == CategoryFold.walletRoom }
        // A pick in the list's own filter (a tag) is the list's alone.
        guard filter.tag == "All" else { return listed }
        var seen = Set(listed.map(\.id))
        return listed + walletFeedRows.live.filter { seen.insert($0.id).inserted }
    }

    /// The Wallet's newest rows, one bounded fetch from the Feed's `.task`,
    /// never a body (§628). The same rows the list would hand over were its
    /// window wide enough: Privy's hidden apps stay hidden (prd §803e).
    @MainActor
    func loadWalletFeedRows() {
        let sources = RoomAccounts.roomSources(CategoryFold.walletRoom)
        var newest = FetchDescriptor<Thing>(
            predicate: #Predicate { sources.contains($0.source) },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        newest.fetchLimit = Self.walletFeedFetchLimit
        // A wallet you follow is never your Feed (prd §1969).
        let leftOut = FollowedNews.followed
        let rows = ((try? modelContext.fetch(newest)) ?? []).filter { thing in
            thing.isLive && Self.scrollCategory(ofSource: thing.source) == CategoryFold.walletRoom
                && !FollowedNews.isFollowedRow(thing, followed: leftOut)
                && (thing.source != PrivyHomeFeed.source || PrivyHomeStore.shared.shows(thing, inRoom: false))
        }
        guard rows.map(\.id) != walletFeedRows.map(\.id) else { return }
        walletFeedRows = rows
    }

    /// One row per app is drawn; this is room for the asks among them.
    static let walletFeedFetchLimit = 200

    /// **NEEDS YOU LEADS ACTIVITY (prd §1807).** It left Home with the
    /// doors: what your account still wants, and what waits on you in the
    /// Wallet, each a row onto its page. Nothing waiting, no section.
    @ViewBuilder
    func activityNeedsSection(_ visible: [Thing]) -> some View {
        // The Mac carries no wallet (prd §1893): only what your apps ask.
        let wallet = WalletHere.isOn
        let money = wallet ? activityMoneyRows(visible) : []
        let asks = wallet ? walletUpcoming(money) : []
        let needs = wallet ? walletNeedsCount(upcoming: asks) : 0
        // **THE ROW NAMES WHAT WAITS (prd §1809).** It read "Money · 13"
        // directly over the Money section, two Moneys in a row; it is the
        // first thing waiting now, and how many more.
        // Under Needs you a row does not say it needs you (§1378, §1862).
        let first = asks.first(where: \.isLive).map { NeedsYouWords.name($0.title) }
        let yours = wallet ? YourAccountDemo.shownAddress : nil
        let pending = yours.map { chrome.walkClosed >= 0 && YourAccountFirstOpen.setupPending($0) } ?? false
        // Before anything has moved the Wallet's own row says it (prd
        // §1839): one row for your account on the whole of Activity.
        let walletCarries = quietActivity && money.isEmpty
        let wants = walletCarries ? nil
            : pending ? String(localized: "Finish setup") : (yours != nil ? yourAccountWants : nil)
        // What waits on you in your apps (prd §1813): the lists a category's
        // page led with, Coming up's asks and what is to you, now here.
        let waiting = quietActivity ? activityNeedThings(visible) : []
        // **RISKS FOUND ARE AN ASK (prd §1843).** Home's Risks card left
        // with the cards; what it counted and you have not seen stands here,
        // one row onto Risks.
        // On Home risks are never an ask (prd §1857): Risks' door counts them.
        let risks = homeHeadShown || !wallet ? 0 : homeRisksUnseen
        // **HOME'S NEEDS YOU IS ONE ROW (prd §1857, user: "only one item in
        // needs you (not risks)").** Your account's ask, else the Wallet's
        // first, else the newest an app asks; the rest wait on their pages.
        let one = homeHeadShown
        let showsNeeds = needs > 0 && !(one && wants != nil)
        let shownWaiting = one ? (wants == nil && needs == 0 ? Array(waiting.prefix(1)) : []) : waiting
        if needs > 0 || wants != nil || !waiting.isEmpty || risks > 0 {
            SectionPanelGroup(anchor: Self.scrollAnchor(WalletSection.needsYou.label)) {
                ActivityWord(name: WalletSection.needsYou.label, open: nil)
            } rows: {
                if let wants {
                    activityAskRow(glyph: WalletSection.yourAccount.glyph,
                                   name: String(localized: "Account"), word: wants) {
                        if pending {
                            chrome.moveWalk = true
                            chrome.moveTray = true
                        } else {
                            chrome.openWalletPage(.yourAccount, fromActivity: WalletSection.needsYou.label)
                        }
                    }
                }
                if showsNeeds {
                    activityAskRow(glyph: ScopeTileGlyph.wallets,
                                   name: first ?? String(localized: "Wallet"),
                                   word: first == nil ? "\(needs)"
                                       : needs > 1 ? String(localized: "\(needs - 1) more") : "") {
                        chrome.openWalletPage(.needsYou, fromActivity: WalletSection.needsYou.label)
                    }
                }
                if risks > 0 {
                    activityAskRow(glyph: WalletSection.threats.glyph,
                                   name: WalletSection.threats.label, word: "\(risks)") {
                        ActivitySeen.shared.leavingForPage()
                        chrome.openWalletPage(.threats, fromActivity: WalletSection.needsYou.label,
                                              keepingScope: true)
                    }
                }
                if !shownWaiting.isEmpty {
                    // What waits on you opens the thing, the whole row (prd
                    // §1840): the review, the failed run, the reply.
                    daySection("", shownWaiting, nextEventID: nil, dated: false, headed: false, inFeed: true)
                }
            }
            .environment(\.feedSectionPanelFilled, false)
            .environment(\.dsTitleOnly, true)
        }
    }

    /// **WHAT WAITS ON YOU IN YOUR APPS (prd §1813).** A category's page led
    /// with these: Work's asks (a review asked of you, a failed run, an open
    /// dispute: `WorkAsk`) and what someone said to you (a reply, a mention
    /// naming you). With no category page they stand in Needs you, each
    /// app's newest, a week at most, by both rules' own window. A like or a
    /// new follower is news, not an ask, and stays its app's row.
    func activityNeedThings(_ visible: [Thing]) -> [Thing] {
        let now = Date.now
        let week = visible.filter {
            $0.isLive && $0.capturedAt <= now && now.timeIntervalSince($0.capturedAt) <= WorkAsk.window
                && !Pinboard.inRoom($0)
        }
        guard !week.isEmpty else { return [] }
        // Each source's section once, never each row's.
        var sectionOf: [String: String] = [:]
        for source in Set(week.map(\.source)) {
            sectionOf[source] = Self.scrollCategory(ofSource: source) ?? ""
        }
        let mine = socialMyHandles
        return Self.newestPerApp(week.filter { thing in
            switch sectionOf[thing.source] {
            case RoomAccounts.workRoom:
                return WorkAsk.needsYou(WorkStage.Row(thing), at: thing.capturedAt, now: now)
            case RoomAccounts.socialRoom:
                guard thing.socialContext == "reply" || thing.socialContext == "mention" else { return false }
                return SocialToYou.isToYou(Self.toYouRow(thing), myHandles: mine)
            default:
                return false
            }
        })
    }

    /// One ask: its glyph in the attention hue, its name, its state in the
    /// attention ink (prd §1004), the chevron of a row that opens.
    func activityAskRow(glyph: String, name: String, word: String, act: @escaping () -> Void) -> some View {
        DSPushRow(title: Text(verbatim: name), fact: Text(verbatim: word), factTone: DS.attentionInk,
                  action: act) {
            Image(systemName: glyph)
                .dsGlyph(.body)
                .foregroundStyle(DS.attention)
                .frame(width: DS.Mark.row)
                .accessibilityHidden(true)
        }
        .feedRowBackground()
        .listRowInsets(.init(top: Self.rowAir, leading: DSRoomChassis.rowInset,
                             bottom: Self.rowAir, trailing: DSRoomChassis.rowInset))
        .listRowSeparator(.hidden)
    }

    /// **MONEY, BY THE SAME RULE (prd §1809, amending §1807's latest
    /// three).** Each money app's newest move, as every category reads; the
    /// word opens all of it, the Wallet's Money page.
    @ViewBuilder
    func activityMoneySection(_ visible: [Thing], nextEventID: UUID?) -> some View {
        let money = activityMoneyRows(visible)
        // What waits on you is Needs you's, never a move (user, 2026-11-14:
        // "one of money moves as a transfer that needs attention is needs
        // you"): a stuck transfer or a dated ask leaves this list.
        let asks = Set(walletUpcoming(money).map(\.id))
        // **A DATE AHEAD IS AN ASK, NEVER A MOVE (prd §1847, user: "ENS
        // shows in wallet but it should have been in needs you").** A name's
        // expiry months out, or one you marked as seen, left Needs you and
        // landed here as the Wallet's newest move.
        let now = Date.now
        let landed = Self.walletMoves(money).filter {
            !asks.contains($0.id) && ($0.dueAt ?? .distantPast) <= now
        }
        let moves = Self.newestPerApp(landed)
        // **THE WALLET ALWAYS SHOWS ONE THING (prd §1847, user: "wallet
        // should have one transaction").** With nothing new its last move
        // stands, in the seen ink (`activityAppRow`).
        let fresh = moves.filter { !ActivitySeen.shared.isHidden($0.id) }
        // **NOTHING HAS MOVED YET: YOUR ACCOUNT STANDS (prd §1839, user:
        // "wallet activity should be there as a place holder too").** A
        // Wallet with no move at all draws its word over your account's row,
        // never the word alone.
        if quietActivity, moves.isEmpty {
            // The first run's card is the Wallet's whole start (prd §1847).
            if !homeBare, WalletHere.isOn { activityWalletStart }
        } else {
        // **THE WORD IS THE CATEGORY'S OWN (prd §1812, user: "'money'
        // shouldn't be the category title it should be wallet like it is in
        // the app library").** Every other word on Activity is its Apps
        // category; this one read "Money".
        // What is new (prd §1831); the word stays when nothing is: it is
        // the door to every move.
        // **ON HOME IT IS ACTIVITY, ONE ROW (prd §1857):** the newest move,
        // the watchlist gone to Holdings' section.
        let word = homeHeadShown ? Self.homeWalletName : String(localized: "Wallet")
        let shown = fresh.isEmpty ? Array(moves.prefix(1)) : fresh
        // **WITH NO FEED THE WALLET'S HISTORY FILLS THE PANEL (prd §1864,
        // user: "how do we make it so it's not so empty").** Its latest
        // moves, seen or not, whichever app made them; one row per app left
        // a single wallet with one row over a black page (§1858's three).
        let latest = landed.sorted { $0.capturedAt > $1.capturedAt }.prefix(Self.homeFeedlessMoves)
        let onHome = homeFeedless ? Array(latest) : Array(shown.prefix(1))
        activitySection(word, homeHeadShown ? onHome : shown,
                        // **THE ROW IS THE DOOR (prd §1849, user: "does wallet
                        // need a chevron if everything else doesn't have one?
                        // tapping a transaction could open history").** The
                        // word opens nothing, as every category's; any row
                        // under it opens the Wallet's history.
                        // On Home the word opens every move too, and wears the
                        // chevron (prd §1857, user: "activity also needs a
                        // chevron in feed"), as Holdings' does.
                        nextEventID: nextEventID,
                        open: homeHeadShown ? {
                            DSHaptic.selection()
                            ActivitySeen.shared.leavingForPage()
                            chrome.openWalletActivity(fromActivity: word)
                        } : nil,
                        keepsWord: true,
                        walletLead: homeHeadShown && !homeBare,
                        rowOpens: {
            DSHaptic.selection()
            // Under Activity, and back to it (prd §1827, §1840).
            chrome.openWalletActivity(fromActivity: word)
        })
        }
    }

    /// The Wallet before anything has moved (prd §1839): its word, then your
    /// account's row. The row says what it needs next, "Finish setup" in the
    /// attention ink until the walk is taken (and Needs you leaves that ask
    /// to it), else "No moves yet"; with no account of yours, the verb that
    /// makes one, as Home's door says it.
    @ViewBuilder
    private var activityWalletStart: some View {
        let yours = YourAccountDemo.shownAddress
        let pending = yours.map { chrome.walkClosed >= 0 && YourAccountFirstOpen.setupPending($0) } ?? false
        // What your account still wants, as Needs you would say it.
        let wants = pending ? String(localized: "Finish setup") : (yours != nil ? yourAccountWants : nil)
        let word = homeHeadShown ? Self.homeWalletName : String(localized: "Wallet")
        SectionPanelGroup(anchor: Self.scrollAnchor(word)) {
            ActivityWord(name: word, open: {
                DSHaptic.selection()
                ActivitySeen.shared.leavingForPage()
                // Under Activity, and back to it (prd §1827, §1840).
                chrome.openWalletActivity(fromActivity: word)
            })
        } rows: {
            if homeHeadShown && !homeBare { homeWalletLeadRows }
            DSPushRow(title: Text(yours == nil ? "Create an account" : "Your account"),
                      subtitle: yours == nil ? nil : wants.map { Text(verbatim: $0) } ?? Text("No moves yet"),
                      subtitleTone: wants != nil ? DS.attentionInk : DS.textSecondary,
                      action: {
                          if yours == nil || pending {
                              chrome.moveWalk = pending
                              chrome.moveTray = true
                          } else {
                              chrome.openWalletPage(.yourAccount, fromActivity: word)
                          }
                      }) {
                Image(systemName: WalletSection.yourAccount.glyph)
                    .dsGlyph(.body)
                    .foregroundStyle(DS.brandInk)
                    .frame(width: DS.Mark.row, height: DS.Mark.row)
                    .accessibilityHidden(true)
            }
            .feedRowBackground()
            .listRowInsets(.init(top: Self.rowAir, leading: DSRoomChassis.rowInset,
                                 bottom: Self.rowAir, trailing: DSRoomChassis.rowInset))
            .listRowSeparator(.hidden)
            // Your account is made on the first run's Activity, as on the
            // Wallet's first open (prd §1741, §1839); in a task, never a
            // body (a Keychain read, prd §628).
            .task { YourAccountFirstOpen.makeIfFresh() }
        }
        .environment(\.feedSectionPanelFilled, false)
        .environment(\.dsTitleOnly, true)
    }

    /// One category, on one panel (prd §1208d, user: "i think G is
    /// necessary now"): the name caps its top, every row of the section
    /// stands on the panel's fill, and an end cap rounds its foot.
    @ViewBuilder
    func scrollSection(_ category: String, _ things: [Thing], nextEventID: UUID?) -> some View {
        let _ = { memo.sectionCounts[category] = things.count }()
        let cap = sectionCaps[category] ?? Self.sectionFirstRows
        panelSection(category, glyph: CategoryFold.glyph(for: category), things: things,
                     choices: sectionChoices(category)) {
            let _ = { Self.sectionCapNow = (category, cap) }()
            categorySections(category, things, nextEventID: nextEventID)
            let _ = { Self.sectionCapNow = nil }()
        }
        // The title and the app's icon, no line under it (prd §1497).
        .environment(\.dsTitleOnly, true)
    }

    /// A named section on its panel (prd §1208d): the name caps the top,
    /// the rows stand on the panel's fill, an end cap rounds the foot. The
    /// Feed's categories and the Wallet's Home lists (prd §1219) both draw
    /// through this one template.
    @ViewBuilder
    func panelSection<Rows: View>(_ name: String, glyph: String, things: [Thing],
                                  choices: [SectionChoice] = [],
                                  @ViewBuilder rows: () -> Rows) -> some View {
        SectionPanelGroup(anchor: Self.scrollAnchor(name), lit: landedSection == name) {
            scrollHeader(name, glyph: glyph, things, choices: choices)
        } rows: {
            rows()
        }
        // Bare (prd §1382): the gaps stay, the fill goes.
        .environment(\.feedSectionPanelFilled, false)
    }

    /// Each category's own sections — the room's tiles and list — as its
    /// page draws them, WITHOUT the newest thing's cover (prd §1208c, user:
    /// "in most places its just waste of space"): `heroShown` is the rooms'
    /// own word for "the box is taken", so their covers stand down and the
    /// newest thing stays a row. A box that says more than the newest thing
    /// stays — Day's timeline, a Subscriptions or Coming up figure.
    @ViewBuilder
    private func categorySections(_ category: String, _ things: [Thing], nextEventID: UUID?) -> some View {
        switch category {
        // Day reads its own rows (`dayFeedRows`): the Feed's list holds none
        // of what is ahead (prd §1343). Day's room on iPad and the Mac draws
        // this section over the room's own rows (prd §1344).
        case HomeScope.notesSection:
            notesFeedSection(things, nextEventID: nextEventID)
        case RoomAccounts.dayRoom:
            dayFeedSections(nextEventID: nextEventID,
                            rows: source == RoomAccounts.dayRoom ? things : nil)
                // The pane's rows (prd §1403): drawn there, never in a list
                // column beside one.
                .environment(\.dsPaneBoxRow, true)
        case RoomAccounts.lifeRoom:
            lifeRoomSections(things, nextEventID: nextEventID)
        case RoomAccounts.workRoom:
            // One row per object (prd §1079) on the Feed too: the Work
            // page's rows arrive folded, and folding twice changes nothing.
            workRoomSections(objectFolded(things), nextEventID: nextEventID, heroShown: true)
        case RoomAccounts.mediaRoom:
            mediaRoomSections(things, nextEventID: nextEventID, heroShown: true)
        case RoomAccounts.socialRoom:
            socialRoomSections(things, nextEventID: nextEventID, heroShown: true)
        default:
            groupedSections(chronoDays(things), nextEventID: nextEventID)
        }
    }

    /// A section's name (prd §1208c, §1208l): a chapter's title in the pink
    /// every title wears, its category's glyph before it and what is new
    /// since your last visit after it (counting down as you read past).
    /// The sections do not fold (§1208c); a category's name opens its page
    /// (prd §1808, amending §1208a). As it reaches the top it
    /// shrinks into the pill that names where you are.
    private func scrollHeader(_ category: String, glyph: String, _ things: [Thing],
                              choices: [SectionChoice] = []) -> some View {
        let seen = NewSeen.shared.ids
        let fresh = newSince.map { since in
            things.filter { $0.isLive && $0.capturedAt > since && !seen.contains($0.id) }.count
        } ?? 0
        // The name opens the category's page (prd §1808); Money and Needs
        // you are no category and stay labels.
        let door: (() -> Void)? = CategoryFold.isCategory(category) && category != CategoryFold.walletRoom
            ? { openCategory(category) } : nil
        return SectionPanelName(name: category, glyph: glyph, choices: choices,
                                adds: sectionAdds(category), open: door) {
            if fresh > 0 {
                HStack(spacing: DS.Space.s1) {
                    Circle().fill(DS.pickInk).frame(width: 7, height: 7)
                    Text("\(fresh) new")
                        .dsText(.subhead12)
                        .foregroundStyle(DS.textSecondary)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(fresh)))
                }
                .transition(.opacity)
            }
        }
        .animation(DS.Motion.standard, value: fresh)
        // NO HANDOFF (prd §1386): the name scrolls under the pinned copy of
        // itself, as a List's section header does; nothing shrinks or fades.
        // Where you are (prd §1208d): each name reports where it stands,
        // so the pill above the scroll names the section you are in.
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { y in
            noteSectionTop(category, y)
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
    }

    /// How far above the line a name starts handing off to the pill.
    static let handoffSpan: CGFloat = 56

    /// The pinned header's foot (prd §1386): a row whose bottom has passed it
    /// is under the header, out of sight (`NewSeenMark` notes it read there). The
    /// demo's band moves the header down, so the line moves with it (§1297).
    static var whereLine: CGFloat { topInset + pinnedHeaderHeight + DSDemoMark.screenClearance }

    /// Where the pinned header's top stands, which is where a section's own
    /// name stands when its row reaches the top. The pinned copy is drawn to
    /// the same measure as the name in the list (`SectionPanelName`'s air,
    /// its + kept as a hidden place), so the two coincide there and the
    /// handover cannot be seen: the name pins as it reaches this line, never
    /// earlier. Pinned at the header's foot, it left the name's lower half
    /// showing under its own copy wherever a scroll or a jump came to rest
    /// (two "Spending"s, two "Accounts", 2026-10-18).
    static var pinLine: CGFloat { topInset + DSDemoMark.screenClearance }

    /// The pinned header's height before it has measured itself: the name's
    /// air above (`s4`), one `heading24` line (28pt, prd §1496), its air
    /// below (`s2`).
    static let pinnedHeaderHeight: CGFloat = 51

    /// The window's top inset, read once: the overlay stands at the list's
    /// top, which is the safe area's.
    private static var topInset: CGFloat {
        if let cached = cachedTopInset { return cached }
        let top = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.safeAreaInsets.top
        if let top, top > 0 { cachedTopInset = top; return top }
        return 59
    }
    private static var cachedTopInset: CGFloat?

    /// A name moved: the section you are in is the last whose name has
    /// reached the top. Written only when it changes, so a scroll costs one
    /// dictionary write per frame and a body pass per section crossed; the
    /// push below is the pinned header's own state and redraws it alone.
    private func noteSectionTop(_ category: String, _ y: CGFloat) {
        memo.sectionTops[category] = y
        let order = pillSections
        let line = Self.pinLine + 0.5
        let current = order.last { (memo.sectionTops[$0] ?? .infinity) <= line }
        // THE NEXT NAME PUSHES THE PINNED ONE OFF (prd §1386's "until the
        // next section's pushes it off", built): as the next section's name
        // rises into the header's height, the header rises with it, so the
        // two never overlap and the next one arrives exactly where its copy
        // takes over.
        var push: CGFloat = 0
        if let current, let i = order.firstIndex(of: current), i + 1 < order.count,
           let next = memo.sectionTops[order[i + 1]] {
            push = min(max(Self.pinLine + pinPush.height - next, 0), pinPush.height)
        }
        if abs(pinPush.offset - push) > 0.25 { pinPush.offset = push }
        guard feedSection != current else { return }
        // A section crossed is felt once (prd §1208l) — a change of place,
        // never a tap.
        if feedSection != nil, current != nil { DSHaptic.selection() }
        feedSection = current
    }

    /// **THE SECTION'S HEADER PINS (prd §1386, amends §1208d's pill).** Once
    /// a section's name has scrolled past, the same header — its pink glyph
    /// and its name at the rows' inset, on the page's ground — holds the top
    /// edge until the next section's pushes it off, as a List's section
    /// headers do. No capsule, no glass, no "Feed ·": nothing new stands at
    /// the top (§752), and the eye reads the header it already knows. A
    /// press still takes the page to its top (prd §1212), a hold still
    /// lists the sections (§1208l).
    @ViewBuilder
    func feedSectionPill(_ proxy: ScrollViewProxy) -> some View {
        Group {
            if !pillSections.isEmpty, let section = feedSection {
                // A press takes the Feed to its top (prd §1212); a hold lists
                // the sections in Feed order with today's counts, and a pick
                // scrolls there (prd §1208l). The Wallet's Home wears the same
                // pill over its lists (prd §1219).
                let wallet = shape == .wallet
                let adds = sectionAdds(section)
                // The list header's row, to its measure: the name's air above
                // and below (`SectionPanelName`) and its + — a full hit target
                // tall, which sets where the name sits — so the copy and the
                // name coincide at the top (`pinLine`), and the + still works
                // while its name is pinned.
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    Menu {
                        ForEach(pillSections, id: \.self) { category in
                            Button {
                                if wallet {
                                    walletHomeJump(category)
                                } else {
                                    chrome.feedJump = category
                                    settleFeedJump(proxy)
                                }
                            } label: {
                                Label {
                                    Text(verbatim: category)
                                } icon: {
                                    Image(systemName: wallet ? Self.walletHomeGlyph(category) : CategoryFold.glyph(for: category))
                                }
                                if !wallet, let n = memo.sectionCounts[category], n > 0 {
                                    Text("\(n) today")
                                }
                            }
                        }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: DSRoomChassis.headGap) {
                            // No transition: the name changes where the list's
                            // own copy stands under it, and the push-off is the
                            // motion. An animated word here drew two names at once.
                            Text(verbatim: section)
                                .dsText(.heading24)
                                .foregroundStyle(DS.headInk)
                                .lineLimit(1)
                                .id(section)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    } primaryAction: {
                        // The pinned copy does what the name under it does
                        // (prd §1808): in Activity a category's name opens
                        // its page; anywhere else it returns to the top.
                        if !wallet, CategoryFold.isCategory(section), section != CategoryFold.walletRoom {
                            openCategory(section)
                        } else {
                            DSHaptic.tap()
                            returnToRoomTop(proxy)
                        }
                    }
                    .buttonStyle(RowPress())
                    .accessibilityElement(children: .combine)
                    .accessibilityHint(wallet ? Text("Scrolls to the top. Hold for the sections.")
                                              : Text("Opens this section. Hold for the sections."))
                    if !adds.isEmpty { SectionAddControl(name: section, adds: adds) }
                }
                .padding(.horizontal, DSRoomChassis.rowInset)
                .padding(.top, DS.Space.s4)
                .padding(.bottom, DS.Space.s2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    // The page's own ground, running up under the status
                    // bar and fading out under the rows that pass beneath.
                    VStack(spacing: 0) {
                        DS.page
                        LinearGradient(colors: [DS.page, DS.page.opacity(0)],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: DS.Space.s3)
                    }
                    .padding(.bottom, -DS.Space.s3)
                    .ignoresSafeArea(edges: .top)
                }
                .modifier(PinnedHeaderPushed(push: pinPush))
                .padding(.top, DSDemoMark.screenClearance)
                // It appears over the name it copies, at one measure, so it
                // simply is there: a fade or a slide drew the two apart.
                .transition(.identity)
            }
        }
        // The pill's own coming and going, and nothing else in the Feed: on
        // the List it animated every row that landed as a section changed.
        .animation(DS.Motion.standard, value: feedSection == nil)
    }

    /// More (prd §1208 item 4): ten more rows in place; the scroll goes on
    /// into the next category.
    func sectionMoreRow(_ category: String) -> some View {
        // The one More row (prd §1386, `DSMoreRow`): grey words and a
        // chevron at the rows' inset, never a disc, never centred.
        DSMoreRow(title: Text("More from \(category)")) {
            withAnimation(DS.Motion.standard) {
                sectionCaps[category] = (sectionCaps[category] ?? Self.sectionFirstRows) + Self.sectionMoreRows
            }
        }
        // In the rows' TEXT column (prd §1734): under the titles it continues,
        // where it stood under their icons.
        .padding(.leading, DS.Mark.row + DS.Space.s3)
        .feedRowBackground()
        .listRowInsets(.init(top: Self.rowAir,
                             leading: DSRoomChassis.rowInset,
                             bottom: Self.rowAir,
                             trailing: DSRoomChassis.rowInset))
        .listRowSeparator(.hidden)
    }

    /// The tray asked for a category (prd §1208 item 6): scroll its name to
    /// the top.
    /// ROOM UNDER THE LAST SECTION (user, 2026-10-10: the landing "is
    /// jarring and inconsistent"): without it the last sections cannot bring
    /// their names to the top, so a jump to them stopped lower than the rest
    /// and the pill named the section above. Air, not a footer.
    static let jumpRoomHeight: CGFloat = 380

    @ViewBuilder
    func jumpRoom(onPanel: Bool) -> some View {
        Section {
            Color.clear
                .frame(height: Self.jumpRoomHeight)
                .listRowInsets(EdgeInsets())
                // Apps' panel carries on to the foot of Activity (prd §1839),
                // and only where the panel stands (prd §1848): with no panel
                // above it the fill was a slab under the last row.
                .listRowBackground(onPanel ? DS.fillQuiet : Color.clear)
                .listRowSeparator(.hidden)
                .accessibilityHidden(true)
        }
    }

    /// Instant landings it takes a lazily laid-out list to settle on a far
    /// section (measured: one stops short by the rows it had not met).
    static let landingPasses = 4

    /// `feedJump`'s word for the page's top, never a section's name.
    static let topJump = "\u{1}top"

    func settleFeedJump(_ proxy: ScrollViewProxy) {
        // The Feed on screen takes the jump, never one mounted beside it.
        guard source == "All", isActive, let category = chrome.feedJump else { return }
        #if DEBUG
        NSLog("[Casberi] feedJump: %@", category)
        #endif
        chrome.feedJump = nil
        // The page's top: a page left for Home lands there (`topJump`).
        if category == Self.topJump {
            Task { @MainActor in
                var instant = Transaction()
                instant.disablesAnimations = true
                for pass in 0..<Self.landingPasses {
                    try? await Task.sleep(for: .milliseconds(pass == 0 ? 60 : 70))
                    withTransaction(instant) { proxy.scrollTo(Self.roomTitleAnchor, anchor: .top) }
                }
            }
            return
        }
        // **ONE LANDING, EVERY TIME (user, 2026-10-10: "it is jarring and
        // inconsistent").** An animated scroll travels to a position the list
        // has only ESTIMATED (rows off screen are not measured yet), and the
        // correction after it slid the page back the other way — up for one
        // section, down for the next. So the jump lands at once, as a section
        // index does (Contacts' letters), settles once more after layout, and
        // the brightening below is what the eye follows.
        Task { @MainActor in
            var instant = Transaction()
            instant.disablesAnimations = true
            // A far section lands on the list's estimate first; each pass
            // measures the rows it lands among, so a few settle it exactly.
            for pass in 0..<Self.landingPasses {
                try? await Task.sleep(for: .milliseconds(pass == 0 ? 60 : 70))
                // Needs you and the Wallet carry their word's anchor, not a
                // category's id (prd §1843: Home's chips jump to them too).
                let target = category == WalletSection.needsYou.label || category == Self.homeWalletName
                    ? Self.scrollAnchor(category) : Self.sectionID(category)
                withTransaction(instant) { proxy.scrollTo(target, anchor: .top) }
            }
            // LANDING (prd §1208l): the section you arrived at brightens once,
            // so the eye finds where it landed.
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(DS.Motion.standard) { landedSection = category }
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(.easeOut(duration: 0.6)) { landedSection = nil }
        }
    }
}

/// A section's panel (prd §1208d, amends §782 for the Feed's sections only):
/// the room's fill, inset to the box's column, its top and foot rounded at
/// the widget radius so a category reads as one object.
extension EnvironmentValues {
    /// `SectionPanel`'s distance from the list's edge (prd §1320).
    @Entry var feedSectionPanelInset: CGFloat = DS.Space.s2
    /// The anchor of the section standing right under Home's jump chips
    /// (prd §1843): it takes no chapter air, since the chips' own gap above
    /// them is that air and the chips belong to the feed they jump through.
    @Entry var feedSectionLeads: String? = nil
    /// Home's money sections (Needs you, Activity, Holdings) stand close:
    /// no section gap over them and a short top on their word (prd §1857,
    /// user: "spacing isn't good", "you can't see the first app on there
    /// above the fold"). The feed's sections keep the one gap.
    @Entry var feedSectionClose: Bool = false
    /// Whether the panel draws its fill: nowhere, since prd §1393 (the
    /// Feed's and the Wallet's since §1382, Library's since §1383). The
    /// shape stays, so rows keep their column and the gaps their height;
    /// the only fills left are the Apps page's folders, which are not panels.
    @Entry var feedSectionPanelFilled: Bool = false
}

struct SectionPanel: View {
    enum Part { case top, middle, bottom }
    let part: Part
    /// Brightened once on landing (prd §1208l).
    var lit = false
    /// How far in from the list's edge the panel stands: the Feed's s2, or
    /// Sources' s4, where its own cards and box stand (prd §1320). Passed in,
    /// never read here: a row's background does not see the row's environment.
    var inset: CGFloat = DS.Space.s2
    /// Off on the Feed and the Wallet (prd §1382): the shape stays, so the
    /// rows keep their column and the gaps their height, and nothing fills it.
    /// Bare by default (prd §1393, then the account pages' caps, user,
    /// 2026-10-18: "all the connect and set up screens … still have gray
    /// cards"): a panel's name and its air say where it starts. The middle
    /// rows read `feedSectionPanelFilled` (false); the top and bottom caps
    /// took this default, so every connect screen kept its grey card.
    var filled = false

    var body: some View {
        let r = DS.Radius.widget
        UnevenRoundedRectangle(topLeadingRadius: part == .top ? r : 0,
                               bottomLeadingRadius: part == .bottom ? r : 0,
                               bottomTrailingRadius: part == .bottom ? r : 0,
                               topTrailingRadius: part == .top ? r : 0,
                               style: .continuous)
            .fill(filled ? (lit ? DS.fillFaint : Self.fill) : Color.clear)
            .padding(.horizontal, inset)
    }

    /// A shade under the boxes and tiles (theirs is `fillFaint`), so they
    /// keep their own wells on the panel.
    static let fill = Color.adaptive(dark: "#111113", light: "#F2F2F7")
}

/// NEW SINCE YOU LOOKED (prd §1208d, §1208l): what scrolled past this
/// visit, observed, so a section's "N new" counts down as you read; a later
/// visit's line moves anyway.
@MainActor @Observable final class NewSeen {
    static let shared = NewSeen()
    var ids: Set<UUID> = []
}

/// **NO DOT ON A ROW (prd §1735, user: "why do we need the red indicator
/// dots? if this is a feed of notification they will always be there").**
/// The dot §1208d drew by every row that came since you left is deleted: in
/// a feed of what arrived, nearly every row wore one. The section's "N new"
/// says it once. This draws nothing; it only notes the row as read once it
/// has scrolled past the top, which is what counts that number down.
struct NewSeenMark: View {
    let id: UUID

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onGeometryChange(for: Bool.self) { $0.frame(in: .global).maxY < FeedScreen.whereLine - 40 } action: { past in
                guard past, !NewSeen.shared.ids.contains(id) else { return }
                NewSeen.shared.ids.insert(id)
            }
            .accessibilityHidden(true)
    }
}


/// Two across; one across at the accessibility text sizes, where a square
/// cannot hold the words (prd §1208l).
struct GlanceGrid<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @ViewBuilder let content: () -> Content

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s2),
                                 count: typeSize.isAccessibilitySize ? 1 : 2),
                  spacing: DS.Space.s2, content: content)
    }
}

/// The glance frame's one height.
enum GlanceMetrics {
    static let height: CGFloat = 168
}

/// THE GLANCE TILE'S FRAME (prd §1208d, §1222): one height, the room's faint
/// fill, a press, a head of mark · category · when, then the words, then
/// "N new". What this app reaches draws a category in it (the Feed's and the
/// Wallet's tiles went with prd §1256 and §1257).
struct GlanceShell<Top: View, Mark: View, Words: View>: View {
    let category: String
    let when: String?
    var fresh: Int = 0
    let accessibility: Text
    let action: () -> Void
    @ViewBuilder let top: Top
    @ViewBuilder let mark: Mark
    @ViewBuilder let words: Words
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                top
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    HStack(spacing: DS.Space.s2) {
                        mark
                        Text(verbatim: category)
                            .dsText(.label12)
                            .fontWeight(.semibold)
                            .foregroundStyle(DS.headInk)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if let when {
                            Text(verbatim: when)
                                .dsText(.label12)
                                .foregroundStyle(DS.textTertiary)
                                .lineLimit(1)
                        }
                    }
                    words
                }
                .padding(.horizontal, DS.Space.s3)
                .padding(.vertical, DS.Space.s3)
                Spacer(minLength: 0)
                if fresh > 0 {
                    Text("\(fresh) new")
                        .dsText(.label12)
                        .fontWeight(.semibold)
                        .foregroundStyle(DS.textSecondary)
                        .padding(.horizontal, DS.Space.s3)
                        .padding(.bottom, DS.Space.s3)
                }
            }
            // A square, until the words need more (the accessibility sizes).
            .frame(maxWidth: .infinity,
                   minHeight: typeSize.isAccessibilitySize ? nil : GlanceMetrics.height,
                   maxHeight: typeSize.isAccessibilitySize ? nil : GlanceMetrics.height,
                   alignment: .topLeading)
            .background(DS.fillFaint, in: RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
        }
        .buttonStyle(PressSpring())
        .accessibilityLabel(accessibility)
        .accessibilityValue(fresh > 0 ? Text("\(fresh) new") : Text(verbatim: ""))
        .accessibilityHint(Text("Shows this section"))
    }
}

/// A section's name on its panel (prd §1208c, §1222): the category's glyph
/// and its name in the brand pink, then whatever the section says beside it.
struct SectionPanelName<Trailing: View>: View {
    let name: String
    let glyph: String
    /// An app's own mark in the glyph column, in place of `glyph`: the
    /// section is that app's reading (Privacy, by Nymis, prd §1701).
    var mark: String? = nil
    /// **A SECTION'S NAME IS `heading24` (prd §1496, user: "would that mean
    /// dropping feed headers to 24?"; "i am now starting to feel the experience
    /// i wanted in the app from the very beginning, the stupid simple").** The
    /// ramp's own rung for a card's name; `heading28` was the lede's fit
    /// ladder borrowed, which put every Feed section a step over every other
    /// section in the app. The Wallet's doors stand on the same rung
    /// (`walletDoor`), so a Feed section and a Wallet door are one anatomy.
    ///
    /// **THE HEADER NAMES ITS CHOICES (prd §1251, user: "s4 is gorgeous").**
    /// In the Feed a section's tiles stand down and its header reads every
    /// choice at the title's own size, the picked one in the pink and the
    /// others grey ("Life Subscriptions"); a tap on a grey word switches.
    /// Empty: the plain name, as before.
    var choices: [SectionChoice] = []
    /// **EVERY SECTION ADDS FROM ITS HEADER (prd §1293).** A + at the end
    /// runs the category's own add, the act of its Sources count's plus
    /// (prd §1292); two acts open a menu of both. Empty: no +.
    var adds: [SectionAdd] = []
    /// **A CATEGORY'S NAME IS ITS DOOR (prd §1808, user: "if i tap social i
    /// can't get to my twitter page").** Activity shows the newest thing from
    /// each app; the name above them opens the category's own page, with
    /// everything in it. Nil: a label, as everywhere else.
    var open: (() -> Void)? = nil
    var inset: CGFloat = DSRoomChassis.rowInset
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DSRoomChassis.headGap) {
            // One glyph column (user, 2026-10-23: "look how all this stuff has
            // different indentation on the headers"): a symbol drawn at its own
            // width put every title at a different x. Centered in a fixed
            // column, every section's name starts at one edge.
            if let mark {
                BridgeIcon(name: mark, size: DS.Mark.row, circular: false)
                    .frame(width: DSRoomChassis.headGlyph)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 8 }
                    .accessibilityHidden(true)
            }
            // **NO GLYPH, AT THE LEFT EDGE (prd §1814, user: "with the glyphs
            // everywhere it can bleed all together"; "drop and put to left
            // edge").** A pink symbol led every name, in the column the rows'
            // icons and their own pink verbs stand in; the name hangs left of
            // the rows' words now and position does the separating. `glyph`
            // is no longer drawn here; an app's own `mark` still is.
            if choices.isEmpty, let open {
                Button {
                    DSHaptic.selection()
                    open()
                } label: {
                    Text(verbatim: name)
                        .dsText(.heading24)
                        .foregroundStyle(DS.headInk)
                        .lineLimit(1)
                        .contentShape(Rectangle())
                }
                .buttonStyle(RowPress())
                .accessibilityHint(Text("Opens \(name)"))
            } else if choices.isEmpty {
                Text(verbatim: name)
                    .dsText(.heading24)
                    .foregroundStyle(DS.headInk)
                    .lineLimit(1)
            } else {
                FlowLayout(spacing: DS.Space.s3, lineSpacing: 0) {
                    ForEach(choices) { choice in
                        Button {
                            DSHaptic.selection()
                            withAnimation(DS.Motion.standard) { choice.pick() }
                        } label: {
                            Text(verbatim: choice.label)
                                .dsText(.heading24)
                                .foregroundStyle(choice.on ? DS.headInk : DS.textTertiary)
                                .lineLimit(1)
                        }
                        .buttonStyle(RowPress())
                        .accessibilityAddTraits(choice.on ? [.isSelected] : [])
                    }
                }
            }
            trailing
            Spacer(minLength: 0)
            if !adds.isEmpty { SectionAddControl(name: name, adds: adds) }
        }
        .accessibilityElement(children: choices.isEmpty && adds.isEmpty && open == nil ? .combine : .contain)
        .accessibilityAddTraits(.isHeader)
        .padding(.leading, inset)
        .padding(.trailing, inset)
        .padding(.top, DS.Space.s4)
        .padding(.bottom, DS.Space.s2)
    }
}

/// A section header's + (prd §1293): one add runs at once, two open a menu
/// of both. Drawn by the header in the list and by its pinned copy, so the +
/// works wherever the name stands (prd §1386).
struct SectionAddControl: View {
    let name: String
    let adds: [SectionAdd]

    var body: some View {
        if let only = adds.first, adds.count == 1 {
            Button {
                DSHaptic.selection()
                only.act()
            } label: { plus }
            .buttonStyle(PressSpring())
            .accessibilityLabel(Text(verbatim: only.label))
        } else if !adds.isEmpty {
            Menu {
                SectionAddMenu(adds: adds)
            } label: { plus }
            .accessibilityLabel(Text("Add to \(name)"))
        }
    }

    /// The header's +, pink as every verb's plus, a full target tall and
    /// wide, on the name's baseline row.
    private var plus: some View {
        Image(systemName: "plus")
            .dsGlyph(.body, weight: .regular)
            .foregroundStyle(DS.brandInk)
            .frame(width: DS.Hit.min, height: DS.Hit.min)
            .contentShape(Rectangle())
    }
}

/// One add a section header offers (prd §1293): its verb and its act.
struct SectionAdd: Identifiable {
    var id: String { label }
    let label: String
    /// What the row follows, under its name in the menu (prd §1300).
    var detail: String? = nil
    /// Set apart from the rows above it by a divider.
    var apart = false
    /// The row's mark: an app's art by its catalogue name, else a glyph.
    var app: String? = nil
    var glyph: String? = nil
    let act: () -> Void
}

/// One row of a + menu (prd §1303): the app's mark, its name, and what it
/// follows under it — the Feed's sections and Sources' counts draw the same.
struct SectionAddMenu: View {
    let adds: [SectionAdd]

    var body: some View {
        ForEach(adds) { add in
            if add.apart { Divider() }
            // Two texts and an image straight in the label: a menu reads them
            // as title, subtitle and icon (a `Label` keeps one line only).
            Button { add.act() } label: {
                Text(verbatim: add.label)
                if let detail = add.detail { Text(verbatim: detail) }
                if let app = add.app {
                    BridgeIcon.menuMark(app)
                } else if let glyph = add.glyph {
                    Image(systemName: glyph)
                }
            }
        }
    }
}

/// One choice a section header names (prd §1251).
struct SectionChoice: Identifiable {
    let id: String
    let label: String
    let on: Bool
    let pick: () -> Void
}

extension FeedScreen {
    /// The choices a Feed section's header names: its category's filters,
    /// the first one spoken as the category itself ("Life", not "All"), no
    /// verbs (Social's Follow stays on Social's own screen).
    func sectionChoices(_ category: String) -> [SectionChoice] {
        switch category {
        // Life's one other choice was Subscriptions (prd §1293): its header
        // is the name alone. Nor Following (prd §1293), nor Work's Coming up or Social's To you
        // (prd §1296, user: "that way all the categories would be simpler"):
        // every row a section holds comes from what you follow, and the
        // header's + is its one act. Work and Social are their names alone;
        // their own screens keep the tiles.
        case RoomAccounts.mediaRoom:
            return MediaScope.allCases.filter { $0 != .subscriptions }.map { s in
                SectionChoice(id: s.rawValue, label: s == .all ? category : s.label,
                              on: chrome.mediaScope == s, pick: { chrome.mediaScope = s })
            }
        default:
            return []
        }
    }
}

extension FeedScreen {
    /// What a Feed section's + adds (prd §1293): since prd §1300 every
    /// catalogue app in the category that follows something by name
    /// (`FollowByName`), A–Z, connected or not; Social ends with the rest of
    /// its apps. A category with no such app draws no +.
    func sectionAdds(_ category: String) -> [SectionAdd] {
        var adds = FollowByName.doors(in: category).map { door in
            SectionAdd(label: door.app, detail: door.what, app: door.app) { followByName(door.app) }
        }
        // MORE SOCIAL APPS LEADS (prd §1303, user: "we don't or ever will
        // have that many bluesky users", then "do the social bluesky thing
        // too"): X, Instagram and TikTok follow nobody by name, so the first
        // row is Sources' Social card, where they connect; Bluesky and
        // Telegram stand under it.
        // **DAY ADDS FROM ITS HEADER (prd §1343, user: "each category header
        // has a + sign by it so we don't need 'new' and 'all'").** An event,
        // a reminder, an email, a subscription to track.
        // Then what Day follows by name — a calendar to subscribe to, now
        // that Calendar is Day's (prd §1347) — set apart under the makes.
        // THE WALLET'S SUBSCRIPTIONS ADDS FROM ITS HEADER (prd §1386): the
        // "+ Track a subscription" row that led its list is deleted; a list
        // with a head adds from its head.
        if shape == .wallet, category == Self.subscriptionsName {
            adds = [SectionAdd(label: SubscriptionWords.track, glyph: SubscriptionWords.planGlyph) {
                feedSheet = .subscriptionAdd
            }]
        }
        if category == RoomAccounts.dayRoom {
            var follows = adds
            if !follows.isEmpty { follows[0].apart = true }
            adds = dayMakes.map { make in
                SectionAdd(label: make.label, glyph: Self.dayMakeGlyph(make)) { makeInDay(make) }
            } + follows
        }
        // **NOTES WRITES FROM ITS HEADER (prd §1347, user: "the plus button
        // just opens notes, same way calendar plus button opens new").** A
        // note, or one spoken, as the Notes page's New and its hold do.
        if category == HomeScope.notesSection {
            adds = [
                SectionAdd(label: String(localized: "New note"), glyph: ScopeTileGlyph.new) { chrome.newNote += 1 },
                SectionAdd(label: String(localized: "Voice note"), glyph: "waveform") { chrome.newNoteByVoice() },
                // **EVERY NOTE, FROM THE FEED (2026-10-16, user: "maybe the
                // plus button should also offer an 'all notes' in its
                // menu").** The Notes page Library's folder opens, on All.
                SectionAdd(label: String(localized: "All notes"), apart: true, glyph: ScopeTileGlyph.all) {
                    chrome.notesScope = .all
                    chrome.notesFolder = nil
                    route.push(.notes)
                },
            ]
        }
        // **THE WALLET'S ACCOUNTS LIST ADDS FROM ITS HEADER (prd §1410):**
        // Follow an account, Connect an app. The Feed's Wallet section that
        // shared the menu is deleted (prd §1489, amending §1347).
        if category == Self.accountsName {
            adds = walletAccountAdds
        }
        // **EVERY + ENDS WITH ITS CATEGORY'S APPS (prd §1620, user, of Work's
        // six: "why those only and not all of them?"; "ok" to one last row).**
        // What you make and what you follow by name come first; the last row
        // opens the catalogue on the category's card, every app there,
        // connected or not. Social's row led (§1303) and now ends, as every
        // section's does.
        if let name = BridgeCatalog.categories.first(where: { $0.name == category })?.name {
            let count = BridgeCatalog.offers.filter { BridgeCatalog.category(of: $0) == name }.count
            // "More agent apps", never "agents apps": the category's noun.
            let noun = name.hasSuffix("s") ? String(name.dropLast()) : name
            adds.append(SectionAdd(label: String(localized: "More \(noun.lowercased()) apps"),
                                   detail: String(localized: "All \(count) in the catalogue"),
                                   apart: !adds.isEmpty,
                                   glyph: "square.grid.2x2") {
                route.openCategory = name
                route.present(.apps)
            })
        }
        return adds
    }

    /// What one of the + rows opens (prd §1300): the tray that app's follow
    /// already runs, on that app; an app that needs an account it doesn't
    /// have yet, or whose follow lives on its own page, opens its page.
    func followByName(_ app: String) {
        let connected = connectedSeatNames.contains(app)
        switch FollowByName.landing(for: app) {
        case .socialFollow:    feedSheet = .socialFollow
        case .reading:         feedSheet = .followingAdd(.reading)
        case .calendar:        feedSheet = .calendarSubscribe
        case .track(let room): feedSheet = .followingAdd(room, seat: app)
        case .github:
            if connected { feedSheet = .followingAdd(.work, seat: app) } else { watchOnGitHub() }
        case .mail:
            if connected { feedSheet = .mailSubscriptionAdd } else { openAppPage(app) }
        case .page:            openAppPage(app)
        }
    }

    func openAppPage(_ app: String) {
        if let destination = BridgeRouter.destination(forOffer: app) { route.openAccount(destination) }
    }

    #if DEBUG
    /// `-sectionAdd "<Category>[|<App>]"` — log what every Feed section's +
    /// lists (`sectionAdd| <Category> | <App> — <what>, …`), then take the
    /// named row of that category's +, because a moving list eats a
    /// simulator tap (prd §1300). Once per launch.
    func sectionAddProbe() {
        guard source == "All", !Self.sectionAddProbed,
              let raw = UserDefaults.standard.string(forKey: "sectionAdd") else { return }
        Self.sectionAddProbed = true
        for category in CategoryOrder.current {
            let adds = sectionAdds(category)
            NSLog("[Casberi] sectionAdd| %@ | %@", category,
                  adds.map { $0.label + ($0.detail.map { " — " + $0 } ?? "") }.joined(separator: ", "))
        }
        let parts = raw.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let add = sectionAdds(parts[0]).first(where: { $0.label == parts[1] }) else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            NSLog("[Casberi] sectionAdd: %@ → %@", parts[0], parts[1])
            add.act()
        }
    }
    #endif
}

extension SectionPanelName where Trailing == EmptyView {
    init(name: String, glyph: String, mark: String? = nil, inset: CGFloat = DSRoomChassis.rowInset) {
        self.init(name: name, glyph: glyph, mark: mark, inset: inset) { EmptyView() }
    }
}

/// ONE SECTION, ON ONE PANEL (prd §1208d, §1222): a chapter's air, the name
/// capping the panel's top, the rows on its fill (each row's
/// `.feedRowBackground()` reads the environment), an end cap rounding the
/// foot. The Feed's categories, the Wallet's Home lists and What this app
/// reaches all stand in it. `anchor` gives the name an identity a `List`
/// knows before laying it out, so a jump can land on it off screen.
struct SectionPanelGroup<Header: View, Rows: View>: View {
    var anchor: String? = nil
    var lit = false
    @Environment(\.feedSectionPanelInset) private var panelInset
    @Environment(\.feedSectionPanelFilled) private var panelFilled
    @Environment(\.dsRoomBoxPlace) private var place
    @Environment(\.dsPaneBoxRow) private var paneRow
    @Environment(\.feedSectionLeads) private var leads
    @Environment(\.feedSectionClose) private var close
    @ViewBuilder let header: Header
    @ViewBuilder let rows: Rows

    @ViewBuilder
    var body: some View {
        // A panel stands where its rows stand (prd §1403): the list's in the
        // list column, the pane's in the pane.
        if (place == .paneBox && !paneRow) || (place == .listWithoutBox && paneRow) {
            EmptyView()
        } else {
            panel
        }
    }

    @ViewBuilder
    private var panel: some View {
        Section {
            ForEach([anchor ?? ""], id: \.self) { _ in
                // A chapter's air stands between panels, never inside one:
                // the one section gap (prd §1386), less the header's own top.
                // The section under Home's jump chips takes none (§1843).
                let under = anchor != nil && anchor == leads
                let tight = under || close
                // On Home the section under the circles takes a little air of
                // its own (prd §1857, user: "there could be a little gap
                // between the app icons and the feed too").
                if under && close {
                    Color.clear
                        .frame(height: DS.Space.s3)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .accessibilityHidden(true)
                } else if !tight {
                    Color.clear
                        .frame(height: DSRoomChassis.sectionGap - DS.Space.s4)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .accessibilityHidden(true)
                }
                header
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(SectionPanel(part: .top, lit: lit, inset: panelInset, filled: panelFilled))
            }
        }
        Group {
            rows
        }
        .environment(\.feedSectionPanel, true)
        Section {
            // A bare panel has no foot (prd §1386): its air is the gap's.
            Color.clear
                .frame(height: panelFilled ? DS.Space.s4 : 0)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(SectionPanel(part: .bottom, inset: panelInset, filled: panelFilled))
                .accessibilityHidden(true)
        }
    }
}

/// **A THING SHEET'S NAMED BLOCK IS THE FEED'S SECTION (prd §1258, bare
/// since prd §1393, user: "we still have gray cards in places like on the
/// wallet thing sheets. they need to be removed from the app everywhere
/// except on the apps page where they are folders").** A pink glyph and the
/// name in the head ink, a figure trailing when the block has one, the rows
/// in the column under it, and no fill: the air between blocks is the seam,
/// as it is between the Feed's sections (§1382). Every titled block on every
/// sheet draws through this, so no sheet keeps a grey label over a loose list.
struct SheetCard<Content: View>: View {
    let name: String
    var trailing: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ONE QUIET WORD (prd §1396, user: "super clean and tidy and
            // minimal and like apple would do"): the group's name at the
            // 17pt head rung, no glyph — the pink on a sheet means a verb —
            // and 32pt of air above it (its s2 plus the s6 every caller
            // already leaves), so the groups read apart. Its rows carry
            // their own 44pt and stand with no air between them.
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                Text(verbatim: name)
                    .dsText(.heading17)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                if let trailing {
                    Spacer(minLength: DS.Space.s2)
                    Text(verbatim: trailing)
                        .dsText(.heading17)
                        .monospacedDigit()
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, DS.Space.s2)
            .padding(.bottom, DS.Space.s1)
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.bottom, DS.Space.s2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // No fill (prd §1393): the block's name and its air say where it
        // starts, as a section's do.
    }
}

/// Wraps a view that is already a block's rows in a `SheetCard` (prd §1258),
/// for a builder whose rows end in modifiers of their own.
struct SheetCardWrap: ViewModifier {
    let name: String
    func body(content: Content) -> some View {
        SheetCard(name: name) { content }
    }
}

/// A SECTION'S CARD OUTSIDE A LIST (prd §1227): `SectionPanelGroup`'s card for
/// a screen that is a plain stack (a tray), the same fill, radius and name.
struct SectionPanelCard<Content: View>: View {
    let name: String
    let glyph: String
    /// How far in the name and rows stand from the card's edge. A card that
    /// already stands in the room's column (Sources, prd §1253) takes the
    /// difference, so its rows land where the Feed's do on the screen.
    var inset: CGFloat = DSRoomChassis.rowInset
    /// Bare on Library's pages (prd §1383), as the Feed's panels are (§1382).
    @Environment(\.feedSectionPanelFilled) private var filled
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionPanelName(name: name, glyph: glyph, inset: inset)
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                content
            }
            .padding(.horizontal, inset)
            .padding(.bottom, DS.Space.s4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(filled ? SectionPanel.fill : Color.clear,
                    in: RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
    }
}

/// One of the Feed's sections as a tile in its row (prd §1328): the
/// category's own glyph and name, in Feed order.
struct FeedSectionTile: DSTileScope {
    let name: String
    var id: String { name }
    var label: String { isReorder ? String(localized: "Reorder") : name }
    var summary: String {
        isReorder ? String(localized: "Reorder sections") : String(localized: "Go to \(name)")
    }
    var glyph: String { isReorder ? ScopeTileGlyph.reorder : CategoryFold.glyph(for: name) }
    static var keepsOrder: Bool { true }

    /// **THE FEED REORDERS FROM ITS OWN ROW (prd §1345, user: "users should
    /// be able to reorder their feed from the feed and not in settings";
    /// "re A: its discoverable").** The last tile, a verb.
    static let reorder = FeedSectionTile(name: "feedSection.reorder")
    var isReorder: Bool { name == Self.reorder.name }
}

/// The pinned header's push (prd §1386): how far the next section's name has
/// pushed it up, and its own height, which sets where the push begins. Its
/// own observable, read only by `PinnedHeaderPushed`, so a frame of push
/// redraws the header, never the Feed around it.
@MainActor @Observable final class PinnedHeaderPush {
    var offset: CGFloat = 0
    var height: CGFloat = FeedScreen.pinnedHeaderHeight
}

/// Rises with the push and reports the header's height.
struct PinnedHeaderPushed: ViewModifier {
    let push: PinnedHeaderPush

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                if abs(push.height - h) > 0.25 { push.height = h }
            }
            .offset(y: -push.offset)
    }
}

/// **A CATEGORY IN ACTIVITY IS A SMALL GREY WORD (prd §1809, user: "i think
/// activity still needs section headers but they can be small … otherwise
/// they all bleed together").** The rung and ink of the day label it
/// replaces; pressed, it opens the category's page. Nil: a label.
struct ActivityWord: View {
    let name: String
    let open: (() -> Void)?
    @Environment(\.feedSectionClose) private var close

    var body: some View {
        Group {
            if let open {
                Button(action: open) { word }
                    .buttonStyle(RowPress())
                    .accessibilityHint(Text("Opens \(name)"))
            } else {
                word
            }
        }
        .accessibilityAddTraits(.isHeader)
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
    }

    /// **A WORD THAT OPENS WEARS A CHEVRON (prd §1811).** "Money" and
    /// "Social" open a page and "Needs you" does not, and the three drew
    /// alike; the door's chevron is `DSPushRow`'s, at its size and gap.
    ///
    /// **A SECTION'S NAME, AT THE LEFT EDGE (prd §1814, user: "we can now
    /// give the section titles in feed same size we use in wallet … the feed
    /// is now cleaner"; "the list runs together"; "drop and put to left
    /// edge").** The word was a small grey label and the sections ran into
    /// one list. It is the section rung now (§1496), white, with no glyph,
    /// standing in the icons' column so it hangs left of every row's words,
    /// and a section's worth of air above it.
    private var word: some View {
        // Centred, so the chevron sits on the word's line, never under it
        // (prd §1862).
        HStack(alignment: .center, spacing: DS.Space.s1) {
            Text(verbatim: name)
                .dsText(.heading24)
                .foregroundStyle(DS.headInk)
                .lineLimit(1)
            if open != nil {
                Image(systemName: "chevron.right")
                    .dsGlyph(.tick, weight: .bold)
                    .foregroundStyle(DS.textSecondary)
                    .accessibilityHidden(true)
            }
        }
            .padding(.leading, DSRoomChassis.rowInset)
            .padding(.trailing, DS.Space.s4)
            // Under Home's chips the header keeps this air and drops only
            // the section gap above it (`SectionPanelGroup`, prd §1846).
            .padding(.top, close ? DS.Space.s4 : DS.Space.s6)
            .padding(.bottom, DS.Space.s1)
            .contentShape(Rectangle())
    }
}
