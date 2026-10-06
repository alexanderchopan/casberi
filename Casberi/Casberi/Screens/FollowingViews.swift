import SwiftUI
import SwiftData

/// What you follow, drawn (prd §1118): the box, a row and one thing's sheet,
/// in the Subscriptions anatomy (§1117) so a feed in Reading, a channel in
/// Media and a repo in Work read like a plan in the Wallet and a list in Day.

extension Following.Room {
    /// The tile's name: what is listed. Work watches; the rest subscribe.
    var tileWord: String {
        self == .work ? String(localized: "Following") : String(localized: "Subscriptions")
    }

    /// The first row's words, and its tray's title (prd §1120): what the
    /// act really is. A feed is followed — nothing exists until you add it,
    /// so there is nothing to "track", and "subscribe" reads as signing up
    /// with the publisher or paying. Work watches.
    var verb: String {
        switch self {
        // One verb in both rooms (user, 2026-10-05: "follow a feed … we can
        // use it in both places"): a channel and a show are feeds too.
        case .reading, .media: String(localized: "Follow a feed")
        case .work:    String(localized: "Follow something")
        }
    }

    /// The verb's undo, in every room (prd §1121); §1117's Track keeps
    /// Stop tracking.
    var stopWord: String {
        String(localized: "Stop following")
    }

    /// "16 posts a month" — the box's statement.
    func statement(_ month: Int) -> String {
        switch self {
        case .reading: month == 1 ? String(localized: "1 post a month") : String(localized: "\(month) posts a month")
        case .media:   String(localized: "\(month) new a month")
        case .work:    month == 1 ? String(localized: "1 update a month") : String(localized: "\(month) updates a month")
        }
    }

    /// "8 posts" — a row's figure, thirty days.
    func figure(_ count: Int) -> String {
        switch self {
        case .reading: count == 1 ? String(localized: "1 post") : String(localized: "\(count) posts")
        case .media:   String(localized: "\(count) new")
        case .work:    count == 1 ? String(localized: "1 update") : String(localized: "\(count) updates")
        }
    }

    /// "12 subscriptions" / "7 watching" — the box's line.
    func count(_ n: Int) -> String {
        self == .work ? String(localized: "\(n) following") : String(localized: "\(n) subscriptions")
    }

    /// The empty box's words.
    var emptyWords: String {
        switch self {
        case .reading: String(localized: "Sites you follow, and how often they post")
        case .media:   String(localized: "Channels, shows and boards you follow")
        case .work:    String(localized: "Repos, packages and models you follow")
        }
    }
}

/// The box: what arrived in thirty days, how many you follow, then the
/// five-week calendar looking back, each one's face on the days it posted —
/// Day's box (§1117) with posts for mail.
struct FollowingFigure: View {
    let room: Following.Room
    let items: [Following.Item]

    var body: some View {
        let month = items.reduce(0) { $0 + $1.lastMonth }
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text(verbatim: room.statement(month))
                .dsText(.heading24).monospacedDigit().foregroundStyle(DS.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(verbatim: Self.line(room, items))
                .foregroundStyle(DS.textTertiary)
                .dsText(.subhead12)
                .lineLimit(1)
            Spacer(minLength: DS.Space.s1)
            WalletCalendar(marks: Self.marks(items), looksBack: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    /// "12 subscriptions · 3 also by mail".
    static func line(_ room: Following.Room, _ items: [Following.Item]) -> String {
        var parts = [room.count(items.count)]
        let mailed = items.filter { FollowingReading.shared.links[$0.id]?.listID != nil }.count
        if mailed > 0 { parts.append(String(localized: "\(mailed) also by mail")) }
        return parts.joined(separator: " · ")
    }

    static func marks(_ items: [Following.Item], now: Date = .now) -> [WalletCalendar.Mark] {
        let from = WalletCalendar.window(now: now, looksBack: true).start
        return items.flatMap { item in
            item.arrivals.prefix(while: { $0 >= from }).enumerated().map { index, day in
                WalletCalendar.Mark(id: "\(item.id)#\(index)", day: day, face: item.name)
            }
        }
    }
}

/// One thing followed: its face, its name, how often · when it last posted ·
/// where it comes from, and its thirty days at the trailing edge.
struct FollowingRow: View {
    let room: Following.Room
    let item: Following.Item

    var body: some View {
        SubscriptionRow(name: item.name, line: Text(verbatim: Self.line(room, item)), face: item.avatar) {
            Text(verbatim: room.figure(item.lastMonth))
                .dsText(.price17).monospacedDigit()
                .foregroundStyle(item.lastMonth > 0 ? DS.textPrimary : DS.textTertiary)
        }
    }

    /// "About weekly · Last Oct 4 · also by mail". A room that reads from
    /// several apps names the app; a follow nothing landed for says so.
    static func line(_ room: Following.Room, _ item: Following.Item) -> String {
        var parts: [String] = []
        if room != .reading || item.seat != "RSS" { parts.append(item.seat) }
        if let cadence = MailSubscriptions.cadenceWords(item.cadenceDays) { parts.append(cadence) }
        if let last = item.last {
            parts.append(String(localized: "Last \(WalletSubscriptionRow.day(last))"))
        } else {
            parts.append(String(localized: "Nothing yet"))
        }
        let link = FollowingReading.shared.links[item.id]
        if link?.listID != nil { parts.append(String(localized: "also by mail")) }
        if link?.planID != nil { parts.append(String(localized: "Paid in Wallet")) }
        return parts.joined(separator: " · ")
    }
}

/// One thing's sheet: how often it posts, the facts, the service's other
/// pages (its mailing list in Day, its plan in the Wallet — named, never
/// priced, §1113), its site, then Stop tracking for a follow kept here.
struct FollowingSheet: View {
    let id: String
    let room: Following.Room
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Environment(ShellChrome.self) private var chrome
    @State private var confirmingStop = false

    private var item: Following.Item? { FollowingReading.shared.item(id) }

    var body: some View {
        ScrollView {
            if let item { content(item) }
        }
        .subscriptionSheet()
        .task(id: id) {
            await ServiceLinks.shared.refresh(modelContext, seats: store.bridges.map(\.name))
            FollowingReading.shared.refresh(room, context: modelContext)
        }
        .confirmationDialog(Text(verbatim: "\(room.stopWord) \(item?.name ?? "")?"), isPresented: $confirmingStop,
                            titleVisibility: .visible) {
            Button(room.stopWord, role: .destructive) {
                if let item { FollowingReading.shared.stop(item, context: modelContext) }
                dismiss()
            }
        } message: {
            if let item, FollowingReading.prunes(item.seat) { Text("What it brought in goes with it.") }
        }
    }

    private func content(_ item: Following.Item) -> some View {
        SubscriptionPage(name: item.name, face: item.avatar, statement: statement(item),
                         facts: facts(item), doors: doors(item))
    }

    private func statement(_ item: Following.Item) -> SubscriptionStatement? {
        if let cadence = MailSubscriptions.cadenceWords(item.cadenceDays) {
            return SubscriptionStatement(figure: cadence)
        }
        return SubscriptionStatement(figure: room.figure(item.lastMonth), word: String(localized: "this month"))
    }

    private func facts(_ item: Following.Item) -> [SubscriptionFact] {
        var out: [SubscriptionFact] = []
        if let last = item.last {
            out.append(.init(String(localized: "Last one"), last.formatted(.dateTime.month(.wide).day())))
        }
        if let since = item.since {
            out.append(.init(String(localized: "Since"), since.formatted(.dateTime.month(.wide).year())))
        }
        out.append(.init(String(localized: "This month"), room.figure(item.lastMonth)))
        out.append(.init(String(localized: "Through"), item.seat))
        if let site = item.site { out.append(.init(String(localized: "From"), SubscriptionWords.host(site))) }
        return out
    }

    private func doors(_ item: Following.Item) -> [SubscriptionDoor] {
        var out: [SubscriptionDoor] = []
        let link = FollowingReading.shared.links[item.id]
        if let listID = link?.listID,
           let list = MailSubscriptionsReading.shared.items.first(where: { $0.id == listID }) {
            out.append(.init(id: "list", icon: SubscriptionWords.listGlyph,
                             title: Text(verbatim: MailSubscriptions.writesWords(list.cadenceDays))) {
                dismiss()
                chrome.open(.list(listID))
            })
        }
        if let planID = link?.planID, SubscriptionsReading.shared.items.contains(where: { $0.id == planID }) {
            out.append(.init(id: "plan", icon: SubscriptionWords.planGlyph, title: Text("Subscription in Wallet")) {
                dismiss()
                chrome.open(.plan(planID))
            })
        }
        if let site = item.site, let url = URL(string: "https://\(site)") {
            out.append(.init(id: "site", icon: SubscriptionWords.wayOutGlyph,
                             title: Text("Open \(SubscriptionWords.host(site))")) { openURL(url) })
        }
        if item.site == nil, let page = item.page, let url = URL(string: page) {
            out.append(.init(id: "page", icon: SubscriptionWords.wayOutGlyph,
                             title: Text("Open on \(SubscriptionWords.host(page))")) { openURL(url) })
        }
        if item.removable {
            out.append(.init(id: "stop", icon: "trash", title: Text(verbatim: room.stopWord), role: .destructive) {
                confirmingStop = true
            })
        }
        return out
    }
}

extension Following {
    /// The door from a plan or a list to the same service where it is
    /// followed: "Posts in Reading", "Uploads in Media", "Updates in Work".
    static func doorWords(_ room: Room) -> LocalizedStringKey {
        switch room {
        case .reading: "Posts in Reading"
        case .media:   "New in Media"
        case .work:    "Updates in Work"
        }
    }
}

/// **WHERE THE LIST WENT (prd §1118, §1119).** On a follow app's settings
/// page, once something is followed: one door to the room that lists it,
/// in place of the roster and its field. The page keeps what only it can
/// do — import, export, disconnect.
struct FollowListDoor: View {
    let room: Following.Room
    let count: Int
    @Environment(ShellChrome.self) private var chrome
    @Environment(HomeRoute.self) private var route

    var body: some View {
        DSDoorRow(icon: room == .work ? ScopeTileGlyph.watch : ScopeTileGlyph.subscriptions,
                  title: Text(verbatim: Self.words(room, count))) {
            route.closeConnectForm()
            route.path = []
            chrome.landOnFollowing(room)
        }
    }

    static func words(_ room: Following.Room, _ count: Int) -> String {
        switch room {
        case .reading: String(localized: "\(count) subscriptions in Reading")
        case .media:   String(localized: "\(count) subscriptions in Media")
        case .work:    String(localized: "\(count) following in Work")
        }
    }
}
