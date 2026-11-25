import SwiftUI

/// **LENT, IN HOLDINGS (prd §1674, §1695).** Over Private: a head, "Lent", with
/// what is lent in dollars, then one row per market with something in it —
/// "USDC" over "Base · 5.1% · Aave", its worth in dollars trailing (the
/// head already says lent). The head opens
/// Lend; a row opens Take back on its market. Your account only, as Private
/// is: a followed wallet's Aave stays under Positions.
///
/// What is lent is read off each aToken (`LendMove.read`), interest
/// included, so the figure grows between reads; the rate is Aave's today.
extension FeedScreen {

    /// **LENT MONEY STANDS IN PUBLIC (prd §1718, option B; retires §1695's
    /// Lent head).** Lent is a fact on a row, not a section: private money
    /// is lent too (on Aave inside Privacy Pools), so a "Lent" section could
    /// never hold all of it. What Aave holds for you on the open chain is
    /// listed among the public rows by worth, each line saying so ("Base ·
    /// 5.1% · Aave"); the Public head's figure counts it (`standing`, a last
    /// reading included, §1697). nil when nothing here is yours to lend.
    var walletLentStanding: (lend: LendMove, account: String, rows: [AaveLend.Market], roundUps: String?)? {
        guard AaveLend.on, selectedSeat == nil, !walletOnFollowing,
              selectedWallet.map(YourAccountDemo.isYours) ?? true, let account = YourAccountDemo.shownAddress else { return nil }
        let lend = LendMove.holdings
        let rows = AaveLend.markets.filter { (Decimal(string: lend.lent[LendMove.key($0)] ?? "0") ?? 0) > 0 }
        return (lend, account, rows, lend.roundUps != "0" ? lend.roundUps : nil)
    }

    /// One row of Public (prd §1718, §1973): a token held idle on one
    /// network, a token lent there, or Round-ups; sorted together by worth
    /// under their network.
    enum PublicRow: Identifiable {
        /// What you hold of one token on one network (prd §1973 item 4): its
        /// dollars and count there; the tap still opens the whole token.
        case held(WalletPortfolio.Position, network: String, usd: Double, amount: Double?)
        case lent(AaveLend.Market)
        case roundUps(String)
        /// AZTEC asked back from Olla (prd §1970): waiting, or ready to claim.
        case ollaBack(units: String, ready: Bool)
        var id: String {
            switch self {
            case .held(let p, let network, _, _): "held:" + network + ":" + p.id
            case .lent(let m): "lent:" + m.aToken
            case .roundUps: "roundups"
            case .ollaBack(_, let ready): ready ? "olla:ready" : "olla:waiting"
            }
        }
    }

    /// One network of Public: Home's line for it, and its rows by worth.
    struct PublicNetwork: Identifiable {
        let place: HomePlace
        let rows: [PublicRow]
        /// Tokens left to "See all" (the cap, `publicNetworkCap`).
        let cut: Bool
        var id: String { place.id }
    }

    /// How many idle tokens one network lists before "See all".
    static let publicNetworkCap = 5

    /// The network ids Aave's markets sit on, as a part's key names them.
    static let lentNetworkIDs: [Int: String] = [8453: "base-mainnet", 1: "eth-mainnet"]

    /// **PUBLIC BY NETWORK (prd §1973 item 4; user, 2026-11-25: "i think we
    /// should do it by network bc it gets hard to process mentally", "look
    /// how organized private looks").** Each network Home lists, in Home's
    /// order, under Home's line (`homePublicPlaces`); under it what you hold
    /// there, by worth: a token's share on that network, and money lent
    /// there. A token on three networks is a row under each; its tap opens
    /// the token, whole. A token read by no contract and no route stands
    /// last under no header, never left out.
    func walletPublicNetworks(tokens: [WalletPortfolio.Position],
                              lent: (lend: LendMove, account: String, rows: [AaveLend.Market], roundUps: String?)?) -> [PublicNetwork] {
        var by: [String: [(usd: Double, row: PublicRow)]] = [:]
        for p in tokens where p.usd > 0 {
            let partsUSD = p.parts.reduce(0) { $0 + $1.usd }
            var nets: [String: (usd: Double, amount: Double?, count: Int)] = [:]
            for part in p.parts {
                let network = String(part.key.split(separator: ":", maxSplits: 1).first ?? Substring(part.key))
                let was = nets[network]
                // A count only when every part there has one, never a short one.
                let amount: Double? = was == nil ? part.amount : (was?.amount).flatMap { a in part.amount.map { a + $0 } }
                nets[network] = ((was?.usd ?? 0) + part.usd, amount, (was?.count ?? 0) + 1)
            }
            for (network, n) in nets {
                // The token's worth shared over its networks by their parts,
                // as Home shares it (`homePublicPlaces`).
                let usd = partsUSD > 0 ? p.usd * n.usd / partsUSD : p.usd * Double(n.count) / Double(p.parts.count)
                by[network, default: []].append((usd, .held(p, network: network, usd: usd, amount: n.amount)))
            }
            if p.parts.isEmpty {
                let network = p.route.flatMap { $0.split(separator: ":", maxSplits: 1).first.map(String.init) } ?? ""
                by[network, default: []].append((p.usd, .held(p, network: network, usd: p.usd, amount: p.amount)))
            }
        }
        var cut: Set<String> = []
        for (network, rows) in by {
            let sorted = rows.sorted { $0.usd > $1.usd }
            if sorted.count > Self.publicNetworkCap { cut.insert(network) }
            by[network] = Array(sorted.prefix(Self.publicNetworkCap))
        }
        if let lent {
            for m in lent.rows {
                by[Self.lentNetworkIDs[m.chainId] ?? "base-mainnet", default: []]
                    .append((walletLentUSD(m, lend: lent.lend, prices: lent.lend.prices) ?? 0, .lent(m)))
            }
            if let units = lent.roundUps {
                by["base-mainnet", default: []].append((RoundUpsPot.dollars(units), .roundUps(units)))
            }
            if let m = AaveLend.olla {
                for ready in [true, false] {
                    let units = lent.lend.ollaBack(ready: ready)
                    guard (Decimal(string: units) ?? 0) > 0 else { continue }
                    by[Self.lentNetworkIDs[m.chainId] ?? "eth-mainnet", default: []]
                        .append((lent.lend.dollars(units, in: m) ?? 0, .ollaBack(units: units, ready: ready)))
                }
            }
        }
        var places = homePublicPlaces().filter { by[$0.id] != nil }
        for network in by.keys.sorted() where !network.isEmpty && !places.contains(where: { $0.id == network }) {
            places.append(HomePlace(id: network, name: HiddenTokens.place("\(network):native"),
                                    usd: by[network]?.reduce(0) { $0 + $1.usd }))
        }
        if by[""] != nil { places.append(HomePlace(id: "", name: "", usd: nil)) }
        return places.map { place in
            PublicNetwork(place: place, rows: (by[place.id] ?? []).sorted { $0.usd > $1.usd }.map(\.row),
                          cut: cut.contains(place.id))
        }
    }

    /// **ROUND-UPS, IN HOLDINGS (prd §1690).** Its own row in Public, never
    /// one of its markets: "Round-ups" over "Base · $6.20 of $10 · Aave", the
    /// dollars trailing. What it holds is set aside, earning, and moves into
    /// your private balance at the figure the line names.
    func walletRoundUpsRow(_ units: String, mask: String?) -> some View {
        let usd = RoundUpsPot.dollars(units)
        let figure = mask ?? WalletValue.exactMoney(usd)
        let at = RoundUpsPot.targetWords
        // Worded as a lent row is ("Base · 5.1% · Aave", prd §1718: network
        // · fact · place): both are Aave on Base.
        // **A USDC ROW (prd §1973 item 8):** the token on top, Round-ups the
        // fact: "USDC 3.78" over "Base · Round-ups, $3.78 of $10 · Aave".
        let pot = mask == nil ? String(localized: "Round-ups, \(RoundUpsPot.figure(units)) of \(at)") : String(localized: "Round-ups")
        // Under Base's header the row drops the network (prd §1973 item 2);
        // its own page keeps it.
        let state = [pot, "Aave"].joined(separator: " · ")
        let full = ["Base", pot, "Aave"].joined(separator: " · ")
        // Its page like every holding's (user, 2026-11-21). No verb: the pot
        // moves itself into your private balance at its figure.
        let holding = WalletHolding(id: "roundups", symbol: "USDC", title: String(localized: "Round-ups"),
                                    figure: figure, usd: mask == nil ? usd : nil, line: full, verbs: [])
        return Button { walletOpenHolding(holding) } label: {
            walletRoundUpsLabel(figure: figure, held: FeedScreen.heldWords(units, decimals: RoundUpsPot.decimals), state: state)
        }
        .buttonStyle(RowPress())
        .dsHover()
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(verbatim: ["USDC", state, figure].joined(separator: ". ")))
        .walletListRow()
    }

    private func walletRoundUpsLabel(figure: String, held: String, state: String) -> some View {
        HStack(alignment: .center, spacing: DSRoomChassis.headGap) {
            AssetMark(name: "USDC", size: DS.Mark.row)
                .frame(width: DSRoomChassis.headGlyph)
                .accessibilityHidden(true)
            // Two lines (2026-11-25, amends §1954): the name over network ·
            // fact · place, no small mark beside them (§1718).
            walletLedgerWords("USDC", held: held, fact: state)
            Spacer(minLength: DS.Space.s2)
            walletRowFigure(figure, tone: DS.textPrimary)
        }
        .walletTwoLineHead()
        .contentShape(Rectangle())
    }

    /// **AZTEC ON ITS WAY BACK FROM OLLA (prd §1970):** "AZTEC" over "On its
    /// way · Olla" while the queue holds it, "Ready to claim · Olla" in the
    /// attention ink once it can be claimed; a tap opens Withdraw on Olla,
    /// which claims what is ready.
    func walletOllaBackRow(_ units: String, ready: Bool, lend: LendMove, mask: String?) -> some View {
        let m = AaveLend.olla
        let usd = m.flatMap { lend.dollars(units, in: $0) }
        let figure = usd.map { mask ?? WalletValue.exactMoney($0) }
        let word = ready ? String(localized: "Ready to claim") : String(localized: "On its way")
        return Button { walletOpenLend(.takeBack, m) } label: {
            HStack(alignment: .center, spacing: DSRoomChassis.headGap) {
                AssetMark(name: "AZTEC", size: DS.Mark.row)
                    .frame(width: DSRoomChassis.headGlyph)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                        Text(verbatim: "AZTEC")
                            .dsText(.body17)
                            .foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                            .layoutPriority(1)
                        // How many (prd §1973 item 1).
                        Text(verbatim: FeedScreen.heldWords(units, decimals: 18))
                            .dsText(.fact15)
                            .monospacedDigit()
                            .foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                    }
                    // Under its network's header (prd §1973 item 2).
                    (Text(verbatim: word).foregroundStyle(ready ? DS.attentionInk : DS.textSecondary)
                     + Text(verbatim: " · Olla").foregroundStyle(DS.textSecondary))
                        .dsText(.subhead12)
                        .lineLimit(1)
                }
                Spacer(minLength: DS.Space.s2)
                walletFigureOverDay(figure, move: usd == nil ? nil : walletHoldingMoves[HoldingMoves.key("AZTEC")])
            }
            .walletTwoLineHead()
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .dsHover()
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(verbatim: ["AZTEC", word, "Olla", figure].compactMap { $0 }.joined(separator: ". ")))
        .walletListRow()
    }

    func walletLentUSD(_ m: AaveLend.Market, lend: LendMove, prices: [String: Double]) -> Double? {
        guard let price = prices[m.symbol.lowercased()], let units = Decimal(string: lend.lent[LendMove.key(m)] ?? "") else { return nil }
        return NSDecimalNumber(decimal: units / pow(10, m.decimals)).doubleValue * price
    }

    func walletOpenLend(_ mode: LendMove.Mode, _ m: AaveLend.Market? = nil) {
        DSHaptic.selection()
        if let m {
            LendMove.opening = (m.chainId, m.symbol)
        }
        chrome.moveLend = mode
        chrome.moveTray = true
    }

    func walletLentRow(_ m: AaveLend.Market, lend: LendMove, mask: String?, prices: [String: Double]) -> some View {
        let units = lend.lent[LendMove.key(m)] ?? "0"
        let usd = walletLentUSD(m, lend: lend, prices: prices)
        let figure = mask ?? usd.map(WalletValue.exactMoney)
            ?? PrivateMoney.figure(units, decimals: m.decimals, symbol: m.symbol)
        let title = m.symbol
        let held = Self.heldWords(units, decimals: m.decimals)
        // Network · fact · place (prd §1718): "Base · 5.1% · Aave"; the rate
        // unread, "Base · Aave".
        let fact = [AaveLend.rateOnly(lend.rates[LendMove.key(m)]), m.placeName].compactMap { $0 }
        // Under its network's header the row drops the network (prd §1973
        // item 2): "5.1% · Aave"; its own page keeps it.
        let line = fact.joined(separator: " · ")
        let state = ([m.network] + fact).joined(separator: " · ")
        // Its page, Withdraw and Deposit on it (user, 2026-11-21): a tap
        // never jumps straight into Move.
        let holding = WalletHolding(id: "lent:" + m.aToken, symbol: m.symbol, figure: figure,
                                    usd: mask == nil ? walletLentUSD(m, lend: lend, prices: prices) : nil, line: state,
                                    verbs: [.lendWithdraw(chainId: m.chainId, symbol: m.symbol),
                                            .lendDeposit(chainId: m.chainId, symbol: m.symbol)])
        return Button { walletOpenHolding(holding) } label: {
            HStack(alignment: .center, spacing: DSRoomChassis.headGap) {
                AssetMark(name: m.symbol, size: DS.Mark.row)
                    .frame(width: DSRoomChassis.headGlyph)
                    .accessibilityHidden(true)
                // Two lines (2026-11-25): network · fact · place (§1718).
                walletLedgerWords(title, held: held, fact: line)
                Spacer(minLength: DS.Space.s2)
                walletFigureOverDay(usd == nil && mask == nil ? nil : figure,
                                    move: usd == nil ? nil : walletHoldingMoves[HoldingMoves.key(m.symbol)])
            }
            .walletTwoLineHead()
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .dsHover()
        .contextMenu { walletHoldingMenu(holding) }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(verbatim: [title, held, line, figure].joined(separator: ". ")))
        .walletListRow()
    }
}
