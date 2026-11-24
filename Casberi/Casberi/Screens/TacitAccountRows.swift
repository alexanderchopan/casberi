import SwiftUI

/// YOUR TACIT ACCOUNT'S PAGE: A MAP OF IT BY NETWORK, THEN FOUR LISTS.
///
/// Balance, Receive, How hidden and Opened by (the ruling of 2026-11-24, of
/// `design/mockups/tacit-account.html`, version C). Closed, the page is one
/// row, Open, over the last reading and its date when there is one. Nothing
/// on it sends.
struct TacitAccountRows: View {
    @Bindable var account = TacitAccount.shared
    /// The wallet app that holds each co-signer key, once a session names it.
    @State private var walletName: String?
    @State private var copied: String?

    private var coSigner: String? { YourAccountFacts.coSigners.first }

    var body: some View {
        let reading = account.reading
        Section {
            if let reading, reading.eth > 0 {
                map(reading).walletListRow()
            }
            state.walletListRow()
        }
        if let reading {
            balance(reading)
            receive(reading)
            hidden(reading)
        }
        Section {
            head(String(localized: "Opened by"), figure: nil).walletListRow()
            opener.walletListRow()
            if reading == nil {
                DSFootnote("Your co-signer signs Tacit's own message. Casberi reads the account and cannot move its money.")
                    .walletListRow()
            }
        }
        .task(id: coSigner) {
            guard let coSigner else { return }
            walletName = YourAccountSignerLink.walletHolding(coSigner)?.name
        }
    }

    // MARK: - The box

    /// Your money by network: Holdings' own map, a tile per network.
    private func map(_ reading: TacitAccount.Reading) -> some View {
        let price = account.ethPrice
        let tiles = reading.held.filter { $0.eth > 0 }.map { held in
            HoldingsTreemap.Holding(id: held.network, usd: price.map { held.eth * $0 } ?? held.eth, route: nil,
                                    display: price == nil ? WalletValue.token(held.eth, "ETH") : nil)
        }
        return HoldingsTreemap(total: account.usd.map(WalletValue.exactMoney) ?? WalletValue.token(reading.eth, "ETH"),
                               holdings: tiles, showsShares: tiles.count > 1)
            .frame(minHeight: DSRoomChassis.leadBox, maxHeight: DSRoomChassis.leadBox)
    }

    // MARK: - Open, reading, closed

    @ViewBuilder private var state: some View {
        switch account.phase {
        case .connecting:
            waiting(String(localized: "Connecting"))
        case .signing:
            waiting(String(localized: "Asking your co-signer"))
        case .reading:
            waiting(String(localized: "Reading Tacit"))
        case .open:
            EmptyView()
        case .closed, .failed:
            VStack(alignment: .leading, spacing: 0) {
                if case .failed(let why) = account.phase {
                    Text(verbatim: why).dsText(.body17).foregroundStyle(DS.destructiveInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .walletRowPitch()
                }
                if let reading = account.reading {
                    Text("as of \(AccountPageShape.ago(reading.asOf))")
                        .dsText(.subhead12)
                        .foregroundStyle(DS.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func waiting(_ words: String) -> some View {
        HStack(spacing: DS.Space.s2) {
            DSSpinner()
            Text(verbatim: words).dsText(.body17).foregroundStyle(DS.textSecondary)
            Spacer(minLength: 0)
        }
        .walletRowPitch()
    }

    // MARK: - The lists

    @ViewBuilder private func balance(_ reading: TacitAccount.Reading) -> some View {
        Section {
            head(String(localized: "Balance"),
                 figure: account.usd.map(WalletValue.exactMoney) ?? WalletValue.token(reading.eth, "ETH"))
                .walletListRow()
            ForEach(reading.held) { held in
                line("ETH", fact: String(localized: "\(held.network) · Private"),
                     figure: account.usd(held).map(WalletValue.exactMoney) ?? WalletValue.token(held.eth, "ETH"),
                     figureInk: held.reached ? DS.textPrimary : DS.textSecondary)
                    .walletListRow()
                // Public: at your public address, not yet in the pool. Always
                // drawn, as Tacit draws both (user, 2026-11-24).
                line("ETH", fact: String(localized: "\(held.network) · Public"),
                         figure: account.ethPrice.map { WalletValue.exactMoney(held.waiting * $0) }
                            ?? WalletValue.token(held.waiting, "ETH"),
                         figureInk: DS.textSecondary)
                    .walletListRow()
            }
        }
    }

    @ViewBuilder private func receive(_ reading: TacitAccount.Reading) -> some View {
        Section {
            head(String(localized: "Receive"), figure: nil).walletListRow()
            copyRow(String(localized: "Private address"),
                    fact: String(localized: "From a Tacit account · \(AddressTail.short(reading.address))"),
                    value: reading.address)
                .walletListRow()
            if !reading.receive.isEmpty {
                copyRow(String(localized: "Public address"),
                        fact: String(localized: "From any wallet or exchange · \(AddressTail.short(reading.receive))"),
                        value: reading.receive)
                    .walletListRow()
            }
        }
    }

    @ViewBuilder private func hidden(_ reading: TacitAccount.Reading) -> some View {
        let pools = reading.held.filter { $0.pool != nil }
        if !pools.isEmpty {
            Section {
                head(String(localized: "How hidden"), figure: nil).walletListRow()
                ForEach(pools) { held in
                    let share = TacitAccount.share(held)
                    let thin = (share ?? 0) >= TacitAccount.thinShare
                    line(held.network,
                         fact: String(localized: "\((held.pool ?? 0).formatted(.number.precision(.significantDigits(2...3)))) ETH in the pool"),
                         factInk: thin ? DS.attentionInk : DS.textTertiary,
                         figure: share.map { String(localized: "\(Int(($0 * 100).rounded()))% yours") } ?? "",
                         figureInk: thin ? DS.attentionInk : DS.textSecondary)
                        .walletListRow()
                }
            }
        }
    }

    /// The co-signer's wallet, and the page's one verb: Open, or Close.
    @ViewBuilder private var opener: some View {
        if DemoMode.isActive {
            // The demo's account is always open and nothing closes it, so
            // the row states the wallet and offers no verb (§83).
            words(String(localized: "Your co-signer"), fact: AddressTail.short(YourAccountDemo.signer))
                .frame(maxWidth: .infinity, alignment: .leading)
                .walletRowPitch()
        } else if let coSigner {
            let busy = account.phase == .connecting || account.phase == .signing || account.phase == .reading
            Button {
                DSHaptic.tap()
                if account.phase == .open { account.close() } else { Task { await account.open(coSigner: coSigner) } }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    words(walletName ?? String(localized: "Your co-signer"), fact: AddressTail.short(coSigner))
                    Spacer(minLength: DS.Space.s2)
                    Text(account.phase == .open ? "Close" : "Open")
                        .dsText(.body17)
                        .foregroundStyle(busy ? DS.textTertiary : DS.pickInk)
                }
                .walletRowPitch()
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPress())
            .disabled(busy)
        } else {
            words(String(localized: "No co-signer yet"), fact: String(localized: "Your account's second key opens Tacit"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .walletRowPitch()
        }
    }

    // MARK: - The parts

    /// A section's name at the section rung, its figure trailing (prd §1496).
    private func head(_ name: String, figure: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DSRoomChassis.headGap) {
            Text(verbatim: name).dsText(.heading24).foregroundStyle(DS.headInk).lineLimit(1)
            Spacer(minLength: DS.Space.s2)
            if let figure {
                Text(verbatim: figure).dsText(.stat24).monospacedDigit().foregroundStyle(DS.textPrimary).lineLimit(1)
            }
        }
        .walletRowPitch()
    }

    /// A name and its grey fact on one line (prd §1954).
    private func words(_ name: String, fact: String, factInk: Color = DS.textTertiary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            Text(verbatim: name).dsText(.body17).foregroundStyle(DS.textPrimary).lineLimit(1).layoutPriority(1)
            Text(verbatim: fact).dsText(.fact15).foregroundStyle(factInk).lineLimit(1)
        }
    }

    private func line(_ name: String, fact: String, factInk: Color = DS.textTertiary,
                      figure: String, figureInk: Color = DS.textPrimary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            words(name, fact: fact, factInk: factInk)
            Spacer(minLength: DS.Space.s2)
            Text(verbatim: figure).dsText(.price17).monospacedDigit().foregroundStyle(figureInk).lineLimit(1)
        }
        .walletRowPitch()
    }

    /// An address, by name and tail; a tap copies it and says so.
    private func copyRow(_ name: String, fact: String, value: String) -> some View {
        Button {
            DSPasteboard.copy(value)
            DSHaptic.tap()
            withAnimation(DS.Motion.standard) { copied = value }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                if copied == value { withAnimation(DS.Motion.standard) { copied = nil } }
            }
        } label: {
            HStack(spacing: DS.Space.s2) {
                // The name over its line, as a co-signer's row reads
                // (`WalletCoSignerRows`): the tail is what is checked, so it
                // is never the part a narrow screen cuts.
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: name).dsText(.body17).foregroundStyle(DS.textPrimary).lineLimit(1)
                    Text(verbatim: fact).dsText(.subhead12).foregroundStyle(DS.textTertiary).lineLimit(1)
                }
                .layoutPriority(1)
                Spacer(minLength: DS.Space.s2)
                Text(copied == value ? "Copied" : "Copy").dsText(.body17).foregroundStyle(DS.pickInk)
            }
            .walletRowPitch()
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
    }
}
