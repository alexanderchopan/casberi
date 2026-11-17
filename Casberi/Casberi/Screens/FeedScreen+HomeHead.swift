import SwiftUI

/// **THE PHONE'S HOME IS ONE SCROLL (prd §1843).** What you have, then what
/// is new: the Wallet stands at the head of the feed's page, on one quiet
/// card (the balance, the day, Public · Private and the map as a band), then
/// the watchlist's moves on one line, Account and its address as two chips,
/// and a row of chips that jump to each section under them. Home's five
/// cards and the separate Activity place are the rail's (iPad, Mac).
///
/// The head is the feed page's (`source == "All"`): that page holds every
/// category's rows, the seen rule (§1831) and the jumps, and the Wallet's
/// reads run on it too (`walletReadsHere`).
extension FeedScreen {
    /// The phone's Home: the feed's page, wearing the Wallet at its head.
    var homeHeadShown: Bool { quietActivity && !inSheet && PhoneHome.isOn }

    /// Where the Wallet's own reads run: its room, and the phone's Home.
    var walletReadsHere: Bool { source == "Wallet" || homeHeadShown }

    /// The word a page goes back to, where it said "Activity": Home on the
    /// phone, whose Activity is Home (prd §1843).
    var feedBackLabel: String {
        roomSizeClass == .compact && PhoneHome.isOn ? PlaceTab.wallet.label : PlaceTab.feed.label
    }

    /// One of the Wallet's pages, from Home's head: it keeps whose money
    /// Home showed, and goes back to Home.
    func homeOpen(_ section: WalletSection) {
        DSHaptic.selection()
        ActivitySeen.shared.leavingForPage()
        chrome.openWalletPage(section, fromActivity: nil, keepingScope: true)
    }

    /// A band tile pressed: a token opens its sheet, as its Holdings row
    /// does; an app's tile opens Apps; Other, Lent, Private and Aztec open
    /// Holdings, where their rows are. Never a page every tile shares.
    func homeOpenTile(_ id: String) {
        if WalletPortfolio.appCell(id) != nil {
            homeOpen(.apps)
        } else if id != HoldingsTreemapLayout.otherID,
                  let position = portfolioUnhidden?.positions.first(where: { $0.symbol == id }) {
            DSHaptic.selection()
            walletOpenToken(position)
        } else {
            homeOpen(.holdings)
        }
    }

    /// The head's rows, first on the page.
    @ViewBuilder
    func homeHeadSection(_ visible: [Thing], jumps: [String]) -> some View {
        Section {
            homeMoneyCard
                // The card's words stand in the rows' column (§763): its
                // edge is the column less its own padding.
                .listRowInsets(.init(top: DS.Space.s2, leading: DSRoomChassis.rowInset - DS.Space.s3,
                                     bottom: DS.Space.s2, trailing: DSRoomChassis.rowInset - DS.Space.s3))
                .feedRowBackground()
                .listRowSeparator(.hidden)
                // What the Wallet's own Home asked for as it stood (§1526,
                // §1561): the launch's scope, the recovery check, the ASP.
                .task {
                    WalletWhoseSwitch.applyLaunchChoice(chrome)
                    RecoveryCheckState.shared.refresh()
                    await PrivateMoneyStore.shared.refresh()
                }
            // Three groups (user: "balance and card; account and watchlist;
            // feed and chips"): the two lines stand close as one row, and
            // the wide gap is above the chips, which belong to the feed.
            VStack(alignment: .center, spacing: -DS.Space.s2) {
                homeWatchlistLine
                homeAccountLine
            }
            // Air between the groups (user: "there is enough room to have
            // more padding between and make the sections feel separate",
            // prd §1846): the lines stand a gap under the card.
            .listRowInsets(.init(top: Self.homeLinesGap, leading: DSRoomChassis.rowInset,
                                 bottom: 0, trailing: DSRoomChassis.rowInset))
            .feedRowBackground()
            .listRowSeparator(.hidden)
            homeJumpChips(jumps)
        }
    }

    // MARK: - The card

    /// Your money on one card: the balance (Holdings' door, §1838), the day
    /// and whose it is, Public · Private, and the band.
    ///
    /// **THE HEAD IS CENTRED (user, 2026-11-17: "i like the idea of the
    /// centered head!", prd §1845):** the balance, the day, Public · Private,
    /// the watchlist and Account stand on the screen's middle; the band
    /// spans the card, and the jump chips and the feed under them keep the
    /// rows' left edge.
    @ViewBuilder
    var homeMoneyCard: some View {
        let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
        VStack(alignment: .center, spacing: DS.Space.s2) {
            if let shown = portfolioShown, shown.totalUSD > 0 {
                let cells = HoldingsBand.cells(shown.foldingPrivate(walletPrivateByToken)
                    .sectionWorth(appsApart: walletOnAll))
                let moves = walletHoldingMoves
                let day = HoldingsTreemap.dayCaption(HoldingMoves.dayChange(cells.map {
                    (usd: $0.usd, move: $0.id == HoldingsTreemapLayout.otherID ? nil : moves[HoldingMoves.key($0.id)])
                }))
                // A last reading says when it was read (§825, §1593).
                let stamp = WalletIngest.subline(totalUSD: shown.totalUSD, tokenCount: 0, stale: shown.asOf)
                Button { homeOpen(.holdings) } label: {
                    HStack(spacing: DS.Space.s2) {
                        Text(verbatim: mask ?? WalletValue.money(shown.totalUSD))
                            .dsText(.heading52)
                            .monospacedDigit()
                            .foregroundStyle(DS.textPrimary)
                            .contentTransition(.numericText())
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        // A door wears a chevron, grey (§1815, §1838).
                        Image(systemName: "chevron.right")
                            .dsGlyph(.tick, weight: .bold)
                            .foregroundStyle(DS.textSecondary)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPress())
                .accessibilityHint(Text("Opens \(WalletSection.holdings.label)"))
                HStack(spacing: DS.Space.s2) {
                    if shown.asOf != nil, stamp.hasPrefix("as of") {
                        Text(verbatim: stamp).dsText(.body17).foregroundStyle(DS.textSecondary).lineLimit(1)
                    } else if let day {
                        Text(verbatim: day.words).dsText(.body17).foregroundStyle(day.ink).lineLimit(1)
                    }
                    homeWhoseWord
                }
                .frame(maxWidth: .infinity)
                homeHalves(total: shown.totalUSD, mask: mask)
                // Each tile opens its own token (`homeOpenTile`); the
                // balance above is Holdings' door.
                HoldingsBand(cells: cells, moves: moves) { homeOpenTile($0) }
                    .padding(.top, DS.Space.s1)
            } else if walletAccountSlots.allSatisfy(\.id.isEmpty) {
                // No account at all: the first one starts here (§1364).
                WalletStartFigure().frame(height: Self.homeStartHeight)
            } else if walletOnlyYourEmptyAccount {
                WalletStartFigure(made: true).frame(height: Self.homeStartHeight)
            } else {
                // Still reading says so, never "No balance yet" (§1587).
                WalletScopeEmptyFigure(section: .home, padded: false, reading: holdingsReads > 0)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .frame(height: Self.homeStartHeight, alignment: .topLeading)
                // A scope with nothing read still offers the way back (§1526).
                HStack { Spacer(minLength: 0); homeWhoseMenu }
            }
        }
        .padding(DS.Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsWell(cornerRadius: DS.Radius.widget, quiet: true)
    }

    /// **THE HEAD'S THREE GROUPS STAND APART (prd §1846).** The watchlist
    /// and Account a gap under the card (was 4pt), the jump chips a section
    /// gap and more under Account (was 24pt); Needs you under the chips
    /// takes `s6` (`ActivityWord`'s tight top, was `s2`).
    static let homeLinesGap: CGFloat = DS.Space.s6
    static let homeChipsGap: CGFloat = DSRoomChassis.sectionGap + DS.Space.s2

    /// The card's height while it has no balance to draw.
    static let homeStartHeight: CGFloat = 200

    /// Public and Private under the balance (§1807): Yours and All only, as
    /// the Private section stands (§1590).
    @ViewBuilder
    func homeHalves(total: Double, mask: String?) -> some View {
        if !walletOnFollowing, selectedWallet.map(YourAccountDemo.isYours) ?? true {
            let hidden = min(total, walletPrivateUSD)
            Button { homeOpen(.holdings) } label: {
                HStack(spacing: DS.Space.s4) {
                    homeHalf(String(localized: "Public"), mask ?? WalletValue.money(total - hidden))
                    homeHalf(String(localized: "Private"), mask ?? WalletValue.money(hidden))
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPress())
            .accessibilityElement(children: .combine)
        }
    }

    private func homeHalf(_ word: String, _ figure: String) -> some View {
        HStack(spacing: DS.Space.s2) {
            Text(verbatim: word).dsText(.body17).foregroundStyle(DS.textSecondary)
            Text(verbatim: figure).dsText(.body17).monospacedDigit().foregroundStyle(DS.textPrimary)
        }
        .lineLimit(1)
    }

    /// Whose money the card shows, said only when it is not yours (user:
    /// "lets get rid of the yours following all on the home screen and only
    /// have it on holdings … too much extra to tap"). The choice is
    /// Holdings'; Home follows it, and a balance that is not yours alone
    /// says so in one grey word, a fact and no control (§83).
    @ViewBuilder
    var homeWhoseWord: some View {
        if WalletWhoseSwitch.offered.count > 1 {
            let lit = WalletWhose.lit(scope: chrome.walletScope, yours: WalletWhoseSwitch.yours,
                                      same: WalletWatch.sameAddress)
            if lit != .yours {
                Text(verbatim: lit.label).dsText(.body17).foregroundStyle(DS.textSecondary).lineLimit(1)
            }
        }
    }

    /// The choice itself, on the card only while a scope has nothing to
    /// draw, so that card is never a dead end (§1526).
    @ViewBuilder
    var homeWhoseMenu: some View {
        let offered = WalletWhoseSwitch.offered
        if offered.count > 1 {
            let lit = WalletWhose.lit(scope: chrome.walletScope, yours: WalletWhoseSwitch.yours,
                                      same: WalletWatch.sameAddress)
            Menu {
                ForEach(offered, id: \.self) { whose in
                    Button {
                        WalletWhoseSwitch.pick(whose, chrome)
                    } label: {
                        if whose == lit {
                            Label(whose.label, systemImage: "checkmark")
                        } else {
                            Text(whose.label)
                        }
                    }
                }
            } label: {
                HStack(spacing: DS.Space.s1) {
                    Text(verbatim: lit.label).dsText(.body17)
                    Image(systemName: "chevron.down").dsGlyph(.tick, weight: .bold).accessibilityHidden(true)
                }
                .foregroundStyle(DS.textSecondary)
                // Drawn at the line's height, targeted at the floor (§717).
                .dsTapTarget()
            }
            .accessibilityLabel(Text("Whose money"))
            .accessibilityValue(Text(verbatim: lit.label))
        }
    }

    // MARK: - The lines

    /// The watchlist's moves on one line (prd §1843): its glyph, then each
    /// token and its day in the day's ink; empty, the verb. It opens the
    /// watchlist.
    @ViewBuilder
    var homeWatchlistLine: some View {
        let tokens = Watchlist.shared.tokens
        let quotes = WatchlistPrices.shared.quotes
        Button {
            if tokens.isEmpty {
                DSHaptic.selection()
                feedSheet = .watchToken
            } else {
                homeOpen(.watchlist)
            }
        } label: {
            HStack(spacing: DS.Space.s4) {
                Image(systemName: WalletSection.watchlist.glyph)
                    .dsGlyph(.body)
                    .foregroundStyle(DS.brandInk)
                    .accessibilityHidden(true)
                if tokens.isEmpty {
                    Text("Watch a token").dsText(.body17).foregroundStyle(DS.pickInk)
                } else {
                    ForEach(tokens.prefix(Self.homeWatchCap)) { token in
                        homeWatchMove(token, quotes[token.id]?.change)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: DS.Hit.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .accessibilityLabel(Text(WalletSection.watchlist.label))
        .task(id: tokens.map(\.id)) { await walletWatchlistRefresh(tokens) }
    }

    /// As many tokens as one line holds at the reading size.
    static let homeWatchCap = 3

    private func homeWatchMove(_ token: WatchedToken, _ percent: Double?) -> some View {
        let change = percent.map(WatchlistRules.change)
        return HStack(spacing: DS.Space.s1) {
            Text(verbatim: token.symbol).foregroundStyle(DS.textPrimary)
            if let change {
                Text(verbatim: change.words)
                    .monospacedDigit()
                    .foregroundStyle(change.tone == .up ? DS.confirmInk
                        : change.tone == .down ? DS.destructiveInk : DS.textSecondary)
            }
        }
        .dsText(.body17)
        .lineLimit(1)
        .fixedSize()
    }

    /// Account and its address, two chips (prd §1843): the first opens the
    /// page (or makes the account, or finishes its setup), the second copies
    /// the public address.
    @ViewBuilder
    var homeAccountLine: some View {
        let yours = YourAccountDemo.shownAddress
        let pending = yours.map { chrome.walkClosed >= 0 && YourAccountFirstOpen.setupPending($0) } ?? false
        HStack(spacing: DS.Space.s2) {
            Button {
                DSHaptic.selection()
                if yours == nil {
                    chrome.moveTray = true
                } else if pending {
                    chrome.moveWalk = true
                    chrome.moveTray = true
                } else {
                    chrome.yourAccountShowsAztec = false
                    homeOpen(.yourAccount)
                }
            } label: {
                Chip(text: yours == nil ? String(localized: "Create account")
                        : pending ? String(localized: "Finish setup") : WalletSection.yourAccount.label,
                     glyph: WalletSection.yourAccount.glyph, selected: true,
                     ink: pending ? DS.attentionInk : nil)
            }
            .buttonStyle(PressSpring())
            if let yours, !pending {
                Button {
                    DSPasteboard.copy(yours)
                    chrome.flash(String(localized: "Address copied"), tone: .success)
                } label: {
                    Chip(text: String(localized: "Copy public address"), glyph: "doc.on.doc", ink: DS.pickInk)
                }
                .buttonStyle(PressSpring())
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - The jumps

    /// The sections standing on the page this visit, in their order: Needs
    /// you when anything waits, the Wallet, each category with something
    /// new, then Apps. One read of what the sections themselves draw.
    func homeJumpNames(_ visible: [Thing]) -> [String] {
        var names: [String] = []
        let money = activityMoneyRows(visible)
        let needs = activityNeedThings(visible)
        let yours = YourAccountDemo.shownAddress
        let pending = yours.map { chrome.walkClosed >= 0 && YourAccountFirstOpen.setupPending($0) } ?? false
        let wants = money.isEmpty ? nil : pending ? "" : (yours != nil ? yourAccountWants : nil)
        if walletNeedsCount(upcoming: walletUpcoming(money)) > 0 || wants != nil || !needs.isEmpty
            || homeRisksUnseen > 0 {
            names.append(WalletSection.needsYou.label)
        }
        names.append(Self.homeWalletName)
        let byCategory = feedSectionRows(visible, hiding: [])
        let asked = Set(needs.map(\.source))
        for category in scrollCategories where category != HomeScope.notesSection {
            let drawn = category == RoomAccounts.dayRoom
                ? !Self.nextPerApp(dayFeedRows.live).isEmpty
                : Self.newestPerApp((byCategory[category] ?? []).live.filter { !asked.contains($0.source) })
                    .contains { !ActivitySeen.shared.isHidden($0.id) }
            if drawn { names.append(category) }
        }
        names.append(PlaceTab.library.label)
        return names
    }

    /// The Wallet's word on the page, as its section says it (§1812).
    static var homeWalletName: String { String(localized: "Wallet") }

    /// The risks found and not yet seen: Home's ask (prd §1843), the count
    /// Home's Risks card wore.
    var homeRisksUnseen: Int {
        guard homeHeadShown else { return 0 }
        return walletLive.flagged.live.filter { !ThreatsSeen.shared.contains($0.id) }.count
    }

    /// The jumps, one chip a section, in a row that runs off the trailing
    /// edge when they do not fit (prd §1843): a chip lands on its section,
    /// and nothing is lit, since the row jumps rather than narrows.
    @ViewBuilder
    func homeJumpChips(_ jumps: [String]) -> some View {
        let names = Self.homeChipNames(jumps)
        if !names.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s2) {
                    ForEach(names, id: \.self) { name in
                        Button {
                            DSHaptic.selection()
                            chrome.feedJump = name == PlaceTab.library.label ? Self.appsPanelName : name
                        } label: {
                            Chip(text: name, selected: true)
                        }
                        .buttonStyle(PressSpring())
                    }
                }
                .padding(.horizontal, DSRoomChassis.rowInset)
            }
            .listRowInsets(.init(top: Self.homeChipsGap, leading: 0, bottom: 0, trailing: 0))
            .feedRowBackground()
            .listRowSeparator(.hidden)
        }
    }

    /// The chips drawn for the page's sections. Needs you takes none (user:
    /// "it's jump chip is unnecessary"): it is always the first thing under
    /// the chips. The Wallet and Apps alone are the whole page: nothing to
    /// jump past, so no row.
    static func homeChipNames(_ jumps: [String]) -> [String] {
        let names = jumps.filter { $0 != WalletSection.needsYou.label }
        return names.count > 2 ? names : []
    }

    /// The section standing right under the chips, which takes no chapter
    /// air of its own (`feedSectionLeads`): the first on the page, when the
    /// chips are drawn.
    static func homeLeadAnchor(_ jumps: [String]) -> String? {
        guard !homeChipNames(jumps).isEmpty, let first = jumps.first else { return nil }
        return scrollAnchor(first)
    }
}
