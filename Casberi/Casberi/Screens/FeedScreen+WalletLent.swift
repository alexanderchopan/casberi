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

    /// One row of Public (prd §1718): a token held idle, a token lent, or
    /// Round-ups; sorted together by worth, so a lent USDC stands where its
    /// dollars put it among the idle ones.
    enum PublicRow: Identifiable {
        case token(WalletPortfolio.Position)
        case lent(AaveLend.Market)
        case roundUps(String)
        var id: String {
            switch self {
            case .token(let p): "token:" + p.id
            case .lent(let m): "lent:" + m.aToken
            case .roundUps: "roundups"
            }
        }
    }

    /// Public's preview rows: the top tokens and every lent row, by worth.
    func walletPublicRows(tokens: [WalletPortfolio.Position], lent: (lend: LendMove, account: String, rows: [AaveLend.Market], roundUps: String?)?) -> [PublicRow] {
        var rows: [(usd: Double, row: PublicRow)] = tokens.map { ($0.usd, .token($0)) }
        if let lent {
            for m in lent.rows { rows.append((walletLentUSD(m, lend: lent.lend, prices: lent.lend.prices) ?? 0, .lent(m))) }
            if let units = lent.roundUps { rows.append((RoundUpsPot.dollars(units), .roundUps(units))) }
        }
        return rows.sorted { $0.usd > $1.usd }.map(\.row)
    }

    /// **ROUND-UPS, IN HOLDINGS (prd §1690).** Its own row in Public, never
    /// one of its markets: "Round-ups" over "Base · $6.20 of $10 · Aave", the
    /// dollars trailing. What it holds is set aside, earning, and moves into
    /// your private balance at the figure the line names.
    func walletRoundUpsRow(_ units: String, mask: String?) -> some View {
        let usd = RoundUpsPot.dollars(units)
        let figure = mask ?? WalletValue.money(usd)
        let at = RoundUpsPot.targetWords
        // Worded as a lent row is ("Base · 5.1% · Aave", prd §1718: network
        // · fact · place): both are Aave on Base.
        let state = (["Base"] + (mask == nil ? [String(localized: "\(RoundUpsPot.figure(units)) of \(at)")] : []) + ["Aave"])
            .joined(separator: " · ")
        return HStack(alignment: .center, spacing: DSRoomChassis.headGap) {
            AssetMark(name: "USDC", size: DS.Mark.badge)
                .frame(width: DSRoomChassis.headGlyph)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Round-ups")
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
                // The line's words carry the place (prd §1718): no small mark
                // beside them, which read as a second token.
                Text(verbatim: state)
                    .dsText(.subhead12)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: DS.Space.s2)
            walletRowFigure(figure, tone: DS.textPrimary)
        }
        .walletRowPitch()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: [String(localized: "Round-ups"), state, figure].joined(separator: ". ")))
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
        let figure = mask ?? walletLentUSD(m, lend: lend, prices: prices).map(WalletValue.money)
            ?? PrivateMoney.figure(units, decimals: m.decimals, symbol: m.symbol)
        let title = m.symbol
        // Network · fact · place (prd §1718): "Base · 5.1% · Aave"; the rate
        // unread, "Base · Aave".
        let state = [m.network, AaveLend.rateOnly(lend.rates[LendMove.key(m)]), "Aave"].compactMap { $0 }.joined(separator: " · ")
        return Button { walletOpenLend(.takeBack, m) } label: {
            HStack(alignment: .center, spacing: DSRoomChassis.headGap) {
                AssetMark(name: m.symbol, size: DS.Mark.badge)
                    .frame(width: DSRoomChassis.headGlyph)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title)
                        .dsText(.body17)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                    // The line's words carry the place (prd §1718, amending
                    // §1685's mark before the rate): "Base · 5.1% · Aave".
                    Text(verbatim: state)
                        .dsText(.subhead12)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: DS.Space.s2)
                walletRowFigure(figure, tone: DS.textPrimary)
            }
            .walletRowPitch()
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .dsHover()
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(verbatim: [title, state, figure].joined(separator: ". ")))
        .accessibilityHint(Text("Takes it back"))
        .walletListRow()
    }
}
