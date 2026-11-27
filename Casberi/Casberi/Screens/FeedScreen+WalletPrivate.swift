import SwiftUI

/// **PRIVATE, IN HOLDINGS (prd §1554).** Under Tokens, Holdings only SHOWS
/// what is private: a head naming it with its total, then one row per token,
/// state and network off the notes Move to private kept (`PrivateMoney.rows`)
/// — "ETH" over "1.0% on Aave" where it earns (Ethereum's yield pools, the
/// rate read live, prd §1563) or its network ("Sepolia", which has no Aave),
/// "ETH" with a grey clock over "Being checked by Privacy Pools" (§1841), "ETH"
/// over "Not approved". The token alone: the head already says private. The Tokens rows above are
/// public balances only; the box counts approved private money as one
/// Private block, and the total counts it once (`PrivateMoneyStore.walletHolding`).
/// No verb here: the acts are Send's (`MovePrivateSentence`). The header
/// opens Send to your private balance; a row opens Send with the Private
/// switch on. Private is never the default.
///
/// The section stands where there is a note to show, or, in a build that can
/// move to private (`PrivateMove.available`: Ethereum, or Sepolia in DEBUG),
/// as the head alone — the door with nothing behind it yet.
extension FeedScreen {

    @ViewBuilder
    var walletPrivateRows: some View {
        let store = PrivateMoneyStore.shared
        let rows = store.rows
        // **BY PLACE (prd §1973 item 7):** each place Home lists, in Home's
        // order, under a header that is Home's line word for word and dollar
        // for dollar; its rows under it, never merged with another place's.
        let places = walletShowsPrivatePlaces ? homePrivatePlaces : []
        // Yours and All only (prd §1590): private money is your Casberi
        // account's, never a followed wallet's or an app's pick. Privacy
        // Pools has no pick (prd §1738): its tile lands here.
        if walletShowsPrivatePlaces, !places.isEmpty || !rows.isEmpty {
            let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
            Group {
                walletPrivateHead(total: mask ?? walletPrivateTotal(rows, prices: store.shownPrices, places: places))
                    .task(id: rows.map(\.id)) {
                        await store.refresh()
                        await store.readPrices()
                        await store.readYield()
                        await RailgunHoldings.shared.refresh()
                        // A new phone finds its private money again here
                        // (prd §1562, every build since §1567): each root's
                        // notes from the pool, its fresh addresses walked
                        // back. Once per root; the line says so meanwhile.
                        // Every root's notes again on a cadence, and what was
                        // sent and not seen asked about (the review of
                        // 2026-10-26, finding 2).
                        await PrivateWatch.findNotes(context: modelContext)
                        await FreshReceive.shared.restore()
                        // What a fresh address was paid moves in from here
                        // too (prd §1560): its row appears as "moving in".
                        await FreshReceive.shared.check(context: modelContext)
                        // A note waiting on the ASP is asked again while the
                        // section shows (the store spaces the asks 20 s).
                        while PrivateMoney.anyWaiting(store.notes), !Task.isCancelled {
                            try? await Task.sleep(for: .seconds(20))
                            await store.refresh()
                        }
                    }
                // One line while a new phone rebuilds it (prd §1567): never
                // a spinner page, gone when done.
                // The savings goal moved to Your account › Spending (prd
                // §1700f item 10): Holdings lists what you hold.
                if store.restoring {
                    Text("Restoring Privacy Pools")
                        .dsText(.subhead12)
                        .foregroundStyle(DS.textSecondary)
                        .padding(.leading, DSRoomChassis.headGlyph + DSRoomChassis.headGap)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .walletListRow()
                        .transition(.opacity)
                }
                // What the private balances add up to against your goal
                // (§1835): all of Private's, so under its head, before any
                // one place's header.
                walletSavingsGoalRow(mask: mask)
                // Empty, a place is its header at $0 (§769: what would fill
                // it, empty); Add money, last, is the way in.
                ForEach(places) { place in
                    walletPlaceHead(place, mask: mask)
                    walletPrivateGroupRows(place, rows: rows, mask: mask)
                }
                // Privacy Pools' notes in a build that cannot move to private
                // still stand, under no header.
                if !places.contains(where: { $0.id == Self.homePoolsPlace }) {
                    walletPrivateGroupRows(HomePlace(id: Self.homePoolsPlace, name: "Privacy Pools", usd: nil),
                                    rows: rows, mask: mask)
                }
            }
        }
    }

    /// Where a private place's header goes: a send to Privacy Pools or
    /// Aztec; nil for a place with no such door (Tacit's page is deleted,
    /// prd §1981).
    func walletPlaceDoor(_ id: String) -> (() -> Void)? {
        switch id {
        case Self.homePoolsPlace where PrivateMove.available: {
            chrome.movePrivately = .deposit
            chrome.moveTray = true
        }
        case Self.homeAztecPlace where Self.aztecTakesMoney: {
            chrome.moveAztec = .deposit
            chrome.moveTray = true
        }
        default: nil
        }
    }

    /// The rows under one private place's header (prd §1973 item 7).
    @ViewBuilder
    func walletPrivateGroupRows(_ place: HomePlace, rows: [PrivateMoney.Row], mask: String?) -> some View {
        let store = PrivateMoneyStore.shared
        switch place.id {
        case Self.homePoolsPlace:
            ForEach(rows) { row in
                walletPrivateRow(row, mask: mask, prices: store.shownPrices)
            }
            // What arrived at a one-time address and has not moved in (prd
            // §1778): never invisible. Its addresses are Privacy Pools'.
            walletFreshWaitingRows(mask: mask, prices: store.shownPrices)
        case Self.homeRailgunPlace:
            // Railgun's tokens (prd §1713, §1721): spendable first, then what
            // Railgun's screening has yet to list.
            walletRailgunRows(mask: mask)
        case Self.homeAztecPlace:
            walletAztecRows
            // Its gas and anything it holds in the open stand with the place
            // they serve (prd §1973 item 8), each line saying which.
            walletAztecPublicRows
        case Self.homeTacitPlace:
            walletTacitRow(mask: mask)
        default:
            EmptyView()
        }
    }

    /// **A PLACE'S HEADER (prd §1973 item 7):** Home's line, word for word
    /// and dollar for dollar — the name grey, everything there in whole
    /// dollars; the network is each row's to say. Tacit's
    /// opens its page, as on Home; Privacy Pools' and Aztec's open a send to
    /// them, as their empty rows did; Railgun's is words.
    @ViewBuilder
    func walletPlaceHead(_ place: HomePlace, mask: String?) -> some View {
        let figure = place.usd.map { $0 < 0.01 ? "$0" : mask ?? WalletValue.exactMoney($0) } ?? ""
        let label = HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            Text(verbatim: place.name).dsText(.fact15)
                .foregroundStyle(DS.textSecondary).lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: DS.Space.s2)
            Text(verbatim: figure).dsText(.fact15).monospacedDigit()
                .foregroundStyle((place.usd ?? 0) < 0.01 ? DS.textSecondary : DS.textPrimary)
                .lineLimit(1)
        }
        // The header's own words and a little air above them, so a group
        // reads as one block under its name (prd §1973 item 11).
        .padding(.top, DS.Space.s2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: [place.name, figure].joined(separator: ". ")))
        if let open = walletPlaceDoor(place.id) {
            Button {
                DSHaptic.selection()
                open()
            } label: { label }
            .buttonStyle(RowPress())
            .dsHover()
            .accessibilityAddTraits(.isButton)
            .walletListRow()
        } else {
            label
                .accessibilityAddTraits(.isHeader)
                .walletListRow()
        }
    }

    /// Private money is yours alone: Yours and All, never a followed wallet
    /// or an app's pick (prd §1590).
    var walletShowsPrivatePlaces: Bool {
        selectedSeat == nil && !walletOnFollowing && (selectedWallet.map(YourAccountDemo.isYours) ?? true)
    }

    /// **WAITING AT A ONE-TIME ADDRESS (prd §1778; a tester, 2026-11-13,
    /// who paid a private address 1,000 USDC and saw no balance anywhere:
    /// "panik").** Money that arrived at a fresh address and has not moved in
    /// showed only under Receive's address. It stands here too: the token,
    /// its state in amber, the amount grey because the total does not count
    /// it yet. A tap opens Receive, where the move is made.
    var walletFreshWaiting: [FreshAddress.Entry] {
        #if DEBUG
        // `-freshWaitingSample YES`: the two rows over the demo, which makes
        // no address and so could never draw them.
        if UserDefaults.standard.bool(forKey: "freshWaitingSample") {
            return [FreshAddress.Entry(index: 1, address: "0x0000000000000000000000000000000000000d58", made: .now,
                                       state: .needsGas(amount: "1000000000"), chainId: 1, symbol: "USDC"),
                    FreshAddress.Entry(index: 2, address: "0x0000000000000000000000000000000000000d59", made: .now,
                                       state: .failed(amount: "10000000000000000"), chainId: 1)]
        }
        #endif
        guard !DemoMode.isActive, let network = PrivacyNetwork.current(debugAsks: PrivateMove.debugNetwork) else { return [] }
        return FreshAddress.waiting(FreshReceive.shared.entries, on: network.chainId)
    }

    @ViewBuilder
    func walletFreshWaitingRows(mask: String?, prices: [String: Double]) -> some View {
        ForEach(walletFreshWaiting) { entry in
            walletFreshWaitingRow(entry, mask: mask, prices: prices)
        }
    }

    private func walletFreshWaitingRow(_ entry: FreshAddress.Entry, mask: String?, prices: [String: Double]) -> some View {
        let symbol = entry.token
        let decimals = FreshTx.railgunToken(symbol: symbol)?.decimals ?? (symbol == "USDC" ? 6 : 18)
        let (amount, state): (String, String) = switch entry.state {
        case .needsGas(let amount): (amount, String(localized: "Needs a little private ETH"))
        case .failed(let amount): (amount, String(localized: "Not moved yet"))
        default: ("0", "")
        }
        let usd: Double? = {
            guard let price = prices[symbol.lowercased()], let units = Decimal(string: amount) else { return nil }
            return NSDecimalNumber(decimal: units / pow(10, decimals)).doubleValue * price
        }()
        let figure = mask ?? usd.map(WalletValue.exactMoney) ?? PrivateMoney.figure(amount, decimals: decimals, symbol: symbol)
        return Button {
            DSHaptic.selection()
            // Receive, where every address money reached has its Status line
            // (prd §1946; §1823's pinned address is every live one now).
            MoveMenu.pick(.receive, chrome)
        } label: {
            HStack(alignment: .center, spacing: DSRoomChassis.headGap) {
                Image(systemName: "clock")
                    .dsGlyph(.body, weight: .regular)
                    .foregroundStyle(DS.attention)
                    .frame(width: DSRoomChassis.headGlyph)
                    .accessibilityHidden(true)
                walletLedgerWords(symbol, held: Self.heldWords(amount, decimals: decimals), fact: state, factInk: DS.attentionInk)
                Spacer(minLength: DS.Space.s2)
                walletRowFigure(figure, tone: DS.textSecondary)
            }
            .walletTwoLineHead()
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .dsHover()
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(verbatim: [symbol, state, figure].joined(separator: ". ")))
        .accessibilityHint(Text("Opens the address it is waiting at"))
        .walletListRow()
    }

    /// **RAILGUN'S TOKENS IN THE PRIVATE BLOCK (prd §1713 items 1, 4 and 5,
    /// §1721).** Network · fact · place, the place last and no inline mark
    /// (§1718): "DAI — Ethereum · Railgun", the dollars trailing (the amount
    /// where Casberi has no price). What Railgun's screening has not yet
    /// listed reads "Private in about an hour", grey, behind a clock: a
    /// state, nobody waiting on you, never amber (item 5). A tap opens Send
    /// from it, which takes it back to your account (§1721 item 3).
    @ViewBuilder
    func walletRailgunRows(mask: String?) -> some View {
        let store = RailgunHoldings.shared
        ForEach(store.spendableShown) { h in
            // Under Railgun's header the line is its network (prd §1973 item 2).
            walletRailgunRow(h, units: h.spendable, line: String(localized: "Ethereum"), pending: false, mask: mask)
        }
        ForEach(store.pendingShown) { h in
            walletRailgunRow(h, units: h.pending, line: String(localized: "Private in about an hour"), pending: true, mask: mask)
        }
    }

    /// What your Tacit account held at its last reading, in dollars; 0 with
    /// no reading or no price.
    var walletTacitUSD: Double {
        TacitAccount.shared.countedUSD ?? 0
    }

    /// Your Tacit account in Holdings › Private: a row for its private ETH
    /// and one for its private TAC on the Tacit chain, each the door to its
    /// page. An account holding only TAC had no row and so no door here
    /// (user, 2026-11-24: "we don't have a way for someone to get to their
    /// tacit page").
    @ViewBuilder
    func walletTacitRow(mask: String?) -> some View {
        let tacit = TacitAccount.shared
        if let reading = tacit.reading, tacit.countedUSD != nil {
            // Under Tacit's header each line is its networks (prd §1973
            // item 2); dollars only where there is a price.
            if reading.eth > 0 {
                walletTacitLine("ETH", held: WalletValue.held(reading.eth), fact: tacitEthLine(reading, place: false),
                                figure: tacit.usd.map { mask ?? WalletValue.exactMoney($0) },
                                move: tacit.usd == nil ? nil : walletHoldingMoves[HoldingMoves.key("ETH")])
            }
            // **ON ITS WAY, AS RAILGUN'S AND AZTEC'S (prd §1983):** a deposit
            // handed and not yet taken, and TAC going back to public or to
            // another Tacit account, each a grey row behind a clock whose tap
            // opens its steps; a state, nobody waiting on you, never amber.
            ForEach(TacitShield.shared.arriving) { a in
                let usd = tacit.tacPrice.map { a.tac * $0 }
                walletTacitWaitingRow(OnItsWay.tacitIn(id: a.id, title: "\(TacitAccountRows.amount(a.tac)) TAC", usd: usd),
                                      line: String(localized: "Tacit · On its way"),
                                      figure: usd.map { mask ?? WalletValue.exactMoney($0) })
            }
            let out = TacitOut.shared
            if out.inFlight {
                let tac = Double(out.units) / 1e8
                let usd = tacit.tacPrice.map { tac * $0 }
                walletTacitWaitingRow(OnItsWay.tacitOut(id: "now", title: "\(TacitAccountRows.amount(tac)) TAC", usd: usd,
                                                        collecting: out.step == .collecting, paid: out.payTo != nil),
                                      line: out.payTo == nil ? String(localized: "Back to public · On its way")
                                          : String(localized: "Sent privately · On its way"),
                                      figure: usd.map { mask ?? WalletValue.exactMoney($0) })
            }
            if let tac = reading.privateTACAll, tac > 0 {
                // What the chain's fees added since the first reading that knew
                // the rate (user, 2026-11-24: "should we show rewards too a
                // user is earning?"), on the row since its page went (§1981).
                let earned = reading.earnedTAC.flatMap { $0 >= 0.0001 ? $0 : nil }
                let fact = earned.map { String(localized: "Tacit chain · earned \(TacitAccountRows.amount($0))") }
                    ?? String(localized: "Tacit chain")
                walletTacitLine("TAC", held: WalletValue.held(tac), fact: fact,
                                figure: tacit.privateTacUSD.map { mask ?? WalletValue.exactMoney($0) },
                                move: tacit.privateTacUSD == nil ? nil : walletHoldingMoves[HoldingMoves.key("TAC")])
            }
            // **YOUR FARMS (prd §1993):** each position its pair, with the TAC
            // it has earned and not claimed; its worth counts in Private.
            // Entered and left on Tacit's page, from Earn, so the row opens
            // nothing, as Tacit's other rows (§1981).
            ForEach(reading.farmed ?? []) { position in
                let earned = position.pendingTAC >= 0.0001
                    ? String(localized: "Tacit farm · earned \(TacitAccountRows.amount(position.pendingTAC))")
                    : String(localized: "Tacit farm")
                walletTacitLine(TacitFarms.name(position.pair), held: nil, fact: earned,
                                figure: tacit.farmUSD(position).map { mask ?? WalletValue.exactMoney($0) }, move: nil)
            }
        }
    }

    /// A Tacit move still travelling: the clock, grey words, its steps on tap.
    private func walletTacitWaitingRow(_ item: OnItsWay.Item, line: String, figure: String?) -> some View {
        Button {
            DSHaptic.selection()
            feedSheet = .onItsWay(item)
        } label: {
            HStack(alignment: .center, spacing: DSRoomChassis.headGap) {
                Image(systemName: "clock")
                    .dsGlyph(.body, weight: .regular)
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: DSRoomChassis.headGlyph)
                    .accessibilityHidden(true)
                walletLedgerWords("TAC", fact: line)
                Spacer(minLength: DS.Space.s2)
                walletFigureOverDay(figure, tone: DS.textSecondary, move: nil)
            }
            .walletTwoLineHead()
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .dsHover()
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(verbatim: [item.title, line, figure].compactMap { $0 }.joined(separator: ". ")))
    }

    /// A Tacit row states what is held; its verbs are Move's (Make private,
    /// back to public, prd §1976, §1977), so it opens nothing (§1981).
    private func walletTacitLine(_ symbol: String, held: String?, fact: String, figure: String?, move: Double?,
                                 factInk: Color = DS.textSecondary) -> some View {
        HStack(alignment: .center, spacing: DSRoomChassis.headGap) {
            AssetMark(name: symbol, size: DS.Mark.row)
                .frame(width: DSRoomChassis.headGlyph)
                .accessibilityHidden(true)
            walletLedgerWords(symbol, held: held, fact: fact, factInk: factInk)
            Spacer(minLength: DS.Space.s2)
            walletFigureOverDay(figure, move: move)
        }
        .walletTwoLineHead()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: [symbol, held, fact, figure].compactMap { $0 }.joined(separator: ". ")))
        .walletListRow()
    }

    private func walletRailgunRow(_ h: RailgunHoldings.Held, units: String, line: String, pending: Bool, mask: String?) -> some View {
        let store = RailgunHoldings.shared
        let figure = mask ?? store.usd(h, units: units).map(WalletValue.exactMoney)
            ?? RailgunHoldings.figure(units, decimals: h.decimals)
        // Its page, Send and Swap on it (user, 2026-11-21); Send opens with
        // your account in To, as the row's tap did (§1721 item 3).
        let usd = store.usd(h, units: units)
        let held = pending ? nil : Self.heldWords(units, decimals: h.decimals)
        let holding = WalletHolding(id: "railgun:" + h.id, symbol: h.symbol, figure: figure,
                                    usd: mask == nil ? usd : nil,
                                    line: pending ? line : String(localized: "Ethereum · Railgun"),
                                    verbs: pending ? [] : [.railgunSend(contract: h.contract), .railgunSwap(contract: h.contract)])
        return Button {
            DSHaptic.selection()
            // Still in Railgun's hour: its steps (prd §1787), nothing to move yet.
            if pending {
                let item = OnItsWay.railgun(id: h.id, title: RailgunHoldings.figure(h.pending, decimals: h.decimals) + " " + h.symbol,
                                            usd: store.usd(h, units: h.pending))
                feedSheet = .onItsWay(item)
                return
            }
            walletOpenHolding(holding)
        } label: {
            HStack(alignment: .center, spacing: DSRoomChassis.headGap) {
                Group {
                    if pending {
                        Image(systemName: "clock")
                            .dsGlyph(.body, weight: .regular)
                            .foregroundStyle(DS.textSecondary)
                    } else {
                        AssetMark(name: h.symbol, size: DS.Mark.row)
                    }
                }
                .frame(width: DSRoomChassis.headGlyph)
                .accessibilityHidden(true)
                walletLedgerWords(h.symbol, held: held, fact: line)
                Spacer(minLength: DS.Space.s2)
                walletFigureOverDay(figure, tone: pending ? DS.textSecondary : DS.textPrimary,
                                    move: pending || usd == nil ? nil : walletHoldingMoves[HoldingMoves.key(h.symbol)])
            }
            .walletTwoLineHead()
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .dsHover()
        .contextMenu { walletHoldingMenu(holding) }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(verbatim: [h.symbol, held, line, figure].compactMap { $0 }.joined(separator: ". ")))
        .walletListRow()
    }

    /// **ADD MONEY, THE LAST ROW UNDER PRIVATE (prd §1776, user: "i have a
    /// hard time getting money into my aztec account", then "'send to your
    /// private balance' is fine but need a 'add money'").** A verb, so a row
    /// (§746), last (§995), and it stays whether or not anything is held:
    /// the empty place's row went once money was in, and the only way back
    /// was a recipient in Send. The sentence it opens is Send's, unchanged.
    /// Which balance: the one you have; with both, Send's To list, which
    /// leads with the two and is told apart by network (§1719).
    @ViewBuilder
    var walletAddMoneyRow: some View {
        if selectedSeat == nil, !walletOnFollowing,
           selectedWallet.map(YourAccountDemo.isYours) ?? true,
           PrivateMove.available || Self.aztecTakesMoney {
            Button { walletAddMoney() } label: {
                HStack(alignment: .center, spacing: DSRoomChassis.headGap) {
                    Image(systemName: "plus")
                        .dsGlyph(.body)
                        .foregroundStyle(DS.pickInk)
                        .frame(width: DSRoomChassis.headGlyph)
                        .accessibilityHidden(true)
                    Text("Add money")
                        .dsText(.body17)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: DS.Space.s2)
                }
                .frame(minHeight: WalletCardStyle.ledgerHead)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPress())
            .dsHover()
            .accessibilityHint(Text("Sends to Privacy Pools"))
            .walletListRow()
        }
    }

    /// **THE SAVINGS GOAL'S STATUS, IN HOLDINGS (prd §1835, user: "agree
    /// roundups and savings goal move there. not the settings, just the
    /// status").** The goal counts both private balances (`savedNow`), so its
    /// row stands under Private, as Round-ups' stands in Public: "Savings
    /// goal" over "$300 of $1,000", the percent trailing. A fact, not a
    /// door: the goal is set on Account. Your own account only, and only
    /// once a goal is set; under Hide balances the line goes and the
    /// percent stays.
    @ViewBuilder
    func walletSavingsGoalRow(mask: String?) -> some View {
        if selectedSeat == nil, !walletOnFollowing,
           selectedWallet.map(YourAccountDemo.isYours) ?? true,
           let goal = SavingsGoalStore.shared.shown {
            let saved = SavingsGoal.savedNow()
            let line = mask == nil ? String(localized: "\(WalletValue.money(saved)) of \(WalletValue.money(goal.dollars))") : nil
            let percent = SavingsGoal.percent(saved: saved, goal: goal)
            HStack(alignment: .center, spacing: DSRoomChassis.headGap) {
                Image(systemName: "target")
                    .dsGlyph(.body)
                    .foregroundStyle(DS.brandInk)
                    .frame(width: DSRoomChassis.headGlyph)
                    .accessibilityHidden(true)
                walletLedgerWords(String(localized: "Savings goal"), fact: line)
                Spacer(minLength: DS.Space.s2)
                walletRowFigure(percent, tone: DS.textPrimary)
            }
            .walletTwoLineHead()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: [String(localized: "Savings goal"), line, percent].compactMap { $0 }.joined(separator: ". ")))
            .walletListRow()
        }
    }

    /// Whether Send offers your private balance on Aztec: its To list's own
    /// rule, so the door never promises a row the list will not draw.
    static var aztecTakesMoney: Bool {
        (YourAccountKey.address != nil || DemoMode.isActive) && AztecProver.isAvailable
    }

    func walletAddMoney() {
        DSHaptic.selection()
        switch (PrivateMove.available, Self.aztecTakesMoney) {
        case (true, true): chrome.moveDraft = MoveSentence.privateDraft()
        case (false, true): chrome.moveAztec = .deposit
        default: chrome.movePrivately = .deposit
        }
        chrome.moveTray = true
    }

    /// The private dollars the balance counts: Privacy Pools' held rows, your
    /// Aztec account's and Railgun's, as the Private section's head adds
    /// them (prd §1700e, §1721).
    var walletPrivateUSD: Double {
        let store = PrivateMoneyStore.shared
        let pools = store.rows.filter { $0.kind == .held }
            .compactMap { PrivateMoney.rowUSD($0, prices: store.shownPrices) }.reduce(0, +)
        let aztecStore = AztecAccountStore.shared
        let aztec = aztecStore.isShown
            ? aztecStore.privateHeld.compactMap { aztecStore.usd($0, units: $0.privateUnits) }.reduce(0, +) : 0
        let railgun = RailgunHoldings.shared
        return pools + aztec + railgun.shown.compactMap { railgun.usd($0, units: $0.amount) }.reduce(0, +)
    }

    /// Your private balance by token, in dollars: Privacy Pools' held notes
    /// and Railgun's, the money the Wallet counts as one "Private" venue.
    var walletPrivateByToken: [String: Double] {
        let store = PrivateMoneyStore.shared
        var out: [String: Double] = [:]
        for row in store.rows where row.kind == .held {
            if let usd = PrivateMoney.rowUSD(row, prices: store.shownPrices) {
                out[row.symbol.uppercased(), default: 0] += usd
            }
        }
        let railgun = RailgunHoldings.shared
        for held in railgun.shown {
            if let usd = railgun.usd(held, units: held.amount) { out[held.symbol.uppercased(), default: 0] += usd }
        }
        return out
    }

    /// **THE MAP IS TOKENS, WHOLE (prd §1809, user: "if it says public and
    /// private below it whats the point it should be aggregated … of
    /// tokens").** The read counts private money as one venue; the map
    /// folds it back into the tokens it is, so ETH is one tile at all of
    /// your ETH and the line under the map says how it splits.
    func walletMapDoc(_ shown: WalletPortfolio) -> [String] {
        WalletIngest.holdingsDoc(shown.foldingPrivate(walletPrivateByToken), appsApart: walletOnAll)
    }

    /// **PUBLIC AND PRIVATE, UNDER HOME'S BALANCE (prd §1807).** The balance
    /// said as its two halves, each a figure; the line opens Holdings, where
    /// both are listed. Yours and All only, as the Private section stands
    /// (§1590), and nothing while there is no balance to split.
    @ViewBuilder
    var walletPublicPrivateLine: some View {
        if selectedSeat == nil, !walletOnFollowing,
           selectedWallet.map(YourAccountDemo.isYours) ?? true,
           let total = portfolioShown?.totalUSD, total > 0 {
            let hidden = min(total, walletPrivateUSD)
            let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
            Button {
                DSHaptic.selection()
                chrome.walletSection = .holdings
            } label: {
                HStack(spacing: DS.Space.s4) {
                    walletHalf(String(localized: "Public"), mask ?? WalletValue.money(total - hidden))
                    walletHalf(String(localized: "Private"), mask ?? WalletValue.money(hidden))
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPress())
            .accessibilityElement(children: .combine)
        }
    }

    /// The line as the box's slot under its number; nil when it draws
    /// nothing, so the box leaves no gap for it.
    var walletPublicPrivateSlot: AnyView? {
        guard selectedSeat == nil, !walletOnFollowing,
              selectedWallet.map(YourAccountDemo.isYours) ?? true,
              let total = portfolioShown?.totalUSD, total > 0 else { return nil }
        return AnyView(walletPublicPrivateLine)
    }

    /// One half of the balance: its word in the secondary ink, its figure.
    private func walletHalf(_ word: String, _ figure: String) -> some View {
        HStack(spacing: DS.Space.s2) {
            Text(verbatim: word).dsText(.body17).foregroundStyle(DS.textSecondary)
            Text(verbatim: figure).dsText(.body17).monospacedDigit().foregroundStyle(DS.textPrimary)
        }
        .lineLimit(1)
    }

    /// The section's total: its places' sum, Home's Private dollar for
    /// dollar (prd §1973 item 7); with none to count (test money, §949), one
    /// token's quantity, else nothing.
    private func walletPrivateTotal(_ rows: [PrivateMoney.Row], prices: [String: Double], places: [HomePlace]) -> String? {
        let held = rows.filter { $0.kind == .held }
        let sum = places.reduce(0) { $0 + ($1.usd ?? 0) }
        if sum >= 0.01 || places.contains(where: { $0.usd != nil }) { return WalletValue.exactMoney(sum) }
        let usd = held.compactMap { PrivateMoney.rowUSD($0, prices: prices) }
        if !usd.isEmpty { return WalletValue.money(usd.reduce(0, +)) }
        guard held.count == 1, let only = held.first else { return nil }
        return PrivateMoney.figure(only.amount, decimals: only.decimals, symbol: only.symbol)
    }

    /// Opens Send privately (prd §1554): to your private balance from the
    /// header, from it (the switch on) from a row.
    func walletOpenPrivate(_ mode: PrivateMove.Mode) {
        DSHaptic.selection()
        chrome.movePrivately = mode
        chrome.moveTray = true
    }

    /// The head: the door anatomy (`walletDoor`), whose page is Move's
    /// private sentence.
    private func walletPrivateHead(total: String?) -> some View {
        Button { walletOpenPrivate(.deposit) } label: {
            HStack(alignment: .firstTextBaseline, spacing: DSRoomChassis.headGap) {
                Text("Private")
                    .dsText(.heading24)
                    .foregroundStyle(DS.headInk)
                    .lineLimit(1)
                Spacer(minLength: DS.Space.s2)
                if let total {
                    Text(verbatim: total)
                        .dsText(.stat24)
                        .monospacedDigit()
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                }
            }
            .walletRowPitch()
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .dsHover()
        .accessibilityLabel(Text(verbatim: [String(localized: "Private"), total].compactMap { $0 }.joined(separator: ". ")))
        .accessibilityHint(Text("Sends to Privacy Pools"))
        .walletListRow()
        // Where Privacy Pools' and Railgun's Library tiles land (prd §1738).
        .id(ShellChrome.privateAnchor)
        .task(id: chrome.walletScrollRequest) {
            guard chrome.walletScrollRequest == ShellChrome.privateAnchor else { return }
            try? await Task.sleep(for: .milliseconds(300))
            cardScrollTarget = ShellChrome.privateAnchor
            chrome.walletScrollRequest = nil
        }
    }

    /// One token in one state on one network: the preview row's anatomy
    /// (`walletPreviewRow`) with a line under the name — the network for
    /// private money, the state for the rest.
    private func walletPrivateRow(_ row: PrivateMoney.Row, mask: String?, prices: [String: Double]) -> some View {
        let figure = mask ?? PrivateMoney.rowUSD(row, prices: prices).map(WalletValue.exactMoney)
            ?? PrivateMoney.figure(row.amount, decimals: row.decimals, symbol: row.symbol)
        let (glyph, hue, state, stateInk): (String?, Color, String, Color) = switch row.kind {
        // What earns says so, in the one Holdings grammar (prd §1718,
        // network · fact · place): "Ethereum · 3.8% on Aave · Privacy Pools";
        // the rate unread, "Ethereum · On Aave · Privacy Pools".
        // A balance the last check proved does not match the chain says so,
        // in amber, in place of its line (prd §1569a).
        case .held where PrivateMoneyStore.shared.mismatched:
            (nil, DS.textSecondary, String(localized: "Doesn't match Ethereum"), DS.attentionInk)
        // Under Privacy Pools' header the line drops the place (prd §1973 item 2).
        case .held: (nil, DS.textSecondary, PrivateMoneyStore.shared.heldLine(row, place: false), DS.textSecondary)
        // Nobody waits on you (prd §1841): grey, and it says who it waits on.
        // Since when (prd §1938): the oldest deposit it sums, by day.
        case .waiting: ("clock", DS.textSecondary, PrivateMoney.beingChecked(since: PrivateMoneyStore.shared.notes
            .filter { $0.status == .waiting && $0.symbol == row.symbol && $0.chainId == row.chainId }.map(\.at).min()), DS.textSecondary)
        case .refused: ("xmark.circle", DS.destructive, String(localized: "Not approved"), DS.destructiveInk)
        }
        // Its page, Send on it (user, 2026-11-21), as every holding's.
        // Its page stands alone, so its line keeps the place.
        let holding = WalletHolding(id: "private:" + row.id, symbol: row.symbol, title: row.title, figure: figure,
                                    usd: mask == nil ? PrivateMoney.rowUSD(row, prices: prices) : nil,
                                    line: row.kind == .held && !PrivateMoneyStore.shared.mismatched
                                        ? PrivateMoneyStore.shared.heldLine(row) : state,
                                    verbs: [.privateSend])
        let usd = PrivateMoney.rowUSD(row, prices: prices)
        let held = row.kind == .held ? Self.heldWords(row.amount, decimals: row.decimals) : nil
        let move = row.kind == .held && usd != nil ? walletHoldingMoves[HoldingMoves.key(row.symbol)] : nil
        return Button {
            // Being checked: its steps (prd §1787), nothing to send yet, and
            // Take it back for the notes it sums (§1576, §1841).
            if row.kind == .waiting {
                let notes = PrivateMoneyStore.shared.notes.filter {
                    $0.status == .waiting && $0.symbol == row.symbol && $0.chainId == row.chainId
                }
                let item = OnItsWay.waitingApproval(id: row.id, title: PrivateMoney.figure(row.amount, decimals: row.decimals, symbol: row.symbol),
                                                    usd: PrivateMoney.rowUSD(row, prices: prices),
                                                    commitments: notes.map(\.commitment))
                DSHaptic.selection()
                feedSheet = .onItsWay(item)
            } else {
                walletOpenHolding(holding)
            }
        } label: {
            HStack(alignment: .center, spacing: DSRoomChassis.headGap) {
                Group {
                    if let glyph {
                        Image(systemName: glyph)
                            .dsGlyph(.body, weight: .regular)
                            .foregroundStyle(hue)
                    } else {
                        AssetMark(name: row.symbol, size: DS.Mark.row)
                    }
                }
                .frame(width: DSRoomChassis.headGlyph)
                .accessibilityHidden(true)
                // "ETH 0.0382" over "Ethereum · 1.5% on Aave".
                walletLedgerWords(row.title, held: held, fact: state, factInk: stateInk)
                Spacer(minLength: DS.Space.s2)
                walletFigureOverDay(figure, tone: row.kind == .held ? DS.textPrimary : DS.textSecondary, move: move)
            }
            .walletTwoLineHead()
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .dsHover()
        .contextMenu { if row.kind != .waiting { walletHoldingMenu(holding) } }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(verbatim: [row.title, held, state, figure].compactMap { $0 }.joined(separator: ". ")))
        .walletListRow()
    }
}

extension FeedScreen {
    /// Take it back on a deposit Privacy Pools is still checking (prd §1576,
    /// from its steps sheet since §1841): each note, one after another, as
    /// Needs you's row does it; a failure says its words.
    func walletTakeBack(_ commitments: [String]) {
        let wanted = Set(commitments.map { $0.lowercased() })
        let notes = PrivateMoneyStore.shared.notes.filter { wanted.contains($0.commitment.lowercased()) }
        guard !notes.isEmpty else { return }
        Task {
            for note in notes {
                let figure = PrivateMoney.Ask(note: note).figure
                if let hash = await PrivateTakeBack.shared.run(note, context: modelContext) {
                    DSHaptic.success()
                    chrome.flash(PrivateMoney.takenBackTitle(figure: figure, to: WalletPrivateAsks.owner), tone: .success)
                    NSLog("privateTakeBack| steps | %@", hash)
                } else {
                    if case .failed(let why) = PrivateTakeBack.shared.stage(note) { chrome.flash(why) }
                    break
                }
            }
            chrome.refreshRooms()
        }
    }
}

/// **NOT APPROVED, IN NEEDS YOU (prd §1561, narrowed by §1841).** One row
/// per deposit 0xBow's ASP refused (or wants a proof of): the red mark,
/// "0.0001 ETH not approved", and its line is the act, "Take it back": the
/// ragequit, a public exit to the address the deposit came from
/// (`PrivateTakeBack`), proved, run against the chain, then signed. A deposit
/// still being checked is not here: it asks nothing of you. The verb is a
/// word, never a pill; nothing explains it but the dialog that names where
/// the money goes.
struct WalletPrivateAsks: View {
    @Environment(ShellChrome.self) private var chrome
    @Environment(\.modelContext) private var context
    @State private var confirming: PrivateMoney.Ask?

    private var store: PrivateMoneyStore { .shared }
    private var taking: PrivateTakeBack { .shared }

    var body: some View {
        let asks = store.asks()
        if !asks.isEmpty {
            Section {
                ForEach(asks) { ask in row(ask) }
            }
            .task(id: asks.map(\.id)) {
                // The ASP is asked again while a row stands (spaced 20 s);
                // every root's notes on their cadence, and what was sent and
                // not seen asked about (the review of 2026-10-26, finding 2).
                while PrivateMoney.anyWaiting(store.notes), !Task.isCancelled {
                    await PrivateWatch.findNotes(context: context)
                    await store.refresh()
                    try? await Task.sleep(for: .seconds(20))
                }
            }
            .confirmationDialog(confirming.map { Text("Take back \($0.figure)?") } ?? Text(verbatim: ""),
                                isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                                titleVisibility: .visible, presenting: confirming) { ask in
                Button(String(localized: "Take it back")) { takeBack(ask) }
                Button(String(localized: "Cancel"), role: .cancel) {}
            } message: { ask in
                // Where it goes, on the network it is on, and what it gives up.
                Text(ask.note.chainId == PrivacyNetwork.ethereum.chainId
                     ? String(localized: "It goes back to your account on Ethereum, in public. This deposit won't be private.")
                     : String(localized: "It goes back to \(Self.owner) on Sepolia, in public."))
            }
        }
    }

    /// Where a ragequit pays: the account's owner, by its tail.
    static var owner: String {
        #if DEBUG
        PrivacyTestnetSender.address.map(YourAccount.short) ?? String(localized: "the address it came from")
        #else
        String(localized: "the address it came from")
        #endif
    }

    private func row(_ ask: PrivateMoney.Ask) -> some View {
        let stage = taking.stage(ask.note)
        let working = stage.map { if case .failed = $0 { false } else { true } } ?? false
        return DSPushRow(title: Text(verbatim: ask.title), subtitle: line(ask, stage: stage),
                         subtitleTone: DS.textSecondary, busy: working, opens: false) {
            guard !working else { return }
            confirming = ask
        } leading: {
            ZStack {
                Color.clear.frame(width: DS.Face.row, height: DS.Face.row)
                Image(systemName: "xmark.circle")
                    .dsGlyph(.body, weight: .semibold)
                    .foregroundStyle(DS.destructive)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityHint(Text("Returns it to the address it came from"))
        .walletListRow()
    }

    /// The line: where the take-back stands, else the act.
    private func line(_ ask: PrivateMoney.Ask, stage: PrivateTakeBack.Stage?) -> Text {
        if let stage {
            if case .failed = stage {
                return Text(verbatim: PrivateTakeBack.words(stage)).foregroundStyle(DS.attentionInk)
            }
            return Text(verbatim: PrivateTakeBack.words(stage))
        }
        return Text("Take it back").foregroundStyle(DS.destructiveInk)
    }

    private func takeBack(_ ask: PrivateMoney.Ask) {
        Task {
            guard let hash = await taking.run(ask.note, context: context) else { return }
            DSHaptic.success()
            chrome.flash(PrivateMoney.takenBackTitle(figure: ask.figure, to: Self.owner), tone: .success)
            chrome.refreshRooms()
            NSLog("privateTakeBack| row | %@", hash)
        }
    }
}

extension WalletPortfolio {
    /// The portfolio with its one "Private" venue folded into the tokens it
    /// holds (prd §1809), for the map. The venue's dollars are what moves:
    /// `byToken` gives the shares, so a price read a moment apart never
    /// changes the total. Unchanged with no such venue or nothing priced.
    func foldingPrivate(_ byToken: [String: Double]) -> WalletPortfolio {
        guard let i = positions.firstIndex(where: { $0.symbol == PrivateMoney.walletSymbol }) else { return self }
        let known = byToken.values.reduce(0, +)
        guard known > 0 else { return self }
        let venue = positions[i]
        let label = venue.holders.first?.label ?? String(localized: "Private")
        var out = self
        out.positions.remove(at: i)
        for (symbol, usd) in byToken.sorted(by: { $0.key < $1.key }) where usd > 0 {
            let add = venue.usd * usd / known
            let holder = Holder(address: PrivateMoney.holderID, label: label, usd: add)
            if let j = out.positions.firstIndex(where: { $0.symbol.uppercased() == symbol }) {
                let held = out.positions[j]
                out.positions[j] = Position(symbol: held.symbol, usd: held.usd + add, route: held.route,
                                            holders: held.holders + [holder], parts: held.parts)
            } else {
                out.positions.append(Position(symbol: symbol, usd: add, route: nil, holders: [holder]))
            }
        }
        out.positions.sort { $0.usd == $1.usd ? $0.symbol < $1.symbol : $0.usd > $1.usd }
        return out
    }
}

extension FeedScreen {
    /// **A LEDGER ROW'S WORDS (prd §1954, §1956):** the name, then one short
    /// fact after it in grey on the same line. The name never gives way; the
    /// fact is cut at its tail.
    func walletLedgerWords(_ name: String, held: String? = nil, fact: String?, factInk: Color = DS.textTertiary,
                           nameInk: Color = DS.textPrimary) -> some View {
        // **TWO LINES (user, 2026-11-25: "i just don't think we have room
        // with it all on one line if we want to show the full information";
        // amends §1954, §1956): the name over the whole line, network · fact
        // · place (§1718).** How many you hold after the name, grey, on every
        // token (prd §1973 item 1), as the Public rows draw it.
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                Text(verbatim: name)
                    .dsText(.body17)
                    .foregroundStyle(nameInk)
                    .lineLimit(1)
                    .layoutPriority(1)
                if let held {
                    Text(verbatim: held)
                        .dsText(.fact15)
                        .monospacedDigit()
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
            }
            if let fact, !fact.isEmpty {
                Text(verbatim: fact)
                    .dsText(.subhead12)
                    .foregroundStyle(factInk == DS.textTertiary ? DS.textSecondary : factInk)
                    .lineLimit(1)
            }
        }
    }
}

extension FeedScreen {
    /// **THE RIGHT SIDE OF A ROW (prd §1973 item 1):** the dollars over the
    /// day's move. No figure, nothing; a move that rounds to zero draws
    /// nothing (§83); the move never stands beside the dollars.
    func walletFigureOverDay(_ figure: String?, tone: Color = DS.textPrimary, move: Double?) -> some View {
        let day = move.map { WatchlistRules.change($0 * 100) }
        let moved = day.map { $0.tone == .up || $0.tone == .down } ?? false
        return VStack(alignment: .trailing, spacing: 2) {
            if let figure {
                walletRowFigure(figure, tone: tone)
            }
            if let day, moved, figure != nil {
                Text(verbatim: day.words)
                    .dsText(.subhead12)
                    .monospacedDigit()
                    .foregroundStyle(day.tone == .up ? DS.confirmInk : DS.destructiveInk)
                    .lineLimit(1)
            }
        }
    }

    /// How many of a token, from its base units: the amount beside a row's
    /// name (prd §1973 item 1), masked under Hide balances.
    static func heldWords(_ units: String, decimals: Int) -> String {
        let whole = (Decimal(string: units) ?? 0) / pow(10, decimals)
        return WalletValue.held(NSDecimalNumber(decimal: whole).doubleValue)
    }
}

extension View {
    /// **A Holdings row of two lines (user, 2026-11-25; amends §1954):** the
    /// name over its line, at the row's own height plus its List row's air,
    /// about 44pt (prd §1973 item 11, user: "should it be more compact in
    /// holdings"). No air of its own: that made 49.
    func walletTwoLineHead() -> some View {
        frame(minHeight: DSFeed.headHeight)
    }
}

extension FeedScreen {
    /// Where your Tacit account's private ETH sits: "Ethereum · Robinhood ·
    /// Tacit", by network, most first; "Tacit" alone with no split read.
    /// `place: false` under Tacit's own header (prd §1973 item 2).
    func tacitEthLine(_ reading: TacitAccount.Reading, place: Bool = true) -> String {
        let names = reading.held.filter { $0.eth > 0 }.sorted { $0.eth > $1.eth }.map(\.network)
        return (names + (place ? [TacitAccount.name] : [])).joined(separator: " · ")
    }
}
