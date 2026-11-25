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
    @Environment(\.openURL) private var openURL
    @Environment(ShellChrome.self) private var chrome
    /// Raises a web page beside this page, through the screen's one sheet
    /// (`FeedSheetRoute.web`): a row here cannot present one itself.
    var openPage: ((URL) -> Void)? = nil

    /// Tacit's own page for TAC, where public TAC is made private.
    static let shieldPage = URL(string: "https://tacit.finance/tac/")!

    private var coSigner: String? { YourAccountFacts.coSigners.first }

    var body: some View {
        let reading = account.reading
        Section {
            if let reading, reading.eth > 0 || (reading.tac ?? 0) > 0 {
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
        // **NO MAP, THE FIGURE (user, 2026-11-24: "that treemap doesn't
        // work for us bc user only holds tac", "we should get rid of it").**
        // A Tacit account holds TAC and maybe ETH, so a map was one tile
        // that said what Public and Private below already say. The page
        // leads with its total and the day, as Home's head does.
        let caption = Self.todayCaption(account, reading)
        return DSFigureReading(number: Self.figure(account, reading), caption: caption?.words ?? "",
                               captionInk: caption?.ink ?? DS.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The day's move over what the account holds, by dollars (Holdings'
    /// own sum, `HoldingMoves.dayChange`): only TAC has a move read here.
    /// nil when no move was read.
    static func todayCaption(_ account: TacitAccount, _ reading: TacitAccount.Reading) -> (words: String, ink: Color)? {
        var held: [(usd: Double, move: Double?)] = []
        if let usd = account.tacUSD { held.append((usd, account.tacMove)) }
        if let usd = account.usd, usd > 0 { held.append((usd, nil)) }
        guard let change = HoldingMoves.dayChange(held) else { return nil }
        let tenths = (abs(change) * 1000).rounded() / 10
        guard tenths > 0 else { return (String(localized: "Flat today"), DS.textSecondary) }
        let figure = tenths.formatted(.number.precision(.fractionLength(1)))
        return change > 0 ? (String(localized: "+\(figure)% today"), DS.confirmInk)
            : (String(localized: "-\(figure)% today"), DS.destructiveInk)
    }

    /// An amount as Holdings' rows say it: the number alone, the symbol
    /// beside it already naming the token ("TAC 23.85").
    static func amount(_ value: Double) -> String {
        value.formatted(.number.precision(.significantDigits(1...4)))
    }

    /// Public's sum: the public TAC in dollars, or its amount with no price.
    private func publicFigure(_ reading: TacitAccount.Reading) -> String? {
        guard let tac = reading.publicTAC else { return nil }
        return account.tacPrice.map { WalletValue.exactMoney(tac * $0) } ?? WalletValue.token(tac, "TAC")
    }

    /// Private's sum, what the Wallet's Private total counts (`privateUSD`);
    /// with no price, the ETH.
    private func privateFigure(_ reading: TacitAccount.Reading) -> String? {
        account.privateUSD.map(WalletValue.exactMoney) ?? WalletValue.token(reading.eth, "ETH")
    }

    /// The page's one figure, over the map and beside Balance: dollars when
    /// everything held has a price; else the TAC of an account holding only
    /// TAC, never "$0.00" over a row of it (user, 2026-11-24: "i'm still
    /// seeing zeroes"); else the ETH.
    static func figure(_ account: TacitAccount, _ reading: TacitAccount.Reading) -> String {
        if let usd = account.pageUSD { return WalletValue.exactMoney(usd) }
        if reading.eth == 0, let tac = reading.tac, tac > 0 { return WalletValue.token(tac, "TAC") }
        return account.usd.map(WalletValue.exactMoney) ?? WalletValue.token(reading.eth, "ETH")
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
                    Text(verbatim: why).dsText(.fact15).foregroundStyle(DS.destructiveInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: WalletCardStyle.ledgerHead)
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
            Text(verbatim: words).dsText(.fact15).foregroundStyle(DS.textSecondary)
            Spacer(minLength: 0)
        }
        .frame(minHeight: WalletCardStyle.ledgerHead)
    }

    // MARK: - The lists

    @ViewBuilder private func balance(_ reading: TacitAccount.Reading) -> some View {
        // **PUBLIC AND PRIVATE APART, AS HOLDINGS IS (prd §1718; user,
        // 2026-11-24: "why don't we separate public and private. so it's
        // like our own holdings").** Each side names its own sum; the page's
        // whole figure stands over the map.
        Section {
            head(String(localized: "Public"), figure: publicFigure(reading))
                .walletListRow()
            // Public, as Tacit counts it: TAC in the co-signer's own wallet.
            // Not read is said, never left out: a missing row and an empty
            // wallet are different answers.
            if let tac = reading.publicTAC {
                // In dollars, as every row under it is; the amount moves
                // into the line (user, 2026-11-24: "the tac just shows tac
                // but not the dollar amount").
                line("TAC", fact: Self.amount(tac),
                     figure: account.tacPrice.map { WalletValue.exactMoney(tac * $0) } ?? WalletValue.token(tac, "TAC"))
                    .walletListRow()
            } else {
                line("TAC", fact: String(localized: "Not read"), figure: "")
                    .walletListRow()
            }
            // **THE DOOR TO TACIT'S SITE (user, 2026-11-24: "for sure do the
            // door").** Casberi reads and cannot move this money: making
            // public TAC private is done on Tacit's own page, with the wallet
            // that holds it, and shows here at the next reading. In the
            // app's own Safari sheet, as every door here opens (user: "why
            // doesn't it show a sheet inside casberi"); the Mac has no such
            // sheet and opens its browser.
            // **BUY TAC (user, 2026-11-24, "do all").** With none public,
            // Swap opens to buy it, on your account, on the pool Swap pins.
            if reading.publicTAC == 0, YourAccountDemo.shownAddress != nil {
                actionRow(String(localized: "Buy TAC"), glyph: "arrow.left.arrow.right") {
                    Task { @MainActor in
                        guard let draft = await MoveSentence.watchedDraft(id: "ethereum:\(TacitPocket.tacToken.lowercased())", symbol: "TAC") else { return }
                        chrome.moveDraft = draft
                        chrome.moveTray = true
                    }
                }
                .walletListRow()
            }
            if let tac = reading.publicTAC, tac > 0 {
                // The rows' own columns, so its words start where theirs do;
                // `DSDoorRow`'s 18pt glyph column would start them short.
                Button {
                    DSHaptic.selection()
                    #if targetEnvironment(macCatalyst)
                    openURL(Self.shieldPage)
                    #else
                    if let openPage { openPage(Self.shieldPage) } else { openURL(Self.shieldPage) }
                    #endif
                } label: {
                    HStack(alignment: .center, spacing: DSRoomChassis.headGap) {
                        Image(systemName: "arrow.up.right")
                            .dsGlyph(.body, weight: .medium)
                            .foregroundStyle(DS.brandInk)
                            .frame(width: DSRoomChassis.headGlyph)
                            .accessibilityHidden(true)
                        Text("Make private on Tacit").dsText(.body17).foregroundStyle(DS.textPrimary).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: WalletCardStyle.ledgerHead)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPress())
                .walletListRow()
            }
        }
        Section {
            head(String(localized: "Private"), figure: privateFigure(reading))
                .walletListRow()
            // Private TAC on the Tacit chain: shares of one pool, at what
            // they are worth now, so what the pool has earned is in the
            // figure. Tacit's pool on Bitcoin is not read.
            if let tac = reading.privateTAC {
                line("TAC", fact: "\(Self.amount(tac)) · \(String(localized: "Tacit chain"))",
                     figure: account.tacPrice.map { WalletValue.exactMoney(tac * $0) } ?? WalletValue.token(tac, "TAC"))
                    .walletListRow()
                // What the chain's fees added to your shares, since the
                // first reading that knew the rate (user: "should we show
                // rewards too a user is earning?").
                if let earned = reading.earnedTAC, earned >= 0.0001, let since = reading.earnedSince {
                    line("TAC", fact: "\(Self.amount(earned)) · \(String(localized: "Earned since \(AccountPageShape.day(since))"))",
                         figure: "+" + (account.tacPrice.map { WalletValue.exactMoney(earned * $0) } ?? WalletValue.token(earned, "TAC")),
                         figureInk: DS.confirmInk)
                        .walletListRow()
                }
                if reading.privateElsewhere == true {
                    line("TAC", fact: String(localized: "More under a passkey, not read"),
                         factInk: DS.attentionInk, figure: "")
                        .walletListRow()
                }
            } else {
                line("TAC", fact: String(localized: "Tacit chain · not read"), figure: "")
                    .walletListRow()
            }
            // Tacit's DeFi pool, its private pool on Ethereum, where a
            // Tacit-chain deposit the chain does not take goes back to. A
            // row only when something is there; not read is said.
            if let tac = reading.defiTAC {
                if tac > 0 {
                    line("TAC", fact: "\(Self.amount(tac)) · \(String(localized: "DeFi pool"))",
                         figure: account.tacPrice.map { WalletValue.exactMoney(tac * $0) } ?? WalletValue.token(tac, "TAC"))
                        .walletListRow()
                }
            } else {
                line("TAC", fact: String(localized: "DeFi pool · not read"), figure: "")
                    .walletListRow()
            }
            // Only what is held, as Holdings lists it: a network at zero
            // is a "$0" row that says nothing (user: "we could make it a bit
            // more clear"). One that did not answer stays, greyed.
            ForEach(reading.held.filter { $0.eth > 0 || !$0.reached }) { held in
                line("ETH", fact: held.eth > 0 ? "\(Self.amount(held.eth)) · \(held.network)" : held.network,
                     figure: account.usd(held).map(WalletValue.exactMoney) ?? WalletValue.token(held.eth, "ETH"),
                     figureInk: held.reached ? DS.textPrimary : DS.textSecondary)
                    .walletListRow()
                if held.waiting > 0 {
                    line("ETH", fact: String(localized: "\(held.network) · arriving"),
                         factInk: DS.attentionInk,
                         figure: account.ethPrice.map { WalletValue.exactMoney(held.waiting * $0) }
                            ?? WalletValue.token(held.waiting, "ETH"),
                         figureInk: DS.textSecondary)
                        .walletListRow()
                }
            }
        }
    }

    /// Three addresses, each named for what it is. Public is the co-signer's
    /// own wallet, as on Tacit's page; the pool's deposit address is its own
    /// row, because ETH sent to it goes private (user, 2026-11-24: "tacit has
    /// two addresses it gives users you need to check. public and private").
    /// Every address, named for who pays it (user, 2026-11-24: "what's the
    /// difference in how the deposit address and private address work?"),
    /// the tail being what is checked.
    @ViewBuilder private func receive(_ reading: TacitAccount.Reading) -> some View {
        Section {
            head(String(localized: "Receive"), figure: nil).walletListRow()
            if let chain = reading.chainAddress, !chain.isEmpty {
                copyRow(String(localized: "Tacit chain address"),
                        fact: String(localized: "Private TAC · \(AddressTail.short(chain))"),
                        value: chain)
                    .walletListRow()
            }
            copyRow(String(localized: "Private address"),
                    fact: String(localized: "Private ETH, Tacit to Tacit · \(AddressTail.short(reading.address))"),
                    value: reading.address)
                .walletListRow()
            if !reading.receive.isEmpty {
                copyRow(String(localized: "Deposit address"),
                        fact: String(localized: "ETH from an exchange · \(AddressTail.short(reading.receive))"),
                        value: reading.receive)
                    .walletListRow()
            }
            copyRow(String(localized: "Public address"),
                    fact: String(localized: "Your wallet · \(AddressTail.short(reading.coSigner))"),
                    value: reading.coSigner)
                .walletListRow()
        }
    }

    @ViewBuilder private func hidden(_ reading: TacitAccount.Reading) -> some View {
        // Only where you hold ETH: a pool you are not in hides nothing of
        // yours, and its row had no figure to give.
        let pools = reading.held.filter { $0.pool != nil && $0.eth > 0 }
        if !pools.isEmpty {
            Section {
                head(String(localized: "How hidden"), figure: nil).walletListRow()
                ForEach(pools) { held in
                    let share = TacitAccount.share(held)
                    let thin = (share ?? 0) >= TacitAccount.thinShare
                    line(held.network,
                         fact: String(localized: "of \((held.pool ?? 0).formatted(.number.precision(.significantDigits(2...3)))) ETH"),
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
                .frame(minHeight: WalletCardStyle.ledgerHead)
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
                        .dsText(.fact15)
                        .foregroundStyle(busy ? DS.textTertiary : DS.pickInk)
                }
                .frame(minHeight: WalletCardStyle.ledgerHead)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPress())
            .disabled(busy)
        } else {
            words(String(localized: "No co-signer yet"), fact: String(localized: "Your account's second key opens Tacit"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: WalletCardStyle.ledgerHead)
        }
    }

    // MARK: - The parts

    /// A verb in the rows' own columns: its glyph where a row's mark stands.
    private func actionRow(_ words: String, glyph: String, act: @escaping () -> Void) -> some View {
        Button {
            DSHaptic.selection()
            act()
        } label: {
            HStack(alignment: .center, spacing: DSRoomChassis.headGap) {
                Image(systemName: glyph)
                    .dsGlyph(.body, weight: .medium)
                    .foregroundStyle(DS.brandInk)
                    .frame(width: DSRoomChassis.headGlyph)
                    .accessibilityHidden(true)
                Text(verbatim: words).dsText(.body17).foregroundStyle(DS.textPrimary).lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(minHeight: WalletCardStyle.ledgerHead)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
    }

    /// A section's name at the section rung, its figure trailing (prd §1496).
    private func head(_ name: String, figure: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DSRoomChassis.headGap) {
            Text(verbatim: name).dsText(.heading24).foregroundStyle(DS.headInk).lineLimit(1)
            Spacer(minLength: DS.Space.s2)
            if let figure {
                Text(verbatim: figure).dsText(.stat24).monospacedDigit().foregroundStyle(DS.textPrimary).lineLimit(1)
            }
        }
        .frame(minHeight: DSFeed.headHeight)
    }

    /// A name and its grey fact on one line (prd §1954).
    private func words(_ name: String, fact: String, factInk: Color = DS.textTertiary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            Text(verbatim: name).dsText(.body17).foregroundStyle(DS.textPrimary).lineLimit(1).layoutPriority(1)
            Text(verbatim: fact).dsText(.fact15).foregroundStyle(factInk).lineLimit(1)
        }
    }

    /// One line at the ledger's 40pt pitch (prd §1954): `walletListRow` adds
    /// the air, so the row holds the head alone (user, 2026-11-24: "the rows
    /// don't seem the same 40 point that our other rows on other pages are").
    ///
    /// It leads with its token's or network's mark, as a Holdings row does
    /// (user, 2026-11-24: "we need to have the token icons for the balances
    /// in tacit").
    private func line(_ name: String, mark: String? = nil, fact: String, factInk: Color = DS.textTertiary,
                      figure: String, figureInk: Color = DS.textPrimary) -> some View {
        HStack(alignment: .center, spacing: DSRoomChassis.headGap) {
            AssetMark(name: mark ?? name, size: DS.Mark.row)
                .frame(width: DSRoomChassis.headGlyph)
                .accessibilityHidden(true)
            words(name, fact: fact, factInk: factInk)
            Spacer(minLength: DS.Space.s2)
            Text(verbatim: figure).dsText(.price17).monospacedDigit().foregroundStyle(figureInk).lineLimit(1)
        }
        .frame(minHeight: WalletCardStyle.ledgerHead)
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
            .frame(minHeight: DSFeed.headHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
    }
}
