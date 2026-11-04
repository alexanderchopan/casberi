import SwiftUI

/// **LENT, IN HOLDINGS (prd §1674).** Under Private: a head, "Lent", with
/// what is lent in dollars, then one row per market with something in it —
/// "USDC" over "5.1% on Aave · Base", its worth in dollars trailing (the
/// head already says lent). The head opens
/// Lend; a row opens Take back on its market. Your account only, as Private
/// is: a followed wallet's Aave stays under Positions.
///
/// What is lent is read off each aToken (`LendMove.read`), interest
/// included, so the figure grows between reads; the rate is Aave's today.
extension FeedScreen {

    @ViewBuilder
    var walletLentRows: some View {
        if AaveLend.on, selectedSeat == nil, !walletOnFollowing,
           selectedWallet.map(YourAccountDemo.isYours) ?? true, let account = YourAccountDemo.shownAddress {
            let lend = LendMove.holdings
            let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
            let prices = lend.prices
            let rows = AaveLend.markets.filter { (Decimal(string: lend.lent[LendMove.key($0)] ?? "0") ?? 0) > 0 }
            Group {
                walletLentHead(total: mask ?? walletLentTotal(rows, lend: lend, prices: prices))
                    .task(id: account) { await lend.read(account: account) }
                ForEach(rows, id: \.aToken) { m in
                    walletLentRow(m, lend: lend, mask: mask, prices: prices)
                }
                if lend.roundUps != "0" { walletRoundUpsRow(lend.roundUps, mask: mask) }
            }
        }
    }

    /// **ROUND-UPS, IN HOLDINGS (prd §1690).** Its own row under Lent, never
    /// one of its markets: "Round-ups" over "$6.20 of $10 on Aave · Base", the
    /// dollars trailing. What it holds is set aside, earning, and moves into
    /// your private balance at the figure the line names.
    private func walletRoundUpsRow(_ units: String, mask: String?) -> some View {
        let usd = RoundUpsPot.dollars(units)
        let figure = mask ?? WalletValue.money(usd)
        let at = RoundUpsPot.figure(RoundUpsPot.shownTarget)
        // Worded as a lent row is ("5.1% on Aave · Base"): both are Aave on Base.
        let state = [mask == nil ? String(localized: "\(RoundUpsPot.figure(units)) of \(at) on Aave") : String(localized: "On Aave"),
                     "Base"].joined(separator: " · ")
        return HStack(alignment: .center, spacing: DSRoomChassis.headGap) {
            AssetMark(name: "USDC", size: DS.Mark.badge)
                .frame(width: DSRoomChassis.headGlyph)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Round-ups")
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
                HStack(spacing: DS.Space.s1) {
                    ProtocolInlineMark(mark: "aave")
                    Text(verbatim: state)
                        .dsText(.subhead12)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: DS.Space.s2)
            walletRowFigure(figure, tone: DS.textPrimary)
        }
        .walletRowPitch()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: [String(localized: "Round-ups"), state, figure].joined(separator: ". ")))
        .walletListRow()
    }

    private func walletLentUSD(_ m: AaveLend.Market, lend: LendMove, prices: [String: Double]) -> Double? {
        guard let price = prices[m.symbol.lowercased()], let units = Decimal(string: lend.lent[LendMove.key(m)] ?? "") else { return nil }
        return NSDecimalNumber(decimal: units / pow(10, m.decimals)).doubleValue * price
    }

    private func walletLentTotal(_ rows: [AaveLend.Market], lend: LendMove, prices: [String: Double]) -> String? {
        let usd = rows.compactMap { walletLentUSD($0, lend: lend, prices: prices) }
        return usd.isEmpty || usd.count < rows.count ? nil : WalletValue.money(usd.reduce(0, +))
    }

    private func walletOpenLend(_ mode: LendMove.Mode, _ m: AaveLend.Market? = nil) {
        DSHaptic.selection()
        if let m {
            LendMove.opening = (m.chainId, m.symbol)
        }
        chrome.moveLend = mode
        chrome.moveTray = true
    }

    /// The head: Private's anatomy, the percent glyph, opening Lend.
    private func walletLentHead(total: String?) -> some View {
        Button { walletOpenLend(.lend) } label: {
            HStack(alignment: .firstTextBaseline, spacing: DSRoomChassis.headGap) {
                Image(systemName: "percent")
                    .dsGlyph(.body)
                    .foregroundStyle(DS.pickInk)
                    .frame(width: DSRoomChassis.headGlyph)
                    .accessibilityHidden(true)
                Text("Lent")
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
        .accessibilityLabel(Text(verbatim: [String(localized: "Lent"), total].compactMap { $0 }.joined(separator: ". ")))
        .accessibilityHint(Text("Lends on Aave"))
        .walletListRow()
    }

    private func walletLentRow(_ m: AaveLend.Market, lend: LendMove, mask: String?, prices: [String: Double]) -> some View {
        let units = lend.lent[LendMove.key(m)] ?? "0"
        let figure = mask ?? walletLentUSD(m, lend: lend, prices: prices).map(WalletValue.money)
            ?? PrivateMoney.figure(units, decimals: m.decimals, symbol: m.symbol)
        let title = m.symbol
        let state = [AaveLend.rateLine(lend.rates[LendMove.key(m)]), m.network].compactMap { $0 }.joined(separator: " · ")
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
                    // Who holds it, its mark before the rate (prd §1685); the
                    // token's mark leads, so Aave's never stands for the coin.
                    HStack(spacing: DS.Space.s1) {
                        ProtocolInlineMark(mark: "aave")
                        Text(verbatim: state)
                            .dsText(.subhead12)
                            .foregroundStyle(DS.textSecondary)
                            .lineLimit(1)
                    }
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
