import SwiftUI
import SwiftData

/// GENERATIVE SEARCH, v1 (prd §1209): a page made from what you typed — a
/// person, an app, a category, a stretch of time or words — in every room's
/// frame: the title, the box, the tiles, the list. Composed by rules over
/// what you keep, no model: the box is the next dated thing, else the
/// newest; the tiles are the categories actually present; the facts under
/// the box are counted, never written. Names among the results are chips
/// that make their own page (a pivot); the way back is the first chip.
struct PivotPage: View {
    let start: PivotQuery

    @Environment(\.modelContext) private var context
    @State private var trail: [PivotQuery] = []
    @State private var things: [Thing] = []
    @State private var composed = false
    @State private var tile = PivotTile(name: nil)
    @State private var shown = Self.firstRows
    @State private var opened: Thing?
    @State private var related: [Related] = []

    static let firstRows = 20
    static let moreRows = 30

    private var query: PivotQuery { trail.last ?? start }

    var body: some View {
        let rows = filtered
        List {
            DSRoomTitleRow(title: query.title, pick: query.pick)
                .dsRoomTitleListRow()
            Section { box(rows) }
            if tiles.count > 1 {
                Section {
                    DSScopeTiles(sections: tiles, active: tile) { picked in
                        withAnimation(DS.Motion.standard) {
                            tile = picked
                            shown = Self.firstRows
                        }
                    }
                    .dsRoomTilesListRow()
                }
            }
            if !related.isEmpty || trail.count > 1 {
                Section { relatedRow }
            }
            Section {
                // Keyed by value and read live (`ThingRowKeying`): a heal can
                // delete a row while this page holds it.
                ForEach(Array(rows.prefix(shown)).keyed) { item in
                    if let thing = item.live { row(thing) }
                }
                if rows.count > shown {
                    Button {
                        DSHaptic.tap()
                        withAnimation(DS.Motion.standard) { shown += Self.moreRows }
                    } label: {
                        DSPushRowLabel(title: Text("More"), fact: Text("\(rows.count - shown) more"),
                                       tint: DS.tint, opens: false) {
                            DSGlyphLead(glyph: "arrow.down", tint: DS.tint)
                        }
                        .padding(.vertical, DS.Space.s2)
                        .frame(minHeight: DS.Hit.min)
                    }
                    .buttonStyle(RowPress())
                    .pivotRowInsets()
                }
            }
        }
        .dsRoomList()
        .dsPageBackground()
        .task(id: query.id) { compose() }
        .sheet(item: $opened) { thing in
            ThingSheetView(thing: thing)
        }
    }

    // MARK: - The box

    @ViewBuilder
    private func box(_ rows: [Thing]) -> some View {
        let now = Date.now
        let next = rows.filter { ($0.dueAt ?? .distantPast) >= now }
            .min { ($0.dueAt ?? now) < ($1.dueAt ?? now) }
        if let lead = next ?? rows.first {
            Button { opened = lead } label: {
                FeedLedeCard(thing: lead, note: facts(rows, next: next))
                    .contentShape(Rectangle())
            }
            .buttonStyle(RowPress())
            .dsRoomLeadListRow()
        } else {
            DSEmptyState(headline: composed ? Text("Nothing yet") : Text(verbatim: query.title),
                         words: composed ? Text("Nothing you keep matches this.") : Text(verbatim: " "),
                         scale: .list(rows: 3))
                .frame(maxWidth: .infinity,
                       minHeight: DSRoomChassis.leadBox, maxHeight: DSRoomChassis.leadBox)
                .dsRoomHeadBlock()
                .dsRoomLeadListRow()
        }
    }

    /// The counted facts under the box (prd §1209 item 3): how many and from
    /// how many apps, the newest, the next, and money moved — arithmetic, so
    /// nothing in it can be wrong in a way a sentence could.
    private func facts(_ rows: [Thing], next: Thing?) -> String {
        var parts: [String] = []
        let apps = Set(rows.map(\.source)).count
        parts.append(apps > 1 ? String(localized: "\(rows.count) things from \(apps) apps")
                              : String(localized: "\(rows.count) things"))
        if let newest = rows.first {
            parts.append(String(localized: "Newest \(PivotWords.relative(newest.capturedAt))"))
        }
        if let next, let due = next.dueAt {
            parts.append(String(localized: "Next \(PivotWords.relative(due))"))
        }
        let moved = rows.compactMap(\.transferUSD).reduce(0) { $0 + abs($1) }
        if moved >= 1 {
            parts.append(BalancePrivacy.shared.value(WalletValue.money(moved)) + " " + String(localized: "moved"))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Tiles

    /// All, then each category the results hold.
    private var tiles: [PivotTile] {
        let present = Set(things.live.compactMap { PivotTile.category(of: $0) })
        let ordered = CategoryOrder.current.filter { present.contains($0) }
        return [PivotTile(name: nil)] + ordered.map { PivotTile(name: $0) }
    }

    private var filtered: [Thing] {
        let live = things.live
        guard let name = tile.name else { return live }
        return live.filter { PivotTile.category(of: $0) == name }
    }

    // MARK: - Rows

    private func row(_ thing: Thing) -> some View {
        let when: Date = thing.dueAt ?? thing.capturedAt
        let app: String = BridgeCatalog.seatName(forSource: thing.source)
        let line = Text(verbatim: app + " · " + when.formatted(.dateTime.month(.abbreviated).day()))
        let source = thing.source
        return Button { opened = thing } label: {
            DSFeedRow(name: thing.title, line: line) {
                BridgeIcon(name: source, size: DS.Mark.row)
            } trailing: { EmptyView() }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .pivotRowInsets()
    }

    // MARK: - Pivots

    /// A name among the results that has a page of its own.
    struct Related: Identifiable, Hashable {
        let query: PivotQuery
        let label: String
        let glyph: String?
        var id: String { query.id }
    }

    private var relatedRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.s2) {
                if trail.count > 1 {
                    let back = trail[trail.count - 2]
                    chip(String(localized: "Back to \(back.title)"), glyph: "chevron.left") {
                        trail.removeLast()
                    }
                }
                ForEach(related) { r in
                    chip(r.label, glyph: r.glyph) {
                        if trail.isEmpty { trail = [start] }
                        trail.append(r.query)
                    }
                }
            }
            .padding(.horizontal, DSRoomChassis.inset)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: DS.Space.s4, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func chip(_ text: String, glyph: String?, act: @escaping () -> Void) -> some View {
        Button {
            DSHaptic.selection()
            withAnimation(DS.Motion.standard) {
                act()
                tile = PivotTile(name: nil)
                shown = Self.firstRows
            }
        } label: {
            Chip(text: text, glyph: glyph)
        }
        .buttonStyle(PressSpring())
    }

    // MARK: - Composing

    private func compose() {
        let q = query
        things = PivotCompose.things(for: q, context: context)
        related = PivotCompose.related(things.live, excluding: q)
        composed = true
    }
}

/// A category as a tile on a composed page; nil is All.
struct PivotTile: DSTileScope {
    let name: String?
    var id: String { name ?? "all" }
    var label: String { name ?? String(localized: "All") }
    var summary: String { name ?? String(localized: "Everything found") }
    var glyph: String { CategoryFold.glyph(for: name ?? "All") }

    /// The tile a thing stands under: its category, Reading's under Media.
    static func category(of thing: Thing) -> String? {
        guard let c = BridgeCatalog.category(forSource: thing.source) else { return nil }
        return c == RoomAccounts.readingRoom ? RoomAccounts.mediaRoom : c
    }
}

/// What a page is made of, read from the store on the main actor.
@MainActor
enum PivotCompose {
    /// The newest things read for the matches no predicate can make (a
    /// sender's domain, a category, a handle): light columns, bounded.
    static let window = 2_000
    static let cap = 400

    static func things(for q: PivotQuery, context: ModelContext) -> [Thing] {
        var found: [UUID: Thing] = [:]
        func add(_ list: [Thing]) { for t in list where t.isLive { found[t.id] = t } }
        lazy var recent: [Thing] = {
            var d = FetchDescriptor<Thing>(sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
            d.fetchLimit = window
            // Every column the matches and the facts read, so none faults a
            // row in one at a time on the main actor.
            d.propertiesToFetch = FeedScreen.lightColumns
                + [\Thing.authorEmail, \Thing.authorHandle, \Thing.transferUSD, \Thing.dueAt,
                   \Thing.sourceRef, \Thing.walletAddress, \Thing.counterpartyAddress]
            return (try? context.fetch(d)) ?? []
        }()
        // A span narrows the fetch itself, so a busy app's month is not lost
        // behind its newest rows.
        let start = q.span?.start ?? .distantPast, end = q.span?.end ?? .distantFuture
        switch q.subject {
        case .person(let id, let name):
            if let contact = ContactIndexSources.contacts.first(where: { $0.id == id }) {
                let ids = ContactSheet.things(for: contact, context: context, limit: cap).map(\.id)
                if !ids.isEmpty {
                    var d = FetchDescriptor<Thing>(predicate: #Predicate { ids.contains($0.id) })
                    d.fetchLimit = cap
                    add((try? context.fetch(d)) ?? [])
                }
            }
            // Named as a sender or in a title too — "Uma Patel <uma@…>",
            // "Design review with Uma" — on word boundaries, so "Uma" never
            // finds "Pumas".
            let folded = name.lowercased()
            if folded.count >= 3 {
                add(recent.filter { thing in
                    PivotWords.wordRange(of: folded, in: thing.title.lowercased()) != nil
                        || PivotWords.wordRange(of: folded, in: (thing.authorHandle ?? "").lowercased()) != nil
                })
            }
        case .app(let name):
            var d = FetchDescriptor<Thing>(predicate: #Predicate {
                $0.source == name && $0.capturedAt >= start && $0.capturedAt < end
            }, sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
            d.fetchLimit = cap
            add((try? context.fetch(d)) ?? [])
            // Its seat under another source name, its mail, its charges — by
            // whole words, and never for a name too short to be one ("X").
            let word = name.lowercased().replacingOccurrences(of: " ", with: "")
            let spoken = name.lowercased()
            add(recent.filter { thing in
                BridgeCatalog.seatName(forSource: thing.source) == name
                    || (word.count >= 3 && PivotWords.wordRange(of: word, in: (thing.authorEmail ?? "").lowercased()) != nil)
                    || (spoken.count >= 3 && PivotWords.wordRange(of: spoken, in: thing.title.lowercased()) != nil)
            })
        case .category(let name):
            add(recent.filter { PivotTile.category(of: $0) == name })
        case .words(let words):
            var d = FetchDescriptor<Thing>(predicate: #Predicate {
                $0.title.localizedStandardContains(words) && $0.capturedAt >= start && $0.capturedAt < end
            }, sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
            d.fetchLimit = cap
            add((try? context.fetch(d)) ?? [])
            let folded = words.lowercased()
            add(recent.filter { thing in
                PivotWords.wordRange(of: folded, in: (thing.authorHandle ?? "").lowercased()) != nil
                    || PivotWords.wordRange(of: folded, in: (thing.authorEmail ?? "").lowercased()) != nil
            })
        case .span:
            guard let span = q.span else { break }
            let start = span.start, end = span.end
            var d = FetchDescriptor<Thing>(predicate: #Predicate { $0.capturedAt >= start && $0.capturedAt < end },
                                           sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
            d.fetchLimit = cap
            add((try? context.fetch(d)) ?? [])
            add(recent.filter { thing in thing.dueAt.map { span.contains($0) } ?? false })
        }
        return found.values
            .filter { $0.isLive && PivotWords.inSpan(q.span, captured: $0.capturedAt, due: $0.dueAt) }
            .sorted { $0.capturedAt > $1.capturedAt }
            .prefix(cap)
            .map { $0 }
    }

    /// The people and apps among the results that have a page of their own,
    /// the most frequent first, the page's own subject left out.
    static func related(_ things: [Thing], excluding q: PivotQuery) -> [Related] {
        var apps: [String: Int] = [:]
        for t in things { apps[BridgeCatalog.seatName(forSource: t.source), default: 0] += 1 }
        var people: [String: (Contact, Int)] = [:]
        let byKey = Dictionary(ContactIndexSources.contacts
            .filter { !$0.isUnnamed && !ContactIndexSources.isYours($0) }
            .flatMap { c in c.identities.map { ($0.key, c) } },
                               uniquingKeysWith: { a, _ in a })
        for t in things {
            let keys = ContactIndex.keys(source: t.source, kind: t.kind.rawValue, sourceRef: t.sourceRef,
                                         authorHandle: t.authorHandle, walletAddress: t.walletAddress,
                                         counterpartyAddress: t.counterpartyAddress,
                                         authorEmail: t.authorEmail, isNotification: false)
            if let c = keys.lazy.compactMap({ byKey[$0] }).first {
                people[c.id] = (c, (people[c.id]?.1 ?? 0) + 1)
            }
        }
        var out: [Related] = []
        for (c, _) in people.values.sorted(by: { $0.1 > $1.1 }).prefix(4) {
            let r = PivotQuery(subject: .person(id: c.id, name: c.name), span: q.span, spanLabel: q.spanLabel)
            if r.id != q.id { out.append(Related(query: r, label: c.name, glyph: "person")) }
        }
        for (app, _) in apps.sorted(by: { $0.value > $1.value }).prefix(4) {
            let r = PivotQuery(subject: .app(app), span: q.span, spanLabel: q.spanLabel)
            if r.id != q.id { out.append(Related(query: r, label: app, glyph: nil)) }
        }
        return out
    }

    typealias Related = PivotPage.Related

    /// What the words could make a page of, best first (prd §1209 item 1):
    /// a person, an app you have, a category, then the words themselves —
    /// each narrowed by a time phrase when one was said.
    static func resolve(_ words: String, apps: [String], categories: [String]) -> [PivotQuery] {
        let time = PivotWords.timeSpan(in: words)
        let rest = (time?.rest ?? words).trimmingCharacters(in: .whitespaces)
        func q(_ s: PivotQuery.Subject) -> PivotQuery {
            PivotQuery(subject: s, span: time?.span, spanLabel: time?.label)
        }
        var out: [PivotQuery] = []
        // A name that is also a month ("April", "June") is still a person or
        // an app: offered first, with no span.
        if time != nil {
            let whole = words.trimmingCharacters(in: .whitespaces)
            for c in ContactIndexSources.contacts
                where !c.isUnnamed && !ContactIndexSources.isYours(c)
                    && (TraySearch.match(c.name, whole, anyWord: true).map { $0 <= .prefix } ?? false) {
                out.append(PivotQuery(subject: .person(id: c.id, name: c.name)))
                if out.count == 2 { break }
            }
            for app in apps where TraySearch.match(app, whole) == .exact {
                out.append(PivotQuery(subject: .app(app)))
            }
        }
        if rest.isEmpty { return Array((out + (time == nil ? [] : [q(.span)])).prefix(4)) }
        if let cat = categories.first(where: { $0.caseInsensitiveCompare(rest) == .orderedSame }) {
            out.append(q(.category(cat)))
        }
        let people = ContactIndexSources.contacts
            .filter { !$0.isUnnamed && !ContactIndexSources.isYours($0) }
            .compactMap { c -> (Contact, TraySearch.Match)? in
                guard let m = TraySearch.match(c.name, rest, anyWord: true), m <= .word else { return nil }
                return (c, m)
            }
            .sorted { $0.1 < $1.1 }
        for (c, _) in people.prefix(2) { out.append(q(.person(id: c.id, name: c.name))) }
        let named = apps.compactMap { app -> (String, TraySearch.Match)? in
            guard let m = TraySearch.match(app, rest), m <= .prefix else { return nil }
            return (app, m)
        }.sorted { $0.1 < $1.1 }
        for (app, _) in named.prefix(2) { out.append(q(.app(app))) }
        if rest.count >= 3 { out.append(q(.words(rest))) }
        return Array(out.prefix(4))
    }
}

extension PivotQuery {
    /// The tray's offer for this page, its span after a dot.
    var offer: String {
        guard let spanLabel, subject != .span else { return offerTitle }
        return offerTitle + " · " + spanLabel
    }

    /// The offer's own words, the span left to the row's line.
    var offerTitle: String {
        switch subject {
        case .person(_, let name): String(localized: "Everything with \(name)")
        case .app(let name): String(localized: "Everything from \(name)")
        case .category(let name): String(localized: "Everything in \(name)")
        case .words(let w): String(localized: "Everything that says “\(w)”")
        case .span: String(localized: "Everything from \(spanLabel ?? "")")
        }
    }
}

private extension View {
    func pivotRowInsets() -> some View {
        listRowInsets(.init(top: DS.Space.s2, leading: DSRoomChassis.rowInset,
                            bottom: DS.Space.s2, trailing: DSRoomChassis.rowInset))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
