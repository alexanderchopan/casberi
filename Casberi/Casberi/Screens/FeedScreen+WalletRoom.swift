import SwiftUI
import SwiftData

// The wallet room's sections, split out of FeedScreen.swift (prd §718).
//
// FeedScreen was one 12,700-line struct, which is why nearly every visual
// ruling about the feed landed with no eyes on it: a file that size is read in
// slices, and a slice cannot show what a room draws. The wallet room is the
// largest self-contained room in it, so it moves first. Nothing here changed
// but the file it lives in and the access level: a member that an extension
// in another file reads cannot be `private`, and every declaration below was
// `private` where it lived before.
extension FeedScreen {
    /// Every token the treemap maps, as rows (prd §483).
    ///
    /// **The half this scope never had.** The room has drawn a holdings BOARD
    /// since §158 and never a list, because the board was the only holdings
    /// object in a room of cards and had to answer everything. Under §483 each
    /// scope is one drawing and one list, and this is the list — the board
    /// keeps the shape of the thing, these say what is in it.
    ///
    /// It reads the SAME `portfolio.positions` the treemap does rather than
    /// re-deriving, so a cell and its row can never disagree about a number,
    /// and it costs no read: the portfolio is already in hand for the crown.
    ///
    /// **`UnitTreemap` caps at six cells**, so on a wallet holding more than
    /// that the board has always been a partial answer with nothing saying so.
    /// The list is where the rest live, which is the other reason it belongs
    /// here rather than behind a door.
    /// Each holding's day move (`HoldingMoves`, prd §1090): the last read's,
    /// while fresh; the demo's fixed table in the demo, which reaches nothing.
    var walletHoldingMoves: [String: Double] {
        DemoMode.isActive ? HoldingMoves.demo : HoldingMoves.current()
    }

    @ViewBuilder
    var walletTokenListSection: some View {
        if let portfolio = portfolioShown, !portfolio.isEmpty {
            let moves = walletHoldingMoves
            let fold = WalletTokenFold(portfolio.positions, total: portfolio.totalUSD)
            Section {
                // **TOKENS LEAD HOLDINGS, AND A LONG TAIL IS ONE ROW (prd
                // §1107, user: "what if someone has dozens of tokens").** The
                // list drew every token, so on a wallet holding forty the
                // Positions under them were forty rows down. Each token worth
                // a twentieth of the whole draws, five at most; the rest fold
                // into one row that opens every one.
                DSGroupHeader(word: String(localized: "Tokens"))
                ForEach(fold.shown) { position in
                    walletTokenRow(position, portfolio: portfolio, moves: moves)
                }
                if !fold.rest.isEmpty {
                    Button {
                        DSHaptic.selection()
                        feedSheet = .walletTokens
                    } label: {
                        WalletTokenFoldRow(fold: fold)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPress())
                    .dsHover()
                    .listRowInsets(EdgeInsets(top: DS.Space.s2,
                                              leading: DSRoomChassis.rowInset(forMark: DS.Face.list),
                                              bottom: DS.Space.s2, trailing: DS.Space.s4))
                    .feedRowBackground()
                    .listRowSeparator(.hidden)
                }
            }
        }
    }

    /// One token: the cell's own door, at row scale — a token's chart when it
    /// is watched, the quick sheet when it is only held (the 2026-07-14
    /// split) — and Markets' alerts from its long press (prd §1090).
    func walletTokenRow(_ position: WalletPortfolio.Position, portfolio: WalletPortfolio,
                        moves: [String: Double]) -> some View {
        Button {
            walletOpenToken(position)
        } label: {
            WalletTokenRowLabel(position: position, total: portfolio.totalUSD,
                                move: moves[HoldingMoves.key(position.symbol)])
                .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .dsHover()
        .contextMenu {
            // ALERT ME (prd §1090): Markets' alerts, from the money you hold.
            // A token with no route has no price to watch, so it offers none.
            if position.route != nil { walletHoldingAlertMenu(position) }
        }
        .listRowInsets(EdgeInsets(top: DS.Space.s2,
                                  leading: DSRoomChassis.rowInset(forMark: DS.Face.list),
                                  bottom: DS.Space.s2, trailing: DS.Space.s4))
        .feedRowBackground()
        .listRowSeparator(.hidden)
    }

    func walletOpenToken(_ position: WalletPortfolio.Position) {
        guard let route = position.route,
              let r = TokenQuickRoute.from(sentinel: "@token:\(route):\(position.symbol)") else { return }
        if let thing = r.watchedThing(in: modelContext) {
            openThing(thing)
        } else {
            feedSheet = .token(r.withHolders(position.holders))
        }
    }

    /// Markets' alert choices (`PriceAlert.choices`), worded relative to the
    /// price because the menu opens before the price is read. Built from the
    /// choices themselves at a unit price, so a choice added or reordered
    /// there is worded and set here with no second list to keep in step.
    @ViewBuilder
    func walletHoldingAlertMenu(_ position: WalletPortfolio.Position) -> some View {
        Section(String(localized: "Alert me when \(position.symbol)")) {
            ForEach(PriceAlert.choices(ref: "", name: "", price: 1)) { template in
                Button { walletSetHoldingAlert(position, template: template) } label: {
                    Text(Self.relativeAlertLabel(template))
                }
            }
        }
    }

    /// "Rises 10%", "Falls 10%", "Moves 10% in a day" — a choice made at a
    /// price of 1, so its target IS its ratio.
    static func relativeAlertLabel(_ template: PriceAlert) -> String {
        let pct = Int((abs(template.target - (template.kind == .move ? 0 : 1)) * 100).rounded())
        switch template.kind {
        case .above: return String(localized: "Rises \(pct)%")
        case .below: return String(localized: "Falls \(pct)%")
        case .move:  return String(localized: "Moves \(pct)% in a day")
        }
    }

    /// Watches the token in Markets if it isn't yet — an alert is checked on
    /// a watched price (prd §1081) — then sets the alert there, where the
    /// Alerts tile lists it and its switch turns it off. The level is taken
    /// from a LIVE price only: the pulse this launch read, else a fresh
    /// resolve. Never `watchPriceUsd`, the price the day you started watching.
    func walletSetHoldingAlert(_ position: WalletPortfolio.Position, template: PriceAlert) {
        guard !DemoMode.isActive else {
            chrome.flash(String(localized: "Alerts work once you leave the demo."))
            return
        }
        guard let routeString = position.route,
              let r = TokenQuickRoute.from(sentinel: "@token:\(routeString):\(position.symbol)") else { return }
        let context = modelContext
        let store = bridges
        Task { @MainActor in
            var thing = r.watchedThing(in: context)
            var price = thing.flatMap { TokenPulse.shared.pulse(for: $0)?.price }
            if thing == nil || price == nil {
                guard let resolved = await TokenWatch.search(r.address).first(where: { $0.id == r.id }) else {
                    chrome.flash(String(localized: "Couldn't find \(position.symbol)'s price to follow."))
                    return
                }
                if thing == nil {
                    thing = TokenWatch.add(resolved, context: context) ?? r.watchedThing(in: context)
                    TokenWatch.registerBridge(store: store, context: context)
                }
                price = resolved.priceUsd.flatMap(Double.init)
            }
            guard let thing, thing.isLive, let ref = thing.sourceRef, let price, price > 0 else {
                chrome.flash(String(localized: "Couldn't find \(position.symbol)'s price to follow."))
                return
            }
            let alert = PriceAlert(ref: ref, name: position.symbol, kind: template.kind,
                                   target: template.kind == .move ? template.target : template.target * price)
            PriceAlertStore.shared.add(alert)
            DSHaptic.success()
            chrome.flash(String(localized: "Alert set: \(position.symbol) \(WatchAlertsSection.title(alert).lowercased())"),
                         tone: .success)
        }
    }

    /// The one drawing this scope leads with, in the box (prd §483, §1107).
    ///
    /// **The rule, in the user's own words: "above the toggles is always a
    /// visual of some kind and then a list below it".** Home's visual is the
    /// crown's line, drawn by the crown itself, so this returns nothing there.
    @ViewBuilder
    func walletScopeVisualSection(_ section: WalletSection, upcoming: [Thing] = []) -> some View {
        switch section {
        case .home:
            EmptyView()
        // **SUBSCRIPTIONS, AND ONLY THEM (prd §1111).** The calendar shows
        // each renewal on its day and the statement what they cost a month;
        // what waits on you and the dated rows moved to Home. It starts the
        // reading here, its own fetch (§1105).
        case .subscriptions:
            walletSubscriptionsFigure
                .task(id: walletSubscriptionsKey) {
                    // The tile's reading, and the doors to each service's
                    // list, which its rows name (prd §1117).
                    await ServiceLinks.shared.refresh(modelContext, seats: bridges.bridges.map(\.name))
                    subscriptionsProbe()
                    subscriptionsCategoryProbe()
                }
        // **THE EMPTY STATE IS IN THE SLOT (prd §611).** A tile onto a page
        // with nothing draws what would fill it, empty.
        case _ where walletScopeIsEmpty(section):
            WalletScopeEmptyFigure(section: section)
        case .holdings:
            holdingsBlockSection
        // **SECURITY'S BOX IS A CHECKUP (prd §1107, user: "checkup is the
        // best").** Six counts, one per kind, each a door to its section.
        case .security:
            walletSecurityFigure
        }
    }

    /// What the crown gives back when it stops drawing the line.
    ///
    /// **THE TOGGLE MUST NOT MOVE BETWEEN SCOPES** (user ruling, prd §483: *"when
    /// toggling between home activity etc, the bar SHOULD NOT MOVE"*). A control
    /// that jumps as you use it is one you stop aiming at — and it jumped by
    /// construction, because Home's crown carries a 96pt chart plus its range
    /// chips while every other scope's crown carries neither.
    ///
    /// So the non-Home crowns reserve exactly what Home's chart and chips
    /// occupy, and the scope's own drawing sits in that reserved space. The
    /// number is spelled here rather than measured, because measuring it would
    /// mean the bar settles a frame LATE — which is the same jump, arriving
    /// slower.
    static var walletVisualSlot: CGFloat { DSRoomChassis.visualSlot }

    /// THE ROOM'S CHROME: the box, the tiles, the account menu (prd §1039).
    ///
    /// `DSRoomScopeChrome` carries the whole ruling; what lives here is the
    /// wallet's own answers to it — its accounts, its crown, its figures.
    ///
    /// **The accounts.** Whole names, never shortened by this caller. "All"
    /// leads and says what it is made of rather than repeating the word.
    ///
    /// **WATCH IS THE ACCOUNTS LIST'S FIRST ROW, NOT A TILE (prd §1107).** It
    /// was the last tile (§1039, §1105); watching adds an account, so it
    /// stands at the head of the list the account will join, and raises the
    /// same Watch tray (§1090).
    @ViewBuilder
    func walletScopeChromeSection(_ active: WalletSection,
                                  visible: [Thing],
                                  upcoming: [Thing],
                                  inert: Set<WalletSection> = [],
                                  streamTotal: Int) -> some View {
        // Read HERE, in this body, and captured by the crown below: read only
        // inside the crown's closure, the head's arrival never re-drew the box
        // (measured: computed, then the box stayed on "No balance yet").
        let seatHead = selectedSeat != nil ? heads?.seatHead : nil
        Section {
            DSRoomScopeChrome(
                source: "Wallet",
                pinned: pinnedWalletSection != nil,
                sections: chrome.walletSections,
                active: active,
                home: .home,
                attention: chrome.walletSectionAttention,
                inert: inert,
                // Instant, for the reason §495 states at length: animating a
                // swap between two slots of different natural height moves
                // everything below and settles it back.
                onPick: { picked in chrome.walletSection = picked },
                accounts: walletAccountSlots,
                scope: chrome.walletScope,
                onPickAccount: { picked in
                    withAnimation(DS.Motion.standard) { chrome.walletScope = picked }
                },
                accountAction: .init(title: String(localized: "Follow a wallet"),
                                     symbol: "plus") { feedSheet = .walletFollow },
                crown: { slot in
                    // **THE BOX IS BACK ON HOME (prd §760, reversing §757's
                    // drop).** Every room's lead is held to this height now, and
                    // Home is where it was taken from, so Home keeps it.
                    DSRoomSlot(headline: nil, reservesHeadline: false) {
                        if slot.isShowing(chrome.walletScope) {
                            // An app the menu picked draws its own head here
                            // when it has one (prd §1048d); else the balance.
                            if let seat = selectedSeat, seatKeepsLine(seat),
                               !walletScopeIsEmpty(.holdings) {
                                // An app that keeps its own line (Privy, prd
                                // §1194, user: "the landing needs to be balance
                                // sparkline. today it repeats the holdings")
                                // leads as an address does: the number and
                                // its line. Holdings stays Holdings' own.
                                walletTilesSection(visible, streamTotal: streamTotal,
                                                   drawsChart: true)
                            } else if selectedSeat != nil, !walletScopeIsEmpty(.holdings) {
                                // An app with money (an exchange, prd §1067;
                                // a Safe, §1069, user: "Safe should still show
                                // balance on home shouldn't it?") leads with
                                // what it holds, the figure its Holdings tile
                                // draws. A Safe's waiting signatures stand in
                                // Home's Needs you, where they already are.
                                holdingsBlockSection
                            } else if let head = seatHead {
                                sourceHeadCard(head, visible: visible)
                                    .environment(\.dsRoomHeadInWell, true)
                            } else if selectedSeat != nil, let newest = visible.first {
                                // An app with no money and no head (a Wise
                                // with nothing priced, Peer, Splits) leads
                                // with its newest thing (prd §1067), as every
                                // other room's app pick does, never the
                                // Wallet's empty balance line.
                                WalletSeatLatestLead(thing: newest)
                                    .contentShape(Rectangle())
                                    .onTapGesture { openThing(newest) }
                                    .dsTapCard()
                            } else {
                                walletTilesSection(visible, streamTotal: streamTotal,
                                                   drawsChart: true)
                            }
                        }
                    }
                },
                figure: { scope in
                    // `reservesHeadline: false` (prd §495): Wallet's figures
                    // name themselves inside their own drawing.
                    DSRoomSlot(headline: nil, reservesHeadline: false) {
                        walletScopeVisualSection(scope, upcoming: upcoming)
                    }
                }
            )
            .listRowInsets(EdgeInsets(top: 0, leading: 0,
                                      bottom: DSRoomChassis.contentGap, trailing: 0))
            .feedRowBackground()
            .listRowSeparator(.hidden)
            .task { walletFollowProbe() }
            // The tray's Wallet folder leads with Follow a wallet (prd §1133)
            // and can be opened from any room, so it asks; the room raises.
            .onChange(of: chrome.walletFollowPending, initial: true) { _, pending in
                guard pending, isActive, pinnedWalletSection == nil else { return }
                chrome.walletFollowPending = false
                feedSheet = .walletFollow
            }
        }
    }

    /// `-walletFollow YES` — raise the Follow tray at mount (prd §1090;
    /// NSLogs `walletFollow:`). Once per launch; a no-op in Release.
    private func walletFollowProbe() {
        #if DEBUG
        guard !Self.walletFollowProbed,
              UserDefaults.standard.bool(forKey: "walletFollow") else { return }
        Self.walletFollowProbed = true
        NSLog("[Casberi] walletFollow: raised")
        feedSheet = .walletFollow
        #endif
    }

    /// The watched wallets as deck cards, "All" first.
    ///
    /// The captions keep the rule the deleted `WalletScopeRail.items` had — a
    /// given name, else the short address — but not its truncation: that
    /// adapter fed a rail, and a rail had 66pt to work in. What is new is the
    /// SUB line, which a card has room for and a slot never did: the short
    /// address under a named wallet, and under "All" the names it is made of.
    var walletAccountSlots: [DSAccountSlot] {
        let watched = wallet.addresses
        let named = watched.map { addr in
            addr.label.isEmpty ? WalletStore.shortAddress(addr.address) : addr.label
        }
        let all = DSAccountSlot(
            id: "",
            name: String(localized: "All accounts"),
            // The roster, not a count: "2 accounts" is a number you already
            // know from the deck, and the names are what tells you whether
            // the one you want is in here.
            sub: named.isEmpty ? nil : ListFormatter.localizedString(byJoining: named),
            faces: watched.prefix(2).map { .wallet(address: $0.address) })
        // **THE APPS THE WALLET FOLDED IN (prd §1048b)**, each under its
        // kind, after the addresses. The addresses take a section of their
        // own only once an app stands beside them; alone, the menu reads as
        // it always did.
        // In the demo, only an app with rows or money (prd §1064, §1065).
        let seats = RoomAccounts.connected(in: source, names: connectedSeatNames)
            .filter(chrome.seatShows)
        let addresses = watched.map { addr in
            DSAccountSlot(
                id: addr.address,
                name: addr.label.isEmpty ? WalletStore.shortAddress(addr.address) : addr.label,
                sub: addr.label.isEmpty ? nil : WalletStore.shortAddress(addr.address),
                faces: [.wallet(address: addr.address)],
                group: seats.isEmpty ? nil : String(localized: "Addresses"))
        }
        let apps = seats.map { seat in
            DSAccountSlot(id: RoomAccounts.scopeID(seat), name: seat.name, sub: nil,
                          faces: [.mark(url: nil, source: seat.mark)], group: seat.group)
        }
        return [all] + addresses + apps
    }


    /// **SIGNATURES WAITING ON YOU, FIRST IN SECURITY (prd §947, §1107).** A
    /// Safe transaction someone proposed and you have not signed is a power
    /// over your wallet waiting on you — the first group, before Delegations
    /// and Approvals (user: "signatures, delegations, approvals"). The row
    /// opens that Safe's own queue.
    var walletSignatureWarnings: [WalletWarning] {
        walletLive.warnings.filter { $0.kind == .safe }
    }

    @ViewBuilder
    var walletSignaturesSection: some View {
        let waiting = walletSignatureWarnings
        if !waiting.isEmpty {
            Section {
                DSGroupHeader(word: String(localized: "Signatures"))
                    .id(SecurityAnchor.signatures.id)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(waiting) { warning in
                        needsYouRow(glyph: warning.kind.glyph, critical: false,
                                    title: warning.rowName ?? warning.title,
                                    line: warning.rowLine ?? warning.subtitle) {
                            if let action = warning.action, let url = URL(string: action.url) {
                                openExternal(url)
                            } else {
                                feedSheet = .worthALook
                            }
                        }
                    }
                }
                .listRowInsets(WalletCardStyle.rowInsets)
                .feedRowBackground()
                .listRowSeparator(.hidden)
            }
        }
    }

    func needsYouRow(glyph: String, critical: Bool, title: String, line: String?,
                             action: @escaping () -> Void) -> some View {
        Button {
            DSHaptic.selection()
            action()
        } label: {
            HStack(spacing: DS.Space.s3) {
                ZStack {
                    Circle().fill(DS.fillFaint)
                    Image(systemName: glyph)
                        .dsGlyph(.subhead, weight: .semibold)
                        .foregroundStyle(critical ? DS.destructive : DS.textPrimary)
                        .accessibilityHidden(true)
                }
                .frame(width: DS.Face.list, height: DS.Face.list)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    if let line {
                        Text(line)
                            .dsText(.subhead12).foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                DSChevron()
            }
            .padding(.vertical, DS.Space.s2)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
    }

    /// "Tell me below …" — the health line a borrow notifies under, one
    /// setting for every lending position (`DeFiRisk.alertLine`).
    @ViewBuilder
    var walletAlertLineMenu: some View {
        let line = DeFiRisk.alertLine
        Section(String(localized: "Tell me when health falls below")) {
            ForEach(DeFiRisk.alertChoices, id: \.self) { choice in
                Button {
                    UserDefaults.standard.set(choice, forKey: DeFiRisk.alertLineKey)
                    DSHaptic.success()
                    chrome.flash(String(localized: "You'll hear when a borrow falls below \(choice.formatted(.number.precision(.fractionLength(1...2))))"),
                                 tone: .success)
                } label: {
                    if choice == line {
                        Label(choice.formatted(.number.precision(.fractionLength(1...2))), systemImage: "checkmark")
                    } else {
                        Text(choice.formatted(.number.precision(.fractionLength(1...2))))
                    }
                }
            }
        }
    }

    // **THE SCOPE TOGGLE'S OWN SECTION IS GONE** (prd §547) — it is the lower
    // deck of `walletScopeRailSection`'s slab now. Two notes from it survive
    // because both are still true of the fused control:
    //
    // It reads `chrome.walletSections` rather than deriving presence at the
    // draw site: the publication is one value computed once per pass, and
    // re-deriving it here is how the strip and the sections it scopes come to
    // disagree about which scopes exist.
    //
    // **PINNING WAS TRIED AND DOES NOT WORK AS A HEADER** (prd §495,
    // 2026-08-27), and fusing does not change that. The strip scrolls away
    // with the crown — measured, entirely off screen — so the control that
    // scopes the room cannot be reached from inside the room it scopes.
    // `.plain` pins section headers, so `Section { EmptyView() } header: {
    // switcher }` looked like the fix that costs no height at rest and
    // therefore does not re-open §483 (which ruled this control OUT of
    // `roomControls`, where pinning it makes a fourth row of chips and pushes
    // the crown to 45% down the screen). It does not pin: a header only stays
    // while its own section has ROWS on screen, and this section has none, so
    // the header leaves with them. Verified on the device, not reasoned about.
    //
    // Pinning properly means making the slab the header of the section that
    // carries the SCOPE'S CONTENT — which differs per scope across a dozen
    // section builders — so it is a real refactor and its own ruling. What
    // ships is §495's return-to-head on a scope change, which removes the JUMP
    // without pretending to fix the reachability. Fusing makes that refactor
    // CHEAPER, since there is now one view to hoist instead of two.

    /// What this room publishes to the shell for §483's toggle — the scopes
    /// that have something, and which of them want you.
    ///
    /// One value rather than two so a single `onChange` carries both; they are
    /// read from the same live state on the same pass and must never be
    /// published a frame apart, or the strip draws a dot on a scope it has
    /// already stopped listing.
    var walletSectionPublication: WalletSectionPublication {
        guard shape == .wallet else { return .init(sections: [], attention: []) }
        // **EVERY SCOPE, ALWAYS (prd §611).** The five flags this used to
        // pass are now `walletScopeIsEmpty`, which decides between a scope's
        // figure and its empty state — the same expressions, one question,
        // so a chip can never lead somewhere blank (§483's Risk report).
        //
        // **`warnings`, not "does Risk exist".** A wallet with a 3.0 health
        // factor HAS a risk reading and is in no trouble at all, so lighting
        // the dot on the reading's presence would light it on every levered
        // wallet forever; it lights only on a position past its protocol's
        // own alert threshold, and never on a scope drawing its empty state.
        let sections = WalletSection.present()
        // **THE AMBER WORD FOLLOWS THE FACT (prd §1107).** A liquidation is a
        // position's, so it lights Holdings; a Safe waiting, a grant with no
        // limit, a delegate, or a transfer made to fool you lights Security.
        var attention: Set<WalletSection> = []
        if walletLive.warnings.contains(where: { $0.kind == .liquidation }) {
            attention.insert(.holdings)
        }
        if walletLive.warnings.contains(where: { $0.kind != .liquidation }),
           !walletScopeIsEmpty(.security) {
            attention.insert(.security)
        }
        return .init(sections: sections, attention: attention)
    }

    /// **THE SCOPE'S RENDER GATE, SPELLED ONCE.** Before §611 these five
    /// expressions were the strip's presence flags, and `wallet-section-selftest`
    /// guarded that each matched its section's own `if` — reported from a
    /// device as a Risk chip selected over an empty page, because `risk` was
    /// flagged on `!= nil` while the section drew on non-empty. They are the
    /// empty-state gate now and the guard is unchanged in spirit: a section
    /// that draws on a different condition than this names a scope that shows
    /// its figure AND its empty state, or neither.
    ///
    /// `permissions` is NOT `exposure.isEmpty` (prd §490): the scope draws for
    /// a wallet with no token grant at all but a Safe module or a 7702 delegate
    /// acting on it, so it reads the section's own holders.
    func walletScopeIsEmpty(_ section: WalletSection) -> Bool {
        switch section {
        // Subscriptions is decided by its own reading, in its figure.
        case .home, .subscriptions: return false
        case .holdings:        return blockStream.els.isEmpty
        // Every kind the checkup counts, the same reads its sections draw on.
        case .security:        return walletSecurityCounts.isEmpty
        }
    }

    /// **A STORED READING SAYS HOW OLD IT IS (prd §1078).** Privy's apps,
    /// Wise and Apple Wallet join the total from what their seats last read,
    /// beside chains read this pass; one line under the tokens names each
    /// place whose reading is past an hour ("Zora 3h ago, Wise yesterday").
    @ViewBuilder
    var walletStaleReadingsSection: some View {
        if let stale = portfolioShown?.staleReadings(), !stale.isEmpty {
            let list = ListFormatter.localizedString(
                byJoining: stale.map { "\($0.label) \(AccountPageShape.ago($0.at))" })
            Section {
                DSFootnote(prose: String(localized: "Last read: \(list)"))
                    .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DSRoomChassis.inset,
                                              bottom: 0, trailing: DSRoomChassis.inset))
                    .feedRowBackground()
                    .listRowSeparator(.hidden)
            }
        }
    }

    /// **THE SCOPES AN APP PICK CANNOT FILL (prd §1078, §1107).** Security is
    /// an address's reading, and an app pick clears it (§1067), so it is inert
    /// for every app. Holdings and Subscriptions are inert only when this app
    /// has nothing there: an exchange holds money, a card pays a subscription.
    /// Home never is. On All, nothing is inert: an empty
    /// scope there explains itself (§611).
    func walletInertSections(visible: [Thing], upcoming: [Thing]) -> Set<WalletSection> {
        var out: Set<WalletSection> = [.security]
        // Privy's apps are Holdings' too (§1124), with money or without.
        if walletScopeIsEmpty(.holdings),
           !visible.live.contains(where: { $0.sourceRef?.hasPrefix(PrivyHomeFeed.refPrefix) == true }) {
            out.insert(.holdings)
        }
        if SubscriptionsReading.shared.items(in: walletSubscriptionSources).isEmpty {
            out.insert(.subscriptions)
        }
        return out
    }

    /// An empty scope's list: rows with nothing in them (prd §769), at the
    /// room's row insets. The lead above already says the state, so VoiceOver
    /// skips these.
    var walletSkeletonRowsSection: some View {
        Section {
            DSSkeletonRows()
                .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.rowInset(forMark: DS.Face.list),
                                          bottom: 0, trailing: DS.Space.s4))
                .feedRowBackground()
                .listRowSeparator(.hidden)
        }
    }

    // **THE FOLLOW DOOR UNDER AN EMPTY LIST IS DELETED (prd §1039).** §771
    // put "Follow address" under an empty Activity or Holdings list, where it
    // was the remedy and the only door in reach. Follow is a tile on every page
    // now, directly above the list, and a second control for one consequence
    // two inches below it is §190's "two doors, one place". NFTs keep theirs:
    // Choose collections is no tile.

    /// NFTs fill by choosing collections for the wallet in scope.
    @ViewBuilder
    var walletNFTDoorSection: some View {
        if let entry = nftShelfWallet {
            Section {
                DSPushRow(title: Text("Choose collections"), tint: DS.tint,
                          action: {
                              feedSheet = .nftPicks(address: entry.address,
                                                    label: entry.label.isEmpty ? entry.short : entry.label)
                          }) {
                    walletDoorLead("square.grid.2x2")
                }
                .modifier(WalletDoorRow())
            }
        }
    }

    /// The 26pt disc every verb row in this room leads with.
    func walletDoorLead(_ glyph: String) -> some View {
        ZStack {
            Circle().fill(DS.fillFaint)
                .frame(width: DS.Face.row, height: DS.Face.row)
            Image(systemName: glyph)
                .accessibilityHidden(true)
                .dsGlyph(.caption, weight: .semibold)
                .foregroundStyle(DS.tint)
        }
    }

    struct WalletDoorRow: ViewModifier {
        func body(content: Content) -> some View {
            content
                .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.rowInset(forMark: DS.Face.list),
                                          bottom: 0, trailing: DS.Space.s4))
                .feedRowBackground()
                .listRowSeparator(.hidden)
        }
    }

    struct WalletSectionPublication: Equatable {
        var sections: [WalletSection]
        var attention: Set<WalletSection>
    }

    // MARK: - The wallet room's section headers

    /// A named block of the wallet room (2026-08-20, user ruling: *"should
    /// there be section headers between things"*).
    ///
    /// The room stacks up to nine live-state cards before the stream, and its
    /// arc — what you hold, what it's doing, who can reach it, what's ahead —
    /// existed only in the `.wallet` case's own comments. On screen it read as
    /// nine slabs of equal weight with no landmarks: no orientation, no sense
    /// of how much was left, which is what "it seems like a long feed" is
    /// describing. These are the landmarks.
    ///
    /// **The card labels STAY.** A header names the block; a card's own
    /// `WalletSectionLabel` distinguishes it from its SIBLINGS inside that
    /// block — "Lending", "Liquidity" and "Perps" all sit under "What it's
    /// doing" and are indistinguishable without their names. The one label
    /// that goes is `walletComingUpSection`'s, which said exactly what its
    /// header now says (§208: never say one thing twice).
    ///
    /// **The grammar is the stream's own day header**, verbatim — `heading24`
    /// in primary ink at the same insets. That is deliberate on two counts:
    /// this room already had a group-header tier and it was the day names, so
    /// "What you hold" and "Today" are peers because they ARE peers (both are
    /// top-level blocks of one room); and a second, smaller tier would mean
    /// inventing a rung the ramp doesn't carry between `heading24` and
    /// `label12`, for one screen.
    ///
    /// **Never rendered over nothing.** Every card here self-gates, so a
    /// header emitted unconditionally would promise content on the wallets
    /// that have least of it — a "What it's doing" over a wallet with no
    /// positions is worse than no header at all, because a header is a claim
    /// that something follows. Hence the hoisted predicates below: each one
    /// asks the same question its cards ask, so the header and the block can
    /// never disagree.
    ///
    /// The hero (balance + flow) deliberately gets NO header — a title above
    /// the first thing on a screen is noise, and the room's own name is the
    /// chip you tapped to get here.
    func walletGroupHeader(_ title: String) -> some View {
        Section {
            Text(title)
                .dsText(.heading24)
                .foregroundStyle(DS.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
                // Index 0 so the header LEADS its block's stagger rather than
                // popping in ahead of it — every other row in this room wears
                // this entrance, and a header that didn't would be the one
                // thing on screen that arrives without the wave.
                .modifier(rowEntrance(0))
                .padding(.leading, DS.Space.s4)
                // s8 above, s1 below (2026-08-22). At s6/s1 the header sat
                // 24 from the card it left and 14 from the card it names —
                // near enough to even that it read as floating between the
                // two rather than belonging to the one below. The gap above
                // has to beat the gap below by enough to be seen doing it;
                // 32 against 14 is that. (Below is s1 plus the next card's
                // own s3, which is why this is not simply doubled.)
                .padding(.top, DS.Space.s8)
                .padding(.bottom, DS.Space.s1)
                .listRowInsets(EdgeInsets())
                .feedRowBackground()
                .listRowSeparator(.hidden)
        }
    }

    /// The picked-NFT shelf's wallet, or nil when the shelf draws nothing.
    ///
    /// Hoisted out of the NFT drawing (2026-08-20; the drawing went with its tile, prd §1048) so the "What you hold"
    /// header can ask whether that block has a second card without restating
    /// the gate — two copies of this condition is how a header starts
    /// appearing over an absent shelf.
    var nftShelfEntry: WalletStore.WatchedAddress? {
        guard let entry = nftShelfWallet else { return nil }
        // Gated on state the ROOM owns (`nftHasCollections`, filled by
        // `loadWalletLive`), never on state the card would have to be alive to
        // fetch — see that function for the pruning trap this avoids.
        guard DemoMode.isActive || nftHasCollections
                || WalletNFTStore.shared.hasPicks(wallet: entry.address)
        else { return nil }
        return entry
    }

    /// The holdings card's tail — the book's shape on the left, the door to
    /// the whole allocation on the right, in ONE tertiary row (2026-08-22,
    /// prd §447).
    ///
    /// **This is what a four-line block reduced to.** §417 promoted the
    /// concentration sentence to a `heading24` lead above the map, on the
    /// reasoning that Lending and Approvals lead with their reading; that was
    /// right for those cards and wrong here, because the §417 group headers
    /// landed a 22pt "What you hold" in the same pass — so the card opened
    /// with two stacked 22pt lines, and the map under them opened with its own
    /// eyebrow repeating the header word for word. Three voices before the
    /// drawing. The reading is not deleted, it is demoted to where its sibling
    /// already lived.
    ///
    /// **What survives is exactly the pair the treemap cannot draw**, which is
    /// the test every cut here was made against: `UnitTreemap` is rank-ordered
    /// rather than area-proportional, so it cannot state a share; and stables
    /// are scattered across its cells by symbol, so it cannot group them. Both
    /// halves are composed by `WalletPortfolio.shapeLine`, never assembled
    /// here — a sentence built in a view would be a second definition of
    /// concentration, and the two would drift.
    ///
    /// Guarded as a WHOLE rather than per-child: both halves self-gate (a
    /// single-position book has no shape, a single wallet has no door), so an
    /// unguarded row would take a spacing slot in the card's stack and draw
    /// nothing in it.
    @ViewBuilder
    var holdingsTail: some View {
        if let portfolio, !portfolio.isEmpty,
           portfolio.shapeLine != nil || portfolio.walletCount > 1 {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                if let shape = portfolio.shapeLine {
                    Text(shape)
                        .dsText(.subhead12).foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
                WalletAllocationDoor(
                    portfolio: portfolio,
                    onOpen: portfolio.walletCount > 1 && selectedWallet == nil
                        ? { feedSheet = .allocation } : nil)
            }
            .padding(.horizontal, DS.Space.s4)
            // s2 from the stack + s1 here = s3 of air under the drawing. A
            // caption sits closer to its figure than two cards sit to each
            // other, and at the bare s2 the row read as a seventh cell.
            .padding(.top, DS.Space.s1)
        }
    }

    /// Does the "What you hold" block have anything in it — the treemap, the
    /// NFT list under it (prd §1048), or both.
    var walletHoldsSomething: Bool {
        !blockStream.els.isEmpty || nftShelfEntry != nil
    }

    /// Where the money moved (2026-08-01, `WalletFlowBand`) — inflows, the
    /// wallet, outflows, sized by what each was worth when it moved.
    ///
    /// Sits directly under the balance card ON PURPOSE, ahead of the treemap:
    /// the crown number's own delta pill and sparkline raise the question
    /// ("it moved — where to?") and this is the answer, so putting the
    /// composition map between cause and effect would separate them for no
    /// gain. It follows the balance card's own window, so the two can never
    /// describe different periods on one screen.
    ///
    /// Whose NFT shelf this room draws (2026-08-15, prd §387) — the scoped
    /// wallet, or the sole watched one.
    ///
    /// nil when several wallets are merged, and the shelf then draws nothing:
    /// a pick is made PER WALLET, so a merged shelf would have to say whose
    /// each piece is, and this room already declines to speak for merged
    /// wallets rather than invent an attribution (the flow band's portrait
    /// used the same reasoning until §771 drew its empty state as a skeleton). The wallet switcher is pinned above
    /// the room, so narrowing to one is a tap away.
    var nftShelfWallet: WalletStore.WatchedAddress? {
        let watched = wallet.addresses
        if let selectedWallet {
            return watched.first { WalletWatch.sameAddress($0.address, selectedWallet) }
        }
        // **UNSCOPED FALLS BACK TO THE FIRST WALLET WITH PICKS, not to nil**
        // (2026-08-26, prd §483). The old `count == 1` rule predates the NFTs
        // SCOPE existing: it was written when this card sat inside one long
        // room, where showing one wallet's art unscoped would have been a
        // silent claim about all of them. As a scope it is worse than
        // conservative, it is broken — anybody watching two wallets got a
        // chip that could never appear, however many collections they had
        // picked, with no way to find out why short of unwatching a wallet.
        //
        // The pick book is what makes the fallback honest: a wallet only
        // qualifies here because its owner named collections FOR it, so the
        // shelf is answering a question that was actually asked. Watch order,
        // never "the one with the most" — a shelf that reshuffles when an
        // airdrop lands reads as broken (§292's total-order rule).
        if watched.count == 1 { return watched.first }
        // The demo has no pick book by ruling (§387 — a picker there teaches a
        // decision that evaporates), so the pick test below would always fail
        // and the scope could never appear in the one place it MUST (the demo
        // is the north star, and a scope invisible there is a feature nobody
        // sees).
        if DemoMode.isActive { return watched.first }
        return watched.first { WalletNFTStore.shared.hasPicks(wallet: $0.address) }
    }

    /// The collections behind the quad, one row each (prd §483, 2026-08-26).
    ///
    /// A separate section rather than a `layout` branch inside one call so the
    /// room's own rule holds: ONE drawing in the slot, ONE list below, and the
    /// slot is height-clipped while the list is not. Both read the same
    /// cached pick fetch, so the pair costs one network read, not two.
    ///
    /// **No price on these rows**, which is the whole reason they can say what
    /// they say: §387 refused a floor and §481 refused it again, on the same
    /// ground — a floor is a bid on the thinnest book in this app, it moves
    /// without you, and printing one puts a number people believe (§83)
    /// beside art somebody keeps for reasons that are not the number. The
    /// shelf stores no value anywhere, so there is nothing here to round.
    @ViewBuilder
    var walletNFTListSection: some View {
        if let entry = nftShelfEntry {
            Section {
                WalletNFTCollectionRows(
                    wallet: entry.address,
                    onEdit: { feedSheet = .nftPicks(address: entry.address,
                                                    label: entry.label.isEmpty ? entry.short : entry.label) },
                    onOpen: { collection, name in
                        route.pushBridge(.nftCollection(wallet: entry.address, collection: collection, name: name))
                    })
                    .feedRowBackground()
                    .listRowSeparator(.hidden)
                    .listRowInsets(WalletCardStyle.rowInsets)
            }
        }
    }

    /// Security's second group — everything that can act as one of your
    /// wallets (prd §514; Permissions' until §1107).
    ///
    /// Separate from `walletApprovalsSection` because the two come from
    /// different reads and only one of them can be tapped: a grant opens its
    /// own prepare card (live allowance, revoke calldata, a Revoke.cash door)
    /// and a delegate has no such destination, so folding them into one list
    /// would give half its rows a chevron and half none.
    @ViewBuilder
    var walletActingSection: some View {
        let holders = WalletPermissionsSource.holders(exposure: walletLive.exposure,
                                                      acting: walletLive.acting)
        if !WalletPermissions.actingHolders(holders).isEmpty
            || walletLive.acting.contains(where: { $0.modulesUnreadable }) {
            Section {
                DSGroupHeader(word: String(localized: "Delegations"))
                    .id(SecurityAnchor.delegations.id)
                WalletActingPartiesRows(holders: holders, acting: walletLive.acting)
                    .modifier(rowEntrance(2))
                    .feedRowBackground()
                    .listRowSeparator(.hidden)
                    .listRowInsets(WalletCardStyle.rowInsets)
            }
        }
    }

    /// Approvals — what someone else can still move (2026-08-03, prd §292).
    ///
    /// Security's third group (prd §1107): it says who else can reach your
    /// money, beside what acts as you and the transfers made to fool you.
    /// Nothing renders without a live grant, which on most wallets is most of
    /// the time.
    ///
    /// The tap resolves the grant back to its `Thing` HERE rather than in the
    /// card, and re-checks `isLive` at the moment of the tap: a foreground
    /// heal can delete an approval row between the card being built and the
    /// finger landing (corollary 4's stale-array window, one layer up).
    @ViewBuilder
    var walletApprovalsSection: some View {
        if !walletLive.exposure.isEmpty {
            Section {
                DSGroupHeader(word: String(localized: "Approvals"))
                    .id(SecurityAnchor.approvals.id)
                WalletApprovalExposureCard(exposure: walletLive.exposure) { grant in
                    guard let thing = walletLive.activeApprovals
                        .first(where: { $0.isLive && $0.id == grant.thingID })
                    else {
                        // A row whose thing a foreground heal tombstoned
                        // between the read and the tap. It used to return in
                        // silence, which is indistinguishable from the door
                        // being broken — and this list already had one
                        // affordance problem (see the card's chevron note).
                        chrome.flash(String(localized: "That grant is no longer here."),
                                     tone: .failure)
                        return
                    }
                    feedSheet = .thing(thing, walk: .none)
                }
                .modifier(rowEntrance(2))
                .feedRowBackground()
                .listRowSeparator(.hidden)
                .listRowInsets(WalletCardStyle.rowInsets)
            }
        }
    }

    /// Lending — Aave and Morpho for the wallets in scope, in ONE card as two
    /// rows (prd §212, 2026-07-25). They were two full cards until this pass;
    /// they were never two subjects, just two providers of one. The treemap
    /// says what you HOLD, this says what you OWE — which is why it earns a
    /// seat here rather than staying two taps down. Nothing renders without a
    /// position on either.
    /// Whether `walletDeFiSection` will draw — the gate spelled once so the
    /// Worth-a-look sheet's walk door and the card it points at can't disagree
    /// (prd §449).
    var hasLendingCard: Bool {
        !walletLive.positions.isEmpty || !walletLive.morpho.isEmpty
    }

    /// **THE APPS THAT HOLD A WALLET FOR YOU, IN HOLDINGS (prd §1124, user:
    /// "the app list should be in holdings").** Privy's room led with its apps
    /// (§803e); the merge (§1048) put that head behind an app pick, and an app
    /// pick with money draws the balance in its place (§1069), so the list
    /// drew nowhere. It is Holdings' third group: the apps holding money by
    /// value, then the ones used lately, newest use first. Read off the rows,
    /// not `PrivyHomeStore`, so the hide and show-empty choices hold (`shows`)
    /// and the demo, whose store is never filled, draws it too.
    func walletAppRows(_ things: [Thing]) -> [FeedRow] {
        let store = PrivyHomeStore.shared
        let apps = things.filter { $0.sourceRef?.hasPrefix(PrivyHomeFeed.refPrefix) == true }
        // Typed steps: the one-chain form type-checked in Debug and timed out
        // in the Release archive (build 756).
        typealias Ranked = (row: FeedRow, usd: Double, used: Date)
        var ranked: [Ranked] = []
        for thing in apps {
            let ref: String = thing.sourceRef ?? ""
            let usd: Double = store.usd(ref) ?? 0
            let active: Date? = store.byRef[ref]?.lastActiveAt
            let used: Date = active ?? thing.capturedAt
            ranked.append((row: FeedRow.single(thing), usd: usd, used: used))
        }
        ranked.sort { (a: Ranked, b: Ranked) -> Bool in
            if a.usd != b.usd { return a.usd > b.usd }
            return a.used > b.used
        }
        return ranked.map { (r: Ranked) -> FeedRow in r.row }
    }

    @ViewBuilder
    func walletAppsSection(_ rows: [FeedRow], nextEventID: UUID?) -> some View {
        if !rows.isEmpty {
            Section {
                DSGroupHeader(word: String(localized: "Apps"))
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                    if case .single(let item) = row.kind, let thing = item.live {
                        shapedListRow(thing, index: i, nextEventID: nextEventID)
                    }
                }
            }
        }
    }

    /// **POSITIONS, UNDER THE TOKENS IN HOLDINGS (prd §1107).** Positions was
    /// its own tile; it is Holdings' second group now, under one header (the
    /// world's word, user: "call it positions"): lending first, closest to
    /// liquidation first, each borrow saying how far it can fall — the
    /// sentence the Risk tile carried — then perps, which state their own
    /// distance, then liquidity. Nothing renders without a position.
    @ViewBuilder
    var walletPositionsSections: some View {
        let lending = hasLendingCard
        let perps = !walletLive.hyperliquid.positions.isEmpty
        let liquidity = !walletLive.uniswap.isEmpty
        if lending || perps || liquidity {
            Section {
                DSGroupHeader(word: String(localized: "Positions"))
                if lending {
                    WalletLendingCard(aave: walletLive.positions, morpho: walletLive.morpho,
                                      falls: walletLendingFalls,
                                      lineMenu: { AnyView(walletAlertLineMenu) })
                        .modifier(rowEntrance(2))
                        .feedRowBackground()
                        .listRowSeparator(.hidden)
                        .listRowInsets(WalletCardStyle.rowInsets)
                }
                if perps {
                    WalletPerpsCard(book: walletLive.hyperliquid)
                        .modifier(rowEntrance(3))
                        .feedRowBackground()
                        .listRowSeparator(.hidden)
                        .listRowInsets(WalletCardStyle.rowInsets)
                }
                if liquidity {
                    WalletLiquidityCard(book: walletLive.uniswap)
                        .modifier(rowEntrance(4))
                        .feedRowBackground()
                        .listRowSeparator(.hidden)
                        .listRowInsets(WalletCardStyle.rowInsets)
                }
            }
        }
    }

    /// Each borrowing protocol's closest position, in words a row can carry
    /// ("can fall 24%", `WalletRiskScale.shortFall`), read off the same
    /// entries the Risk tile drew, so the sentence and the old bars agree.
    var walletLendingFalls: [String: String] {
        let entries = WalletRiskScaleSource.entries(aave: walletLive.positions,
                                                    morpho: walletLive.morpho,
                                                    hyperliquid: walletLive.hyperliquid)
        var worst: [String: WalletRiskScale.Entry] = [:]
        for entry in entries {
            let parts = entry.id.split(separator: ":", omittingEmptySubsequences: false)
            let name: String
            switch parts.first {
            case "aave" where parts.count > 1: name = String(parts[1])
            case "morpho": name = "Morpho"
            default: continue
            }
            if let held = worst[name], held.headroom <= entry.headroom { continue }
            worst[name] = entry
        }
        return worst.compactMapValues(WalletRiskScale.shortFall)
    }


    /// What's still ahead in this room — the in-scope things carrying a future
    /// `dueAt`, soonest first (2026-07-31).
    ///
    /// These rows were effectively invisible, and it took two separate
    /// mechanisms to hide them. `dayGroups` DROPS future-dated things by
    /// design ("what's still ahead lives on Home's Coming up lane, not here",
    /// 2026-07-19) — but that lane retired with the Home board in §131, so
    /// what it pointed at no longer exists. And these particular rows dodge
    /// that drop only to land in a worse place: `AerodromeDeFi`,
    /// `HyperliquidDeFi` and `ENSExpiry` all stamp `capturedAt: .now` and
    /// carry the deadline on `dueAt`, reconciling the row IN PLACE as the date
    /// moves — so a vote window that first landed three weeks ago sorts three
    /// weeks down a stream ordered by arrival, far past the five-row preview,
    /// no matter how soon it closes.
    ///
    /// Which is the whole problem: a weekly vote deadline and a lock expiry
    /// are the two rows in this room where being late is the only failure
    /// mode, and they were the two least likely to be seen.
    ///
    /// **THEY ARE THE "COMING UP" SCOPE NOW, AND HOME IS ONLY WHAT HAPPENED
    /// (prd §1041, user: "its own tile").** Every one, uncapped — the
    /// three-row cap was for the head of a history feed, and this is a scope
    /// of its own — soonest first, which is the point of the scope. They
    /// leave Home's stream whole, so a deadline is never read as a move.
    ///
    /// **WHAT IS STILL PENDING LEADS IT (prd §1048, step 4).** The folded apps
    /// carry things that are waiting with no date to wait for: a Safe
    /// transaction still in the queue (`SafeBridge.pendingSnapshot`, the
    /// loop-closer's own state, because a queued row keeps its old tags after
    /// it executes) and a Privacy Pools deposit not yet cleared. They are
    /// "now", so they come before anything dated, newest first. Peer's open
    /// trades and Rocket Money's bills are not here: neither stores a pending
    /// item or a due date the room could read.
    /// How long a price rise stands in Needs you: one monthly cycle.
    static let priceRiseWindow: TimeInterval = 30 * 86_400

    func walletUpcoming(_ visible: [Thing]) -> [Thing] {
        let now = Date.now
        let live = visible.live
        let pending = live.filter { thing in
            guard let ref = thing.sourceRef else { return false }
            if thing.source == SafeBridge.sourceName { return walletSafePending.contains(ref) }
            if thing.source == PrivacyPoolsBridge.sourceName, ref.hasPrefix(PrivacyPoolsRoom.depositPrefix) {
                return PrivacyPoolsRoom.state(tags: thing.tags).map { !$0.resolved } ?? false
            }
            // Off chain: a Wise transfer Wise is holding until you act, and a
            // subscription that went up, until the next charge at the new
            // price would land — the decision is keep it or cancel first.
            if thing.source == WiseShape.source { return WiseShape.isStuck(tags: thing.tags) }
            if thing.source == AppleWalletBridge.sourceName, thing.tags.contains("Price rise") {
                return now.timeIntervalSince(thing.capturedAt) < Self.priceRiseWindow
            }
            return false
        }
        .sorted { $0.capturedAt > $1.capturedAt }
        // A bill that repeats is Subscriptions' (prd §1105), never two tiles'.
        let dated = live
            .filter { ($0.dueAt ?? .distantPast) > now && !SubscriptionsSource.isBill($0, now: now) }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
        return pending + dated
    }

    /// **SUBSCRIPTIONS' BOX (prd §1105, §1111): what they cost a month, one
    /// line, and the five weeks as a calendar** (`WalletSubscriptionsFigure`), a face on
    /// each renewal's day. No subscription draws the scope's empty state
    /// (§769) once the reading has landed, and nothing before it.
    @ViewBuilder
    var walletSubscriptionsFigure: some View {
        let reading = SubscriptionsReading.shared
        let subscriptions = reading.items(in: walletSubscriptionSources)
        if subscriptions.isEmpty {
            if reading.read {
                WalletScopeEmptyFigure(section: .subscriptions)
            } else {
                Color.clear
            }
        } else {
            WalletSubscriptionsFigure(subscriptions: subscriptions,
                                      monthly: reading.total(of: subscriptions))
        }
    }

    // `walletComingUpSection` — the deadlines' own card, drawn nowhere since
    // §483 parked it — is deleted: Coming up is a scope now (prd §1041),
    // its rows under the feed's day headers and its figure in the box.

    /// "Closes Thursday" / "In 3 weeks" — when the deadline lands, in the
    /// grain that's actually useful at that distance. Guarded internally
    /// because it takes a raw `Thing` from a call site that may re-evaluate
    /// (corollary 4's rule for shared helpers).
    ///
    /// Forwards to `FeedLedeFace.dueLine` (prd §389 amendment) so the cover's
    /// countdown and this one are the same formatting — they sit on the same
    /// screen, often about the same thing, and two copies is where a countdown
    /// quietly starts disagreeing with itself depending on where you read it.
    static func dueLine(_ thing: Thing) -> String? {
        guard thing.isLive, let due = thing.dueAt else { return nil }
        return FeedLedeFace.dueLine(due)
    }


    /// The newest few transactions, drawn INSIDE the balance card
    /// (2026-08-18, user ruling: "the real answer is the user will want to see
    /// them above the fold").
    ///
    /// **Not a second row anatomy.** These are `BandRow`s with the money
    /// column, byte-identical to what the stream below draws, because §212's
    /// law for this room is one row shape and a compact variant here would be
    /// the second. So a row reads the same whether you meet it up top or two
    /// screens down, and the fold's rows and this card's can never disagree
    /// about how a transfer looks.
    ///
    /// **The door is the section label's count-link, not a centred see-all
    /// row.** `WalletRowChevron`'s own note records that this room once
    /// carried six grammars for "there's more" and that exactly two survived
    /// the §212 pass — a chevron on a row, and a count-link on a section
    /// label. This is the second one, at its documented shape.
    ///
    /// **Every row it takes, the stream gives up** (see the `.wallet` case's
    /// `led` set), so nothing is said twice and nothing is hidden: the rest of
    /// the stream still reads below, and the full history is one tap away.
    @ViewBuilder
    func walletTodayCard(_ rows: [Thing], streamTotal: Int) -> some View {
        // Only when there IS more behind it — a wallet whose whole history is
        // these three rows would otherwise get a door onto what it can already
        // see (the honesty rule's dead-control clause).
        let hasMore = streamTotal > rows.count
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            WalletSectionLabel(
                title: walletLatestLabel(rows),
                // NO COUNTER (user ruling, prd §483: *"we can just say see all
                // activity or see activity. we dont need a counter"*). The
                // number was a second fact competing with the verb, and it is
                // the one that changes every sync.
                trailingTitle: hasMore ? String(localized: "See activity") : nil,
                onTapTrailing: hasMore
                    ? { route.pushBridge(.walletHistory(scope: walletHistoryScope)) }
                    : nil)
            ForEach(Array(rows.keyed.enumerated()), id: \.element.id) { i, item in
                // `live` INSIDE the closure, before any read (corollary 3):
                // this re-evaluates against the array it already holds when a
                // heal's delete lands.
                if let thing = item.live {
                    Button {
                        openThing(thing)
                    } label: {
                        BandRow(thing: thing, moneyColumn: true, rippleIndex: i)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPress())
                    .dsHover()
                    .macHoverLift()
                }
            }
        }
        // **NO SURFACE (user ruling, prd §483: *"we need to put the
        // transactions that are showing outside of a card, remember we are
        // going to the restrained design?"*).** The rows sit bare on the page
        // and separate by air and heading weight, which is the direction's own
        // rule: text sections lose their box, DRAWINGS keep one. The sparkline
        // directly above still has its ground because `TokenChartPlot`'s fill
        // is calibrated against it; three rows of type need nothing.
        //
        // Only the horizontal inset survives, so the rows land on the same
        // 18pt margin the crown's figure and the toggle already sit on — a
        // card's own padding was what put them 36pt in.
        .padding(.vertical, DS.Space.s2)
    }

    /// What to call the card above — and the reason it is a function rather
    /// than the literal "Today" the mock carried.
    ///
    /// A day word is only honest while every row it covers falls on that day.
    /// A wallet that last moved in March would wear "Today" over three
    /// five-month-old transfers — §83's fake status, in the largest claim on
    /// the card. So the day label is used when the rows agree on a day (the
    /// ordinary case on an active wallet, where it reads exactly as asked),
    /// and the room's own neutral word otherwise. Each row carries its own
    /// timestamp either way, so nothing is lost by the fallback.
    func walletLatestLabel(_ rows: [Thing]) -> String {
        let days = Set(rows.live.map { Self.groupingCalendar.startOfDay(for: $0.capturedAt) })
        if days.count == 1, let day = days.first { return dayLabel(day) }
        // **"Recent", not "Activity" (prd §483).** This fallback read "Activity"
        // until the scope strip took that word for a chip — and this card only
        // draws in the scopes where that chip is NOT selected, so the room said
        // "Activity" in a card 300pt below an "Activity" chip that was greyed
        // out. Two different things wearing one word, with the deselected one
        // implying the card belonged to a scope you were not in.
        return String(localized: "Recent")
    }

    /// One row per move, newest first (prd §942). The runs of routine
    /// transfers this folded into "9 transfers" are unfolded: a fold hid the
    /// counterparty and the amount — the two things Activity is read for.
    func walletStreamRows(_ things: [Thing]) -> [FeedRow] {
        walletStream(things).rows
    }

    /// Home's rows with each move between your own accounts drawn once (prd
    /// §1078, `WalletOwnMoves`): the received leg leaves the list, and the
    /// sent leg's row carries it in `ownMoves`, keyed by the sent leg's id.
    func walletStream(_ things: [Thing]) -> (rows: [FeedRow], ownMoves: [UUID: KeyedThing]) {
        let legs = things.compactMap { thing -> WalletOwnMoves.Leg? in
            guard let direction = thing.transferDirection,
                  direction == "sent" || direction == "received" else { return nil }
            return .init(id: thing.id, sent: direction == "sent",
                         address: thing.walletAddress, counterparty: thing.counterpartyAddress,
                         amount: thing.transferAmount, link: thing.externalLink, at: thing.capturedAt)
        }
        let pairs = WalletOwnMoves.pairs(legs)
        guard !pairs.isEmpty else {
            return (things.prefix(Self.walletPreviewRows).map(FeedRow.single), [:])
        }
        let byID = Dictionary(things.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let folded = Set(pairs.map(\.received))
        var ownMoves: [UUID: KeyedThing] = [:]
        for pair in pairs {
            if let received = byID[pair.received] { ownMoves[pair.sent] = KeyedThing(received) }
        }
        let rows = things.filter { !folded.contains($0.id) }
            .prefix(Self.walletPreviewRows).map(FeedRow.single)
        return (rows, ownMoves)
    }

    /// The stream preview's day sections.
    ///
    /// A near-twin of `groupedSections`/`daySection`, and separate on purpose:
    /// those speak `[Thing]`, and a fold is not a thing. Same guards
    /// throughout — `live` re-checked inside the content closure, identity off
    /// `FeedRow`'s stored id, never the model.
    @ViewBuilder
    func walletStreamSections(_ rows: [FeedRow], ownMoves: [UUID: KeyedThing] = [:],
                              panelled: Bool = false,
                              nextEventID: UUID?) -> some View {
        let groups = walletStreamDays(rows)
        // The same boundary the rest of the feed draws, over `FeedRow`'s own
        // stored dates — dropping it here would have quietly cost this room
        // its "new since" divider.
        walletDaySections(groups, boundary: boundaryID(in: groups), ownMoves: ownMoves,
                          panelled: panelled, nextEventID: nextEventID)
    }

    /// **"NEEDS YOU" LEADS HOME (prd §1090, Work's §1080 carried over; Home's
    /// since §1111, when Coming up became Subscriptions).**
    /// The undated rows — a Safe transaction in the queue, a deposit waiting
    /// on proof — are the ones the box counts as "need you now", so their
    /// group says so, named by what it is rather than a time word, in the
    /// primary ramp (§740: only a day wears the brand hue).
    static var needsYouGroup: String { String(localized: "Needs you") }

    /// The day sections Home draws twice — what's ahead, then the stream.
    @ViewBuilder
    func walletDaySections(_ groups: [(String, [FeedRow])], boundary: String?,
                           ownMoves: [UUID: KeyedThing] = [:],
                           named: Set<String> = [],
                           headless: Bool = false,
                           panelled: Bool = false,
                           nextEventID: UUID?) -> some View {
        ForEach(Array(groups.enumerated()), id: \.element.0) { groupIndex, group in
            let (label, dayRows) = group
            // Rows in a day share ONE card silhouette (2026-07-21); a single
            // that stands alone breaks the run, and a fold — like the All
            // room's bundles — merges into it like any row-shaped thing.
            let positions = cardRunPositions(
                count: dayRows.count,
                isBreaker: { i in
                    if case .single(let item) = dayRows[i].kind,
                       let thing = item.live { return standsAlone(thing) }
                    return false
                },
                isBoundary: { dayRows[$0].id == boundary })
            Section {
                // UNPINNED (2026-08-29) — a ROW, not a `header:`, for the reason
                // the twin in `bundledSections` gives at length: `.plain` pins a
                // header, this one clears the backdrop that would make a pinned one
                // legible, and a header with neither draws on top of the rows
                // scrolling under it. Nothing moves — the insets were already zeroed
                // and every pad is spelled out, so the row lands where the header
                // did.
                // A list whose panel already says its name draws no second
                // header (prd §1219).
                if !headless {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                        // The day wears the brand hue, as every day header in
                        // the feed does (prd §740); this was the one in primary.
                        Text(label).dsText(.heading20)
                            .foregroundStyle(named.contains(label) ? DS.textPrimary : DS.brandInk)
                    }
                    .textCase(nil)
                    // On a panel the day stands in the rows' column, as the
                    // Feed's days do (prd §1219).
                    .padding(.leading, panelled ? DSRoomChassis.rowInset : DS.Space.s4)
                    // The FIRST day heading sits directly under the scope
                    // switcher, which already carries its own bottom inset — the
                    // macro pad belongs BETWEEN days, not above the first one, and
                    // spending it there opened a ~45pt dead band on Activity that
                    // Home (whose lead section is a small header) never had.
                    .padding(.top, groupIndex == 0 ? DS.Space.s1 : DS.Space.s6)
                    .padding(.bottom, DS.Space.s1)
                    .listRowInsets(EdgeInsets())
                    .feedRowBackground()
                    .listRowSeparator(.hidden)
                }
                ForEach(Array(dayRows.enumerated()), id: \.element.id) { i, row in
                    if row.id == boundary { newSinceDivider }
                    switch row.kind {
                    case .single(let item):
                        // `live` INSIDE the closure, before any read
                        // (corollary 3): this re-evaluates against the array
                        // it already holds when a heal's delete lands.
                        if let thing = item.live {
                            if let partner = ownMoves[thing.id]?.live {
                                walletOwnMoveRow(sent: thing, received: partner, index: i)
                            } else if thing.transferDirection == "received" || thing.transferDirection == "sent" {
                                walletMoveRow(thing, index: i)
                            } else {
                                shapedListRow(thing, index: i, nextEventID: nextEventID,
                                              position: positions[i])
                            }
                        }
                    default:
                        // The stream holds singles only since prd §942.
                        EmptyView()
                    }
                }
            }
        }
    }

    /// **A MOVE BETWEEN YOUR OWN ACCOUNTS (prd §1078).** One row for both
    /// legs: "Moved 0.5 ETH", where it went from and to, and the amount with
    /// no sign and no colour, because the money stayed yours (§83). It opens
    /// the leg that left.
    func walletOwnMoveRow(sent: Thing, received: Thing, index: Int) -> some View {
        let amount = sent.transferAmount ?? ""
        let money = sent.transferUSD.flatMap { usd -> String? in
            guard usd.isFinite else { return nil }
            let text = WalletValue.money(usd)
            return text.contains(where: { ("1"..."9").contains($0) }) ? text : nil
        }
        let route = "\(walletPlaceName(sent)) → \(walletPlaceName(received))"
        return Button {
            openThing(sent)
        } label: {
            HStack(spacing: DS.Space.s3) {
                WalletMarkView(mark: .symbol("arrow.left.arrow.right", tint: DS.textSecondary),
                               size: DS.Face.list)
                VStack(alignment: .leading, spacing: 1) {
                    Text(amount.isEmpty ? String(localized: "Moved") : String(localized: "Moved \(amount)"))
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Text(route)
                        .dsText(.subhead12).foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: DS.Space.s2)
                if let money {
                    Text(money)
                        .dsText(.price17).foregroundStyle(DS.textSecondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .dsHover()
        .modifier(rowEntrance(index))
        .accessibilityLabel(Text("Moved \(amount), \(route)"))
        .listRowInsets(EdgeInsets(top: DS.Space.s2,
                                  leading: DSRoomChassis.rowInset(forMark: DS.Face.list),
                                  bottom: DS.Space.s2, trailing: DSRoomChassis.rowInset))
        .feedRowBackground()
        .listRowSeparator(.hidden)
    }

    /// An account's name on a move: the watched address's label, else its
    /// short form; a folded app's leg names the app.
    func walletPlaceName(_ thing: Thing) -> String {
        guard thing.source == "Wallet" else { return BridgeCatalog.seatName(forSource: thing.source) }
        guard let address = thing.walletAddress else { return thing.source }
        if let entry = wallet.addresses.first(where: { WalletWatch.sameAddress($0.address, address) }),
           !entry.label.isEmpty {
            return entry.label
        }
        return WalletStore.shortAddress(address)
    }

    /// **ONE MOVE, IN THE WALLET LIST'S ANATOMY (prd §942).** Who it was
    /// with — their face and name, a short address when they have none —
    /// which of your accounts when the room shows all of them, and the amount
    /// signed by direction in plain ink, dollars where the move was priced.
    /// The All feed's transfer row led with a verb ("Received") and, for a
    /// nameless counterparty, said nothing else; Holdings and Accounts one
    /// tile over are mark, name, amount.
    @ViewBuilder
    func walletMoveRow(_ thing: Thing, index: Int) -> some View {
        let received = thing.transferDirection == "received"
        let sign = received ? "+" : "−"
        // **WHO, THEN DOLLARS, THEN THE QUANTITY ON THE LINE (prd §1090).**
        // A card spend names no merchant on chain, so its title was "Spent
        // $12.40 with Gnosis Pay" beside "−12.40 USDC": the amount twice and
        // the card cut off. Its who is the card; the dollars stand on the
        // right; the token's quantity moves to the line under the name.
        let who = thing.transferCounterparty.flatMap { $0.isEmpty ? nil : $0 }
            ?? thing.counterpartyAddress.map(WalletStore.shortAddress)
            ?? (WalletCards.isSpend(thing) ? BridgeCatalog.seatName(forSource: thing.source) : thing.title)
        let account = selectedWallet == nil && wallet.addresses.count > 1
            ? WalletStore.shared.label(forAddress: thing.walletAddress) : nil
        let parsed = WalletFlow.parseAmount(thing.transferAmount ?? "")
        // A dollar coin's quantity IS dollars; anything else needs the read's price.
        let usd = thing.transferUSD.flatMap { $0.isFinite ? $0 : nil }
            ?? (WalletStables.isDollar(parsed.symbol) ? parsed.amount : nil)
        // **AN AMOUNT THAT READS AS NOTHING WEARS NO SIGN (§83).** Dollars
        // where they round to something; else the token's own quantity; and a
        // stamp that says no quantity ("ETH") or only zeros ("0.0000 ETH") is
        // drawn quiet and unsigned, never "+$0".
        let amount: (text: String, known: Bool, dollars: Bool) = {
            if let usd {
                let money = WalletValue.payment(usd)
                if money.contains(where: { ("1"..."9").contains($0) }) { return (sign + money, true, true) }
            }
            let raw = thing.transferAmount ?? ""
            if raw.contains(where: { ("1"..."9").contains($0) }) { return (sign + raw, true, false) }
            // A bare unit ("ETH") with no number read as a broken row (prd
            // §953): draw nothing on the right; a real zero keeps its "0".
            return raw.contains(where: \.isNumber) ? (raw, false, false) : ("", false, false)
        }()
        // The quantity rides the line only when the right side is dollars —
        // otherwise it IS the right side, and saying it twice is the defect.
        let quantity = amount.dollars && (thing.transferAmount ?? "").contains(where: { ("1"..."9").contains($0) })
            ? WalletValue.transferAmount(thing) : nil
        let line = [account, quantity].compactMap { $0 }.joined(separator: " · ")
        Button {
            openThing(thing)
        } label: {
            HStack(spacing: DS.Space.s3) {
                let symbol = WalletFlow.parseAmount(thing.transferAmount ?? "").symbol
                if let address = thing.counterpartyAddress, !address.isEmpty {
                    WalletFace(address: address, size: DS.Face.list, circular: true)
                } else if symbol.isEmpty, thing.source != "Wallet" {
                    // A folded app's row with no token (a Wise transfer, prd
                    // §1067) wears its app's mark, not a "?" monogram.
                    BridgeIcon(name: BridgeCatalog.seatName(forSource: thing.source),
                               size: DS.Face.list, circular: true)
                } else if symbol.isEmpty {
                    // No address and no token (a transfer named only in its
                    // title, "from sam.eth"): the way it moved, never
                    // AssetMark's "?" for an empty name (prd §1076).
                    WalletMarkView(mark: .symbol(thing.transferDirection == "sent"
                                                    ? "arrow.up.right" : "arrow.down.left",
                                                 tint: DS.textSecondary),
                                   size: DS.Face.list)
                } else {
                    AssetMark(name: symbol, size: DS.Face.list)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(who)
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    if !line.isEmpty {
                        Text(line)
                            .dsText(.subhead12).foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: DS.Space.s2)
                Text(amount.text)
                    .dsText(.price17)
                    .foregroundStyle(amount.known ? DS.textPrimary : DS.textTertiary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .dsHover()
        .modifier(rowEntrance(index))
        .accessibilityLabel(Text("\(received ? String(localized: "Received from") : String(localized: "Sent to")) \(who), \(amount.text)"))
        .listRowInsets(EdgeInsets(top: DS.Space.s2,
                                  leading: DSRoomChassis.rowInset(forMark: DS.Face.list),
                                  bottom: DS.Space.s2, trailing: DSRoomChassis.rowInset))
        .feedRowBackground()
        .listRowSeparator(.hidden)
    }

    /// The due rows grouped under the day each falls due, soonest first.
    func walletComingUpDays(_ upcoming: [Thing]) -> [(String, [FeedRow])] {
        var order: [String] = []
        var groups: [String: [FeedRow]] = [:]
        // What is pending with no date (a Safe transaction in the queue, a
        // deposit under review, prd §1048 step 4) is waiting NOW, so it leads
        // under a time word rather than dropping off the list it heads.
        let now = Self.needsYouGroup
        for thing in upcoming.live where thing.dueAt == nil || (thing.dueAt ?? .distantFuture) <= .now {
            if groups[now] == nil { order.append(now) }
            groups[now, default: []].append(.single(thing))
        }
        for thing in upcoming.live {
            guard let due = thing.dueAt, due > .now else { continue }
            let label = dayLabel(due)
            if groups[label] == nil { order.append(label) }
            groups[label, default: []].append(.single(thing))
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    /// Day groups over the stream's rows, newest first — `dayGroups`' rule
    /// (including its "drop what's still ahead" clause, which is now genuinely
    /// true here: anything future-dated leads Home under its own day, §1111).
    func walletStreamDays(_ rows: [FeedRow]) -> [(String, [FeedRow])] {
        let today = Self.groupingCalendar.startOfDay(for: .now)
        var order: [String] = []
        var groups: [String: [FeedRow]] = [:]
        for row in rows where Self.groupingCalendar.startOfDay(for: row.date) <= today {
            let label = dayLabel(row.date)
            if groups[label] == nil { order.append(label) }
            groups[label, default: []].append(row)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    /// The stream's door — only when there's more behind it than the preview
    /// showed (no dead control when five rows is the whole history).
    /// The history screen's scope: an app the menu picked (`seat:<name>`), an
    /// address's book key, or nil for every row (prd §1048, step 4).
    var walletHistoryScope: String? {
        selectedSeat.map(RoomAccounts.scopeID) ?? selectedWallet.map(AddressBook.key(for:))
    }

    @ViewBuilder
    func walletSeeAllSection(total: Int) -> some View {
        if total > Self.walletPreviewRows {
            Section {
                WalletSeeAllRow(count: total) {
                    route.pushBridge(.walletHistory(scope: walletHistoryScope))
                }
                .listRowSeparator(.hidden)
                // On the page itself, not in a card — a quiet continuation
                // line, not another surface (user, 2026-07-20, twice).
                .feedRowBackground()
            }
        }
    }


    /// The wallet leads with holdings — real, from Alchemy (WalletIngest),
    /// one treemap per watched address, same doc Home and the Wallet screen
    /// render (ruling 2026-07-09: the old mock demo-only block never showed a
    /// real user anything real).
    @ViewBuilder
    var holdingsBlockSection: some View {
        if !blockStream.els.isEmpty {
                            VStack(alignment: .leading, spacing: DS.Space.s2) {
                    // THE DRAWING LEADS (2026-08-22, prd §447) — nothing above
                    // the map at all. §417 put the concentration sentence here
                    // at `heading24` on Lending's and Approvals' anatomy, and
                    // the same pass put a 22pt "What you hold" header directly
                    // above this card: two display lines stacked, then the
                    // map's own eyebrow saying the header's words again. The
                    // reading moved down to `holdingsTail`, beside the stables
                    // line it always belonged with; the header is the card's
                    // title and always was.
                    GenRender(id: "root", els: blockStream.els)
                        // The day's heat map (prd §1090): each tile's move.
                        .environment(\.holdingsDayMoves, walletHoldingMoves)
                        // A tapped holdings cell opens its token's chart
                        // (2026-07-14): the thing sheet when watched, the quick
                        // sheet when it's just held; a routeless native-coin
                        // cell keeps its old door — the Wallet screen (no dead
                        // controls). The Feed sets its own handler —
                        // HomeScreen's doesn't reach this surface.
                        .environment(\.genProjectTap) { name in
                            if let route = TokenQuickRoute.from(sentinel: name) {
                                if let thing = route.watchedThing(in: modelContext) {
                                    openThing(thing)
                                } else {
                                    // The combined map merges wallets, so a
                                    // cell tapped there carries the "held in"
                                    // breakdown with it (prd §155) — the fact
                                    // the per-wallet maps used to carry by
                                    // never merging in the first place.
                                    feedSheet = .token(route.withHolders(
                                        portfolio?.holders(forSymbol: route.symbol ?? "") ?? []))
                                }
                            } else if name == "@wallet" {
                                route.pushBridge(.wallet)
                            }
                        }
                    // The map says WHAT you hold; this one row says the two
                    // things it is structurally unable to say, and opens the
                    // rest. Three separate text objects until 2026-08-22 — see
                    // **THE TAIL LINE IS GONE** (user ruling, prd §483:
                    // *"get rid of the words"*). It carried a concentration
                    // sentence ("ETH 62% · 28% stables") and an "All 3 ›" door.
                    //
                    // Both were answers to a question the board alone could not
                    // settle — WHICH tokens, in what share — and the token list
                    // directly below the toggle now answers it properly, with
                    // every holding, its amount and its own percentage. The
                    // door in particular pointed at a tray showing less than
                    // the list it would have covered.
                }
                // **THE MAP FILLS THE BOX, IT DOES NOT SPELL A HEIGHT**
                // (2026-09-01, user: *"treemap is clipped in wallet"*).
                //
                // `GenTagMap` drew 160pt of cells under its own eyebrow,
                // subline and 18pt top padding — ~250pt into a 210pt
                // `DSRoomSlot`, which clips — so the bottom row of the
                // treemap was sliced along its lower edge. The same class the
                // chassis already records for the NFT quad, by a different
                // route: there the box lost a reserved headline, here the
                // drawing was taller than the box all along.
                //
                // The flag makes the cells absorb whatever the header leaves,
                // so it fits at any Dynamic Type size and survives any later
                // change to `visualSlot`.
                .environment(\.genFillsRoomSlot, true)
                // NO BOTTOM PADDING. The old `s3` closed the holdings CARD
                // (prd §160), and §483 deleted that card; inside a fixed box
                // it is no longer air below the map but 14pt taken OFF it,
                // which is 14pt the cells are then clipped by. Every other
                // scope's figure fills the slot — the NFT quad derives its
                // cell size from the whole of `visualSlot` — and this one
                // does now too.
                // **NO CARD** (user ruling, prd §483: *"your treemap is in a
                // card, we don't do cards"*). The room's drawings sit bare on
                // the page — the sparkline does, the flow diagram does, and a
                // surface under this one made it the only boxed figure left.
                //
                // **It IMPROVES the magnitude ramp rather than costing it**,
                // which is the opposite of what I assumed: `DS.ink`'s dark floor
                // is #131316 and the card was #111113 — two points apart, so the
                // quietest cell was very nearly invisible ON the card. Against
                // the #000 page it is nineteen points clear. The ramp is
                // untouched, and the user's "Darker" pick from 2026-08-10
                // stands.
                // The SECTION's own arrival, not the cells' — GenTagMap
                // already stages its cells once mounted; this is what
                // stops the whole treemap from hard-popping in the moment
                // the holdings read lands (2026-07-20, wallet streaming fix).
                .modifier(rowEntrance(1))
                // The card needs the page gutter the bare map didn't (it used
                // to bleed to the screen edge and self-pad its cells).
        }
    }
}


/// An app's newest thing, drawn inside the Wallet's box (prd §1067): its
/// mark, where and when, the title on the box's headline rung and a line of
/// its words. The box supplies the well, so this draws none.
struct WalletSeatLatestLead: View {
    let thing: Thing

    /// Liveness guard (build 188, `ThingRowKeying.swift`): a heal can delete
    /// the thing while this is on screen.
    var body: some View {
        if thing.isLive { liveBody }
    }

    private var liveBody: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s2) {
                BridgeIcon(name: BridgeCatalog.seatName(forSource: thing.source),
                           size: DS.Face.badge, circular: true)
                Text(thing.source)
                Text(verbatim: "·")
                LiveTimeText(date: thing.capturedAt)
            }
            .dsText(.subhead12)
            .foregroundStyle(DS.textTertiary)
            Text(thing.title)
                .dsText(.heading28)
                .foregroundStyle(DS.textPrimary)
                .lineLimit(3)
            // A link is no line to read (prd §1070's rule, kept here too).
            if !thing.content.isEmpty, !FeedLedeCard.isBareLink(thing.content) {
                Text(thing.content)
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
