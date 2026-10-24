import SwiftUI
import SwiftData

/// **THE WALLET'S DOORS AND THE PAGES BEHIND THEM (prd §1480).**
///
/// Home is the overview: the balance and its line in the box, then six doors.
/// Holdings and Spending put their lists behind doors too, so every page fits
/// one screen and a list longer than its screen is one tap away. Every page
/// shows every account at once, and the account menu narrows it to one.
///
/// A door is one row — the page's glyph, its name, a line only where it says
/// what the figure cannot, the figure trailing, a chevron — and a press opens
/// its page (`chrome.walletSection`). A page is a `WalletSection` with no
/// tile; its title's category word goes back to the page it opened from
/// (`WalletSection.parent`, `clearRoomPick`).
extension FeedScreen {

    // MARK: - The door row

    /// One door: the page's glyph, its name, an optional line, its figure
    /// trailing and the chevron. `act` replaces opening the page (a verb row:
    /// Create an account, Follow an account, the Tokens sheet).
    @ViewBuilder
    func walletDoor(_ section: WalletSection, name: String? = nil, line: String? = nil,
                    lineTone: Color = DS.textTertiary, figure: String? = nil,
                    act: (() -> Void)? = nil) -> some View {
        // The Feed's row (prd §744), not a settings row: its 44pt head, its
        // line, and the figure in Activity's money rung, so a door and the
        // transaction under it share one pitch and one figure size.
        Button {
            DSHaptic.selection()
            if let act { act() } else { chrome.walletSection = section }
        } label: {
            DSFeedRow(name: name ?? section.label,
                      line: line.map { Text(verbatim: $0).foregroundStyle(lineTone) },
                      trailingBesideLine: true) {
                walletDoorLead(section.glyph)
            } trailing: {
                if let figure { walletRowFigure(figure) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .dsHover()
        .accessibilityLabel(Text(verbatim: [name ?? section.label, figure, line]
            .compactMap { $0 }.joined(separator: ". ")))
        .walletListRow()
    }

    /// A Wallet row's figure: Activity's money rung, tabular, one line.
    func walletRowFigure(_ figure: String, tone: Color = DS.textPrimary) -> some View {
        Text(verbatim: figure)
            .dsText(.price17)
            .monospacedDigit()
            .foregroundStyle(tone)
            .lineLimit(1)
    }

    /// Home's empty state for one account (prd §1492): the doors' rows drawn
    /// empty, under "Nothing needs you on <account>".
    var walletHomeQuiet: some View {
        let headline = roomPick.map { String(localized: "Nothing needs you on \($0)") }
            ?? String(localized: "Nothing needs you")
        return DSEmptyState(headline: Text(verbatim: headline),
                            words: Text(WalletSection.needsYou.emptyBody ?? ""),
                            scale: .list(rows: 3))
            .walletListRow()
    }

    /// The doors as one section under the tiles, no header: the title above
    /// already names the page (prd §1480, user: "do we even need to say
    /// 'Overview'").
    @ViewBuilder
    func walletDoorsSection<Rows: View>(@ViewBuilder _ rows: () -> Rows) -> some View {
        Section { rows() }
    }

    // MARK: - Home's six doors

    /// Your account's line: each control's state, a missing one in amber
    /// (prd §1480 item 2). Recovery leads, because losing the phone is the
    /// one thing the others cannot undo.
    var yourAccountLine: (text: String, wants: Bool) {
        var parts: [String] = []
        var wants = false
        if RecoveryKeyNudge.shown {
            parts.append(String(localized: "No recovery key"))
            wants = true
        } else {
            parts.append(String(localized: "Recovery on"))
        }
        if let facts = YourAccountFacts.current {
            if facts.signers > 0 {
                parts.append(facts.signers == 1 ? String(localized: "1 signer")
                                                : String(localized: "\(facts.signers) signers"))
            } else {
                parts.append(String(localized: "No signer"))
                wants = true
            }
            if let dollars = facts.limitDollars, let period = facts.limitPeriod {
                parts.append(String(localized: "$\(dollars) a \(period)"))
            }
            if let step = facts.roundUpStep {
                parts.append(String(localized: "round-ups $\(step)"))
            }
        }
        return (parts.joined(separator: " · "), wants)
    }

    /// The accounts Following lists: every slot but All and your own.
    var walletFollowingSlots: [DSAccountSlot] {
        walletAccountSlots.filter { slot in
            !slot.id.isEmpty && !Self.isYourAccount(slot.id)
        }
    }

    /// "3 wallets · 2 apps": what Following holds, by kind.
    func followingLine(_ slots: [DSAccountSlot]) -> String {
        let apps = slots.filter { RoomAccounts.isSeat($0.id) }.count
        let wallets = slots.count - apps
        var parts: [String] = []
        if wallets > 0 {
            parts.append(wallets == 1 ? String(localized: "1 wallet") : String(localized: "\(wallets) wallets"))
        }
        if apps > 0 {
            parts.append(apps == 1 ? String(localized: "1 app") : String(localized: "\(apps) apps"))
        }
        return parts.joined(separator: " · ")
    }

    /// "3 approvals · 2 delegations": the Permissions door's line.
    static func permissionsLine(_ counts: WalletSecurityCounts) -> String {
        var parts: [String] = []
        if counts.approvals > 0 {
            parts.append(counts.approvals == 1 ? String(localized: "1 approval")
                                               : String(localized: "\(counts.approvals) approvals"))
        }
        if counts.delegations > 0 {
            parts.append(counts.delegations == 1 ? String(localized: "1 delegation")
                                                 : String(localized: "\(counts.delegations) delegations"))
        }
        return parts.joined(separator: " · ")
    }

    /// "1 poisoning · 1 fake token · 1 fake transfer": the Threats door's line.
    static func threatsLine(_ counts: WalletSecurityCounts) -> String {
        var parts: [String] = []
        if counts.poisoning > 0 { parts.append(String(localized: "\(counts.poisoning) poisoning")) }
        if counts.fakeTokens > 0 {
            parts.append(counts.fakeTokens == 1 ? String(localized: "1 fake token")
                                                : String(localized: "\(counts.fakeTokens) fake tokens"))
        }
        if counts.fakeTransfers > 0 {
            parts.append(counts.fakeTransfers == 1 ? String(localized: "1 fake transfer")
                                                   : String(localized: "\(counts.fakeTransfers) fake transfers"))
        }
        return parts.joined(separator: " · ")
    }

    /// A card's ask (prd §1480 item 8): an amount due, or an offer ending
    /// within a week. Nil when the card asks nothing.
    static func cardAsk(_ card: WalletCardRoll.Card, now: Date = .now) -> String? {
        let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
        if let due = card.due {
            if let owed = card.owed {
                return String(localized: "\(mask ?? CardSpendRoom.money(owed, code: card.owedCurrency)) due \(WalletSubscriptionRow.day(due))")
            }
            return String(localized: "Due \(WalletSubscriptionRow.day(due))")
        }
        if card.offers > 0, let ends = card.offerEnds, ends.timeIntervalSince(now) < 7 * 86_400 {
            return String(localized: "\(cardOffersWords(card.offers)), the first ends \(WalletSubscriptionRow.day(ends))")
        }
        return nil
    }

    /// Every ask Needs you holds, counted once: the undated and dated rows
    /// Home's list led with, a Safe signature waiting, the key nudges and
    /// the cards that ask.
    func walletNeedsCount(upcoming: [Thing]) -> Int {
        let groups = walletComingUpDays(upcoming)
        let rows = Self.things(groups.flatMap(\.1)).filter(\.isLive).count
        let onAll = selectedSeat == nil && selectedWallet == nil
        let nudges = (onAll && OutsideKeyNudge.shown ? 1 : 0) + (onAll && RecoveryKeyNudge.shown ? 1 : 0)
        let cards = onAll ? SpendingReading.shared.cards.filter { Self.cardAsk($0) != nil }.count : 0
        return rows + walletSignatureWarnings.count + nudges + cards
    }

    /// **HOME, THE OVERVIEW (prd §1480 item 2).** Under the box and the
    /// tiles, six doors: Your account, Following, Needs you, Permissions,
    /// Threats, Markets. Needs you, Permissions and Threats draw no row while
    /// empty; Your account stands on All or with your account picked.
    @ViewBuilder
    func walletHomeDoors(upcoming: [Thing]) -> some View {
        let onAll = selectedSeat == nil && selectedWallet == nil
        let yours = YourAccountDemo.shownAddress
        let yoursPicked = yours.map { a in chrome.walletScope.map { WalletWatch.sameAddress($0, a) } ?? false } ?? false
        let following = walletFollowingSlots
        let needs = walletNeedsCount(upcoming: upcoming)
        let counts = walletSecurityCounts
        let permissions = counts.delegations + counts.approvals
        walletDoorsSection {
            if yours != nil, onAll || yoursPicked {
                let line = yourAccountLine
                walletDoor(.yourAccount, line: line.text,
                           lineTone: line.wants ? DS.attentionInk : DS.textTertiary)
            } else if yours == nil, onAll {
                // **NONE YET: THE VERB (prd §1480 item 2).** Move makes it.
                walletDoor(.yourAccount, name: String(localized: "Create an account"),
                           act: { chrome.moveTray = true })
            }
            // **FOLLOWING AND MARKETS ARE THE ROOM'S, NOT AN ACCOUNT'S (prd
            // §1491, user: "i am on railgun and see 'markets' why is that?"):**
            // with one account picked, Home lists only what is that account's.
            if onAll {
                if following.isEmpty {
                    walletDoor(.following, name: String(localized: "Follow an account"),
                               act: { feedSheet = .walletFollow })
                } else {
                    walletDoor(.following, line: followingLine(following), figure: "\(following.count)")
                }
            }
            if needs > 0 {
                walletDoor(.needsYou, figure: "\(needs)")
            }
            if permissions > 0 {
                // A grant with no limit wants you (prd §1107a).
                walletDoor(.permissions, line: Self.permissionsLine(counts),
                           lineTone: counts.unlimited > 0 ? DS.attentionInk : DS.textTertiary,
                           figure: "\(permissions)")
            }
            if counts.flagged > 0 {
                // Every threat is red (prd §1463).
                walletDoor(.threats, line: Self.threatsLine(counts),
                           lineTone: DS.destructiveInk, figure: "\(counts.flagged)")
            }
            if onAll {
                let watched = marketsWatches(walletMarketsRows).count
                walletDoor(.markets, line: watched == 0 ? String(localized: "Follow a coin or a stock") : nil,
                           figure: watched == 0 ? nil : "\(watched)")
            }
            // **ONE ACCOUNT WITH NOTHING ON HOME SAYS SO (prd §1492, user: "ok"
            // to "Nothing needs you on Railgun").** With Following and Markets
            // on All only (§1491), an app with no asks, grants or threats left
            // Home blank under the tiles. §769's empty state fills it: what
            // would stand here, empty, and the account named. The pick still
            // lands on Home; it never jumps to Activity.
            if !onAll, !(yours != nil && yoursPicked), needs == 0, permissions == 0, counts.flagged == 0 {
                walletHomeQuiet
            }
        }
        // **BESIDE A PANE THE DOORS STAY IN THE LIST (prd §1480 item 11):**
        // they are Home's only list, so the list column keeps them and the
        // pane keeps the balance; a page opens in the list column.
        .task(id: walletMarketsKey) { loadWalletMarkets() }
        // The cards' asks need the Spending reading, which starts here
        // whatever Home shows (it did under the deleted Spending list).
        .task(id: walletSpendingKey) { await SpendingReading.shared.refresh(modelContext) }
    }

    // MARK: - Holdings' doors

    /// What each account holds, summed off the portfolio's holders: an
    /// address, or a venue (an exchange, validators, cash, Privy).
    var walletHolderTotals: [WalletPortfolio.Holder] {
        guard let positions = portfolioShown?.positions else { return [] }
        var byID: [String: (label: String, usd: Double)] = [:]
        for position in positions {
            for holder in position.holders {
                byID[holder.address, default: (holder.label, 0)].usd += holder.usd
            }
        }
        return byID.map { WalletPortfolio.Holder(address: $0.key, label: $0.value.label, usd: $0.value.usd) }
            .sorted { $0.usd > $1.usd }
    }

    /// The Accounts page's addresses and venues: your own account first,
    /// whatever it holds — a $0 account is still yours to open — then the
    /// rest largest first.
    var walletAccountHolders: [WalletPortfolio.Holder] {
        var holders = walletHolderTotals
        guard selectedSeat == nil, let own = YourAccountDemo.shownAddress else { return holders }
        let mine = holders.firstIndex { WalletWatch.sameAddress($0.address, own) }
            .map { holders.remove(at: $0) }
        holders.insert(mine ?? WalletPortfolio.Holder(address: own, label: String(localized: "Your account"), usd: 0),
                       at: 0)
        return holders
    }

    /// **HOLDINGS, WHAT THE MONEY IS (prd §1480 item 4).** The treemap in the
    /// box, then five doors: Accounts, Tokens, Positions, Apps, NFTs.
    @ViewBuilder
    func walletHoldingsDoors(all: [Thing]) -> some View {
        let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
        let holders = walletAccountHolders
        let appAccounts = walletAccountRows(all)
        let apps = walletAppRows(all)
        let tokens = portfolioShown?.positions ?? []
        let tokensUSD = tokens.reduce(0) { $0 + $1.usd }
        // Every token hidden still leaves the door, to the Hidden row.
        let anyHidden = portfolioUnhidden?.positions.contains { walletHidden.contains($0.symbol.uppercased()) } ?? false
        let positions = walletPositionCount
        walletDoorsSection {
            if !holders.isEmpty || !appAccounts.isEmpty {
                walletDoor(.holdingAccounts, figure: "\(holders.count + appAccounts.count)")
            }
            if !tokens.isEmpty || anyHidden {
                walletDoor(.holdings, name: String(localized: "Tokens"),
                           line: tokens.count == 1 ? String(localized: "1 token")
                                                   : String(localized: "\(tokens.count) tokens"),
                           figure: mask ?? WalletValue.money(tokensUSD),
                           act: { feedSheet = .walletTokens })
            }
            if positions > 0 {
                walletDoor(.positions, figure: "\(positions)")
            }
            if !apps.isEmpty {
                walletDoor(.apps, figure: "\(apps.count)")
            }
            // An app the menu picked holds no collections (prd §1048b).
            if selectedSeat == nil {
                walletDoor(.nfts)
            }
        }
    }

    /// How many positions Holdings' Positions page lists, by kind.
    var walletPositionCount: Int {
        (hasLendingCard ? 1 : 0)
            + walletLive.hyperliquid.positions.count
            + walletLive.uniswap.positions.count
            + walletLive.aztecStaking.stakes.count
            + walletLive.zfiOrders.orders.count
    }

    // MARK: - Spending's doors

    /// **SPENDING, A READING OF ACTIVITY (prd §1480 item 5).** The window's
    /// total in the box, then three doors: Subscriptions, Places, Fees — one
    /// name per group, the box's Recurring and The rest retired.
    @ViewBuilder
    var walletSpendingDoors: some View {
        let reading = SpendingReading.shared
        let page = reading.page
        let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
        if !(page.places.isEmpty && page.subscriptions.isEmpty && page.fees.isEmpty) {
            walletDoorsSection {
                if !page.subscriptions.isEmpty {
                    walletDoor(.subscriptions,
                               line: page.subscriptions.count == 1 ? String(localized: "1 plan")
                                                                   : String(localized: "\(page.subscriptions.count) plans"),
                               figure: mask ?? AppleWalletRoom.money(page.recurring, "USD"))
                }
                if !page.places.isEmpty {
                    walletDoor(.places,
                               line: page.places.first.map { String(localized: "\($0.name) the most") },
                               figure: mask ?? AppleWalletRoom.money(page.rest, "USD"))
                }
                if !page.fees.isEmpty {
                    // Not in the total (prd §1476 item 1), and said so.
                    walletDoor(.fees, line: WalletSpendingFigure.feesLine(page, mask: mask),
                               figure: mask ?? AppleWalletRoom.money(page.feesTotal, "USD"))
                }
            }
        } else if reading.read {
            walletSkeletonRowsSection
        }
    }

    // MARK: - The pages

    /// **THE LIST UNDER A PAGE (prd §1480).** Each page draws the sections
    /// that shipped elsewhere, moved and not redrawn: Your account is
    /// `MoveSecurity`, Permissions and Threats are Security's groups, Places
    /// and Fees are Spending's.
    @ViewBuilder
    func walletPageSections(_ section: WalletSection, all: [Thing], upcoming: [Thing],
                            nextEventID: UUID?) -> some View {
        switch section {
        case .yourAccount:
            walletAccountSection
        case .following:
            walletFollowingPage
        case .needsYou:
            walletNeedsYouPage(upcoming: upcoming, nextEventID: nextEventID)
        case .permissions:
            if counts(\.delegations) + counts(\.approvals) == 0 { walletSkeletonRowsSection }
            walletActingSection
            walletApprovalsSection
        case .threats:
            if walletSecurityCounts.flagged == 0 { walletSkeletonRowsSection }
            walletFlaggedSection(.poisoning, anchor: .poisoning,
                                 word: String(localized: "Address poisoning"))
            walletFlaggedSection(.spoofedSymbol, anchor: .fakeTokens,
                                 word: String(localized: "Fake tokens"))
            walletFlaggedSection(.fakeTransfer, anchor: .fakeTransfers,
                                 word: String(localized: "Fake transfers"))
        case .holdingAccounts:
            walletHolderAccountsPage(all: all, nextEventID: nextEventID)
        case .positions:
            if walletPositionCount == 0 { walletSkeletonRowsSection }
            walletPositionsSections
        case .apps:
            let apps = walletAppRows(all)
            if apps.isEmpty { walletSkeletonRowsSection }
            walletAppsSection(apps, nextEventID: nextEventID)
        case .nfts:
            if nftShelfEntry == nil {
                walletNFTDoorSection
            }
            walletNFTListSection
        case .places:
            walletSpendingGroup(.places)
        case .fees:
            walletSpendingGroup(.fees)
        default:
            EmptyView()
        }
    }

    private func counts(_ key: KeyPath<WalletSecurityCounts, Int>) -> Int {
        walletSecurityCounts[keyPath: key]
    }

    /// Following's page: every account you follow and every app folded in,
    /// your own account apart (it is Your account's), then the ways in.
    @ViewBuilder
    var walletFollowingPage: some View {
        let slots = walletFollowingSlots
        if slots.isEmpty { walletSkeletonRowsSection }
        walletCard(WalletSection.following.label, glyph: WalletSection.following.glyph) {
            ForEach(slots) { slot in walletAccountRow(slot) }
        }
        .alert(String(localized: "Name this account"),
               isPresented: Binding(get: { walletNaming != nil }, set: { if !$0 { walletNaming = nil } })) {
            TextField(String(localized: "Name"), text: $walletNameDraft)
            Button(String(localized: "Save")) { saveWalletName() }
            Button(String(localized: "Cancel"), role: .cancel) { walletNaming = nil }
        } message: {
            Text(String(localized: "Blank shows the address instead."))
        }
        Section {
            ForEach(walletAccountAdds.filter { $0.label != String(localized: "Create an account") }, id: \.label) { add in
                DSPushRow(title: Text(verbatim: add.label), tint: DS.pickInk, opens: false) {
                    DSHaptic.selection()
                    add.act()
                } leading: {
                    walletDoorLead(add.glyph ?? ScopeTileGlyph.new)
                }
                .walletListRow()
            }
        }
    }

    /// Needs you's page: a Safe signature waiting first (power over your
    /// money, §947), then the key nudges, the undated asks, the cards that
    /// ask, then the dated rows under their days. No cap: the page is the
    /// list.
    @ViewBuilder
    func walletNeedsYouPage(upcoming: [Thing], nextEventID: UUID?) -> some View {
        let groups = walletComingUpDays(upcoming)
        let needs = groups.first { $0.0 == Self.needsYouGroup }?.1 ?? []
        let dated = groups.filter { $0.0 != Self.needsYouGroup }
        let onAll = selectedSeat == nil && selectedWallet == nil
        let cards = onAll ? SpendingReading.shared.cards.filter { Self.cardAsk($0) != nil } : []
        if walletNeedsCount(upcoming: upcoming) == 0 { walletSkeletonRowsSection }
        walletSignaturesSection
        Section {
            if onAll && RecoveryKeyNudge.shown { RecoveryKeyNudge().listRow }
            if onAll && OutsideKeyNudge.shown { OutsideKeyNudge().listRow }
        }
        if !needs.isEmpty {
            walletDaySections([(Self.needsYouGroup, needs)], boundary: nil,
                              named: [Self.needsYouGroup], headless: true, nextEventID: nextEventID)
        }
        if !cards.isEmpty {
            walletCard(String(localized: "Cards"), glyph: ScopeTileGlyph.cards) {
                ForEach(cards) { card in
                    let app = BridgeCatalog.seatName(forSource: card.app)
                    Button {
                        route.openSetup(forOffer: app)
                    } label: {
                        DSFeedRow(name: card.name, line: Text(verbatim: Self.cardAsk(card) ?? "")) {
                            BridgeIcon(name: app, size: DS.Face.row, circular: true)
                        } trailing: { EmptyView() }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPress())
                    .walletListRow()
                }
            }
        }
        if !dated.isEmpty {
            walletDaySections(dated, boundary: nil, nextEventID: nextEventID)
        }
    }

    /// Holdings' Accounts page: each account's balance, largest first, then
    /// what an app holds for you as it read it (§1341), which the total
    /// leaves out.
    @ViewBuilder
    func walletHolderAccountsPage(all: [Thing], nextEventID: UUID?) -> some View {
        let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
        let holders = walletAccountHolders
        let appAccounts = walletAccountRows(all)
        if holders.isEmpty && appAccounts.isEmpty { walletSkeletonRowsSection }
        if !holders.isEmpty {
            walletCard(WalletSection.holdingAccounts.label, glyph: WalletSection.holdingAccounts.glyph) {
                ForEach(holders) { holder in
                    let isVenue = WalletPortfolio.isVenue(holder.address)
                    // Your own account keeps a name you gave it, else "Your account".
                    let watchedLabel = wallet.addresses.first { WalletWatch.sameAddress($0.address, holder.address) }
                        .map(\.label).flatMap { $0.isEmpty ? nil : $0 }
                    let name = isVenue ? holder.label
                        : watchedLabel ?? (Self.isYourAccount(holder.address) ? String(localized: "Your account")
                                                                                : WalletStore.shortAddress(holder.address))
                    Button {
                        DSHaptic.selection()
                        if !isVenue { withAnimation(DS.Motion.standard) { chrome.walletScope = holder.address } }
                    } label: {
                        DSFeedRow(name: name, trailingBesideLine: true) {
                            Group {
                                if let app = Self.privyApp(holder.address), app.logoURL != nil {
                                    // A Privy app wears its own logo, as Privy's
                                    // room draws it; the catalogue has none.
                                    PrivyAppMark(logoURL: app.logoURL)
                                } else if isVenue {
                                    BridgeIcon(name: holder.label, size: DS.Face.row)
                                } else {
                                    WalletFace(address: holder.address, size: DS.Face.row, circular: true)
                                }
                            }
                        } trailing: {
                            walletRowFigure(mask ?? WalletValue.money(holder.usd))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPress())
                    .dsHover()
                    .walletListRow()
                }
            }
        }
        walletAccountsSection(appAccounts, nextEventID: nextEventID)
    }

    /// The Privy app a `privy:` holder names, for its logo.
    static func privyApp(_ holderID: String) -> PrivyHomeFeed.App? {
        guard holderID.hasPrefix(WalletPortfolio.privyHolderPrefix) else { return nil }
        let id = String(holderID.dropFirst(WalletPortfolio.privyHolderPrefix.count))
        return PrivyHomeStore.shared.apps.first { $0.id == id }
    }

    // MARK: - The pages' boxes

    /// **A PAGE'S BOX (prd §1480).** A page with a figure of its own draws
    /// it; a door's page states its count; Holdings' and Spending's pages
    /// keep their tile's figure, so the box says which tile you are in.
    @ViewBuilder
    func walletPageFigure(_ section: WalletSection, upcoming: [Thing]) -> some View {
        switch section {
        case .yourAccount:
            WalletYourAccountFigure(address: YourAccountDemo.shownAddress)
        case .following:
            let slots = walletFollowingSlots
            DSFigureReading(number: "\(slots.count)",
                            caption: slots.isEmpty ? String(localized: "Nothing followed") : followingLine(slots))
        case .needsYou:
            let n = walletNeedsCount(upcoming: upcoming)
            DSFigureReading(number: "\(n)", caption: String(localized: "waiting on you"))
        case .permissions:
            let c = walletSecurityCounts
            DSFigureReading(number: "\(c.delegations + c.approvals)",
                            caption: String(localized: "can spend from you"),
                            alarm: c.unlimited > 0 ? String(localized: "\(c.unlimited) with no limit") : nil)
        case .threats:
            DSFigureReading(number: "\(walletSecurityCounts.flagged)",
                            caption: String(localized: "trying to fool you"))
        default:
            EmptyView()
        }
    }

    /// Spending's group on its own page, as the Spending tile listed it.
    @ViewBuilder
    func walletSpendingGroup(_ section: WalletSection) -> some View {
        let reading = SpendingReading.shared
        let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
        switch section {
        case .places:
            if reading.page.places.isEmpty { walletSkeletonRowsSection }
            if !reading.page.places.isEmpty {
                walletCard(WalletSection.places.label, glyph: WalletSection.places.glyph) {
                    ForEach(reading.page.places, id: \.name) { place in
                        spendingPlaceRow(place, window: reading.window, mask: mask)
                    }
                }
            }
        case .fees:
            if reading.page.fees.isEmpty { walletSkeletonRowsSection }
            if !reading.page.fees.isEmpty {
                walletCard(WalletSection.fees.label, glyph: WalletSection.fees.glyph) {
                    ForEach(reading.page.fees, id: \.name) { network in
                        spendingFeeRow(network, window: reading.window, mask: mask)
                    }
                }
            }
        default:
            EmptyView()
        }
    }

    // MARK: - Activity

    /// **ACTIVITY, THE STREAM (prd §1480 item 3).** Every transaction by day,
    /// no header, no cap but the room's own fetch, then the door to the whole
    /// history behind it.
    @ViewBuilder
    func walletActivitySections(_ all: [Thing], nextEventID: UUID?) -> some View {
        let moves = Self.walletMoves(all)
        let stream = walletStream(moves, cap: nil)
        if stream.rows.isEmpty {
            walletSkeletonRowsSection
        } else {
            walletStreamSections(stream.rows, ownMoves: stream.ownMoves, nextEventID: nextEventID)
            walletSeeAllSection(total: moves.count)
        }
    }
}

/// **YOUR ACCOUNT'S BOX (prd §1480 item 6):** who it is — the face, the name,
/// the address to copy — the way Apple's own account page opens.
struct WalletYourAccountFigure: View {
    let address: String?
    @Environment(ShellChrome.self) private var chrome

    var body: some View {
        VStack(spacing: DS.Space.s2) {
            if let address {
                // A profile's face (`DS.Face.profile`), as a person's page opens.
                WalletFace(address: address, size: DS.Face.profile, circular: true)
                Text(verbatim: WalletStore.shared.displayName(forWatched: address) ?? WalletStore.yourAccountName)
                    .dsText(.heading24).foregroundStyle(DS.textPrimary)
                Button {
                    DSHaptic.selection()
                    UIPasteboard.general.string = address
                    chrome.flash(String(localized: "Address copied"), tone: .success)
                } label: {
                    HStack(spacing: DS.Space.s1) {
                        Text(verbatim: WalletStore.shortAddress(address))
                            .dsText(.body17).monospacedDigit()
                        Image(systemName: "doc.on.doc").dsGlyph(.body).accessibilityHidden(true)
                    }
                    .foregroundStyle(DS.textSecondary)
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPress())
                .accessibilityLabel(Text("Copy address"))
            } else {
                DSFigureReading(number: String(localized: "No account yet"),
                                caption: String(localized: "Move makes one"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
