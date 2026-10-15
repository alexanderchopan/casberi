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
        // **OVERVIEW (prd §1257, user: "ok do the overview card").** One
        // card, a row per list — what it is, its figure, one line — each a
        // jump to its list, where the tiles stood (§1219). The lists under it
        // keep every row: a row here names a list, it does not show its items.
        var lines: [OverviewLine] = []
        let _ = {
            let waiting = Self.things(needs + dated).filter(\.isLive)
            if let first = waiting.first {
                lines.append(OverviewLine(name: Self.needsYouGroup, figure: "\(waiting.count)",
                                          line: first.title))
            }
            if let plan = plans.first { lines.append(Self.planGlance(plan)) }
            if onAll, let s = Self.spendingGlance(SpendingReading.shared.reading) { lines.append(s) }
            if let card = cards.first { lines.append(Self.cardGlance(card)) }
        }()

        Group {
            walletOverview(lines)
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
        let restNeeds = needs
        let restDated = dated
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

        let restMoves = stream.rows
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
        [overviewName, needsYouGroup, subscriptionsName, spendingName, cardsName, transactionsName]
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

    // MARK: - Overview (prd §1257)

    /// One of Overview's rows: a list's name, its figure, and one line.
    struct OverviewLine {
        let name: String
        let figure: String
        let line: String
    }

    /// The card: the Feed's panel, a row per list with its pink glyph, the
    /// name over the line and the figure trailing; a press lands on the list.
    @ViewBuilder
    func walletOverview(_ lines: [OverviewLine]) -> some View {
        if !lines.isEmpty {
            walletPanel(Self.overviewName, glyph: ScopeTileGlyph.home, things: []) {
                ForEach(lines, id: \.name) { item in
                    Button {
                        DSHaptic.selection()
                        walletHomeJump(item.name)
                    } label: {
                        HStack(spacing: DS.Space.s3) {
                            DSActRow.disc(Self.walletHomeGlyph(item.name))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: item.name)
                                    .dsText(.body17)
                                    .foregroundStyle(DS.textPrimary)
                                Text(verbatim: item.line)
                                    .dsText(.subhead12)
                                    .foregroundStyle(DS.textTertiary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: DS.Space.s2)
                            Text(verbatim: item.figure)
                                .dsText(.heading17)
                                .monospacedDigit()
                                .foregroundStyle(DS.textPrimary)
                                .lineLimit(1)
                        }
                        .frame(minHeight: DSActRow.height)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPress())
                    .accessibilityLabel(Text(verbatim: "\(item.name). \(item.figure), \(item.line)"))
                    .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.rowInset,
                                              bottom: 0, trailing: DSRoomChassis.rowInset))
                    .feedRowBackground()
                    .listRowSeparator(.hidden)
                }
            }
        }
    }

    static var overviewName: String { String(localized: "Overview") }

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
    static func planGlance(_ item: Subscriptions.Item) -> OverviewLine {
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
        return OverviewLine(name: subscriptionsName, figure: amount, line: title)
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
                    .contextMenu { stopTrackingMenu(item) }
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
    static func cardGlance(_ card: WalletCardRoll.Card) -> OverviewLine {
        let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
        if let owed = card.owed, let due = card.due {
            return OverviewLine(name: cardsName,
                                figure: mask ?? CardSpendRoom.money(owed, code: card.owedCurrency),
                                line: String(localized: "\(card.name) · Due \(WalletSubscriptionRow.day(due))"))
        }
        if card.spent > 0 || card.offers == 0 {
            return OverviewLine(name: cardsName,
                                figure: mask ?? AppleWalletRoom.money(max(card.spent, 0), "USD"),
                                line: String(localized: "\(card.name) · This month"))
        }
        return OverviewLine(name: cardsName, figure: cardOffersWords(card.offers), line: card.name)
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
        guard let compare = spendingCompare(reading, now: now, mask: mask) else { return total }
        return "\(total) · \(compare)"
    }

    /// "$280 less than this point in September", or nil under Hide balances
    /// or with nothing read last month.
    static func spendingCompare(_ reading: Spending.Reading, now: Date = .now, mask: String?) -> String? {
        guard mask == nil, let earlier = reading.earlier,
              let last = Calendar.current.date(byAdding: .month, value: -1, to: now) else { return nil }
        let lastMonth = last.formatted(.dateTime.month(.wide))
        let diff = reading.total - earlier
        if abs(diff) < 1 {
            return String(localized: "about the same as this point in \(lastMonth)")
        } else if diff < 0 {
            return String(localized: "\(AppleWalletRoom.money(-diff, "USD")) less than this point in \(lastMonth)")
        } else {
            return String(localized: "\(AppleWalletRoom.money(diff, "USD")) more than this point in \(lastMonth)")
        }
    }

    /// **THE MONTH, NEVER ONE PURCHASE (prd §1246, user: "what is the
    /// difference between spending and transactions they show same
    /// number").** The tile drew the newest purchase, which is most days the
    /// newest move, so it matched Transactions' tile. It draws what the list
    /// leads with: this month's total over last month to the same day.
    static func spendingGlance(_ reading: Spending.Reading, now: Date = .now) -> OverviewLine? {
        guard !reading.places.isEmpty else { return nil }
        let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
        let month = now.formatted(.dateTime.month(.wide))
        // The line stands alone here, so it opens a sentence.
        let title = spendingCompare(reading, now: now, mask: mask)
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            ?? String(localized: "So far in \(month)")
        return OverviewLine(name: spendingName,
                            figure: mask ?? AppleWalletRoom.money(reading.total, "USD"), line: title)
    }

    static func spendingTimes(_ count: Int) -> String {
        count == 1 ? String(localized: "Once") : String(localized: "\(count) times")
    }
}
