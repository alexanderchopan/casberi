import SwiftUI
import SwiftData

/// **THE WALLET'S DOORS AND THE PAGES BEHIND THEM (prd §1480).**
///
/// Home is the overview: the balance and its line in the box, then five doors (Markets is a tile, §1498).
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

    /// **A DOOR IS A SECTION'S NAME WITH A FIGURE (prd §1496, user: "i think
    /// the 24 size is good"; "would apple show the subtext on home?").** The
    /// page's glyph in the Feed header's column, its name at the section
    /// rung, its figure trailing at the same rung, no line, every door one
    /// height: a Feed section and a Wallet door are one anatomy, and Home
    /// scans as a list of names and numbers. What a door's line said (a count
    /// by kind, a state) is the page's; the state Home must show rides the
    /// figure's ink (`figureTone`, §1004: a status takes the ink), or a short
    /// `word` at the row rung in its ink where there is no figure ("No
    /// recovery key", amber — the way Apple trails "Off"). `act` replaces
    /// opening the page (a verb row: Create an account, Follow an account,
    /// the Tokens sheet).
    @ViewBuilder
    func walletDoor(_ section: WalletSection, name: String? = nil, figure: String? = nil,
                    figureTone: Color = DS.textPrimary, word: String? = nil,
                    wordTone: Color = DS.textSecondary, act: (() -> Void)? = nil) -> some View {
        walletDoorRow(name: name ?? section.label, figure: figure,
                      figureTone: figureTone, word: word, wordTone: wordTone, opens: act == nil) {
            if let act { act() } else { chrome.walletSection = section }
        }
        // Where back from this door's page lands (prd §1587).
        .id(Self.walletDoorAnchor(section))
    }

    /// A door's row, drawn for a section or by hand.
    ///
    /// **A DOOR WEARS A CHEVRON, A SECTION'S NAME DOES NOT (prd §1815, user:
    /// "door wears a chevron; yes").** With the glyphs gone (§1814)
    /// "Following 4" and "Keys" drew alike, and one opens a page. `opens`:
    /// the row goes to a page; a verb or a sheet (`act`) draws none.
    func walletDoorRow(name: String, figure: String? = nil,
                       figureTone: Color = DS.textPrimary, word: String? = nil,
                       wordTone: Color = DS.textSecondary, opens: Bool = false,
                       act: @escaping () -> Void) -> some View {
        Button {
            DSHaptic.selection()
            act()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: DSRoomChassis.headGap) {
                // No glyph, at the left edge (prd §1814).
                Text(verbatim: name)
                    .dsText(.heading24)
                    .foregroundStyle(DS.headInk)
                    .lineLimit(1)
                    // The name keeps its width; a trailing word gives way
                    // ("Apple Wall…" beside "Synced 6m ago", prd §1618).
                    .layoutPriority(1)
                Spacer(minLength: DS.Space.s2)
                if let figure {
                    Text(verbatim: figure)
                        .dsText(.stat24)
                        .monospacedDigit()
                        .foregroundStyle(figureTone)
                        .lineLimit(1)
                        // A count that changes rolls, never pops (prd §1587).
                        .contentTransition(.numericText())
                        .animation(DS.Motion.standard, value: figure)
                } else if let word {
                    Text(verbatim: word)
                        .dsText(.body17)
                        .foregroundStyle(wordTone)
                        .lineLimit(1)
                }
                if opens {
                    Image(systemName: "chevron.right")
                        .dsGlyph(.tick, weight: .bold)
                        .foregroundStyle(DS.textSecondary)
                        .accessibilityHidden(true)
                }
            }
            .walletRowPitch()
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .dsHover()
        .accessibilityLabel(Text(verbatim: [name, figure ?? word]
            .compactMap { $0 }.joined(separator: ". ")))
        .walletListRow()
    }

    static func walletDoorAnchor(_ section: WalletSection) -> String { "wallet.door.\(section.rawValue)" }

    /// A Wallet row's figure: Activity's money rung, tabular, one line.
    func walletRowFigure(_ figure: String, tone: Color = DS.textPrimary) -> some View {
        Text(verbatim: figure)
            .dsText(.price17)
            .monospacedDigit()
            .foregroundStyle(tone)
            .lineLimit(1)
    }

    /// The doors as one section under the tiles, no header: the title above
    /// already names the page (prd §1480, user: "do we even need to say
    /// 'Overview'").
    @ViewBuilder
    func walletDoorsSection<Rows: View>(@ViewBuilder _ rows: () -> Rows) -> some View {
        Section { rows() }
    }

    /// Needs you's count on one account, for its cleared beat (prd §1587).
    struct NeedsBeat: Equatable { let scope: String?; let needs: Int; var demo = DemoMode.isActive }

    // MARK: - Home's five doors

    /// What Your account's door trails, in amber: the control that is missing
    /// (prd §1480 item 2, §1496), nothing when every key stands. Recovery
    /// leads, because losing the phone is the one thing the others cannot
    /// undo; the rest of the line ("1 signer · $100 a month · round-ups $1")
    /// is the page's.
    var yourAccountWants: String? {
        var parts: [String] = []
        if RecoveryKeyNudge.shown { parts.append(String(localized: "No recovery key")) }
        if let facts = YourAccountFacts.current, facts.signers == 0 {
            parts.append(parts.isEmpty ? String(localized: "No co-signer") : String(localized: "no co-signer"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The accounts Following lists: the wallets you follow, never All, your
    /// own, or an app the Wallet folded in (prd §1504, user: "i'm nto
    /// following any wallets so why would it show Safe") — an app is
    /// Holdings' Apps, and the account menu still picks it.
    var walletFollowingSlots: [DSAccountSlot] {
        walletAccountSlots.filter { slot in
            !slot.id.isEmpty && !Self.isYourAccount(slot.id) && !RoomAccounts.isSeat(slot.id)
        }
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

    /// Private money is yours (prd §1561): its asks stand on All and with
    /// your account picked, never on another account's or Following's.
    var walletShowsPrivate: Bool {
        if walletOnAll { return true }
        guard let yours = YourAccountDemo.shownAddress, let scope = chrome.walletScope else { return false }
        return WalletWatch.sameAddress(scope, yours)
    }

    /// Every ask Needs you holds, counted once: the undated and dated rows
    /// Home's list led with, a Safe signature waiting, the key nudges and
    /// the cards that ask.
    func walletNeedsCount(upcoming: [Thing]) -> Int {
        let groups = walletComingUpDays(upcoming)
        let rows = Self.things(groups.flatMap(\.1)).filter(\.isLive).count
        let onAll = walletOnAll
        let nudges = (onAll && OutsideKeyNudge.shown ? 1 : 0) + (onAll && RecoveryKeyNudge.shown ? 1 : 0)
            + (onAll && RecoveryCheckNudge.shown ? 1 : 0)
        let cards = onAll ? SpendingReading.shared.cards.filter { Self.cardAsk($0) != nil }.count : 0
        // A deposit waiting for 0xBow's approval, or refused (prd §1561).
        let deposits = walletShowsPrivate ? PrivateMoneyStore.shared.asks().count : 0
        // A limit order waiting for its price (prd §1673 item 7).
        let orders = walletShowsPrivate ? YourAccountOrders.open.count : 0
        // Money on its way out of Aztec, to finish on Ethereum (prd §1700e).
        let exits = walletShowsPrivate ? AztecAccountStore.shared.pendingExits.count : 0
        return rows + walletSignatureWarnings.count + nudges + cards + deposits + orders + exits
    }

    /// **HOME, THE OVERVIEW (prd §1480 item 2).** Under the box and the
    /// tiles, five doors: Your account, Following, Needs you, Permissions,
    /// Threats (Markets is a tile, §1498). Needs you, Permissions and Threats
    /// STAND while empty on All and on a picked account (prd §1729): a fresh
    /// account otherwise never met the Threats page, where Privacy by Nymis
    /// lives (§1701). On an app pick, Permissions and Threats still leave
    /// while empty (§1618). Your account stands on All or with your account picked.
    @ViewBuilder
    func walletHomeDoors(upcoming: [Thing]) -> some View {
        let onAll = walletOnAll
        let yours = YourAccountDemo.shownAddress
        let yoursPicked = yours.map { a in chrome.walletScope.map { WalletWatch.sameAddress($0, a) } ?? false } ?? false
        let following = walletFollowingSlots
        let needs = walletNeedsCount(upcoming: upcoming)
        let counts = walletSecurityCounts
        let permissions = counts.delegations + counts.approvals + (walletShowsAztecGrants ? AztecGrantsStore.shared.grants.count : 0)
        // One account with nothing on Home (prd §1492's quiet state).
        let quiet = !onAll && !walletOnFollowing && !(yours != nil && yoursPicked)
            && needs == 0 && permissions == 0 && counts.flagged == 0
        // The walk's close re-reads the pending mark below (prd §1741b).
        let walkClosed = chrome.walkClosed
        walletDoorsSection {
          // HOME IS SIX CARDS (prd §1807) on the whole Wallet; an app or
          // Following picked keeps its doors, which are that pick's own.
          if selectedSeat == nil, !walletOnFollowing {
            walletHomeCards(yours: yours, walkClosed: walkClosed, onAll: onAll,
                            yoursPicked: yoursPicked, flagged: counts.flagged)
          } else {
            // Account (prd §1536): your Casberi account's keys and settings,
            // not a pick — Yours on the switch is the pick.
            if let yours, walkClosed >= 0, YourAccountFirstOpen.setupPending(yours), onAll || yoursPicked {
                // **MADE FOR YOU, THE WALK BEHIND THE DOOR (prd §1741, user:
                // "i don't like … that it says no recovery key bc there is
                // more in there for a user like roundups").** One word for
                // everything the walk holds; the tap opens the walk.
                walletDoor(.yourAccount, word: String(localized: "Finish setup"), wordTone: DS.attentionInk,
                           act: {
                               chrome.moveWalk = true
                               chrome.moveTray = true
                           })
            } else if yours != nil, onAll || yoursPicked {
                walletDoor(.yourAccount, word: yourAccountWants, wordTone: DS.attentionInk)
                    // Read when Home stands, never in a body (prd §1515): the
                    // demo, and a launch before the first foreground sweep.
                    .task { RecoveryCheckState.shared.refresh() }
            } else if yours == nil, onAll {
                // **NONE YET: THE VERB (prd §1480 item 2).** Move makes it.
                walletDoor(.yourAccount, name: String(localized: "Create an account"),
                           act: { chrome.moveTray = true })
                    // The first open of an empty Wallet makes it (prd §1741);
                    // in a task, never a body (a Keychain read, prd §628).
                    .task { YourAccountFirstOpen.makeIfFresh() }
            }
            // **FOLLOWING IS THE ROOM'S, NOT AN ACCOUNT'S (prd §1491, user: "i
            // am on railgun and see 'markets' why is that?"):** with one
            // account picked, Home lists only what is that account's. Markets
            // left Home for its own tile (§1498), dimmed on a pick.
            // Following is a word on the switch (prd §1536), its wallets
            // listed on Home when it is lit; with none followed, the verb.
            if onAll, following.isEmpty {
                walletDoor(.following, name: String(localized: "Follow an account"),
                           act: { feedSheet = .walletFollow })
            }
            // **EVERY APP NAMES ITS ACCOUNT (prd §1618 item 1, user: "you would
            // think all of them have an account row naming the account too").**
            // The line its own account page states; the row opens that page.
            if let seat = selectedSeat {
                walletDoor(.yourAccount, name: seat.name,
                           word: bridges.bridges.first { seat.owns($0.name) }?.statusLine,
                           act: { openAppPage(seat.name) })
            }
            // **NEEDS YOU STANDS AT 0 (prd §1618 item 1 on an app, §1729
            // everywhere, user: "Yes, build A").** A COUNT IS WHITE (prd
            // §1737, user: "we can just make them all white. b/c it is really
            // subjective isn't it?"): pink, amber and red stood on three doors
            // in a row and which count earned which was a judgement. The door
            // says what it counts; none is grey.
            walletDoor(.needsYou, figure: "\(needs)", figureTone: needs > 0 ? DS.textPrimary : DS.textSecondary)
            // **PERMISSIONS AND THREATS STAND WHILE EMPTY (prd §1729, user:
            // "they wouldn't see … that they can use something like nymis").**
            // A door that leaves while empty hides the page behind it: a fresh
            // account never reached Threats, where Privacy by Nymis lives
            // (§1701). So on All and on a picked account the two doors stand,
            // their state one grey word (§1496). On an app pick they still
            // leave while empty: the app's page is its own (§1618).
            // ONE row per door, its trailing text computed: two rows under one
            // anchor crossfade as the counts land (seen: "None" under "5").
            let appPicked = selectedSeat != nil
            if permissions > 0 || !appPicked {
                // The count is white (prd §1737); a grant with no limit is
                // said on its own row inside (prd §1107a).
                walletDoor(.permissions, figure: permissions > 0 ? "\(permissions)" : nil,
                           figureTone: DS.textPrimary,
                           word: permissions > 0 ? nil : String(localized: "None"))
            }
            if counts.flagged > 0 || !appPicked {
                // Every threat is red on its own row (prd §1463); the door's
                // count is white (prd §1737). The count is what you have
                // not seen yet, and none left says so (prd §1587). No threat
                // found, and the word says whether Nymis has looked (§1729
                // item 2): "Unscanned" while an account in scope has never
                // been read, "None" once every one has.
                let unseen = walletLive.flagged.live.filter { !ThreatsSeen.shared.contains($0.id) }.count
                let word: String? = counts.flagged > 0
                    ? (unseen > 0 ? nil : String(localized: "All seen"))
                    : (walletPrivacySlots.contains { NymisScans.shared.reading($0.id) == nil }
                       ? String(localized: "Unscanned") : String(localized: "None"))
                walletDoor(.threats, figure: unseen > 0 ? "\(unseen)" : nil,
                           figureTone: DS.textPrimary, word: word)
            }
            // §1492's quiet state ("Nothing needs you on Railgun") is deleted
            // (prd §1729): the doors standing at 0 and None say it, and an app
            // picked draws its account and Needs you instead (§1618).
          }
        }
        // **AN APP PICKED WITH NOTHING ON HOME OPENS ON ITS ACTIVITY (prd
        // §1615 item 6, user: "yes", reversing §1492's "never jumps").** Ten Wallet
        // apps opened on "Nothing needs you on Peer" with their rows a tap
        // away. Once per pick, so the Home tile still stands on Home.
        .task(id: chrome.walletScope) {
            guard chrome.walletPickLanding else { return }
            chrome.walletPickLanding = false
            if quiet { chrome.walletSection = .activity }
        }
        // **BESIDE A PANE THE DOORS STAY IN THE LIST (prd §1480 item 11):**
        // they are Home's only list, so the list column keeps them and the
        // pane keeps the balance; a page opens in the list column.
        // The cards' asks need the Spending reading, which starts here
        // whatever Home shows (it did under the deleted Spending list).
        // After the open has drawn and the hand is still: the reading is two
        // months of rows, fetched on the main actor, and Home draws without it
        // (docs/specs/wallet-perf-spec.md B4).
        .task(id: walletSpendingKey) {
            await GestureGate.idle()
            guard !Task.isCancelled else { return }
            // Subscriptions first, as Spending's page does: a plan tracked by
            // hand counts on its renewal day from that reading, and once this
            // key has run, the page's own refresh leaves.
            await SubscriptionsReading.shared.refresh(modelContext, key: walletSubscriptionsKey)
            await SpendingReading.shared.refresh(modelContext, key: walletSpendingKey)
        }
        // **THE LAST ASK CLEARED IS A MOMENT (prd §1587).** Needs you going
        // to nothing on the same account plays one success beat and says so;
        // a scope switch that changes the count is not one.
        .onChange(of: NeedsBeat(scope: chrome.walletScope, needs: needs)) { was, now in
            guard was.scope == now.scope, was.demo == now.demo, was.needs > 0, now.needs == 0 else { return }
            // A pick's rows settle for a moment after it lands, and a count
            // that falls then cleared nothing (prd §1618 item 8: "Nothing needs
            // you" flashed on opening Railgun).
            guard Date().timeIntervalSince(chrome.walletScopeChangedAt) > 3 else { return }
            chrome.flash(String(localized: "Nothing needs you"), tone: .success)
        }
        // A deposit's approval is asked here too, so Needs you's count is
        // the ASP's latest when Home stands (prd §1561; spaced 20 s).
        .task {
            await PrivateMoneyStore.shared.refresh()
            // A move sent and not yet seen is asked about here too (finding 2).
            if !PrivatePending.shared.ops.isEmpty { await PrivateWatch.findNotes(context: modelContext) }
        }
    }

    // MARK: - Home's cards

    /// **HOME'S SIX CARDS, A–Z (prd §1807, §1809, §1871).** Account, Activity,
    /// Apps, Risks, Spending, Watchlist: each a button onto its place, its
    /// state on its top edge. Activity is a card since §1809; Permissions
    /// is inside Risks.
    @ViewBuilder
    func walletHomeCards(yours: String?, walkClosed: Int, onAll: Bool, yoursPicked: Bool,
                         flagged: Int) -> some View {
        let pending = yours.map { walkClosed >= 0 && YourAccountFirstOpen.setupPending($0) } ?? false
        let unseen = walletLive.flagged.live.filter { !ThreatsSeen.shared.contains($0.id) }.count
        let riskWord: String? = flagged > 0
            ? (unseen > 0 ? "\(unseen)" : String(localized: "All seen"))
            : (walletPrivacySlots.contains { NymisScans.shared.reading($0.id) == nil }
               ? String(localized: "Unscanned") : String(localized: "None"))
        let tokens = Watchlist.shared.tokens
        let mover = WatchlistRules.biggestMover(tokens, quotes: WatchlistPrices.shared.quotes)
        // The apps you have connected, never the catalogue's size.
        let apps = bridges.connectedCount
        // Spending's total, read by Home's own task (`walletSpendingKey`).
        let spending = SpendingReading.shared
        let spent = !(spending.page.places.isEmpty && spending.page.subscriptions.isEmpty)
        let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
        // The phone's cards share the screen's height (prd §1808); beside a
        // pane they keep the standard one.
        let cardHeight = roomSizeClass == .compact
            ? DSHomeCardMetrics.height(screen: UIScreen.main.bounds.height) : DSHomeCardMetrics.height
        LazyVGrid(columns: [GridItem(.flexible(), spacing: DSHomeCardMetrics.gap), GridItem(.flexible())],
                  spacing: DSHomeCardMetrics.gap) {
            DSHomeCard(glyph: WalletSection.yourAccount.glyph,
                       name: WalletSection.yourAccount.label,
                       // With nothing wanted the card says whose it is (prd
                       // §1818): the one card whose corner stood empty.
                       figure: yours == nil ? String(localized: "Create")
                           : pending ? String(localized: "Finish setup")
                           : yourAccountWants ?? yours.map { AddressTail.short($0) },
                       figureTone: yours == nil ? DS.pickInk
                           : pending || yourAccountWants != nil ? DS.attentionInk : DS.textSecondary,
                       height: cardHeight) {
                if yours == nil {
                    chrome.moveTray = true
                } else if pending {
                    chrome.moveWalk = true
                    chrome.moveTray = true
                } else {
                    chrome.walletSection = .yourAccount
                }
            }
            // **ACTIVITY IS A CARD (prd §1809, user: "wdyt if activity was a
            // tile on home").** The place beside Home on the swipe. No count
            // (user: "there are always new ones"): a number that never
            // reaches zero says nothing.
            // What it wears instead (user: "if it could show app icons in
            // circles on it that would be interesting"): the three apps
            // that last brought something, newest first, side by side.
            DSHomeCard(glyph: PlaceTab.feed.glyph, name: PlaceTab.feed.label,
                       trailing: activityFaces.isEmpty ? nil : AnyView(
                           HStack(spacing: DS.Space.s1) {
                               ForEach(activityFaces, id: \.self) { name in
                                   BridgeIcon(name: name, size: DS.Face.badge, circular: true)
                               }
                           }),
                       height: cardHeight) {
                PlaceTab.open(.feed, chrome: chrome, route: route)
            }
            DSHomeCard(glyph: PlaceTab.library.glyph, name: PlaceTab.library.label,
                       figure: apps > 0 ? "\(apps)" : nil,
                       height: cardHeight) {
                PlaceTab.open(.library, chrome: chrome, route: route)
            }
            // Holdings has no card (prd §1838): the balance over the map is
            // its door.
            DSHomeCard(glyph: WalletSection.threats.glyph, name: WalletSection.threats.label,
                       figure: riskWord,
                       figureTone: unseen > 0 ? DS.attentionInk : DS.textSecondary,
                       height: cardHeight) {
                chrome.walletSection = .threats
            }
            // **SPENDING IS A CARD (prd §1871, user: "yes" to a card for
            // iPad and Mac).** Its page had no door since §1807: the
            // window's total, or nothing until read; Hide balances masks it.
            DSHomeCard(glyph: WalletSection.spending.glyph, name: WalletSection.spending.label,
                       figure: spent ? (mask ?? AppleWalletRoom.money(spending.page.total, "USD")) : nil,
                       height: cardHeight) {
                chrome.walletSection = .spending
            }
            // Whose money Home shows, as the page reads it (prd §1524).
            .onChange(of: walletSpendingScope, initial: true) { _, scope in
                SpendingReading.shared.narrow(scope)
            }
            DSHomeCard(glyph: WalletSection.watchlist.glyph, name: WalletSection.watchlist.label,
                       figure: tokens.isEmpty ? nil
                           : mover.map { "\($0.symbol) \($0.change.words)" } ?? "\(tokens.count)",
                       figureTone: mover.map { $0.change.tone == .up ? DS.confirmInk : DS.destructiveInk }
                           ?? DS.textSecondary,
                       height: cardHeight) {
                if tokens.isEmpty { feedSheet = .watchToken } else { chrome.walletSection = .watchlist }
            }
        }
        // HOME FITS ONE SCREEN (user, 2026-11-14: "i wish the home tiles
        // didn't scroll!"): no air above the cards beyond the box's own, so
        // the third row clears the bar.
        .padding(.bottom, DS.Space.s2)
        // The Wallet's one row insets (prd §1482): the cards stand in the
        // rows' column.
        .walletStackRow()
        // Read when Home stands, never in a body (prd §1515, §628).
        .task {
            if yours == nil, onAll { YourAccountFirstOpen.makeIfFresh() }
            RecoveryCheckState.shared.refresh()
        }
        .task(id: tokens.map(\.id)) { await walletWatchlistRefresh(tokens) }
        // Read when Home stands and when something lands, never in a body
        // (prd §628).
        .task(id: chrome.refreshPulse) { loadActivityFaces() }
    }

    /// The apps behind the newest things outside the Wallet, three at most,
    /// for the Activity card: names only, never a model kept (prd §617).
    @MainActor
    func loadActivityFaces() {
        let now = Date.now
        var recent = FetchDescriptor<Thing>(predicate: #Predicate { $0.capturedAt <= now },
                                            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        recent.fetchLimit = 60
        let things = (try? modelContext.fetch(recent)) ?? []
        var seen = Set<String>()
        var faces: [String] = []
        for thing in things where thing.isLive {
            let source = thing.source
            // An app's mark only: a note of yours has none, and drew a grey
            // person among the icons.
            guard let category = BridgeCatalog.category(forSource: source),
                  category != CategoryFold.walletCategory, !Pinboard.isWritten(source) else { continue }
            let name = BridgeCatalog.seatName(forSource: source)
            if seen.insert(name).inserted { faces.append(name) }
            if faces.count == 3 { break }
        }
        if faces != activityFaces { activityFaces = faces }
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

    /// Holdings' money by whose it is (prd §1503): your own account, the
    /// wallets you follow, and what apps hold for you — a venue, a cash
    /// account, a Privy app.
    var walletHolderGroups: (you: WalletPortfolio.Holder?, following: [WalletPortfolio.Holder],
                             apps: [WalletPortfolio.Holder]) {
        let holders = walletAccountHolders
        let you = holders.first { Self.isYourAccount($0.address) && !WalletPortfolio.isVenue($0.address) }
        let rest = holders.filter { $0.address != you?.address }
        return (you,
                rest.filter { !WalletPortfolio.isVenue($0.address) },
                // Private money is a place but no app's (prd §1554): it is
                // its own section and block, never an Apps row.
                rest.filter { WalletPortfolio.isVenue($0.address) && $0.usd > 0
                    && $0.address != WalletPortfolio.privateHolderID && $0.address != WalletPortfolio.lentHolderID })
    }

    /// **HOLDINGS, WHAT THE MONEY IS (prd §1480 item 4, §1503, §1536).** The
    /// treemap in the box, then Apps on All (its total, never a count — user:
    /// "i don't care that i have 90 apps. i care about the total of tokens in
    /// those apps"), then Tokens, Positions, NFTs, for whatever the switch
    /// picked.
    @ViewBuilder
    func walletHoldingsDoors(all: [Thing]) -> some View {
        let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
        let groups = walletHolderGroups
        let appAccounts = walletAccountRows(all)
        // What your wallets hold, and nothing another section counts: not
        // Lent, not Private, and on All not an app's (prd §1695, §1696).
        let tokens = portfolioShown?.tokensOnly(appsApart: walletOnAll).positions ?? []
        // Every token hidden still leaves the door, to the Hidden row.
        let anyHidden = !(portfolioUnhidden?.hiddenItems(walletHidden).isEmpty ?? true)
        let positions = walletPositionCount
        let money = { (holders: [WalletPortfolio.Holder]) in
            mask ?? WalletValue.money(holders.reduce(0) { $0 + $1.usd })
        }
        let hasApps = !groups.apps.isEmpty || !appAccounts.isEmpty
        // **NO WHOSE ROWS (prd §1536, user: "i think yours following all
        // switch is most sensible").** You and Following were rows here that
        // picked an account, the same choice the box's switch makes, under
        // other words. The switch is the one control; Holdings shows what it
        // picked: one token list, its top three, and the apps on All only
        // (an app's money is in All and in neither of the others).
        walletDoorsSection {
            if walletOnAll, hasApps {
                // No chevron on a section's total (prd §1862): Accounts
                // reads as Public and Private do; its row still opens Accounts.
                walletDoor(.apps, figure: money(groups.apps), act: { chrome.walletSection = .apps })
                ForEach(Array(groups.apps.sorted { $0.usd > $1.usd }.prefix(Self.holdingsPreviewCount))) { app in
                    walletPreviewRow(app.label, figure: mask ?? WalletValue.money(app.usd),
                                     act: { chrome.walletSection = .apps }) {
                        if let bank = SimpleFINShape.connID(fromHolder: app.address) {
                            BankMark(connID: bank, size: DS.Mark.row)
                        } else {
                            BridgeIcon(name: Self.venueMark(app), size: DS.Mark.row)
                        }
                    }
                }
            }
            // **PUBLIC · PRIVATE (prd §1718, user: "the title 'Tokens' is
            // somewhat confusing b/c the whole screen is tokens"; "the
            // private stuff can be 'lent' also"; option B).** The section
            // says WHERE the money is; each row's line says what it is doing
            // there. What your accounts hold in the open — idle tokens and
            // what Aave holds for you, by worth together — under one head
            // whose dollars add up to the number above (prd §1695, §1696;
            // the lent standing, a last reading included, §1697). Lent is
            // no longer a section: private money is lent too.
            let lent = walletLentStanding
            if !tokens.isEmpty || anyHidden || lent.map({ !$0.rows.isEmpty || $0.roundUps != nil }) == true {
                walletDoor(.holdings, name: String(localized: "Public"),
                           figure: mask ?? WalletValue.money(walletPublicUSD),
                           act: { feedSheet = .walletTokens })
                    .task(id: lent?.account) {
                        if let lent { await lent.lend.read(account: lent.account) }
                    }
                // A token's row opens that token, every one (prd §1670); a
                // lent row opens Take back; the door and See all open the
                // tokens list.
                ForEach(walletPublicRows(tokens: Array(tokens.prefix(Self.holdingsPreviewCount)), lent: lent)) { row in
                    switch row {
                    case .token(let token):
                        walletTokenPreview([token], mask: mask) { walletOpenToken($0) }
                    case .lent(let m):
                        if let lent { walletLentRow(m, lend: lent.lend, mask: mask, prices: lent.lend.prices) }
                    case .roundUps(let units):
                        walletRoundUpsRow(units, mask: mask)
                    case .ollaBack(let units, let ready):
                        if let lent { walletOllaBackRow(units, ready: ready, lend: lent.lend, mask: mask) }
                    }
                }
                // What your Aztec account holds in the open: its gas, first
                // (prd §1700e). Never in the figure above.
                walletAztecPublicRows
                if tokens.count > Self.holdingsPreviewCount || anyHidden {
                    DSMoreRow(title: Text("See all \(tokens.count) tokens")) { feedSheet = .walletTokens }
                        .walletListRow()
                }
            }
            // What the app picked holds of its own (prd §1702, §1703), as its
            // read left it: a card's balance, a name, a card's limit, a Cash
            // account, money in escrow. Never in the total. A row that is a
            // landed thing opens it; the rest open the app's page.
            if let seat = selectedSeat {
                ForEach(walletSeatItems(all), id: \.name) { item in
                    walletPreviewRow(item.name,
                                     figure: item.usd > 0 ? (mask ?? WalletValue.money(item.usd)) : item.figure,
                                     act: {
                                         if let ref = item.ref { openBySourceRef(ref, in: all) } else { appSettings?() }
                                     }) {
                        BridgeIcon(name: seat.mark, size: DS.Mark.row)
                    }
                }
            }
            // Then what is private (prd §1718: Public · Private; Lent's rows
            // stand in Public since option B).
            walletPrivateRows
            // Your Aztec account's holdings, after 0xBow's (prd §1700 item 4).
            walletAztecRows
            // What the private balances add up to against your goal (§1835).
            walletSavingsGoalRow(mask: mask)
            // The section's one verb, last (prd §1776).
            walletAddMoneyRow
            if positions > 0 {
                walletDoor(.positions)
                ForEach(Array(walletPositionPreview.prefix(Self.holdingsPreviewCount)), id: \.name) { row in
                    walletPreviewRow(row.name, figure: row.word,
                                     tone: row.alert ? DS.attentionInk : DS.textSecondary,
                                     act: { chrome.walletSection = .positions }) {
                        BridgeIcon(name: row.mark, size: DS.Mark.row)
                    }
                }
            }
            // An app the menu picked holds no collections (prd §1048b).
            if selectedSeat == nil {
                walletDoor(.nfts)
                // Its collections under it, as Tokens' top three stand
                // under Tokens; one opens its pieces (prd §1672).
                if let entry = nftShelfEntry {
                    WalletNFTCollectionRows(wallet: entry.address, onEdit: { chrome.walletSection = .nfts }) { collection, name in
                        route.pushBridge(.nftCollection(wallet: entry.address, collection: collection, name: name))
                    }
                    .walletStackRow()
                }
            }
        }
        // **AN APP PICKED LISTS WHAT IT HOLDS FOR YOU (prd §1618 item 2):**
        // Privy's apps (§1124) and an app's accounts (§1341) were Holdings'
        // and drew nowhere once its doors became All's alone.
        if selectedSeat != nil {
            let apps = walletAppRows(all)
            if !apps.isEmpty {
                // An app's own apps (Privy's), apart from its Accounts below.
                walletCard(String(localized: "Apps"), glyph: WalletSection.apps.glyph) {
                    ForEach(Array(apps.enumerated()), id: \.element.id) { i, row in
                        if case .single(let item) = row.kind, let thing = item.live {
                            shapedListRow(thing, index: i, nextEventID: nil, air: Self.rowAir)
                        }
                    }
                }
            }
            walletAccountsSection(appAccounts, nextEventID: nil)
        }
    }

    /// How many rows a Holdings door previews under it (prd §1525).
    static let holdingsPreviewCount = 3

    /// **PUBLIC IS ONE FIGURE, HOLDINGS' AND HOME'S (prd §1862).** What your
    /// wallets hold in the open and what Aave holds for you, never an app's
    /// money (Accounts on All) nor Private: Home said the balance less
    /// Private, $55K over Holdings' $24K.
    var walletPublicUSD: Double {
        let tokens = portfolioShown?.tokensOnly(appsApart: walletOnAll).positions ?? []
        let lent = walletLentStanding
        let lentUSD = lent.flatMap { $0.lend.standing(account: $0.account)?.usd } ?? 0
        return tokens.reduce(0) { $0 + $1.usd } + lentUSD
    }

    /// The biggest tokens the given accounts hold, biggest first, cut to the
    /// preview. Addresses match as the portfolio stores them, lower case.
    static func topTokens(_ portfolio: WalletPortfolio?, held addresses: [String]) -> [WalletPortfolio.Position] {
        guard let portfolio, !addresses.isEmpty else { return [] }
        let slice = portfolio.scoped(toAddresses: Set(addresses.map { $0.lowercased() }))
        return Array(slice.positions.sorted { $0.usd > $1.usd }.prefix(holdingsPreviewCount))
    }

    /// One of a door's top three (prd §1525): the mark in the door's glyph
    /// column, the name and figure a rung under the door's, so the door
    /// still reads as the heading. A press opens what the door opens.
    /// The name and figure are the primary ink (prd §1731): grey at this
    /// rung read as a row you could not press.
    func walletPreviewRow<Mark: View>(_ name: String, line: String? = nil, lineInk: Color = DS.textSecondary,
                                      held: String? = nil,
                                      figure: String?, tone: Color = DS.textPrimary,
                                      move: Double? = nil,
                                      act: @escaping () -> Void,
                                      @ViewBuilder mark: () -> Mark) -> some View {
        Button {
            DSHaptic.selection()
            act()
        } label: {
            HStack(alignment: .center, spacing: DSRoomChassis.headGap) {
                mark()
                    .frame(width: DSRoomChassis.headGlyph)
                    .accessibilityHidden(true)
                // A line under the name where the row has one to say: a
                // token's networks (prd §1718); an app's row has none.
                VStack(alignment: .leading, spacing: 2) {
                    // How many you hold, after the name on its line, grey
                    // (prd §1954): the row reads "ETH 1.42".
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                        Text(verbatim: name)
                            .dsText(.body17)
                            .foregroundStyle(DS.textPrimary)
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
                    if let line {
                        Text(verbatim: line)
                            .dsText(.subhead12)
                            .foregroundStyle(lineInk)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: DS.Space.s2)
                // The figure over its day, as Home's token rows (prd §1862);
                // a day that rounds to zero draws nothing (§83).
                let day = move.map { WatchlistRules.change($0 * 100) }
                let moved = day.map { $0.tone == .up || $0.tone == .down } ?? false
                if line == nil {
                    // **ONE LINE, THE DAY BEFORE THE FIGURE (prd §1954):**
                    // the figure pins to the edge, so the dollars read down
                    // one column and the day down the one beside it.
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                        if let day, moved {
                            Text(verbatim: day.words)
                                .dsText(.fact15)
                                .monospacedDigit()
                                .foregroundStyle(day.tone == .up ? DS.confirmInk : DS.destructiveInk)
                                .lineLimit(1)
                        }
                        if let figure {
                            walletRowFigure(figure, tone: tone)
                        }
                    }
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        if let figure {
                            walletRowFigure(figure, tone: tone)
                        }
                        if let day, moved {
                            Text(verbatim: day.words)
                                .dsText(.subhead12)
                                .monospacedDigit()
                                .foregroundStyle(day.tone == .up ? DS.confirmInk : DS.destructiveInk)
                                .lineLimit(1)
                        }
                    }
                }
            }
            // **HOLDINGS IS A LEDGER (prd §1954, amending §1482 and §1862):**
            // a one-line row stands at the ledger's 40pt pitch so the whole
            // list reads at once; a row with a line under it keeps the
            // Wallet's 52.
            .frame(minHeight: line == nil ? WalletCardStyle.ledgerHead : DSFeed.headHeight)
            .padding(.vertical, line == nil ? 0 : FeedScreen.rowAir)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .dsHover()
        .accessibilityLabel(Text(verbatim: [name, held, line, figure].compactMap { $0 }.joined(separator: ". ")))
        .walletListRow()
    }

    /// A door's tokens, each wearing the mark its treemap tile wears, over
    /// the networks it sits on (prd §1718).
    @ViewBuilder
    func walletTokenPreview(_ tokens: [WalletPortfolio.Position], mask: String?,
                            act: @escaping (WalletPortfolio.Position) -> Void) -> some View {
        ForEach(tokens) { token in
            // One line (prd §1954): the symbol, how many you hold, the day,
            // the dollars. The networks are the token's page's (its places).
            // Ethereum disagreeing twice in a row (prd §1825) still takes a
            // line of its own in amber: a warning is never folded away.
            let differs = HoldingsCheckStore.shared.mismatched(token)
            walletPreviewRow(token.symbol,
                             line: differs ? String(localized: "Doesn't match Ethereum") : nil,
                             lineInk: DS.attentionInk,
                             held: token.amount.map { WalletValue.held($0) },
                             figure: mask ?? WalletValue.money(token.usd),
                             move: walletHoldingMoves[HoldingMoves.key(token.symbol)], act: { act(token) }) {
                AssetMark(name: token.symbol, size: DS.Mark.row)
            }
            // Hide from the row you see first, as from the Tokens list
            // (prd §1591); the list's Hidden row brings it back.
            .contextMenu { TokenHideMenu(position: token) { walletSetHidden($0, hidden: $1) } }
        }
    }

    /// Positions' preview (prd §1525), in the page's order: each borrow by
    /// how far it can fall (the page's own words, `walletLendingFalls`), else
    /// lending; then perps, liquidity, AZTEC staked and zFi orders, each its
    /// count.
    var walletPositionPreview: [(name: String, mark: String, word: String?, alert: Bool)] {
        var rows: [(name: String, mark: String, word: String?, alert: Bool)] = []
        if hasLendingCard {
            let falls = walletLendingFalls.sorted { $0.key < $1.key }
            if falls.isEmpty {
                rows.append((String(localized: "Lending"), "Aave", nil, false))
            } else {
                // Each borrow by the protocol it is on, in its own mark:
                // the key is already that name, so prefixing "Aave · " drew
                // "Aave · Aave" and dressed a Spark loan in Aave's mark.
                for (name, fall) in falls {
                    rows.append((name, name, fall, true))
                }
            }
        }
        func count(_ n: Int, one: String, many: String) -> String? {
            n == 0 ? nil : (n == 1 ? one : many)
        }
        let perps = walletLive.hyperliquid.positions.count
        if let word = count(perps, one: String(localized: "1 perp"), many: String(localized: "\(perps) perps")) {
            rows.append(("Hyperliquid", "Hyperliquid", word, false))
        }
        let pools = walletLive.uniswap.positions.count
        if let word = count(pools, one: String(localized: "1 pool"), many: String(localized: "\(pools) pools")) {
            rows.append(("Uniswap", "Uniswap", word, false))
        }
        let stakes = walletLive.aztecStaking.stakes.count
        if let word = count(stakes, one: String(localized: "1 stake"), many: String(localized: "\(stakes) stakes")) {
            rows.append(("Aztec", "Aztec", word, false))
        }
        let orders = walletLive.zfiOrders.orders.count
        if let word = count(orders, one: String(localized: "1 order"), many: String(localized: "\(orders) orders")) {
            rows.append(("zFi", "zFi", word, false))
        }
        return rows
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
    /// total in the box, then the doors: Subscriptions, Places, Fees — one
    /// name per group, the box's Recurring and The rest retired — and
    /// Round-ups (prd §1523), what the change bought, outside the total.
    @ViewBuilder
    var walletSpendingDoors: some View {
        let reading = SpendingReading.shared
        let page = reading.page
        let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
        let roundUps = !page.roundUps.isEmpty || page.roundUpsWaiting > 0
        if !(page.places.isEmpty && page.subscriptions.isEmpty && page.fees.isEmpty) || roundUps {
            walletDoorsSection {
                if !page.subscriptions.isEmpty {
                    walletDoor(.subscriptions, figure: mask ?? AppleWalletRoom.money(page.recurring, "USD"))
                }
                if !page.places.isEmpty {
                    walletDoor(.places, figure: mask ?? AppleWalletRoom.money(page.rest, "USD"))
                }
                if !page.fees.isEmpty {
                    // Not in the total (prd §1476 item 1): the Fees page's box
                    // says so (`feesLine`); a door carries no line (§1496).
                    walletDoor(.fees, figure: mask ?? AppleWalletRoom.money(page.feesTotal, "USD"))
                }
                if roundUps {
                    // What the change bought this window, never in the total
                    // (prd §1523): kept, not spent. Nothing bought yet, the
                    // door says what waits instead of a zero.
                    if page.roundUps.isEmpty {
                        walletDoor(.roundUps, word: Self.spendingRoundUpWaiting(page.roundUpsWaiting, mask: mask))
                    } else {
                        walletDoor(.roundUps, figure: mask ?? AppleWalletRoom.money(page.roundUpsTotal, "USD"))
                    }
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
        case .recoveryKey:
            // Its verdict leads the page: no box (prd §1969).
            Section {
                RecoveryCheckFigure().walletListRow()
            }
            RecoveryCheckRows()
        case .nodes:
            // How many networks read from your node leads the page: no box (prd §1969).
            Section {
                OwnNodeFigure().walletListRow()
            }
            OwnNodeRows()
        case .tacit:
            // Its map by network leads the page, in its first row: no box
            // of the room's (prd §1969's rule for a page with its own figure).
            TacitAccountRows()
        case .following:
            walletFollowingPage
        case .needsYou:
            walletNeedsYouPage(upcoming: upcoming, nextEventID: nextEventID)
        case .permissions:
            walletPermissionRows(standsEmpty: true)
        case .threats:
            // What gives your addresses away, by Nymis (prd §1701).
            let privacy = walletPrivacySlots
            walletPrivacySection(privacy)
            // Empty rows only while the whole page is empty: with a
            // permission under it the page has rows (prd §1809).
            let allowed = selectedSeat == nil && !walletOnFollowing
                && (counts(\.delegations) + counts(\.approvals) > 0 || walletShowsAztecGrants)
            if walletSecurityCounts.flagged == 0 && privacy.isEmpty && !allowed { walletSkeletonRowsSection }
            // **PERMISSIONS ARE RISKS' (prd §1809, user: "we can finally
            // combine permissions and risk").** Both answer "is anything
            // unsafe?". The order is the user's: privacy, then what you
            // allowed, then what was found ("privacy first then the
            // permissions stuff then the threat stuff"). An app or
            // Following picked keeps Permissions as its own door.
            if selectedSeat == nil, !walletOnFollowing { walletPermissionRows(standsEmpty: false) }
            // **YOU CAN PUT THEM AWAY, AND IT SAYS SO (prd §1849, user: "i
            // want a user to be able to know they can dismiss the risks").**
            // Holding a row was the only way; one row marks every finding
            // as seen while any is not. **A seen finding leaves (prd §1919):**
            // each is stamped, then gone; with none left the page says All
            // seen, and the Seen row under the findings holds the rest.
            let flaggedThreats = walletLive.flagged.live
            let unseenThreats = flaggedThreats.filter { !ThreatsSeen.shared.contains($0.id) }
            let seenThreats = flaggedThreats.filter {
                ThreatsSeen.shared.contains($0.id) && walletThreatsLeaving[$0.id] == nil
            }
            // The findings' own head (`DSRisksStateRow`): how many are new,
            // the stamped ones counted until they leave, over the verb.
            let stamping = walletThreatsLeaving.count
            if !unseenThreats.isEmpty || stamping > 0 {
                DSRisksStateRow(new: unseenThreats.count + stamping)
                    .animation(DS.Motion.standard, value: unseenThreats.count + stamping)
                    .walletListRow()
                if !unseenThreats.isEmpty {
                    DSDoorRow(icon: "eye", title: Text("Mark all as seen")) {
                        walletMarkAllThreatsSeen(unseenThreats)
                    }
                    .walletListRow()
                }
            } else if !walletAllSeenHeld, !seenThreats.isEmpty {
                DSRisksStateRow(new: 0)
                    .walletListRow()
            }
            walletFlaggedSection(.poisoning, anchor: .poisoning,
                                 word: String(localized: "Address poisoning"))
            walletFlaggedSection(.spoofedSymbol, anchor: .fakeTokens,
                                 word: String(localized: "Fake tokens"))
            walletFlaggedSection(.fakeTransfer, anchor: .fakeTransfers,
                                 word: String(localized: "Fake transfers"))
            walletSeenThreatsSection(seenThreats)
        case .holdingAccounts:
            let following = walletHolderGroups.following
            if following.isEmpty { walletSkeletonRowsSection }
            walletHolderList(following, section: .holdingAccounts)
        case .positions:
            if walletPositionCount == 0 { walletSkeletonRowsSection }
            walletPositionsSections
        case .apps:
            walletHolderAppsPage(all: all, nextEventID: nextEventID)
        case .nfts:
            if nftShelfWallet == nil {
                walletNFTChooseEachSection
            } else if nftShelfEntry == nil {
                walletNFTDoorSection
            }
            walletNFTListSection
        case .places:
            walletSpendingGroup(.places)
        case .fees:
            walletSpendingGroup(.fees)
        case .roundUps:
            walletSpendingGroup(.roundUps)
        case .watchlist:
            walletWatchlistPage
        case .watchedToken:
            walletWatchedTokenPage
        case .followedWallet:
            walletFollowedPage(all: all, nextEventID: nextEventID)
        default:
            EmptyView()
        }
    }

    private func counts(_ key: KeyPath<WalletSecurityCounts, Int>) -> Int {
        walletSecurityCounts[keyPath: key]
    }

    // Following's page and a followed wallet's are `FeedScreen+Followed.swift` (prd §1969).

    /// Needs you's page: a Safe signature waiting first (power over your
    /// money, §947), then the key nudges, the undated asks, the cards that
    /// ask, then the dated rows under their days. No cap: the page is the
    /// list.
    @ViewBuilder
    func walletNeedsYouPage(upcoming: [Thing], nextEventID: UUID?) -> some View {
        let groups = walletComingUpDays(upcoming)
        let needs = groups.first { $0.0 == Self.needsYouGroup }?.1 ?? []
        let dated = groups.filter { $0.0 != Self.needsYouGroup }
        let onAll = walletOnAll
        let cards = onAll ? SpendingReading.shared.cards.filter { Self.cardAsk($0) != nil } : []
        if walletNeedsCount(upcoming: upcoming) == 0 { walletSkeletonRowsSection }
        walletSignaturesSection(upcoming: upcoming)
        // Money of yours waiting on 0xBow, or refused (prd §1561).
        if walletShowsPrivate { WalletPrivateAsks() }
        // A limit order waiting for its price (prd §1673 item 7).
        if walletShowsPrivate { WalletOrderAsks() }
        if walletShowsPrivate { WalletAztecExitAsks() }
        Section {
            if onAll && RecoveryKeyNudge.shown { RecoveryKeyNudge().listRow }
            // The monthly check (prd §1515): one row when it is due.
            if onAll && RecoveryCheckNudge.shown { RecoveryCheckNudge().listRow }
            if onAll && OutsideKeyNudge.shown { OutsideKeyNudge().listRow }
        }
        if !needs.isEmpty {
            walletDaySections([(Self.needsYouGroup, needs)], boundary: nil,
                              named: [Self.needsYouGroup], headless: true, nextEventID: nextEventID)
                .environment(\.dsNeedsYouSeeable, true)
        }
        if !cards.isEmpty {
            walletCard(String(localized: "Cards"), glyph: ScopeTileGlyph.cards) {
                ForEach(cards) { card in
                    let app = BridgeCatalog.seatName(forSource: card.app)
                    Button {
                        DSHaptic.selection()
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
                .environment(\.dsNeedsYouSeeable, true)
        }
    }

    /// Holdings' Apps page (prd §1503): what each app holds for you, largest
    /// first, an app holding nothing left out (Home's Following still lists
    /// it), then what an app holds as it read it (§1341), which the total
    /// leaves out.
    @ViewBuilder
    func walletHolderAppsPage(all: [Thing], nextEventID: UUID?) -> some View {
        let apps = walletHolderGroups.apps
        let appAccounts = walletAccountRows(all)
        if apps.isEmpty && appAccounts.isEmpty { walletSkeletonRowsSection }
        walletHolderList(apps, section: .apps)
        walletAccountsSection(appAccounts, nextEventID: nextEventID)
    }

    /// A venue row's mark: its own name's when one is bundled ("Apple
    /// Cash"), else the app that holds it — an account named as its bank
    /// names it ("Savings") wears its app's, never a blank square (prd §1663).
    static func venueMark(_ holder: WalletPortfolio.Holder) -> String {
        guard BrandMark.image(for: holder.label) == nil,
              let seat = RoomAccounts.seats(for: CategoryFold.walletRoom).first(where: { $0.holds(holder.address) })
        else { return holder.label }
        return seat.mark
    }

    /// One group of Holdings' money, each holder its balance; a wallet's row
    /// narrows the Wallet to it.
    @ViewBuilder
    func walletHolderList(_ holders: [WalletPortfolio.Holder], section: WalletSection) -> some View {
        let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
        if !holders.isEmpty {
            walletCard(section.label, glyph: section.glyph) {
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
                        // **AN APP'S ROW NARROWS TO THE APP (prd §1587, §83):**
                        // the Wallet's menu pick for its seat, else the app itself.
                        else if let seat = RoomAccounts.seats(for: CategoryFold.walletRoom).first(where: { $0.holds(holder.address) }) {
                            withAnimation(DS.Motion.standard) { chrome.walletScope = RoomAccounts.scopeID(seat) }
                        } else {
                            chrome.openApp(holder.label)
                        }
                    } label: {
                        DSFeedRow(name: name, trailingBesideLine: true) {
                            Group {
                                if let app = Self.privyApp(holder.address), app.logoURL != nil {
                                    // A Privy app wears its own logo, as Privy's
                                    // room draws it; the catalogue has none.
                                    PrivyAppMark(logoURL: app.logoURL)
                                } else if let bank = SimpleFINShape.connID(fromHolder: holder.address) {
                                    BankMark(connID: bank, size: DS.Face.row)
                                } else if isVenue {
                                    BridgeIcon(name: Self.venueMark(holder), size: DS.Face.row)
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
        case .recoveryKey:
            EmptyView()
        case .nodes:
            EmptyView()
        // Following has no box (prd §1969): its limit is its list's footnote.
        case .following:
            EmptyView()
        // **YOUR BALANCE, REACHED (prd §1710)**: the disc is what the
        // wallets hold, the delegates and modules the Delegations list holds
        // (§1677) reach their accounts', the grants sit inside at their dollars.
        default:
            EmptyView()
        }
    }

    /// Permissions' rows: who acts for you, what you approved, what Aztec
    /// apps hold, and what moves a Safe with nobody signing. On Risks the
    /// empty rows are Risks' own, so they are not drawn twice.
    @ViewBuilder
    func walletPermissionRows(standsEmpty: Bool) -> some View {
        // The authorizations you gave Aztec apps count as permissions too
        // (prd §1762): the page is not empty while one stands.
        if standsEmpty, counts(\.delegations) + counts(\.approvals) == 0, !walletShowsAztecGrants {
            // What you just took back, else the empty rows (§769).
            if JustRevoked.today(scope: chrome.walletScope).isEmpty { walletSkeletonRowsSection }
            else { walletRevokedTodaySection }
        }
        walletActingSection
        walletApprovalsSection
        // The co-signer's own approvals, one door to the record (prd §1861).
        walletCoSignerSection
        walletAztecGrantsSection
        // What can move a Safe of yours with nobody signing (prd §1786,
        // from Account's page): on All, or with your account picked.
        if let account = YourAccountDemo.shownAddress,
           chrome.walletScope == nil || WalletWatch.sameAddress(chrome.walletScope ?? "", account) {
            WalletUnsignedSection(part: .unsigned, onOpenSafe: walletOpenSafe, queueKey: Self.safeQueueKey(visible))
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
        case .roundUps:
            // **WHAT THE CHANGE BOUGHT (prd §1523):** the change still
            // waiting first, then each buy, newest first.
            let page = reading.page
            if page.roundUps.isEmpty && page.roundUpsWaiting <= 0 { walletSkeletonRowsSection }
            if !page.roundUps.isEmpty || page.roundUpsWaiting > 0 {
                walletCard(WalletSection.roundUps.label, glyph: WalletSection.roundUps.glyph) {
                    if page.roundUpsWaiting > 0 {
                        spendingRoundUpWaitingRow(page.roundUpsWaiting, mask: mask)
                    }
                    ForEach(page.roundUps, id: \.tx) { buy in
                        spendingRoundUpRow(buy, mask: mask)
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
            walletSeeAllSection(older: all.count >= min(Self.sourceRoomFetchLimit, rowBudget ?? .max) || selectedWallet != nil || selectedSeat != nil)
        }
    }

    /// The rows the pane's Activity holds before its door.
    static let walletPaneRows = 8

    /// **THE PANE'S ACTIVITY (prd §1742).** Beside a pane the Wallet's box
    /// stood over an empty column: the phone keeps every list behind a door
    /// (§1480) because it has one column, and the Mac has two. Under the box
    /// the pane lists the newest moves by day, then the door to Activity,
    /// which opens in the list column as every Wallet page does. Nothing
    /// while there are no moves: the box stands alone, as it did.
    @ViewBuilder
    func walletPaneActivity(_ all: [Thing], nextEventID: UUID?) -> some View {
        let moves = Self.walletMoves(all)
        let stream = walletStream(moves, cap: Self.walletPaneRows)
        if !stream.rows.isEmpty {
            walletCard(WalletSection.activity.label, glyph: WalletSection.activity.glyph) {
                walletStreamSections(stream.rows, ownMoves: stream.ownMoves, nextEventID: nextEventID)
                if moves.count > Self.walletPaneRows {
                    DSMoreRow(title: Text("All activity")) {
                        withAnimation(DS.Motion.standard) { chrome.walletSection = .activity }
                    }
                    .walletListRow()
                }
            }
        }
    }
}

/// **YOUR ACCOUNT'S BOX (prd §1480 item 6):** who it is — the face, the name,
/// the address to copy. The one place the WHOLE address stands (user,
/// 2026-10-31: "this is the one place seeing entire address maybe is
/// helpful"), centred as a person's page opens (the canvas's C): the face,
/// the name, the address in Receive's grid (§1586), then Copy address. The
/// grid copies on a tap too.
struct WalletYourAccountFigure: View {
    let address: String?
    @State private var profileOpen = false

    var body: some View {
        if let address {
            VStack(spacing: DS.Space.s1) {
                // **THE FACE AND THE NAME ARE YOURS TO SET HERE (prd §1860,
                // user: "on your account page user should be able to tap to
                // add their name and avatar just like in settings").** One
                // tap asks the name-and-photo question (`ProfileEditing`);
                // the name you gave leads, else the account's label.
                Button { profileOpen = true } label: {
                    VStack(spacing: DS.Space.s1) {
                        WalletFace(address: address, size: DS.Face.sheet, circular: true)
                        Text(verbatim: ProfileStore.shared.name
                                ?? WalletStore.shared.displayName(forWatched: address)
                                ?? WalletStore.yourAccountName)
                            .dsText(.heading24).foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                            .padding(.top, DS.Space.s1)
                            .contentTransition(.opacity)
                    }
                }
                .buttonStyle(RowPress())
                .accessibilityHint(Text("Changes your name or photo"))
                .profileEditing(isPresented: $profileOpen)
                // No address under the name (prd §1947, user: "is user going to
                // understand what that is … why do we have that one instead
                // of the others"): each account copies its own, in Your accounts.
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            DSFigureReading(number: String(localized: "No account yet"),
                            caption: String(localized: "Move makes one"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
