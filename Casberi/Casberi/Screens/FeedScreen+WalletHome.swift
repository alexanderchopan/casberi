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
        // **A BALANCE IS NOT A TRANSACTION (prd §1341, user, of an Acorns
        // account under Transactions: "this is terrible").** An account and
        // an app that made you a wallet are states; Holdings lists them.
        let moves = Self.walletMoves(all)
        let stream = walletStream(moves)
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
        // **ACCOUNTS LEADS OVERVIEW (prd §1410, user: "a line that says
        // 'accounts' and has how many you are tracking").** What the balance
        // is made of: the addresses you follow and the apps folded in, as the
        // accounts menu lists them, never the All slot.
        let accounts = walletAccountSlots.filter { !$0.id.isEmpty }
        let _ = {
            if !accounts.isEmpty {
                lines.append(OverviewLine(name: Self.accountsName, figure: "\(accounts.count)"))
            }
            let waiting = Self.things(needs + dated).filter(\.isLive)
            let asks = waiting.count + (OutsideKeyNudge.shown ? 1 : 0) + (RecoveryKeyNudge.shown ? 1 : 0)
            if asks > 0 {
                lines.append(OverviewLine(name: Self.needsYouGroup, figure: "\(asks)"))
            }
            if let plan = plans.first { lines.append(Self.planGlance(plan)) }
            if onAll, let s = Self.spendingGlance(SpendingReading.shared.reading) { lines.append(s) }
            if let card = cards.first { lines.append(Self.cardGlance(card)) }
        }()

        // THE PANE'S WALLET BOX CARRIES OVERVIEW, THEN COMING UP (prd
        // §1407): under the balance and its line, where the mockup draws
        // them; beside a pane the list column keeps Needs you and the
        // transactions. `dsPaneBoxRow` is the one mechanism (§1403).
        Group {
            walletOverview(lines)
        }
        .environment(\.dsPaneBoxRow, true)
        // The Spending reading (and the cards it reads) starts here, whatever
        // Home shows; Subscriptions reads its own.
        .task(id: walletSpendingKey) { await SpendingReading.shared.refresh(modelContext) }
        .task(id: walletSubscriptionsKey) {
            guard tracks else { return }
            await ServiceLinks.shared.refresh(modelContext, seats: bridges.bridges.map(\.name))
        }

        // The Accounts list stands first, where its Overview row points
        // (prd §1410): a state, not news, so it does not displace Needs you
        // from leading what happened.
        if !accounts.isEmpty {
            walletAccountsSection(accounts)
        }

        // **NEEDS YOU, THEN WHAT IS DATED (prd §1232).** One list: what
        // waits on you, undated, leads; the dated rows follow under their
        // days. Five rows across both, then the door.
        let restNeeds = needs
        // Beside a pane the dated rows are the pane's Coming up (prd §1407).
        let paned = roomBoxPlace != .list
        let restDated = paned ? [] : dated
        if paned, !dated.isEmpty {
            walletPanel(Self.comingUpName, glyph: ScopeTileGlyph.comingUp, things: Self.things(dated)) {
                walletDaySections(walletRowDays(dated), boundary: nil, panelled: true,
                                  nextEventID: nextEventID)
            }
            .environment(\.dsPaneBoxRow, true)
        }
        // Your account's outside key leads Needs you while it has none
        // (prd §1432), on All, where the account stands among the rest.
        let nudge = onAll && OutsideKeyNudge.shown
        // Money on a network without the recovery key leads (prd §1442m).
        let unprotected = onAll && RecoveryKeyNudge.shown
        if !restNeeds.isEmpty || !restDated.isEmpty || nudge || unprotected {
            let open = walletOpenSections.contains("needs")
            let total = restNeeds.count + restDated.count
            let firstNeeds = open ? restNeeds : Array(restNeeds.prefix(Self.walletHomeCap))
            let firstDated = open ? restDated : Array(restDated.prefix(max(0, Self.walletHomeCap - firstNeeds.count)))
            walletPanel(Self.needsYouGroup, glyph: Self.walletHomeGlyph(Self.needsYouGroup),
                        things: Self.things(restNeeds + restDated)) {
                if unprotected { RecoveryKeyNudge().listRow }
                if nudge { OutsideKeyNudge().listRow }
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

        // A Wallet with no account offers one thing, in its box (prd §1364):
        // Track waits for the first account unless something is tracked.
        if tracks, !plans.isEmpty || !walletAccountSlots.allSatisfy(\.id.isEmpty) {
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
                walletSeeAllSection(total: moves.count)
            }
        }
        jumpRoom
    }

    /// What happened, without the states (`MoneyReceipt.isState`): the one
    /// filter Transactions and the history behind its door share (§837).
    static func walletMoves(_ things: [Thing]) -> [Thing] {
        things.filter { !MoneyReceipt.isState(source: $0.source, ref: $0.sourceRef) }
    }

    /// Home's lists in order, for the pill (prd §1219, §1232).
    static var walletHomeNames: [String] {
        [overviewName, accountsName, needsYouGroup, subscriptionsName, spendingName, cardsName, transactionsName]
    }

    static func walletHomeGlyph(_ name: String) -> String {
        switch name {
        // The pinned copy of Overview's name asks here too, so it wears the
        // card's own glyph, not the default.
        case overviewName: return ScopeTileGlyph.home
        case accountsName: return ScopeTileGlyph.accounts
        case needsYouGroup: return ScopeTileGlyph.alerts
        case subscriptionsName: return ScopeTileGlyph.subscriptions
        case spendingName: return ScopeTileGlyph.spending
        case cardsName: return ScopeTileGlyph.cards
        default: return ScopeTileGlyph.activity
        }
    }

    static var accountsName: String { String(localized: "Accounts") }
    static var subscriptionsName: String { String(localized: "Subscriptions") }
    static var spendingName: String { String(localized: "Spending") }
    static var cardsName: String { String(localized: "Cards") }
    static var transactionsName: String { String(localized: "Transactions") }

    // MARK: - Overview (prd §1257)

    /// One of Overview's rows: a list's name and its figure. **No sub-line
    /// (prd §1331, user: "don't need the subtext")**: the line under each
    /// name restated the list's first item (a raw status, a truncated
    /// comparison); the list itself is right below.
    struct OverviewLine {
        let name: String
        let figure: String
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
                            Text(verbatim: item.name)
                                .dsText(.body17)
                                .foregroundStyle(DS.textPrimary)
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
                    .accessibilityLabel(Text(verbatim: "\(item.name). \(item.figure)"))
                    .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.rowInset,
                                              bottom: 0, trailing: DSRoomChassis.rowInset))
                    .feedRowBackground()
                    .listRowSeparator(.hidden)
                }
            }
        }
    }

    // MARK: - Accounts (prd §1410)

    /// **THE WALLET ADDS ACCOUNTS WHERE THE FEED ADDS FOLLOWS (prd §1410,
    /// user: "we need a way while in wallet to be able to add accounts there
    /// same way like in feed you can add stuff to follow").** Until now the
    /// one door was the accounts menu's first row, which on the phone lives
    /// in the tray behind the face. Accounts is a list on Home like the
    /// others: the accounts menu's rows — the addresses you follow, then the
    /// apps folded in — five then a door, and its header wears the Feed's +
    /// (`walletAccountAdds`). A tap scopes the Wallet to one as the menu does,
    /// the one showing ticked, a second tap back to All; a hold on an address
    /// offers Stop following (§1302's rule) and on an app its settings.
    @ViewBuilder
    func walletAccountsSection(_ slots: [DSAccountSlot]) -> some View {
        let open = walletOpenSections.contains("accounts")
        let shown = open ? slots : Array(slots.prefix(Self.walletHomeCap))
        walletPanel(Self.accountsName, glyph: Self.walletHomeGlyph(Self.accountsName), things: []) {
            ForEach(shown) { slot in walletAccountRow(slot) }
            walletHomeDoor("accounts", total: slots.count)
        }
    }

    /// One account: its face, its name over the line the menu gives it, the
    /// pick ticked in the pick's ink.
    @ViewBuilder
    func walletAccountRow(_ slot: DSAccountSlot) -> some View {
        let picked = slot.isShowing(chrome.walletScope)
        DSPushRow(title: Text(verbatim: slot.name),
                  subtitle: slot.sub.map { Text(verbatim: $0) },
                  fact: picked ? Text(Image(systemName: "checkmark")) : nil,
                  factTone: DS.pickInk, opens: false) {
            DSHaptic.selection()
            withAnimation(DS.Motion.standard) { chrome.walletScope = picked ? nil : slot.id }
        } leading: {
            // A face keeps its own ramp, centred in the Feed's column (§1170).
            Group {
                switch slot.faces.first {
                case .wallet(let address)?:
                    WalletFace(address: address, size: DS.Face.row, circular: true)
                case .mark(_, let source)?, .avatar(_, let source)?:
                    BridgeIcon(name: source, size: DS.Face.row)
                case nil:
                    BridgeIcon(name: slot.name, size: DS.Face.row)
                }
            }
            .frame(width: DS.Mark.row, height: DS.Mark.row)
        }
        .accessibilityLabel(Text(verbatim: picked ? "\(slot.name), showing" : slot.name))
        // The air the Subscriptions rows take, so the two lists read alike.
        .listRowInsets(EdgeInsets(top: Self.rowAir, leading: DSRoomChassis.rowInset,
                                  bottom: Self.rowAir, trailing: DSRoomChassis.rowInset))
        .feedRowBackground()
        .listRowSeparator(.hidden)
        .contextMenu {
            if case .wallet(let address)? = slot.faces.first {
                // What you follow goes from a hold on its row (prd §1302),
                // through the book row's own unwatch, Undo included.
                if let entry = AddressBook.shared.entry(for: address) {
                    Button(role: .destructive) {
                        WalletUnwatch.perform(entry, context: modelContext, chrome: chrome)
                    } label: {
                        Label(String(localized: "Stop following"), systemImage: "trash")
                    }
                }
            } else {
                // An app's page, as the tray's hold offers it (prd §1159).
                Button { openAppPage(slot.name) } label: {
                    Label(String(localized: "Settings"), systemImage: "slider.horizontal.3")
                }
            }
        }
    }

    /// The two ways in, on the Accounts header and the Feed's Wallet section
    /// alike (prd §1410; §1347's one row grew): the tray that follows an
    /// address, and the catalogue landed on its Wallet card — 24 apps, too
    /// many for a menu, so the one door to the catalogue (§1234) as Social's
    /// More social apps is (§1303).
    ///
    /// **Create an account leads (prd §1422 item 4, §1433)** while this phone
    /// has no account of its own: Move, where it is made — or, when iCloud
    /// Keychain holds one's recovery key, taken back.
    var walletAccountAdds: [SectionAdd] {
        var adds: [SectionAdd] = []
        if YourAccountKey.address == nil {
            adds.append(SectionAdd(label: String(localized: "Create an account"),
                                   glyph: ScopeTileGlyph.move) { chrome.moveTray = true })
        }
        return adds + [SectionAdd(label: String(localized: "Follow an account"),
                    glyph: ScopeTileGlyph.wallets) { feedSheet = .walletFollow },
         SectionAdd(label: String(localized: "Connect an app"),
                    glyph: ScopeTileGlyph.apps) {
            route.openCategory = CategoryFold.walletRoom
            route.present(.apps)
        }]
    }

    static var overviewName: String { String(localized: "Overview") }
    /// The pane's dated group beside a pane (prd §1407).
    static var comingUpName: String { String(localized: "Coming up") }

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
        return OverviewLine(name: subscriptionsName, figure: amount)
    }

    /// **SUBSCRIPTIONS ON HOME IS A LIST (prd §1232, user: "if subscriptions
    /// goes on home i don't think it needs a calendar it can just be a list
    /// section").** Track first, the plans that renew soonest, then the
    /// whole page — the calendar and the map — one door down, in its sheet.
    @ViewBuilder
    func walletHomeSubscriptionsSection(_ plans: [Subscriptions.Item]) -> some View {
        walletPanel(Self.subscriptionsName, glyph: Self.walletHomeGlyph(Self.subscriptionsName), things: []) {
            Section {
                // Track leads from the header's + (prd §1386), not a row.
                ForEach(Array(plans.prefix(Self.walletHomeCap))) { item in
                    Button {
                        feedSheet = .subscription(item.id)
                    } label: {
                        WalletSubscriptionRow(item: item, writes: Self.walletSubscriptionWrites(item))
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
                    // The one More row (prd §1386), never centred.
                    DSMoreRow(title: plans.count > Self.walletHomeCap
                                  ? Text(verbatim: String(localized: "See all \(plans.count)"))
                                  : Text("See all"), opens: true) {
                        chrome.walletSection = .subscriptions
                    }
                    .listRowInsets(.init(top: Self.rowAir, leading: DSRoomChassis.rowInset,
                                         bottom: Self.rowAir, trailing: DSRoomChassis.rowInset))
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
        if let owed = card.owed, card.due != nil {
            return OverviewLine(name: cardsName,
                                figure: mask ?? CardSpendRoom.money(owed, code: card.owedCurrency))
        }
        if card.spent > 0 || card.offers == 0 {
            return OverviewLine(name: cardsName,
                                figure: mask ?? AppleWalletRoom.money(max(card.spent, 0), "USD"))
        }
        return OverviewLine(name: cardsName, figure: cardOffersWords(card.offers))
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
                // The one More row (prd §1386): at the rows' inset, grey,
                // a chevron; never centred.
                DSMoreRow(title: open ? Text("Show fewer")
                                      : Text(verbatim: noun ?? String(localized: "See all \(total)")),
                          opens: !open) {
                    withAnimation(DS.Motion.standard) {
                        if open { walletOpenSections.remove(key) } else { walletOpenSections.insert(key) }
                    }
                }
                .listRowInsets(.init(top: Self.rowAir, leading: DSRoomChassis.rowInset,
                                     bottom: Self.rowAir, trailing: DSRoomChassis.rowInset))
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
        return OverviewLine(name: spendingName,
                            figure: mask ?? AppleWalletRoom.money(reading.total, "USD"))
    }

    static func spendingTimes(_ count: Int) -> String {
        count == 1 ? String(localized: "Once") : String(localized: "\(count) times")
    }
}
