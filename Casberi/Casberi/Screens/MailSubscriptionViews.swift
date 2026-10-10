import SwiftUI
import SwiftData

/// Day's Subscriptions tile, drawn (prd §1111): the box, a row, and one
/// list's sheet. The Wallet's tile lists what charges you; this one lists
/// what writes to you, in the same anatomy — the box a figure, the rows
/// `DSFeedRow`, the sheet `SubscriptionSheet`'s.

/// The box (prd §1117, was §1111's bars): the Wallet's box in mail. How
/// much mail the lists sent in thirty days where the Wallet states what they
/// cost a month, one line, then the same five-week calendar looking back,
/// each list's face on the days it wrote.
struct MailSubscriptionsFigure: View {
    let items: [MailSubscriptions.Item]

    var body: some View {
        let month = items.reduce(0) { $0 + $1.lastMonth }
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text(verbatim: Self.statement(month))
                .dsText(.heading24).monospacedDigit().foregroundStyle(DS.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(verbatim: Self.line(items))
                .foregroundStyle(DS.textTertiary)
                .dsText(.subhead12)
                .lineLimit(1)
            Spacer(minLength: DS.Space.s1)
            WalletCalendar(marks: Self.marks(items), looksBack: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    /// "16 mails a month", the Wallet's "$77.98 a month" in mail.
    static func statement(_ month: Int) -> String {
        month == 1 ? String(localized: "1 mail a month") : String(localized: "\(month) mails a month")
    }

    /// "6 subscriptions · 2 added by you · 3 stopped" — the Wallet's line,
    /// how many still write, then what else is on the list (prd §1160).
    static func line(_ items: [MailSubscriptions.Item]) -> String {
        let writing = items.filter { !$0.stopped }
        var parts = [String(localized: "\(writing.count) subscriptions")]
        let added = writing.filter(\.byYou).count
        if added > 0 { parts.append(String(localized: "\(added) added by you")) }
        let stopped = items.count - writing.count
        if stopped > 0 { parts.append(String(localized: "\(stopped) stopped")) }
        return parts.joined(separator: " · ")
    }

    /// Every arrival as a face on its day; the calendar keeps one face a day
    /// and counts the rest.
    static func marks(_ items: [MailSubscriptions.Item], now: Date = .now) -> [WalletCalendar.Mark] {
        // Only what the five weeks can show: a daily list keeps years.
        let from = WalletCalendar.window(now: now, looksBack: true).start
        return items.flatMap { item in
            item.arrivals.prefix(while: { $0 >= from }).enumerated().map { index, day in
                WalletCalendar.Mark(id: "\(item.id)#\(index)", day: day, face: item.name)
            }
        }
    }
}

/// One list: its face, its name, how often · when it last wrote · the other
/// room, and its mails in thirty days at the trailing edge — the Wallet's
/// row with mail for money (prd §1117).
struct MailSubscriptionRow: View {
    let item: MailSubscriptions.Item
    /// The service's plan in the Wallet, when §1113's identity found one.
    var paid = false

    var body: some View {
        SubscriptionRow(name: item.name, line: Text(verbatim: Self.line(item, paid: paid))) {
            Text(verbatim: Self.figure(item.lastMonth))
                .dsText(.price17).monospacedDigit()
                .foregroundStyle(item.lastMonth > 0 ? DS.textPrimary : DS.textTertiary)
        }
    }

    /// "6 mails", the trailing slot where the Wallet states a price.
    static func figure(_ count: Int) -> String {
        count == 1 ? String(localized: "1 mail") : String(localized: "\(count) mails")
    }

    /// "About weekly · Last Oct 4 · Paid in Wallet". Under three mails there
    /// is no cadence, so a sender you added says so in its place. A list
    /// that stopped stands under Stopped, so it says when it last wrote and
    /// not how often it used to (prd §1160).
    static func line(_ item: MailSubscriptions.Item, paid: Bool) -> String {
        var parts: [String] = []
        if !item.stopped {
            if let cadence = MailSubscriptions.cadenceWords(item.cadenceDays) {
                parts.append(cadence)
            } else if item.byYou {
                parts.append(String(localized: "Added by you"))
            }
        }
        parts.append(String(localized: "Last \(WalletSubscriptionRow.day(item.last))"))
        // No price outside the Wallet (§1113): the row names the room.
        if paid { parts.append(String(localized: "Paid in Wallet")) }
        return parts.joined(separator: " · ")
    }
}

/// One list's sheet: how often it writes where the Wallet's shows a price,
/// the facts, this service's other pages (`ServiceLinks`: the app's feed,
/// the plan you pay for — named, never priced, because what a thing costs is
/// the Wallet's, prd §1111), the way out, Stop tracking for a sender the
/// person added (§1115), then its newest mail. It composes
/// `SubscriptionPage`, as the Wallet's `SubscriptionSheet` does.
struct MailSubscriptionSheet: View {
    let id: String
    /// Opens one of its mails (the sheet closes first: one sheet at a time).
    var onOpen: (UUID) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Environment(ShellChrome.self) private var chrome
    @State private var recent: [Thing] = []
    @State private var confirmingRemove = false

    private var item: MailSubscriptions.Item? {
        MailSubscriptionsReading.shared.items.first { $0.id == id }
    }

    var body: some View {
        ScrollView {
            if let item {
                content(item)
            }
        }
        // Solid, and as tall as its page (no see-through sheets, prd §886).
        .subscriptionSheet()
        .task(id: id) {
            loadRecent()
            await ServiceLinks.shared.refresh(modelContext, seats: store.bridges.map(\.name))
            // And what you follow, for the door to it (prd §1118): only the
            // rooms whose follows have sites; Work's never write to you.
            FollowingReading.shared.refresh(.reading, context: modelContext)
            FollowingReading.shared.refresh(.media, context: modelContext)
        }
        // The Wallet's words for the same act (prd §1115).
        .confirmationDialog(Text("Stop tracking \(item?.name ?? "")?"), isPresented: $confirmingRemove,
                            titleVisibility: .visible) {
            Button("Stop tracking", role: .destructive) {
                if let address = item?.address { MailSubscriptionStore.shared.remove(address: address) }
                MailSubscriptionsReading.shared.refresh(modelContext)
                dismiss()
            }
        } message: {
            Text("Only what you added goes. Mail sent as a list stays.")
        }
    }

    /// Its three newest mails, read once the sheet is up (prd §628).
    private func loadRecent() {
        guard let ids = item.map({ Array($0.mailIDs.prefix(3)) }), !ids.isEmpty else { return }
        let d = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { ids.contains($0.id) },
                                       sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        recent = ((try? modelContext.fetch(d)) ?? []).live
    }

    private func content(_ item: MailSubscriptions.Item) -> some View {
        SubscriptionPage(name: item.name,
                         statement: item.stopped
                             ? SubscriptionStatement(figure: String(localized: "Stopped"))
                             : MailSubscriptions.rate(item.cadenceDays)
                                 .map { SubscriptionStatement(figure: "\($0.count)", word: $0.word) },
                         facts: facts(item),
                         doors: doors(item)) {
            if !recent.live.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Recent")
                        .dsText(.heading20).foregroundStyle(DS.textPrimary)
                        .padding(.bottom, DS.Space.s1)
                    ForEach(recent.keyed) { row in
                        if let thing = row.live { recentRow(thing, face: item.name) }
                    }
                }
            }
        }
    }

    /// When · since · so far · who · found in — the order the Wallet's sheet
    /// keeps.
    private func facts(_ item: MailSubscriptions.Item) -> [SubscriptionFact] {
        var out: [SubscriptionFact] = []
        out.append(.init(String(localized: "Last one"), item.last.formatted(date: .abbreviated, time: .shortened)))
        out.append(.init(String(localized: "Since"), item.since.formatted(.dateTime.month(.wide).year())))
        out.append(.init(String(localized: "Mails"), "\(item.count)"))
        if let address = item.address { out.append(.init(String(localized: "From"), address)) }
        out.append(.init(String(localized: "Found in"), ListFormatter.localizedString(byJoining: item.sources)))
        return out
    }

    /// This service's other pages, then the way out. Each is drawn only
    /// while its destination exists (prd §83).
    private func doors(_ item: MailSubscriptions.Item) -> [SubscriptionDoor] {
        var out: [SubscriptionDoor] = []
        let link = ServiceLinks.shared.byList[item.id]
        if let (followed, room) = FollowingReading.shared.followed(listID: item.id) {
            out.append(.init(id: "followed", icon: ScopeTileGlyph.subscriptions,
                             title: Text(Following.doorWords(room))) {
                dismiss()
                chrome.open(.followed(followed.id, room))
            })
        }
        if let app = link?.app {
            out.append(.init(id: "app", icon: SubscriptionWords.appGlyph, title: Text("Open \(app)")) {
                dismiss()
                chrome.openApp(app)
            })
        }
        if let planID = link?.planID,
           SubscriptionsReading.shared.items.contains(where: { $0.id == planID }) {
            out.append(.init(id: "plan", icon: SubscriptionWords.planGlyph, title: Text("Subscription in Wallet")) {
                dismiss()
                chrome.open(.plan(planID))
            })
        }
        if let url = item.unsubscribe {
            out.append(.init(id: "unsubscribe", icon: SubscriptionWords.wayOutGlyph,
                             title: unsubscribeTitle(url)) { openURL(url) })
        }
        // A sender the person added from a mail's sheet (prd §1115) goes the
        // way a hand-added plan does.
        if item.byYou, item.address != nil {
            out.append(.init(id: "stop", icon: "trash", title: Text("Stop tracking"), role: .destructive) {
                confirmingRemove = true
            })
        }
        return out
    }

    private func recentRow(_ thing: Thing, face: String) -> some View {
        Button { onOpen(thing.id) } label: {
            DSFeedRow(name: thing.title,
                      line: Text(verbatim: thing.capturedAt.formatted(date: .abbreviated, time: .omitted))) {
                SubscriptionFace(name: face)
            } trailing: { EmptyView() }
                .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
    }

    /// "Unsubscribe on weeklyfold.com", or in Mail for a mailto link — the
    /// Wallet's "Manage on <site>", for a list.
    private func unsubscribeTitle(_ url: URL) -> Text {
        if url.scheme?.lowercased() == "mailto" { return Text("Unsubscribe in Mail") }
        let host = SubscriptionWords.host(url.host ?? "")
        return host.isEmpty ? Text("Unsubscribe") : Text("Unsubscribe on \(host)")
    }
}

/// TRACK A SUBSCRIPTION, from Day (prd §1117): the Wallet's tray in mail. A
/// sender is never typed: the list is everyone whose mail this month carried
/// no list header (`MailSubscriptions.candidates`), the most mail first, and
/// a tap tracks one. Every mail from that address then files, the older
/// ones too (§1115), and the tray closes on Day's tile with the row in it.
/// Search mail reads every header-less sender kept, not only this month
/// (§1134), so a sender from March is found by typing.
struct MailSubscriptionAddTray: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ShellChrome.self) private var chrome
    @State private var query = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        let searching = !query.trimmingCharacters(in: .whitespaces).isEmpty
        let reading = MailSubscriptionsReading.shared
        let candidates = searching ? Self.matching(reading.senders, query: query) : reading.candidates
        // The find tray's shape (`DSTraySearchField`): the rows, and the
        // field at the bottom on glass.
        DSTray(title: SubscriptionWords.track, height: 640, detents: [.large]) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if candidates.isEmpty {
                        DSEmptyState(headline: searching ? DSProse.text("No mail matches")
                                                         : DSProse.text("No one else wrote this month"),
                                     words: searching ? Text("Try a name or an address")
                                                      : Text("Search mail for anyone who wrote before"),
                                     scale: .list(rows: 3))
                            .padding(.horizontal, DS.Space.s4)
                    } else {
                        DSTrayHead(searching ? String(localized: "From your mail")
                                             : String(localized: "Writes to you most"))
                        ForEach(candidates) { candidate in
                            Button { track(candidate) } label: {
                                SubscriptionRow(name: candidate.name,
                                                line: Text(verbatim: Self.line(candidate, searching: searching))) {
                                    Image(systemName: "plus")
                                        .dsGlyph(.body)
                                        .foregroundStyle(DS.tint)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(RowPress())
                            .dsHover()
                            .padding(.horizontal, DS.Space.s4)
                            .accessibilityLabel(Text("Track \(candidate.name)"))
                        }
                    }
                }
                .padding(.bottom, 96)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                DSTraySearchField(placeholder: String(localized: "Search mail"),
                                  text: $query, focus: $fieldFocused) { EmptyView() }
            }
        }
        .task { MailSubscriptionsReading.shared.refresh(modelContext) }
    }

    /// "mia@example.com · 4 mails in 30 days"; searched, every mail kept and
    /// the newest one's day, "mia@example.com · 12 mails · Last Mar 4".
    static func line(_ candidate: MailSubscriptions.Candidate, searching: Bool = false) -> String {
        guard searching else {
            let count = candidate.count == 1
                ? String(localized: "1 mail in 30 days")
                : String(localized: "\(candidate.count) mails in 30 days")
            return [candidate.address, count].joined(separator: " · ")
        }
        let count = candidate.count == 1
            ? String(localized: "1 mail")
            : String(localized: "\(candidate.count) mails")
        let last = String(localized: "Last \(WalletSubscriptionRow.day(candidate.last))")
        return [candidate.address, count, last].joined(separator: " · ")
    }

    /// A name or an address that holds what was typed.
    static func matching(_ all: [MailSubscriptions.Candidate], query: String) -> [MailSubscriptions.Candidate] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.address.localizedCaseInsensitiveContains(q) }
    }

    /// The one write, `-mailSubscriptionAdd`'s and the mail sheet's: the
    /// sender's address joins the store, and the toast says it.
    private func track(_ candidate: MailSubscriptions.Candidate) {
        guard MailSubscriptionStore.shared.add(address: candidate.address, name: candidate.name) != nil else { return }
        DSHaptic.selection()
        chrome.flash(String(localized: "Tracking \(candidate.name)"))
        dismiss()
    }
}
