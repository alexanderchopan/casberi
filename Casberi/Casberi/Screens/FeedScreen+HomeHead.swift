import SwiftUI

/// **THE PHONE'S HOME IS ONE SCROLL (prd §1843).** What you have, then what
/// is new: the Wallet stands at the head of the feed's page, on the page's
/// own black and its left edge (prd §1851: the balance large, the day with
/// Public · Private on one row, Holdings as a row), then its doors as one row
/// of words (Account, Risks, Apps, the address), and a row of circles that
/// jump to each section under them. Home's five
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

    /// The head's rows, first on the page.
    @ViewBuilder
    func homeHeadSection(_ visible: [Thing], jumps: [String], panel: Bool) -> some View {
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
                    // Your account is made on the first run's Home (prd
                    // §1741, §1839); here since the first run draws no
                    // Wallet section to make it (prd §1847).
                    YourAccountFirstOpen.makeIfFresh()
                    WalletWhoseSwitch.applyLaunchChoice(chrome)
                    RecoveryCheckState.shared.refresh()
                    await PrivateMoneyStore.shared.refresh()
                }
            // Three groups (user: "balance and card; account and watchlist;
            // feed and chips"): the two lines stand close as one row, and
            // the wide gap is above the chips, which belong to the feed.
            // **THE FIRST RUN SAYS IT ONCE (prd §1847).** Until your account
            // is set up the card is the Wallet's whole start: no watchlist
            // line and no chips under it.
            // Apps is a chip here once its panel has left the page's foot
            // (prd §1848), so it stands even before the account does.
            if !homeBare || !panel {
                homeAccountLine(apps: !panel, bare: homeBare)
                // Air between the groups (user: "there is enough room to have
                // more padding between and make the sections feel separate",
                // prd §1846): the lines stand a gap under the card.
                .listRowInsets(.init(top: Self.homeLinesGap, leading: DSRoomChassis.rowInset,
                                     bottom: 0, trailing: DSRoomChassis.rowInset))
                .feedRowBackground()
                .listRowSeparator(.hidden)
            }
            homeCircles(jumps, visible)
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
    ///
    /// **THE HEAD STANDS ON THE PAGE (prd §1850).** With a balance to show it
    /// draws no card: the balance, the day, the map and the watchlist stand
    /// on the page's own black, centred, and the feed under them keeps the
    /// rows' left edge. Only the start (no balance yet) keeps its well.
    @ViewBuilder
    var homeMoneyCard: some View {
        if (portfolioShown?.totalUSD ?? 0) > 0 {
            // On the rows' own left edge (the row's inset is the well's).
            homeMoneyStack
                .padding(.horizontal, DS.Space.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            homeMoneyStack
                .padding(DS.Space.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .dsWell(cornerRadius: DS.Radius.widget, quiet: true)
        }
    }

    @ViewBuilder
    private var homeMoneyStack: some View {
        let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if let shown = portfolioShown, shown.totalUSD > 0 {
                let worth = shown.foldingPrivate(walletPrivateByToken).sectionWorth(appsApart: walletOnAll)
                let cells = HoldingsBand.cells(worth)
                let moves = walletHoldingMoves
                let day = Self.homeDay(HoldingMoves.dayChange(cells.map {
                    (usd: $0.usd, move: $0.id == HoldingsTreemapLayout.otherID ? nil : moves[HoldingMoves.key($0.id)])
                }))
                // A last reading says when it was read (§825, §1593).
                let stamp = WalletIngest.subline(totalUSD: shown.totalUSD, tokenCount: 0, stale: shown.asOf)
                Button { homeOpen(.holdings) } label: {
                    HStack(spacing: DS.Space.s2) {
                        Text(verbatim: mask ?? WalletValue.money(shown.totalUSD))
                            .dsText(.price84)
                            .monospacedDigit()
                            .foregroundStyle(DS.textPrimary)
                            .contentTransition(.numericText())
                            .lineLimit(1)
                            .minimumScaleFactor(0.45)
                        // A door wears a chevron, grey (§1815, §1838).
                        Image(systemName: "chevron.right")
                            .dsGlyph(.tick, weight: .bold)
                            .foregroundStyle(DS.textSecondary)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPress())
                .accessibilityHint(Text("Opens \(WalletSection.holdings.label)"))
                // **ONE ROW OF FACTS (prd §1851).** The day, then Public and
                // Private, on the balance's own left edge; a balance too wide
                // for one row stands the halves under the day.
                let lead = HStack(spacing: DS.Space.s2) {
                    if shown.asOf != nil, stamp.hasPrefix("as of") {
                        Text(verbatim: stamp).dsText(.body17).foregroundStyle(DS.textSecondary).lineLimit(1)
                    } else if let day {
                        DSDayPill(words: day.words, ink: day.ink)
                    }
                    homeWhoseWord
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: DS.Space.s4) {
                        lead
                        homeHalves(total: shown.totalUSD, mask: mask)
                    }
                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        lead
                        homeHalves(total: shown.totalUSD, mask: mask)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // **HOLDINGS IS A ROW (prd §1851, over §1850's band).** The
                // three biggest and each one's day; the row opens Holdings,
                // where the map is.
                Button { homeOpen(.holdings) } label: {
                    DSHomeFactRow(glyph: WalletSection.holdings.glyph, name: WalletSection.holdings.label,
                                  items: Self.homeHoldingItems(worth, moves))
                }
                .buttonStyle(RowPress())
            } else if walletAccountSlots.allSatisfy(\.id.isEmpty) {
                // No account at all: the first one starts here (§1364).
                WalletStartFigure(bare: homeBare).frame(height: homeBare ? nil : Self.homeStartHeight)
            } else if walletOnlyYourEmptyAccount {
                // Made for you and not yet set up: still the start (§1847).
                WalletStartFigure(made: !homeSetupPending, walk: homeSetupPending, bare: homeBare)
                    .frame(height: homeBare ? nil : Self.homeStartHeight)
            } else {
                // Still reading says so, never "No balance yet" (§1587).
                WalletScopeEmptyFigure(section: .home, padded: false, reading: holdingsReads > 0)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .frame(height: Self.homeStartHeight, alignment: .topLeading)
                // A scope with nothing read still offers the way back (§1526).
                HStack { Spacer(minLength: 0); homeWhoseMenu }
            }
        }
    }

    /// The day on its pill: the move alone ("+0.9%"), in the day's ink; a
    /// day that rounds to zero says so in grey (§83).
    static func homeDay(_ change: Double?) -> (words: String, ink: Color)? {
        guard let change else { return nil }
        let day = WatchlistRules.change(change * 100)
        return (day.words, day.tone == .up ? DS.confirmInk : day.tone == .down ? DS.destructiveInk : DS.textSecondary)
    }

    /// As many holdings as the row names.
    static let homeHoldingsCap = 3

    /// The row's holdings: the biggest tokens, each by its symbol and its
    /// day. Tokens only (user: "for holdings there are no long names"): an
    /// app's or a bank account's tile is never one, nor is Other.
    static func homeHoldingItems(_ worth: [String: Double], _ moves: [String: Double]) -> [DSHomeFactRow.Item] {
        // Lent and Private are places your tokens sit, not tokens (user:
        // "why does it say lent in the holdings row").
        let places: Set<String> = [HoldingsTreemapLayout.otherID, WalletPortfolio.lentSymbol,
                                    PrivateMoney.walletSymbol, AztecAccountStore.walletSymbol]
        return worth.filter { $0.value > 0 && !places.contains($0.key) && WalletPortfolio.appCell($0.key) == nil }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(homeHoldingsCap).map { cell in (id: cell.key, usd: cell.value) }.map { cell in
            let name = cell.id
            guard let move = moves[HoldingMoves.key(cell.id)] else {
                return DSHomeFactRow.Item(id: cell.id, name: name)
            }
            let day = WatchlistRules.change(move * 100)
            return DSHomeFactRow.Item(id: cell.id, name: name, change: day.words,
                                      ink: day.tone == .up ? DS.confirmInk
                                          : day.tone == .down ? DS.destructiveInk : DS.textSecondary)
        }
    }

    /// Your account was made for you and its walk has not been taken.
    var homeSetupPending: Bool {
        YourAccountDemo.shownAddress.map { chrome.walkClosed >= 0 && YourAccountFirstOpen.setupPending($0) } ?? false
    }

    /// **THE FIRST RUN (prd §1847).** No account of yours is set up and the
    /// Wallet holds nobody else's: the card says "Set up your wallet" once,
    /// and the watchlist line, the chips and the Wallet's section wait for
    /// the account. Someone who follows an account and made none keeps all
    /// of them.
    var homeBare: Bool {
        guard homeHeadShown else { return false }
        let yours = YourAccountDemo.shownAddress
        guard yours == nil || homeSetupPending else { return false }
        return WalletStore.shared.addresses.allSatisfy { held in
            yours.map { WalletWatch.sameAddress(held.address, $0) } ?? false
        }
    }

    /// **TWO GROUPS, NOT THREE STRIPS (prd §1850, over §1846).** The doors
    /// stand right under the watchlist, the foot of the money over them;
    /// the break is above the circles, which are the feed's. Needs you under
    /// the circles takes `s6` (`ActivityWord`'s tight top).
    static let homeLinesGap: CGFloat = DS.Space.s2
    static let homeChipsGap: CGFloat = DS.Space.s8

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
                .fixedSize()
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPress())
            .accessibilityElement(children: .combine)
        }
    }

    private func homeHalf(_ word: String, _ figure: String) -> some View {
        HStack(spacing: DS.Space.s2) {
            Text(verbatim: word).foregroundStyle(DS.textSecondary)
            Text(verbatim: figure).monospacedDigit().foregroundStyle(DS.textPrimary)
        }
        .dsText(.heading20)
        .fontWeight(.bold)
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

    /// **THE WATCHLIST IS THE WALLET SECTION'S (prd §1851, over §1849).** One
    /// row over the Wallet's newest move: its glyph, its name, the token that
    /// moved most today; empty, the verb. It opens the watchlist.
    @ViewBuilder
    var homeWatchRow: some View {
        let tokens = Watchlist.shared.tokens
        let quotes = WatchlistPrices.shared.quotes
        Button {
            if tokens.isEmpty {
                DSHaptic.selection()
                feedSheet = .watchToken
            } else {
                ActivitySeen.shared.leavingForPage()
                homeOpen(.watchlist)
            }
        } label: {
            DSHomeFactRow(glyph: WalletSection.watchlist.glyph, name: WalletSection.watchlist.label,
                          items: Self.homeWatchItems(tokens, quotes),
                          verb: String(localized: "Watch a token"))
        }
        .buttonStyle(RowPress())
        .task(id: tokens.map(\.id)) { await walletWatchlistRefresh(tokens) }
        .feedRowBackground()
        .listRowInsets(.init(top: 0, leading: DSRoomChassis.rowInset, bottom: 0, trailing: DSRoomChassis.rowInset))
        .listRowSeparator(.hidden)
    }

    /// The one token the row names: the day's biggest mover, else the first
    /// on the list (unread, it says its name alone).
    static func homeWatchItems(_ tokens: [WatchedToken], _ quotes: [String: WatchlistRules.Quote]) -> [DSHomeFactRow.Item] {
        if let mover = WatchlistRules.biggestMover(tokens, quotes: quotes) {
            return [DSHomeFactRow.Item(id: mover.symbol, name: mover.symbol, change: mover.change.words,
                                       ink: mover.change.tone == .up ? DS.confirmInk : DS.destructiveInk)]
        }
        guard let first = tokens.first else { return [] }
        let day = (quotes[first.id]?.change).map(WatchlistRules.change)
        return [DSHomeFactRow.Item(id: first.id, name: first.symbol, change: day?.words)]
    }

    /// **HOME'S DOORS, ONE ROW OF WORDS (prd §1850, over §1849's round
    /// buttons):** Account (or the verb that makes or finishes it), Risks and
    /// Apps, each a word and a chevron (`DSHomeDoor`), then the address's
    /// tail and its copy. Risks takes the attention ink and a count while a
    /// finding is unseen; the copy says "Copied" in its own place.
    @ViewBuilder
    func homeAccountLine(apps: Bool, bare: Bool) -> some View {
        let yours = YourAccountDemo.shownAddress
        let pending = homeSetupPending
        let risks = homeRisksUnseen
        HStack(alignment: .center, spacing: DS.Space.s4) {
            if !bare {
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
                    DSHomeDoor(name: yours == nil ? String(localized: "Create account")
                                  : pending ? String(localized: "Finish setup") : WalletSection.yourAccount.label,
                               tone: pending ? .attention : .rest)
                }
                .buttonStyle(RowPress())
                // **RISKS IS ALWAYS HERE (prd §1847, user: "if i dismiss all
                // the 'needs you' items then i can no longer see my privacy
                // score").** Its ask in Needs you leaves once seen; the door
                // stays, and says how many are unseen.
                if !walletAccountSlots.allSatisfy(\.id.isEmpty) {
                    Button {
                        ActivitySeen.shared.leavingForPage()
                        homeOpen(.threats)
                    } label: {
                        DSHomeDoor(name: WalletSection.threats.label,
                                   tone: risks > 0 ? .attention : .rest, count: risks > 0 ? risks : nil)
                    }
                    .buttonStyle(RowPress())
                }
            }
            // **APPS IS A DOOR AT THE HEAD (prd §1848).** Its panel stood at
            // the foot of the feed, a slab you scrolled into.
            if apps {
                Button {
                    DSHaptic.selection()
                    ActivitySeen.shared.leavingForPage()
                    route.present(.apps)
                } label: {
                    DSHomeDoor(name: PlaceTab.library.label)
                }
                .buttonStyle(RowPress())
            }
            if !bare, let yours, !pending {
                HomeCopyAction(address: yours)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - The jumps

    /// The sections standing on the page this visit, in their order: Needs
    /// you when anything waits, the Wallet, each category with something
    /// new, then Apps. One read of what the sections themselves draw.
    func homeJumpNames(_ visible: [Thing], panel: Bool) -> [String] {
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
        // The first run draws no Wallet section to jump to (prd §1847).
        // (a bank's rows still draw one, and keep the jump).
        if !(homeBare && Self.walletMoves(money).isEmpty) { names.append(Self.homeWalletName) }
        let byCategory = feedSectionRows(visible, hiding: [])
        let asked = Set(needs.map(\.source))
        for category in scrollCategories where category != HomeScope.notesSection {
            let drawn = category == RoomAccounts.dayRoom
                ? !Self.nextPerApp(dayFeedRows.live).isEmpty
                : Self.newestPerApp((byCategory[category] ?? []).live.filter { !asked.contains($0.source) })
                    .contains { !ActivitySeen.shared.isHidden($0.id) }
            if drawn { names.append(category) }
        }
        // Apps is a jump only while its panel is on the page (prd §1848).
        if panel { names.append(PlaceTab.library.label) }
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
    ///
    /// **THE JUMPS ARE CIRCLES (prd §1850, over the chips):** Needs you with
    /// how many wait, the Wallet, then each category wearing the mark of the
    /// app whose row leads it.
    @ViewBuilder
    func homeCircles(_ jumps: [String], _ visible: [Thing]) -> some View {
        let names = Self.homeCircleNames(jumps)
        if !names.isEmpty {
            let byCategory = feedSectionRows(visible, hiding: [])
            let asked = Set(activityNeedThings(visible).map(\.source))
            let waiting = homeNeedsCount(visible)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: DS.Space.s2) {
                    ForEach(names, id: \.self) { name in
                        Button {
                            DSHaptic.selection()
                            chrome.feedJump = name
                        } label: {
                            if name == WalletSection.needsYou.label {
                                DSHomeCircle(name: name, tone: .attention) { DSHomeCircleCount(count: waiting) }
                            } else if name == Self.homeWalletName {
                                DSHomeCircle(name: name) { DSHomeCircleGlyph(glyph: ScopeTileGlyph.wallets) }
                            } else if let app = homeCircleApp(name, byCategory, asked: asked),
                                      BridgeIcon.hasMark(app) {
                                DSHomeCircle(name: name) {
                                    BridgeIcon(name: app, size: DS.Mark.hero, circular: true)
                                }
                            } else {
                                DSHomeCircle(name: name) { DSHomeCircleGlyph(glyph: CategoryFold.glyph(for: name)) }
                            }
                        }
                        .buttonStyle(PressSpring())
                        .dsTapTarget()
                    }
                }
                .padding(.horizontal, DSRoomChassis.rowInset - (DSHomeCircleMetrics.column - DSHomeCircleMetrics.face) / 2)
            }
            .listRowInsets(.init(top: Self.homeChipsGap, leading: 0, bottom: 0, trailing: 0))
            .feedRowBackground()
            .listRowSeparator(.hidden)
        }
    }

    /// The app whose row leads a category's section this visit: the mark
    /// its circle wears. Read as the section itself reads its rows.
    func homeCircleApp(_ category: String, _ byCategory: [String: [Thing]], asked: Set<String>) -> String? {
        if category == RoomAccounts.dayRoom { return Self.nextPerApp(dayFeedRows.live).first?.source }
        return Self.newestPerApp((byCategory[category] ?? []).live.filter { !asked.contains($0.source) })
            .first { !ActivitySeen.shared.isHidden($0.id) }?.source
    }

    /// How many things wait in Needs you, as its section counts its rows:
    /// your account's ask, the Wallet's asks, the unseen risks, and what the
    /// apps ask.
    func homeNeedsCount(_ visible: [Thing]) -> Int {
        let money = activityMoneyRows(visible)
        let yours = YourAccountDemo.shownAddress
        let pending = yours.map { chrome.walkClosed >= 0 && YourAccountFirstOpen.setupPending($0) } ?? false
        let wants = money.isEmpty ? nil : pending ? "" : (yours != nil ? yourAccountWants : nil)
        return (wants == nil ? 0 : 1) + walletNeedsCount(upcoming: walletUpcoming(money))
            + homeRisksUnseen + activityNeedThings(visible).count
    }

    /// The circles drawn for the page's sections: every section standing on
    /// it, once the feed has a category to jump to. The Wallet alone (with
    /// or without Needs you) is the whole page: nothing to jump past, so no
    /// row. Apps' panel takes none (it is a door at the head, §1848).
    static func homeCircleNames(_ jumps: [String]) -> [String] {
        let names = jumps.filter { $0 != PlaceTab.library.label }
        let categories = names.filter { $0 != WalletSection.needsYou.label && $0 != homeWalletName }
        return categories.isEmpty ? [] : names
    }

    /// The section standing right under the circles, which takes no chapter
    /// air of its own (`feedSectionLeads`): the first on the page, when the
    /// circles are drawn.
    static func homeLeadAnchor(_ jumps: [String]) -> String? {
        guard !homeCircleNames(jumps).isEmpty, let first = jumps.first else { return nil }
        return scrollAnchor(first)
    }
}

/// The address's copy, one of Home's round buttons (prd §1849): pressed, its
/// disc turns to the confirm hue and a check and its word reads "Copied" for
/// a moment (§867), in place of a toast.
private struct HomeCopyAction: View {
    let address: String
    @State private var copied = false

    var body: some View {
        Button {
            DSPasteboard.copy(address)
            DSHaptic.selection()
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                copied = false
            }
        } label: {
            // Not a door: the address's tail, grey, and the copy's glyph in
            // the chevron's place (prd §1850).
            HStack(spacing: DS.Space.s1) {
                Text(verbatim: copied ? String(localized: "Copied") : AddressTail.short(address))
                    .dsText(.body17)
                    .monospacedDigit()
                    .foregroundStyle(copied ? DS.confirmInk : DS.textSecondary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .dsGlyph(.subhead)
                    .foregroundStyle(copied ? DS.confirm : DS.textSecondary)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
            }
            .frame(minHeight: DS.Hit.min)
            .contentShape(Rectangle())
            .animation(DS.Motion.standard, value: copied)
        }
        .buttonStyle(RowPress())
        .accessibilityLabel(Text("Copy address"))
    }
}
