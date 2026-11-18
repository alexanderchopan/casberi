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
            // **PUBLIC, THEN PRIVATE, AS HOLDINGS HAS THEM (prd §1858).**
            if homePlated && !homeBare { homeHoldingRows() }
            if !homeBare || !panel {
                homeAccountLine(apps: homePlated || !panel, bare: homeBare)
                // Air between the groups (user: "there is enough room to have
                // more padding between and make the sections feel separate",
                // prd §1846): the lines stand a gap under the card.
                .listRowInsets(.init(top: Self.homeLinesGap, leading: DSRoomChassis.rowInset,
                                     bottom: 0, trailing: DSRoomChassis.rowInset))
                .feedRowBackground()
                .listRowSeparator(.hidden)
            }
            // What is new stands on its panel from here down (prd §1858).
            if !homeBare {
                HomePanelCap()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
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
        if homePlated {
            // **THE BALANCE IS THE PAGE'S FIRST LINE (prd §1857, over §1855's
            // plate and §1856's foot; user, of the mock: "this is probably
            // the smartest option").** No plate: the balance, the day with
            // Public and Private, then the doors, on the page's black in the
            // rows' column, so the feed starts high. Holdings is a section
            // under Activity (`homeHoldingsSection`).
            homeMoneyStack
                .padding(.horizontal, DS.Space.s3)
                .padding(.top, DS.Space.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            homeMoneyStack
                .padding(DS.Space.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .dsWell(cornerRadius: DS.Radius.widget, quiet: true)
        }
    }

    /// There is a balance to show: the head is the balance's lines, and the
    /// doors and Holdings stand under it.
    var homePlated: Bool { (portfolioShown?.totalUSD ?? 0) > 0 }

    @ViewBuilder
    private var homeMoneyStack: some View {
        let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if let shown = portfolioShown, shown.totalUSD > 0 {
                let worth = shown.foldingPrivate(walletPrivateByToken).sectionWorth(appsApart: walletOnAll)
                let moves = walletHoldingMoves
                let day = Self.homeDay(HoldingMoves.dayChange(Self.homeDayCells(worth).map {
                    (usd: $0.value, move: $0.key == HoldingsTreemapLayout.otherID ? nil : moves[HoldingMoves.key($0.key)])
                }))
                // A last reading says when it was read (§825, §1593).
                let stamp = WalletIngest.subline(totalUSD: shown.totalUSD, tokenCount: 0, stale: shown.asOf)
                Button { homeOpen(.holdings) } label: {
                    HStack(spacing: DS.Space.s2) {
                        Text(verbatim: mask ?? WalletValue.money(shown.totalUSD))
                            .dsText(.price52)
                            .monospacedDigit()
                            .foregroundStyle(DS.textPrimary)
                            .contentTransition(.numericText())
                            .lineLimit(1)
                            .minimumScaleFactor(0.45)
                        // The one door to Holdings wears its chevron again
                        // (prd §1858, §1815): no "Holdings" word stands on
                        // Home to say so for it.
                        Image(systemName: "chevron.right")
                            .dsGlyph(.tick, weight: .bold)
                            .foregroundStyle(DS.textSecondary)
                            .accessibilityHidden(true)
                        Spacer(minLength: DS.Space.s2)
                        // The day beside the balance; a last reading says
                        // when it was read (§825, §1593).
                        if shown.asOf != nil, stamp.hasPrefix("as of") {
                            Text(verbatim: stamp).dsText(.subhead12).foregroundStyle(DS.textSecondary).lineLimit(1)
                        } else if let day {
                            DSDayPill(words: day.words, ink: day.ink)
                        }
                        homeWhoseWord
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPress())
                .accessibilityHint(Text("Opens \(WalletSection.holdings.label)"))
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

    /// The day pill reads the map's five biggest and the rest as Other, as
    /// it did under the band (§1843).
    static func homeDayCells(_ worth: [String: Double]) -> [(key: String, value: Double)] {
        let sorted = worth.filter { $0.value > 0 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        let rest = sorted.dropFirst(5).reduce(0) { $0 + $1.value }
        return Array(sorted.prefix(5)) + (rest > 0 ? [(key: HoldingsTreemapLayout.otherID, value: rest)] : [])
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

    // MARK: - Holdings

    /// Nobody has built a feed: no category beyond Day and Notes is
    /// connected. The wallet then takes the room (prd §1858).
    var homeFeedless: Bool {
        !HomeScope.feedCategories(chips: chrome.chipOrder).contains {
            $0 != RoomAccounts.dayRoom && $0 != HomeScope.notesSection
        }
    }

    /// How many apps' newest moves Activity shows on Home while there is no
    /// feed (prd §1858). Still each app's newest (§1809), never the latest
    /// three of one app.
    static let homeFeedlessMoves = 3

    /// **PUBLIC, THEN PRIVATE (prd §1858, user: "today our holdings page
    /// separates public from private in two sections").** Under the balance,
    /// on the page: each side's name and total, then its biggest tokens, two
    /// each (three while there is no feed). The names are labels (user:
    /// "don't do that b/c they go to the same place"); the balance is the
    /// door to Holdings; a public token opens itself, as on Holdings. Private
    /// money is yours alone (§1590), and a side with nothing draws nothing.
    @ViewBuilder
    func homeHoldingRows() -> some View {
        let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
        let count = homeFeedless ? 3 : 2
        let total = portfolioShown?.totalUSD ?? 0
        let hidden = walletShowsPrivatePlaces ? min(total, walletPrivateUSD) : 0
        let pub = total - hidden < 0.01 ? []
            : Array((portfolioShown?.tokensOnly(appsApart: walletOnAll).positions ?? [])
                .filter { $0.usd > 0 }
                .sorted { $0.usd != $1.usd ? $0.usd > $1.usd : $0.symbol < $1.symbol }
                .prefix(count))
        let priv = hidden < 0.01 ? []
            : Array(homePrivateByToken.filter { $0.value > 0 }
                .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                .prefix(count))
        if !pub.isEmpty {
            homeSideHead(String(localized: "Public"), mask ?? WalletValue.money(total - hidden))
            walletTokenPreview(pub, mask: mask) { walletOpenToken($0) }
        }
        if !priv.isEmpty {
            homeSideHead(String(localized: "Private"), mask ?? WalletValue.money(hidden))
            ForEach(priv, id: \.key) { held in
                walletPreviewRow(held.key, figure: mask ?? WalletValue.money(held.value),
                                 act: { homeOpen(.holdings) }) {
                    AssetMark(name: held.key, size: DS.Mark.badge)
                }
            }
        }
    }

    /// A side's name and its total: a label, never a door.
    private func homeSideHead(_ name: String, _ figure: String) -> some View {
        HStack(spacing: DS.Space.s2) {
            Text(verbatim: name).dsText(.heading17).fontWeight(.bold).foregroundStyle(DS.textPrimary)
            Spacer(minLength: DS.Space.s2)
            Text(verbatim: figure).dsText(.price17).monospacedDigit().foregroundStyle(DS.textPrimary)
        }
        .lineLimit(1)
        .frame(minHeight: 34)
        .padding(.top, DS.Space.s1)
        .accessibilityElement(children: .combine)
        .listRowInsets(.init(top: 0, leading: DSRoomChassis.rowInset, bottom: 0, trailing: DSRoomChassis.rowInset))
        .feedRowBackground()
        .listRowSeparator(.hidden)
    }

    /// Your private balance by token, with your Aztec account's private
    /// tokens beside Privacy Pools' and Railgun's: every part of the
    /// "Private" figure on the line above (`walletPrivateUSD`).
    var homePrivateByToken: [String: Double] {
        var out = walletPrivateByToken
        let aztec = AztecAccountStore.shared
        if aztec.isShown {
            for held in aztec.privateHeld {
                if let usd = aztec.usd(held, units: held.privateUnits) { out[held.name.uppercased(), default: 0] += usd }
            }
        }
        return out
    }

    // MARK: - The lines

    /// **THE WATCHLIST LEADS ACTIVITY (prd §1858, back from Holdings' section, §1857, was the Wallet
    /// section's under §1851).** Its glyph, its name, the token that moved
    /// most today; empty, the verb. It opens the watchlist.
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
                          verb: String(localized: "Watch a token"), inRowColumns: true)
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
        // Risks are never Home's ask (prd §1857, user: "risk is subjective
        // user can go there if they want to look"): its door says the count.
        if walletNeedsCount(upcoming: walletUpcoming(money)) > 0 || wants != nil || !needs.isEmpty {
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

    /// The Wallet's moves on Home, as their section says it: Activity
    /// (prd §1857, was "Wallet" under §1812). The rail's Activity page keeps
    /// "Wallet", where Activity is the page itself.
    static var homeWalletName: String { String(localized: "Activity") }

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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: DS.Space.s2) {
                    ForEach(names, id: \.self) { name in
                        Button {
                            DSHaptic.selection()
                            chrome.feedJump = name
                        } label: {
                            if let app = homeCircleApp(name, byCategory, asked: asked),
                                      BridgeIcon.hasMark(app) {
                                DSHomeCircle(name: name) {
                                    BridgeIcon(name: app, size: DS.Face.seat, circular: true)
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
            .listRowInsets(EdgeInsets())
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

    /// The circles drawn for the page's sections: every section standing on
    /// it, once the feed has a category to jump to. The Wallet alone (with
    /// or without Needs you) is the whole page: nothing to jump past, so no
    /// row. Apps' panel takes none (it is a door at the head, §1848).
    static func homeCircleNames(_ jumps: [String]) -> [String] {
        // **THE CIRCLES ARE THE FEED'S APPS (prd §1857, user: "we no longer
        // need the needs you and wallet circles do we? bc they are always at
        // the top").** Needs you, Activity and Holdings stand right under the
        // circles, so a jump to them goes nowhere.
        jumps.filter {
            $0 != PlaceTab.library.label && $0 != WalletSection.needsYou.label && $0 != homeWalletName
        }
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
