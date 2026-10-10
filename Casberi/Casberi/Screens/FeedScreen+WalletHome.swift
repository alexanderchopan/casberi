import SwiftUI

/// **HOME IS FOUR SHORT LISTS (user, 2026-10-08): Needs you, Coming up,
/// Spending, Transactions — five rows each, then a door**, in the Feed's
/// shape since prd §1219: a glance tile per list, each list on a panel. Needs you, Coming
/// up and Spending open in place (they are bounded: what waits, what is
/// dated, the places this month); Transactions keeps its history screen.
extension FeedScreen {

    /// Rows a Home section shows before its door.
    static let walletHomeCap = 5

    @ViewBuilder
    func walletHomeSections(upcoming: [Thing], all: [Thing], nextEventID: UUID?) -> some View {
        let groups = walletComingUpDays(upcoming)
        let needs = groups.first { $0.0 == Self.needsYouGroup }?.1 ?? []
        let dated = groups.filter { $0.0 != Self.needsYouGroup }.flatMap(\.1)
        // Spending reads every card and wallet together, so it stands on All.
        let spends = selectedSeat == nil && selectedWallet == nil
        let stream = walletStream(all)
        // **THE FEED'S SHAPE (prd §1219, user: "we need to be reusing
        // templates").** A tile per list with its most recent item — the
        // Feed's `GlanceTile` — then each list on the Feed's panel, skipping
        // what its tile showed (§1208l).
        let specs = Self.walletGlance([
            (Self.needsYouGroup, Self.things(needs)),
            (Self.comingUpName, Self.things(dated)),
            (Self.spendingName, spends ? [SpendingReading.shared.latest].compactMap { $0 } : []),
            (Self.transactionsName, Self.things(stream.rows)),
        ])
        let shown = Self.glanceShown(specs, lede: nil)
        let unseen: ([FeedRow]) -> [FeedRow] = { rows in
            rows.filter { row in Self.things([row]).allSatisfy { !shown.contains($0.id) } }
        }

        Group {
            contentsGrid(specs) { name in walletHomeJump(name) }
        }
        // The Spending reading starts here, whatever Home shows.
        .task(id: walletSpendingKey) { await SpendingReading.shared.refresh(modelContext) }

        let restNeeds = unseen(needs)
        if !restNeeds.isEmpty {
            let open = walletOpenSections.contains("needs")
            walletPanel(Self.needsYouGroup, glyph: Self.walletHomeGlyph(Self.needsYouGroup), things: Self.things(restNeeds)) {
                walletDaySections([(Self.needsYouGroup, open ? restNeeds : Array(restNeeds.prefix(Self.walletHomeCap)))],
                                  boundary: nil, named: [Self.needsYouGroup], headless: true,
                                  nextEventID: nextEventID)
                walletHomeDoor("needs", total: restNeeds.count)
            }
        }

        let restDated = unseen(dated)
        if !restDated.isEmpty {
            let open = walletOpenSections.contains("coming")
            walletPanel(Self.comingUpName, glyph: Self.walletHomeGlyph(Self.comingUpName), things: Self.things(restDated)) {
                walletDaySections(walletRowDays(open ? restDated : Array(restDated.prefix(Self.walletHomeCap))),
                                  boundary: nil, panelled: true, nextEventID: nextEventID)
                walletHomeDoor("coming", total: restDated.count)
            }
        }

        if spends {
            walletSpendingSection
        }

        let restMoves = unseen(stream.rows)
        if !restMoves.isEmpty {
            walletPanel(Self.transactionsName, glyph: Self.walletHomeGlyph(Self.transactionsName), things: Self.things(restMoves)) {
                walletStreamSections(restMoves, ownMoves: stream.ownMoves, panelled: true, nextEventID: nextEventID)
                walletSeeAllSection(total: all.count)
            }
        }
    }

    /// Home's lists in order, for the pill (prd §1219).
    static var walletHomeNames: [String] { [needsYouGroup, comingUpName, spendingName, transactionsName] }

    static func walletHomeGlyph(_ name: String) -> String {
        switch name {
        case needsYouGroup: return ScopeTileGlyph.alerts
        case comingUpName: return ScopeTileGlyph.comingUp
        case spendingName: return ScopeTileGlyph.cards
        default: return ScopeTileGlyph.activity
        }
    }

    static var comingUpName: String { String(localized: "Coming up") }
    static var spendingName: String { String(localized: "Spending") }
    static var transactionsName: String { String(localized: "Transactions") }

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

    /// **A MONEY BOX LEADS WITH ITS FIGURE (prd §1223)**, as the Feed's
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
        panelScrollTarget = Self.sectionID(name)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            panelScrollTarget = Self.scrollAnchor(name)
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
