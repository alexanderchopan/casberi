import SwiftUI

/// **HOME IS FIVE SHORT LISTS (prd §1232, amends the four of 2026-10-08):
/// Needs you, Subscriptions, Spending, Cards, Transactions — five rows each,
/// then a door**, in the Feed's shape since prd §1219: a glance tile per
/// list, each list on a panel. Needs you took Coming up (user: "'needs you'
/// and 'coming up' are they really materially different?"): what waits
/// first, then what is dated, by day. Subscriptions is a plain list (no
/// calendar), its whole page one door down; Transactions keeps its history.
extension FeedScreen {

    /// Rows a Home section shows before its door.
    static let walletHomeCap = 5

    @ViewBuilder
    func walletHomeSections(upcoming: [Thing], all: [Thing], nextEventID: UUID?) -> some View {
        let groups = walletComingUpDays(upcoming)
        let needs = groups.first { $0.0 == Self.needsYouGroup }?.1 ?? []
        let dated = groups.filter { $0.0 != Self.needsYouGroup }.flatMap(\.1)
        // Spending and Cards read every card and wallet together, so they
        // stand on All.
        let onAll = selectedSeat == nil && selectedWallet == nil
        let stream = walletStream(all)
        // An address pays no subscription a reading here can see (§1105).
        let sources = walletSubscriptionSources
        let tracks = sources.map { !$0.isEmpty } ?? true
        let plans = tracks ? Self.walletHomePlans(SubscriptionsReading.shared.items(in: sources)) : []
        let cards = onAll ? SpendingReading.shared.cards : []
        // **THE FEED'S SHAPE (prd §1219, user: "we need to be reusing
        // templates").** A tile per list with its most recent item — the
        // Feed's `GlanceTile` — then each list on the Feed's panel, skipping
        // what its tile showed (§1208l). Subscriptions and Cards are rosters,
        // not news, so their tiles are a plain `GlanceShell` and their lists
        // keep every row.
        let specs = Self.walletGlance([
            (Self.needsYouGroup, Self.things(needs + dated)),
            (Self.spendingName, onAll ? [SpendingReading.shared.latest].compactMap { $0 } : []),
            (Self.transactionsName, Self.things(stream.rows)),
        ])
        let shown = Self.glanceShown(specs, lede: nil)
        let unseen: ([FeedRow]) -> [FeedRow] = { rows in
            rows.filter { row in Self.things([row]).allSatisfy { !shown.contains($0.id) } }
        }
        var tiles: [WalletGlance] = []
        let _ = {
            func spec(_ name: String) -> GlanceSpec? { specs.first { $0.category == name } }
            if let s = spec(Self.needsYouGroup) { tiles.append(.listed(s)) }
            if let plan = plans.first { tiles.append(Self.planGlance(plan)) }
            if let s = spec(Self.spendingName) { tiles.append(.listed(s)) }
            if let card = cards.first { tiles.append(Self.cardGlance(card)) }
            if let s = spec(Self.transactionsName) { tiles.append(.listed(s)) }
        }()

        Group {
            walletGlanceGrid(tiles)
        }
        // The Spending reading (and the cards it reads) starts here, whatever
        // Home shows; Subscriptions reads its own.
        .task(id: walletSpendingKey) { await SpendingReading.shared.refresh(modelContext) }
        .task(id: walletSubscriptionsKey) {
            guard tracks else { return }
            await ServiceLinks.shared.refresh(modelContext, seats: bridges.bridges.map(\.name))
        }

        // **NEEDS YOU, THEN WHAT IS DATED (prd §1232).** One list: what
        // waits on you, undated, leads; the dated rows follow under their
        // days. Five rows across both, then the door.
        let restNeeds = unseen(needs)
        let restDated = unseen(dated)
        if !restNeeds.isEmpty || !restDated.isEmpty {
            let open = walletOpenSections.contains("needs")
            let total = restNeeds.count + restDated.count
            let firstNeeds = open ? restNeeds : Array(restNeeds.prefix(Self.walletHomeCap))
            let firstDated = open ? restDated : Array(restDated.prefix(max(0, Self.walletHomeCap - firstNeeds.count)))
            walletPanel(Self.needsYouGroup, glyph: Self.walletHomeGlyph(Self.needsYouGroup),
                        things: Self.things(restNeeds + restDated)) {
                if !firstNeeds.isEmpty {
                    walletDaySections([(Self.needsYouGroup, firstNeeds)],
                                      boundary: nil, named: [Self.needsYouGroup], headless: true,
                                      nextEventID: nextEventID)
                }
                if !firstDated.isEmpty {
                    walletDaySections(walletRowDays(firstDated), boundary: nil, panelled: true,
                                      nextEventID: nextEventID)
                }
                walletHomeDoor("needs", total: total)
            }
        }

        if tracks {
            walletHomeSubscriptionsSection(plans)
        }

        if onAll {
            walletSpendingSection
        }

        if !cards.isEmpty {
            walletCardsSection(cards)
        }

        let restMoves = unseen(stream.rows)
        if !restMoves.isEmpty {
            walletPanel(Self.transactionsName, glyph: Self.walletHomeGlyph(Self.transactionsName), things: Self.things(restMoves)) {
                walletStreamSections(restMoves, ownMoves: stream.ownMoves, panelled: true, nextEventID: nextEventID)
                walletSeeAllSection(total: all.count)
            }
        }
        jumpRoom
    }

    /// Home's lists in order, for the pill (prd §1219, §1232).
    static var walletHomeNames: [String] {
        [needsYouGroup, subscriptionsName, spendingName, cardsName, transactionsName]
    }

    static func walletHomeGlyph(_ name: String) -> String {
        switch name {
        case needsYouGroup: return ScopeTileGlyph.alerts
        case subscriptionsName: return ScopeTileGlyph.subscriptions
        case spendingName: return ScopeTileGlyph.spending
        case cardsName: return ScopeTileGlyph.cards
        default: return ScopeTileGlyph.activity
        }
    }

    static var subscriptionsName: String { String(localized: "Subscriptions") }
    static var spendingName: String { String(localized: "Spending") }
    static var cardsName: String { String(localized: "Cards") }
    static var transactionsName: String { String(localized: "Transactions") }

    // MARK: - The tiles

    /// A Home tile: a thing's, the Feed's `GlanceTile`, or a roster's, the
    /// same frame (`GlanceShell`) holding a figure and what it is.
    enum WalletGlance {
        case listed(GlanceSpec)
        case plain(name: String, mark: String?, when: Date?, amount: String, title: String)

        var name: String {
            switch self {
            case .listed(let spec): return spec.category
            case .plain(let name, _, _, _, _): return name
            }
        }
    }

    @ViewBuilder
    func walletGlanceGrid(_ tiles: [WalletGlance]) -> some View {
        if !tiles.isEmpty {
            Section {
                GlanceGrid {
                    ForEach(tiles, id: \.name) { tile in
                        switch tile {
                        case .listed(let spec):
                            GlanceTile(category: spec.category, fresh: Self.fresh(spec.things, since: newSince),
                                       newest: spec.newest, next: spec.next,
                                       pictured: spec.pictured, cast: spec.cast, figure: spec.money) {
                                DSHaptic.selection()
                                walletHomeJump(spec.category)
                            }
                        case .plain(let name, let mark, let when, let amount, let title):
                            GlanceShell(category: name, when: when.map { LiveTimeText.short($0) },
                                        accessibility: Text(verbatim: "\(name). \(amount), \(title)")) {
                                DSHaptic.selection()
                                walletHomeJump(name)
                            } top: {
                                EmptyView()
                            } mark: {
                                if let mark {
                                    BridgeIcon(name: mark, size: DS.Mark.badge)
                                        .frame(width: DS.Mark.badge, height: DS.Mark.badge)
                                } else {
                                    SubscriptionFace(name: title, size: DS.Mark.badge)
                                        .frame(width: DS.Mark.badge, height: DS.Mark.badge)
                                }
                            } words: {
                                Text(verbatim: amount)
                                    .dsText(.heading24)
                                    .monospacedDigit()
                                    .foregroundStyle(DS.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                Text(verbatim: title)
                                    .dsText(.subhead12)
                                    .foregroundStyle(DS.textSecondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DSRoomChassis.inset,
                                          bottom: 0, trailing: DSRoomChassis.inset))
                .feedRowBackground()
                .listRowSeparator(.hidden)
            }
        }
    }

    // MARK: - Subscriptions

    /// What renews soonest first, then what has no date, most expensive first.
    static func walletHomePlans(_ items: [Subscriptions.Item]) -> [Subscriptions.Item] {
        items.sorted { a, b in
            switch (a.next, b.next) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return (a.monthly ?? 0) > (b.monthly ?? 0)
            }
        }
    }

    /// The plan that renews next: its price, its name and the day.
    static func planGlance(_ item: Subscriptions.Item) -> WalletGlance {
        let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
        let amount: String
        if item.amount == 0 {
            amount = SubscriptionWords.free
        } else if let price = item.amount {
            amount = mask ?? CardSpendRoom.money(price, code: item.currency)
        } else {
            amount = "—"
        }
        let name = shownName(item.name)
        let title = item.next.map { String(localized: "\(name) · Renews \(WalletSubscriptionRow.day($0))") } ?? name
        return .plain(name: subscriptionsName, mark: nil, when: nil, amount: amount, title: title)
    }

    /// **SUBSCRIPTIONS ON HOME IS A LIST (prd §1232, user: "if subscriptions
    /// goes on home i don't think it needs a calendar it can just be a list
    /// section").** Track first, the plans that renew soonest, then the
    /// whole page — the calendar and the map — one door down, in its sheet.
    @ViewBuilder
    func walletHomeSubscriptionsSection(_ plans: [Subscriptions.Item]) -> some View {
        walletPanel(Self.subscriptionsName, glyph: Self.walletHomeGlyph(Self.subscriptionsName), things: []) {
            Section {
                DSDoorRow(icon: "plus", title: Text(SubscriptionWords.track)) {
                    feedSheet = .subscriptionAdd
                }
                .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.rowInset,
                                          bottom: 0, trailing: DSRoomChassis.rowInset))
                .feedRowBackground()
                .listRowSeparator(.hidden)
                ForEach(Array(plans.prefix(Self.walletHomeCap))) { item in
                    Button {
                        feedSheet = .subscription(item.id)
                    } label: {
                        WalletSubscriptionRow(item: item, writes: walletSubscriptionWrites(item))
                            .contentShape(Rectangle())
                            .arrivalWash(SubscriptionStore.shared.justTracked(item.id), hue: DS.brand)
                    }
                    .buttonStyle(RowPress())
                    .dsHover()
                    .listRowInsets(EdgeInsets(top: Self.rowAir, leading: DSRoomChassis.rowInset,
                                              bottom: Self.rowAir, trailing: DSRoomChassis.rowInset))
                    .feedRowBackground()
                    .listRowSeparator(.hidden)
                }
            }
            if !plans.isEmpty {
                Section {
                    // The count only when the list holds back some.
                    DSMoreLink(title: plans.count > Self.walletHomeCap
                                   ? Text(verbatim: String(localized: "See all \(plans.count)"))
                                   : Text("See all"), opens: true) {
                        chrome.walletSection = .subscriptions
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Space.s1)
                    .listRowSeparator(.hidden)
                    .feedRowBackground()
                }
            }
        }
    }

    // MARK: - Cards

    /// The card that asks something of you soonest, else the most used.
    static func cardGlance(_ card: WalletCardRoll.Card) -> WalletGlance {
        let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
        if let owed = card.owed, let due = card.due {
            return .plain(name: cardsName, mark: card.app, when: nil,
                          amount: mask ?? CardSpendRoom.money(owed, code: card.owedCurrency),
                          title: String(localized: "\(card.name) · Due \(WalletSubscriptionRow.day(due))"))
        }
        if card.spent > 0 || card.offers == 0 {
            return .plain(name: cardsName, mark: card.app, when: nil,
                          amount: mask ?? AppleWalletRoom.money(max(card.spent, 0), "USD"),
                          title: String(localized: "\(card.name) · This month"))
        }
        return .plain(name: cardsName, mark: card.app, when: nil,
                      amount: cardOffersWords(card.offers), title: card.name)
    }

    static func cardOffersWords(_ count: Int) -> String {
        count == 1 ? String(localized: "1 offer") : String(localized: "\(count) offers")
    }

    /// One line per card: what it owes and when, its offers and when the
    /// first ends, else how many purchases this month.
    static func cardLine(_ card: WalletCardRoll.Card, mask: String?) -> String {
        var parts: [String] = []
        if let due = card.due {
            if let owed = card.owed {
                parts.append(String(localized: "\(mask ?? CardSpendRoom.money(owed, code: card.owedCurrency)) due \(WalletSubscriptionRow.day(due))"))
            } else {
                parts.append(String(localized: "Due \(WalletSubscriptionRow.day(due))"))
            }
        } else if let owed = card.owed {
            parts.append(String(localized: "\(mask ?? CardSpendRoom.money(owed, code: card.owedCurrency)) owed"))
        }
        if card.offers > 0 {
            if let ends = card.offerEnds {
                parts.append(String(localized: "\(cardOffersWords(card.offers)), first ends \(WalletSubscriptionRow.day(ends))"))
            } else {
                parts.append(cardOffersWords(card.offers))
            }
        }
        if parts.isEmpty {
            parts.append(card.purchases == 0 ? String(localized: "Nothing this month")
                                             : spendingTimes(card.purchases))
        }
        return parts.joined(separator: " · ")
    }

    /// **CARDS (prd §1232).** Each card: what it spent this month (the
    /// figure), what it owes and when, and the offers on it. A row opens the
    /// app that reads the card.
    @ViewBuilder
    func walletCardsSection(_ cards: [WalletCardRoll.Card]) -> some View {
        let open = walletOpenSections.contains("cards")
        let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
        walletPanel(Self.cardsName, glyph: Self.walletHomeGlyph(Self.cardsName), things: []) {
            Section {
                ForEach(open ? cards : Array(cards.prefix(Self.walletHomeCap))) { card in
                    let app = BridgeCatalog.seatName(forSource: card.app)
                    Button {
                        route.openSetup(forOffer: app)
                    } label: {
                        DSFeedRow(name: card.name, line: Text(verbatim: Self.cardLine(card, mask: mask))) {
                            BridgeIcon(name: app, size: DS.Face.row, circular: true)
                        } trailing: {
                            if card.spent > 0 {
                                Text(verbatim: mask ?? AppleWalletRoom.money(card.spent, "USD"))
                                    .dsText(.price17).monospacedDigit().foregroundStyle(DS.textPrimary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPress())
                    .dsHover()
                    .listRowInsets(EdgeInsets(top: Self.rowAir, leading: DSRoomChassis.rowInset,
                                              bottom: Self.rowAir, trailing: DSRoomChassis.rowInset))
                    .feedRowBackground()
                    .listRowSeparator(.hidden)
                }
            }
            walletHomeDoor("cards", total: cards.count)
        }
    }

    /// The live things behind a list's rows, in order.
    static func things(_ rows: [FeedRow]) -> [Thing] {
        rows.compactMap { row in
            if case .single(let item) = row.kind { return item.live }
            return nil
        }
    }

    /// One tile per list that has something, its most recent item leading
    /// and the one after it in grey, as the Feed's tiles are (prd §1219).
    static func walletGlance(_ lists: [(String, [Thing])]) -> [GlanceSpec] {
        lists.compactMap { name, things in
            let live = things.filter(\.isLive)
            guard let first = live.first else { return nil }
            return GlanceSpec(category: name, things: live, newest: first,
                              next: live.dropFirst().first, pictured: nil, cast: nil,
                              money: walletFigure(first))
        }
    }

    /// **A MONEY BOX LEADS WITH ITS FIGURE (prd §1224)**, as the Feed's
    /// money tiles do: the amount the row would show, through Hide balances,
    /// over who or what it was — the counterparty, a card's name, else the
    /// title's first clause, so a long title never runs out of the box.
    static func walletFigure(_ thing: Thing) -> (title: String, amount: String)? {
        guard thing.isLive else { return nil }
        let sign = thing.transferDirection == "received" ? "+" : ""
        let amount: String
        if let usd = thing.transferUSD, usd.isFinite, usd != 0 {
            amount = sign + WalletValue.payment(usd)
        } else if let value = thing.priceValue, value.isFinite, value != 0 {
            amount = sign + BalancePrivacy.shared.value(
                abs(value).formatted(.currency(code: thing.priceCurrency ?? "USD")))
        } else if let raw = WalletValue.transferAmount(thing),
                  raw.contains(where: { ("1"..."9").contains($0) }) {
            amount = sign + raw
        } else {
            return nil
        }
        let name = thing.transferCounterparty.flatMap { $0.isEmpty ? nil : $0 }
            ?? (WalletCards.isSpend(thing) ? BridgeCatalog.seatName(forSource: thing.source) : nil)
            ?? Self.firstClause(thing.title)
        return (name, amount)
    }

    /// "Needs attention · £200 → €235 · Deposit" → "Needs attention".
    static func firstClause(_ title: String) -> String {
        let cut = [" · ", " — "].compactMap { title.range(of: $0)?.lowerBound }.min()
        return cut.map { String(title[..<$0]) } ?? title
    }

    /// A Home list on the Feed's panel, under an identity the list knows
    /// before its rows are laid out — the Feed's own `sectionID` — so a
    /// tile can scroll to a list still off screen.
    func walletPanel<Rows: View>(_ name: String, glyph: String, things: [Thing],
                                 @ViewBuilder rows: @escaping () -> Rows) -> some View {
        ForEach([Self.sectionID(name)], id: \.self) { _ in
            panelSection(name, glyph: glyph, things: things, rows: rows)
        }
    }

    /// A tile's press: its list's name comes to the top, where the pill
    /// takes it over, and brightens once — the Feed's landing (prd §1208l),
    /// the section's identity first, then its name, as `settleFeedJump` does.
    func walletHomeJump(_ name: String) {
        Task { @MainActor in
            // The Feed's landing: at once, settled over a few passes.
            for pass in 0..<Self.landingPasses {
                if pass > 0 { try? await Task.sleep(for: .milliseconds(70)) }
                panelScrollTarget = Self.sectionID(name)
                await Task.yield()
            }
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(DS.Motion.standard) { landedSection = name }
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(.easeOut(duration: 0.6)) { landedSection = nil }
        }
    }

    /// The due rows under the day each falls due, in the order given.
    func walletRowDays(_ rows: [FeedRow]) -> [(String, [FeedRow])] {
        var order: [String] = []
        var groups: [String: [FeedRow]] = [:]
        for row in rows {
            guard case .single(let item) = row.kind, let due = item.live?.dueAt else { continue }
            let label = dayLabel(due)
            if groups[label] == nil { order.append(label) }
            groups[label, default: []].append(row)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    /// "See all 9" under a capped section, "Show fewer" once it is open; no
    /// door when the cap already shows everything.
    @ViewBuilder
    func walletHomeDoor(_ key: String, total: Int, noun: String? = nil) -> some View {
        if total > Self.walletHomeCap {
            let open = walletOpenSections.contains(key)
            Section {
                DSMoreLink(title: open ? Text("Show fewer")
                                       : Text(verbatim: noun ?? String(localized: "See all \(total)")),
                            opens: !open) {
                    withAnimation(DS.Motion.standard) {
                        if open { walletOpenSections.remove(key) } else { walletOpenSections.insert(key) }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Space.s1)
                .listRowSeparator(.hidden)
                .feedRowBackground()
            }
        }
    }

    // MARK: - Spending

    /// What left your accounts this month, by place (`Spending`): a line
    /// against last month to the same day, then the places, largest first.
    @ViewBuilder
    var walletSpendingSection: some View {
        let reading = SpendingReading.shared.reading
        if !reading.places.isEmpty {
                let open = walletOpenSections.contains("spending")
                let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
                walletPanel(Self.spendingName, glyph: Self.walletHomeGlyph(Self.spendingName), things: []) {
                Section {
                    Text(verbatim: Self.spendingLine(reading, mask: mask))
                        .dsText(.label12).foregroundStyle(DS.textSecondary)
                        .padding(.leading, DSRoomChassis.rowInset)
                        .padding(.bottom, DS.Space.s1)
                        .listRowInsets(EdgeInsets())
                        .feedRowBackground()
                        .listRowSeparator(.hidden)
                    ForEach(open ? reading.places : Array(reading.places.prefix(Self.walletHomeCap)),
                            id: \.name) { place in
                        SubscriptionRow(name: place.name, line: Text(verbatim: Self.spendingTimes(place.count))) {
                            Text(verbatim: mask ?? AppleWalletRoom.money(place.usd, "USD"))
                                .dsText(.price17).monospacedDigit().foregroundStyle(DS.textPrimary)
                        }
                        .listRowInsets(EdgeInsets(top: Self.rowAir, leading: DSRoomChassis.rowInset,
                                                  bottom: Self.rowAir, trailing: DSRoomChassis.rowInset))
                        .feedRowBackground()
                        .listRowSeparator(.hidden)
                    }
                }
                walletHomeDoor("spending", total: reading.places.count,
                               noun: String(localized: "All \(reading.places.count) places"))
                }
        }
    }

    /// Re-read when the room's rows change or the demo flips.
    var walletSpendingKey: String { "\(DemoMode.isActive)|\(walletSubscriptionsKey)" }

    /// "$3,410 in October · $280 less than this point in September".
    static func spendingLine(_ reading: Spending.Reading, now: Date = .now, mask: String?) -> String {
        let month = now.formatted(.dateTime.month(.wide))
        let total = String(localized: "\(mask ?? AppleWalletRoom.money(reading.total, "USD")) in \(month)")
        guard mask == nil, let earlier = reading.earlier,
              let last = Calendar.current.date(byAdding: .month, value: -1, to: now) else { return total }
        let lastMonth = last.formatted(.dateTime.month(.wide))
        let diff = reading.total - earlier
        let compare: String
        if abs(diff) < 1 {
            compare = String(localized: "about the same as this point in \(lastMonth)")
        } else if diff < 0 {
            compare = String(localized: "\(AppleWalletRoom.money(-diff, "USD")) less than this point in \(lastMonth)")
        } else {
            compare = String(localized: "\(AppleWalletRoom.money(diff, "USD")) more than this point in \(lastMonth)")
        }
        return "\(total) · \(compare)"
    }

    static func spendingTimes(_ count: Int) -> String {
        count == 1 ? String(localized: "Once") : String(localized: "\(count) times")
    }
}
