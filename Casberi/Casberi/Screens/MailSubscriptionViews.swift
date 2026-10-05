import SwiftUI
import SwiftData

/// Day's Subscriptions tile, drawn (prd §1111): the box, a row, and one
/// list's sheet. The Wallet's tile lists what charges you; this one lists
/// what writes to you, in the same anatomy — the box a figure, the rows
/// `DSFeedRow`, the sheet `SubscriptionSheet`'s.

/// The box: how many lists, how much mail they sent this month, and the
/// loudest four as bars, each its share of the loudest.
struct MailSubscriptionsFigure: View {
    let items: [MailSubscriptions.Item]
    /// The bars grow in once, on the room's arrival; under Reduce Motion they
    /// are simply there.
    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let month = items.reduce(0) { $0 + $1.lastMonth }
        let top = Array(items.prefix(4))
        let peak = max(1, top.map(\.lastMonth).max() ?? 1)
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text("\(items.count) subscriptions")
                .dsText(.heading24).foregroundStyle(DS.textPrimary)
                .lineLimit(1)
            Text("\(month) mails in \(Int(MailSubscriptions.windowDays)) days")
                .dsText(.subhead12).foregroundStyle(DS.textTertiary)
                .lineLimit(1)
            Spacer(minLength: DS.Space.s2)
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                ForEach(top) { item in
                    HStack(spacing: DS.Space.s2) {
                        SubscriptionFace(name: item.name, size: DS.Face.row)
                        // The name beside its face: a letter alone names nobody.
                        Text(verbatim: item.name)
                            .dsText(.subhead12).foregroundStyle(DS.textSecondary)
                            .lineLimit(1)
                            .frame(width: 96, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(DS.fillFaint)
                                Capsule().fill(DS.fillStrong)
                                    .frame(width: grown
                                           ? max(6, geo.size.width * CGFloat(item.lastMonth) / CGFloat(peak))
                                           : 6)
                            }
                        }
                        .frame(height: 8)
                        Text(verbatim: "\(item.lastMonth)")
                            .dsText(.subhead12).monospacedDigit()
                            .foregroundStyle(DS.textSecondary)
                            .frame(minWidth: 24, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("\(item.name), \(item.lastMonth) mails"))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            guard !grown else { return }
            if reduceMotion { grown = true } else { withAnimation(DS.Motion.standard) { grown = true } }
        }
    }
}

/// One list: its face, its name, and how often it writes and how much —
/// `SubscriptionRow`, the Wallet's row, with no figure at its trailing edge.
struct MailSubscriptionRow: View {
    let item: MailSubscriptions.Item

    var body: some View {
        SubscriptionRow(name: item.name, line: Text(verbatim: Self.line(item))) {
            EmptyView()
        }
    }

    /// "About weekly · 12 mails" — the cadence once there is one.
    static func line(_ item: MailSubscriptions.Item) -> String {
        [MailSubscriptions.cadenceWords(item.cadenceDays),
         String(localized: "\(item.count) mails")]
            .compactMap(\.self).joined(separator: " · ")
    }
}

/// One list's sheet: how often it writes where the Wallet's shows a price,
/// the facts, this service's other pages (`ServiceLinks`: the app's feed,
/// the plan you pay for — named, never priced, because what a thing costs is
/// the Wallet's, prd §1111), the way out, then its newest mail. It composes
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
                         statement: MailSubscriptions.rate(item.cadenceDays)
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
