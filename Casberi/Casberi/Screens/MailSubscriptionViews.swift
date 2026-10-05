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

/// One list: its face, its name, and how often it writes and how much.
struct MailSubscriptionRow: View {
    let item: MailSubscriptions.Item

    var body: some View {
        DSFeedRow(name: item.name, line: Text(verbatim: Self.line(item))) {
            SubscriptionFace(name: item.name)
        } trailing: {
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
/// the facts, the way out, then its newest mail.
struct MailSubscriptionSheet: View {
    let id: String
    /// Opens one of its mails (the sheet closes first: one sheet at a time).
    var onOpen: (UUID) -> Void = { _ in }
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @State private var recent: [Thing] = []

    private var item: MailSubscriptions.Item? {
        MailSubscriptionsReading.shared.items.first { $0.id == id }
    }

    var body: some View {
        ScrollView {
            if let item {
                content(item)
                    .padding(DS.Space.s4)
            }
        }
        .dsInk()
        .dsReadSheet()
        .task(id: id) { loadRecent() }
    }

    /// Its three newest mails, read once the sheet is up (prd §628).
    private func loadRecent() {
        guard let ids = item.map({ Array($0.mailIDs.prefix(3)) }), !ids.isEmpty else { return }
        let d = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { ids.contains($0.id) },
                                       sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        recent = ((try? modelContext.fetch(d)) ?? []).live
    }

    @ViewBuilder
    private func content(_ item: MailSubscriptions.Item) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            HStack(spacing: DS.Space.s3) {
                SubscriptionFace(name: item.name, size: DS.Face.rowCircle)
                Text(verbatim: item.name)
                    .dsText(.heading24).foregroundStyle(DS.textPrimary)
                    .lineLimit(2)
            }
            if let rate = MailSubscriptions.rateWords(item.cadenceDays) {
                Text(verbatim: rate)
                    .dsText(.price40).foregroundStyle(DS.textPrimary)
            }
            VStack(spacing: 0) {
                if let words = MailSubscriptions.cadenceWords(item.cadenceDays) {
                    fact(String(localized: "Writes"), words)
                }
                fact(String(localized: "Last one"), item.last.formatted(date: .abbreviated, time: .shortened))
                fact(String(localized: "Since"), item.since.formatted(.dateTime.month(.wide).year()))
                fact(String(localized: "Mails"), "\(item.count)")
                if let address = item.address { fact(String(localized: "From"), address) }
                fact(String(localized: "Found in"), ListFormatter.localizedString(byJoining: item.sources))
            }
            if let url = item.unsubscribe {
                DSDoorRow(icon: "arrow.up.right", title: unsubscribeTitle(url)) { openURL(url) }
            }
            DSFootnote(Text("Casberi can't unsubscribe for you."))
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

    /// "Unsubscribe on weeklyfold.com", or in Mail for a mailto link.
    private func unsubscribeTitle(_ url: URL) -> Text {
        if url.scheme?.lowercased() == "mailto" { return Text("Unsubscribe in Mail") }
        let host = (url.host ?? "").replacingOccurrences(of: "www.", with: "")
        return host.isEmpty ? Text("Unsubscribe") : Text("Unsubscribe on \(host)")
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
            Text(verbatim: label).dsText(.body17).foregroundStyle(DS.textPrimary)
            Spacer(minLength: DS.Space.s2)
            Text(verbatim: value).dsText(.body17).foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, DS.Space.s2)
        .accessibilityElement(children: .combine)
    }
}
