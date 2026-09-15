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
    /// **§295'S OWN READING, IN THE SCOPE IT NEVER HAD (prd §689).**
    ///
    /// `AddressConnections.map(context:)` is the adapter that has been
    /// running all along — it builds the edges while the models are live and
    /// hands back a value, which is what keeps this immune to the liveness
    /// crash class rather than merely guarded against it (CLAUDE.md
    /// corollaries 1–6).
    @ViewBuilder var walletActivitySection: some View {
        let caption = selectedWallet.map {
            WalletScopeRail.caption(for: $0, in: wallet.addresses).name
        } ?? (wallet.addresses.count == 1
              ? String(localized: "1 wallet")
              : String(localized: "\(String(wallet.addresses.count)) wallets"))
        Section {
            RoomActivityChart(dates: visible.map(\.capturedAt),
                              caption: caption,
                              box: DSRoomChassis.visualSlot)
                .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.inset,
                                          bottom: DSRoomChassis.contentGap,
                                          trailing: DSRoomChassis.inset))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    @ViewBuilder var walletConnectionsSection: some View {
        Section {
            RoomConnectionsFigure(map: AddressConnections.map(context: modelContext),
                                  box: DSRoomChassis.visualSlot,
                                  yours: String(localized: "the accounts you follow"))
                .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.inset,
                                          bottom: DSRoomChassis.contentGap,
                                          trailing: DSRoomChassis.inset))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    /// The wallets you watch — what each IS and how it relates, never what it
    /// holds: Holdings owns that, one chip away (prd §689).
    @ViewBuilder var walletAccountsListSection: some View {
        let map = AddressConnections.map(context: modelContext)
        // `WalletStore.shared.addresses` is the same watched set the map is
        // built from — one source, so a row can never name a wallet the spine
        // has never heard of.
        let rows = WalletStore.shared.addresses.map { wallet in
            RoomAccountsRows.Row(
                key: AddressBook.key(for: wallet.address),
                address: wallet.address,
                name: wallet.label.isEmpty ? wallet.short : wallet.label,
                kind: nil,
                connections: map?.nodes.filter {
                    $0.walletKeys.contains(AddressBook.key(for: wallet.address))
                }.count ?? 0,
                unreached: false)
        }
        let tied = RoomAccountsRows.tied(
            map, watchedKeys: Set(WalletStore.shared.addresses.map { AddressBook.key(for: $0.address) }))
        if !rows.isEmpty {
            Section {
                RoomAccountsRows(rows: rows + tied)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
    }

    @ViewBuilder
    var walletTokenListSection: some View {
        if let portfolio, !portfolio.isEmpty {
            Section {
                ForEach(portfolio.positions) { position in
                    Button {
                        // The cell's own door, at row scale — a token's chart
                        // when it is watched, the quick sheet when it is only
                        // held (the 2026-07-14 split, unchanged).
                        if let route = position.route,
                           let r = TokenQuickRoute.from(sentinel: "@token:\(route):\(position.symbol)") {
                            if let thing = r.watchedThing(in: modelContext) {
                                openThing(thing)
                            } else {
                                feedSheet = .token(r.withHolders(position.holders))
                            }
                        }
                    } label: {
                        HStack(spacing: DS.Space.s3) {
                            TokenIcon(symbol: position.symbol, size: DS.Face.list)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(position.symbol)
                                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                                    .lineLimit(1)
                                // Whose it is, only where that is a real
                                // question — one watched wallet has no split to
                                // report and the line would be noise (§212's
                                // own guard, one level down).
                                if position.holders.count > 1 {
                                    Text(position.holders.prefix(2)
                                            .map(\.label).joined(separator: " · "))
                                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: DS.Space.s2)
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(WalletValue.money(position.usd))
                                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                                    .monospacedDigit()
                                // Its share of everything — the one fact the
                                // board states that a bare amount does not, and
                                // the reason someone opens this scope at all.
                                if portfolio.totalUSD > 0 {
                                    // Whole percents: a holdings share is read
                                    // to compare, not to reconcile, and "56%"
                                    // beside "55.7%" is precision nobody asked
                                    // for on a figure that moves hourly.
                                    Text("\(Int((position.usd / portfolio.totalUSD * 100).rounded()))%")
                                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                                        .monospacedDigit()
                                }
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPress())
                    .dsHover()
                    .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DS.Space.s4,
                                              bottom: DS.Space.s2, trailing: DS.Space.s4))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        }
    }

    /// The one drawing this scope leads with, above the toggle (prd §483).
    ///
    /// **The rule, in the user's own words: "above the toggles is always a
    /// visual of some kind and then a list below it".** Home's visual is the
    /// sparkline, drawn by the crown itself, so this returns nothing there —
    /// the slot is already filled rather than empty.
    ///
    /// Two scopes have no drawing yet and say so by drawing nothing rather than
    /// by inventing one: `nfts`, whose grid IS its picture and belongs with its
    /// rows, and `permissions`, whose exposure card is one object carrying both
    /// halves. Splitting those is worth doing deliberately, not as a side
    /// effect of a layout pass.
    @ViewBuilder
    func walletScopeVisualSection(_ section: WalletSection) -> some View {
        switch section {
        // Home's drawing is the sparkline, which the crown draws itself — so
        // this slot is already filled there rather than empty.
        case .home:        EmptyView()
        // **THE EMPTY STATE IS IN THE SLOT (prd §611, §610's ruling carried
        // here).** Activity keeps `WalletFlowEmptyFigure`, which says which
        // of three things is true of the window; the five standing scopes
        // had nothing at all, so a chip onto Positions on a wallet with no
        // positions opened 258 blank points.
        case _ where walletScopeIsEmpty(section):
            WalletScopeEmptyFigure(section: section)
        // **THE FAMILY'S ACTIVITY CHART (prd §690, user: "Home Activity chart
        // could be same chart the devnets have").** §483 kept the band here so
        // Activity carried no second value figure; the band moves to Home and
        // that substance holds — this slot draws WHEN, like the other four.
        case .activity:    walletActivitySection
        case .holdings:    holdingsBlockSection
        // **§295 RESTORED (prd §689).** "N of your addresses are connected"
        // drew at the foot of the Wallet manager until that screen went; the
        // model never stopped running. This is its slot.
        case .accounts:    walletConnectionsSection
        case .positions:   walletCompositionSection
        // **THE RANKED BARS LEAD, NOT "Worth a look"** (prd §483, 2026-08-26).
        // The warnings row is a ROW — one line with a chevron — so in a 210pt
        // slot it drew a sentence and 180pt of nothing, while the one drawing
        // this scope has sat below it in the list. They swap: the bars head
        // the scope, the row keeps its place at the top of the list where a
        // door belongs.
        case .risk:        walletRiskSection
        case .nfts:        walletNFTSection
        case .permissions: walletPermissionsSection
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

    /// THE ROOM'S CHROME, AND THERE IS NO BAR IN IT (prd §744, 2026-09-15).
    ///
    /// Was `walletScopeRailSection` — the fused rail slab (§547), one deck of
    /// faces over one deck of chips. Two complaints killed it and both were
    /// measurable rather than matters of taste: a watched wallet's name cut at
    /// ten characters (`accountle…` beside `alexanderc…`, on a roster whose
    /// names differ only past the cut), and a scope was a 12pt word with no
    /// rest fill under it, which is a caption's size and a caption's weight
    /// for what the user rightly called *"a category of the wallet"*.
    ///
    /// `DSRoomScopeChrome` carries the whole ruling; what lives here is the
    /// wallet's own three answers to it.
    ///
    /// **The accounts.** Whole names, never shortened by this caller — the
    /// card exists to have room for one. "All" leads, as the rail's own All
    /// slot did, and says what it is made of rather than repeating the word.
    ///
    /// **The crown rides the card.** `walletTilesSection` is the room's
    /// identity and it reads the CURRENT pick, so it draws on the card that
    /// is showing and the neighbours reserve its box. KNOWN, and named rather
    /// than hidden: a card mid-drag shows its head over an empty crown box
    /// until the page settles, because the crown's inputs (`portfolio`,
    /// `walletLive`, `selectedWallet`) are room state and not parameters. The
    /// fix is to thread a scope through `walletTilesSection` and its four
    /// sources, which is a change to the READING layer and does not belong in
    /// the pass that moves the chrome.
    ///
    /// **The act.** Watching a wallet had no door in the room at all — the
    /// only one is `WalletWatchField` on the account page, five taps away
    /// behind the room gear (user, 2026-09-15: *"the wallets follow button is
    /// missing and that's a fail"*). This is a DOOR to that field and not a
    /// second field, so §466's "one way to watch a wallet" is intact: the row
    /// pushes `WalletScreen`, exactly as the four bridge setup screens' own
    /// slabs do.
    ///
    /// **It says "Follow address", which is the user's word and not the app's
    /// existing one** (2026-09-15, ruling on the first cut: *"as for watch a
    /// wallet i would say follow address"*). The four setup screens still say
    /// `Watch a wallet` for this same destination — a drift worth closing, and
    /// a wider change than this pass.
    ///
    /// It rides the ALL card only, like every act in this family: following is
    /// something the ROOM does, not something one account does.
    @ViewBuilder
    func walletScopeChromeSection(_ active: WalletSection,
                                  visible: [Thing],
                                  streamTotal: Int) -> some View {
        // ONE pass, read eight times — see `walletScopeReadings`.
        let readings = walletScopeReadings(streamTotal: streamTotal)
        Section {
            DSRoomScopeChrome(
                sections: chrome.walletSections,
                active: active,
                home: .home,
                attention: chrome.walletSectionAttention,
                // Instant, for the reason §495 states at length: animating a
                // swap between two slots of different natural height moves
                // everything below and settles it back.
                onPick: { picked in chrome.walletSection = picked },
                accounts: walletAccountSlots,
                scope: chrome.walletScope,
                onPickAccount: { picked in
                    withAnimation(DS.Motion.standard) { chrome.walletScope = picked }
                },
                reading: { readings[$0] },
                crown: { slot in
                    // The box is reserved on every card so paging never
                    // changes the deck's height; only the showing card fills
                    // it (see the note above).
                    DSRoomSlot(headline: nil, reservesHeadline: false) {
                        if slot.isShowing(chrome.walletScope) {
                            walletTilesSection(visible, streamTotal: streamTotal,
                                               drawsChart: true)
                        }
                    }
                },
                acts: { slot in
                    if slot.id.isEmpty {
                        DSPushRow(title: Text("Follow address"),
                                  subtitle: Text("Paste an address, or connect a wallet app"),
                                  prominent: true,
                                  action: { route.pushBridge(.wallet) }) {
                            Image(systemName: "eye")
                                .dsGlyph(DS.Space.s4, weight: .semibold)
                                .foregroundStyle(DS.tint)
                                .frame(width: DS.Face.row, height: DS.Face.row)
                        }
                    }
                }
            )
            .listRowInsets(EdgeInsets(top: 0, leading: 0,
                                      bottom: DSRoomChassis.contentGap, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
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
        return [all] + watched.map { addr in
            DSAccountSlot(
                id: addr.address,
                name: addr.label.isEmpty ? WalletStore.shortAddress(addr.address) : addr.label,
                sub: addr.label.isEmpty ? nil : WalletStore.shortAddress(addr.address),
                faces: [.wallet(address: addr.address)])
        }
    }

    /// WHAT EACH SCOPE HOLDS, BEFORE YOU OPEN IT (prd §744).
    ///
    /// The row's right-hand fact. §611 put every scope on every wallet on the
    /// rule that a chip onto a sentence teaching the scope beats a chip onto
    /// nothing — but a chip could only keep that promise AFTER the tap. A row
    /// keeps it before, and an empty scope answers with the same
    /// `emptyHeadline` its slot would have drawn, so the two never disagree.
    ///
    /// **Built ONCE per body pass, as a map.** The obvious shape — a
    /// `(WalletSection) -> String?` the rows call — runs eight times a render,
    /// and three of these answers are a fetch (`AddressConnections.map`, the
    /// permissions holders, the risk scale). That is the cost class
    /// `row-cost-audit.py` exists to catch, so the work happens here and the
    /// rows read a dictionary.
    ///
    /// Absent, never empty-string, where the room genuinely cannot say it
    /// cheaply: a row with no fact still opens, and a fact that guesses is
    /// worse than none (§83).
    func walletScopeReadings(streamTotal: Int) -> [WalletSection: String] {
        var out: [WalletSection: String] = [:]
        for section in chrome.walletSections where section != .home {
            if walletScopeIsEmpty(section) {
                out[section] = section.emptyHeadline
                continue
            }
            switch section {
            case .home:
                break
            case .activity:
                out[section] = String(localized: "\(streamTotal) moves")
            case .holdings:
                out[section] = String(localized: "\(blockStream.els.count) tokens")
            case .accounts:
                if let map = AddressConnections.map(context: modelContext) {
                    out[section] = String(localized: "\(map.nodes.count) connected")
                }
            case .positions, .nfts:
                // Both are counted by the figure they open onto and by nothing
                // cheap here: the positions card is assembled from four live
                // reads and the NFT shelf from a per-address fetch. A row with
                // no fact is honest; a row with a stale one is not.
                break
            case .risk:
                let count = (walletRiskEntries ?? []).count
                if count > 0 { out[section] = String(localized: "\(count) to watch") }
            case .permissions:
                let holders = WalletPermissionsSource.holders(exposure: walletLive.exposure,
                                                              context: modelContext)
                if !holders.isEmpty {
                    out[section] = String(localized: "\(holders.count) live approvals")
                }
            }
        }
        return out
    }

    /// The composition strip, lifted OUT of the crown card and into the
    /// `Positions` scope (prd §483, 2026-08-26).
    ///
    /// It sat in the crown until the toggle moved below the sparkline: with the
    /// control under the chart, anything else still in that card would sit
    /// between the sparkline and the toggle the user asked to put directly
    /// beneath it. And it belongs here anyway — it is the SUMMARY of exactly
    /// what this scope holds, which is the room's own rule that a scope leads
    /// with the drawing that summarizes its own rows.
    ///
    /// §240's "inside the balance card rather than a card of its own" is the
    /// ruling this amends: that reasoning was that "what's it worth" is one
    /// glance and this is the rest of that glance's answer. Still true — the
    /// crown is one tap away in every scope, and the figure it summarizes is
    /// still directly above it on the Positions scope itself.
    @ViewBuilder
    var walletCompositionSection: some View {
        let composition = walletComposition
        if !composition.isEmpty {
                            WalletCompositionStrip(
                    composition: composition,
                    onOpenDeposits: { feedSheet = .deposits(composition) },
                    // Owed gets no door on purpose — the Lending card below
                    // already states health per protocol.
                    onOpenLocks: { feedSheet = .locks(composition) })
                    // BARE ON THE PAGE (user ruling, prd §483: *"we don't do
                    // cards"*). A scope's lead drawing sits in the visual slot
                    // exactly as the sparkline, the treemap and the flow band
                    // do — a tinted plate under one of four otherwise
                    // identical slots reads as that scope being a different
                    // kind of thing, which it is not.
                    .padding(.bottom, DS.Space.s3)
        }
    }

    /// The Worth-a-look strip, lifted out of the crown card into the `Risk`
    /// scope for the same reason (prd §483) — and it is what that scope is
    /// FOR, so it heads it rather than trailing the leverage axis.
    @ViewBuilder
    var walletWarningsSection: some View {
        let warnings = walletLive.warnings
        if !warnings.isEmpty {
            Section {
                WalletWarningsStrip(warnings: warnings) { feedSheet = .worthALook }
                    // Bare, for `walletCompositionSection`'s reason.
                    .padding(.bottom, DS.Space.s3)
                    .listRowInsets(WalletCardStyle.rowInsets)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
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
        let attention: Set<WalletSection> =
            walletLive.warnings.isEmpty || walletScopeIsEmpty(.risk) ? [] : [.risk]
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
        case .home:        return false
        case .activity:    return false
        case .holdings:    return blockStream.els.isEmpty
        // **EMPTY IS "NOTHING CONNECTS THEM" (prd §689)** — the rows list what
        // you watch either way; the slot's job is the relationship.
        case .accounts:    return AddressConnections.map(context: modelContext)?
                                    .nodes.isEmpty ?? true
        case .positions:   return !(hasLendingCard
                                    || !walletLive.uniswap.isEmpty
                                    || !walletLive.hyperliquid.positions.isEmpty)
        case .nfts:        return nftShelfEntry == nil
        case .risk:        return (walletRiskEntries ?? []).isEmpty
        case .permissions: return WalletPermissionsSource.holders(exposure: walletLive.exposure,
                                                                  acting: walletLive.acting).isEmpty
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
    /// **The grammar is the stream's own day header**, verbatim — `heading22`
    /// in primary ink at the same insets. That is deliberate on two counts:
    /// this room already had a group-header tier and it was the day names, so
    /// "What you hold" and "Today" are peers because they ARE peers (both are
    /// top-level blocks of one room); and a second, smaller tier would mean
    /// inventing a rung the ramp doesn't carry between `heading22` and
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
                .dsText(.heading22)
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
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    /// The picked-NFT shelf's wallet, or nil when the shelf draws nothing.
    ///
    /// Hoisted out of `walletNFTSection` (2026-08-20) so the "What you hold"
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

    /// Every leveraged position on one axis, or nil when there are fewer than
    /// two to compare. Hoisted for `nftShelfEntry`'s reason.
    var walletRiskEntries: [WalletRiskScale.Entry]? {
        WalletRiskScaleSource.strip(aave: walletLive.positions,
                                    morpho: walletLive.morpho,
                                    hyperliquid: walletLive.hyperliquid)
    }

    // MARK: - Walking from the risk axis to a card (prd §417)

    /// Scroll anchors for the two cards the risk strip's dots can reach.
    /// Spelled once here and attached with `.id(…)` below, so the tap and the
    /// target can't drift apart.
    static let lendingAnchor = "wallet.card.lending"
    static let perpsAnchor = "wallet.card.perps"
    /// Reached from the Worth-a-look sheet's approvals walk row (prd §449),
    /// not from the risk axis — approvals aren't a leveraged position and have
    /// no dot. Spelled here beside its siblings so all three anchors and their
    /// `.id(…)` sites stay in one place.
    static let approvalsAnchor = "wallet.card.approvals"

    /// Which card states the position behind a dot, from the entry id
    /// `WalletRiskScaleSource` stamped.
    ///
    /// **Matched on the id's namespace, never on the label** — a label is
    /// localized display text ("Morpho · wstETH/USDC"), so keying on it would
    /// send a Spanish device nowhere. nil is a deliberate, safe outcome: a
    /// protocol that joins the axis without a card here scrolls nowhere rather
    /// than scrolling to the wrong card.
    static func riskCardAnchor(for id: String) -> String? {
        if id.hasPrefix("aave:") || id.hasPrefix("morpho:") { return lendingAnchor }
        if id.hasPrefix("hl:") { return perpsAnchor }
        return nil
    }

    /// The holdings card's tail — the book's shape on the left, the door to
    /// the whole allocation on the right, in ONE tertiary row (2026-08-22,
    /// prd §447).
    ///
    /// **This is what a four-line block reduced to.** §417 promoted the
    /// concentration sentence to a `heading22` lead above the map, on the
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
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
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
    /// NFT shelf, or both.
    var walletHoldsSomething: Bool {
        !blockStream.els.isEmpty || nftShelfEntry != nil
    }

    /// Does the "What it's doing" block have anything in it.
    ///
    /// The risk strip is derived FROM the three books below it, so it can
    /// never be the only thing here — it is named anyway rather than inferred,
    /// because "the strip implies a book" is a cross-file fact that would fail
    /// silently the day either side changes.
    var walletDoingSomething: Bool {
        walletRiskEntries != nil
            || !walletLive.positions.isEmpty
            || !walletLive.morpho.isEmpty
            || !walletLive.uniswap.isEmpty
            || !walletLive.hyperliquid.positions.isEmpty
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
    /// Nothing renders without something to list — `WalletFlow.home` declines
    /// only when no move in the window carried a price AND none came in as a
    /// token (prd §727). The brief keeps `WalletFlow.band` and its floor.
    ///
    /// **A DECLINE IS DRAWN, NOT LEFT AS AIR (2026-09-03, prd §589).** The
    /// slot is fixed (§483), so a nil band was a fixed box of nothing over a
    /// stream full of moves — reported as "the activity chart isn't showing",
    /// with no way from the screen to tell a quiet window from a broken price
    /// read. `WalletFlowEmptyFigure` names the cause off the same ladder the
    /// probe reads, the vibenet room's `activityEmptyFigure` rule one venue
    /// over.
    @ViewBuilder
    var walletFlowSection: some View {
        let verdict = WalletFlowSource.home(from: visible, since: flowWindowStart)
        if let home = verdict.home {
            // **ROWS, NOT THE BAND (prd §692, user: "i don't like the sankey on
            // the home list area it looks weird to have a chart there now that
            // i see it").** Same `Band`, same window, same numbers — the list
            // half of a room draws a list. `WalletFlowBand` itself stays: the
            // brief renders it through `GenRenderer`, where a diagram is the
            // right shape for a card somebody reads once.
            WalletFlowRows(home: home, windowLabel: balanceRange.flowLabel)
                    .modifier(rowEntrance(1))
        } else if let decline = verdict.decline {
            WalletFlowEmptyFigure(decline: decline, windowLabel: balanceRange.flowLabel,
                                  spineAddress: spineWalletAddress)
                .modifier(rowEntrance(1))
        }
    }

    /// The cutoff the flow band reads back to — nil for `.watched`, which
    /// means the whole record.
    var flowWindowStart: Date? {
        balanceRange.span.map { Date.now.addingTimeInterval(-$0) }
    }

    /// Whose face rides the flow band's spine: the scoped wallet, or the sole
    /// watched one. nil when several wallets are merged — the band is then
    /// about all of them, and a face belonging to one would claim the flows
    /// were that wallet's (the honesty rule, applied to a portrait).
    var spineWalletAddress: String? {
        if let selectedWallet { return selectedWallet }
        let watched = wallet.addresses
        return watched.count == 1 ? watched.first?.address : nil
    }

    /// Whose NFT shelf this room draws (2026-08-15, prd §387) — the scoped
    /// wallet, or the sole watched one.
    ///
    /// nil when several wallets are merged, and the shelf then draws nothing:
    /// a pick is made PER WALLET, so a merged shelf would have to say whose
    /// each piece is, and this room already declines to speak for merged
    /// wallets rather than invent an attribution (`spineWalletAddress`, same
    /// reasoning applied to a portrait). The wallet switcher is pinned above
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
                                                    label: entry.label.isEmpty ? entry.short : entry.label) })
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(WalletCardStyle.rowInsets)
            }
        }
    }

    /// The picked-NFT shelf. Renders nothing at all for a wallet with no picks
    /// and no collections to pick — which is most wallets, and is why this is
    /// the one wallet card that can be completely absent without meaning a
    /// read failed.
    @ViewBuilder
    var walletNFTSection: some View {
        // The gate itself lives in `nftShelfEntry` (2026-08-20) — the "What
        // you hold" header asks the same question, and one copy is what keeps
        // the header and this card from ever disagreeing.
        if let entry = nftShelfEntry {
                            WalletNFTShelfCard(
                    wallet: entry.address,
                    label: entry.label.isEmpty ? entry.short : entry.label,
                    onEdit: { feedSheet = .nftPicks(address: entry.address,
                                                    label: entry.label.isEmpty ? entry.short : entry.label) })
                    .modifier(rowEntrance(2))
        }
    }

    /// Every leveraged position on one axis (2026-08-01, `WalletRiskStrip`),
    /// directly ABOVE the lending card it summarises — the cards below state
    /// each position in its own protocol's units, and this is the one view
    /// that puts them in an order. Declines under two positions, where the
    /// cards already say it better.
    @ViewBuilder
    var walletRiskSection: some View {
        if let entries = walletRiskEntries {
                            WalletRiskStrip(entries: entries, onPick: { entry in
                    // Overview → detail (prd §417). The strip ranks every
                    // leveraged position on one axis; the card below states the
                    // one you picked in its own protocol's units. The target is
                    // derived from the entry's OWN id prefix, which
                    // `WalletRiskScaleSource` already builds — so a new
                    // protocol joining the axis lands on `nil` and simply
                    // doesn't scroll, rather than scrolling somewhere wrong.
                    cardScrollTarget = Self.riskCardAnchor(for: entry.id)
                })
                    .modifier(rowEntrance(2))
        }
    }

    /// Approvals — what someone else can still move (2026-08-03, prd §292).
    ///
    /// Sits with the risk reads rather than the holdings ones, because that's
    /// what it is: every card above says what your money is doing, and this
    /// says who else can reach it. Nothing renders without a live grant, which
    /// on most wallets is most of the time.
    ///
    /// The tap resolves the grant back to its `Thing` HERE rather than in the
    /// card, and re-checks `isLive` at the moment of the tap: a foreground
    /// heal can delete an approval row between the card being built and the
    /// finger landing (corollary 4's stale-array window, one layer up).
    /// WHO CAN ACT FOR YOU — the `Permissions` scope's lead (prd §490).
    ///
    /// The scope had NO drawing at all until this: it opened straight onto the
    /// approvals list, which is the shape §247 named as the gap ("a room that
    /// leads with a list of its own rows"). The reading it leads with now is
    /// one the list structurally cannot make — a Safe module and an EIP-7702
    /// delegate have no dollar amount, so they can never be ranked into a card
    /// built on `min(allowance, balance) × price`, and they are the most
    /// dangerous things in this scope.
    ///
    /// Declines when there is genuinely nothing, which on most wallets is most
    /// of the time — no grants and nothing acting is the healthy state, and a
    /// card announcing it would be a permanent fixture saying "fine".
    @ViewBuilder
    var walletPermissionsSection: some View {
        let holders = WalletPermissionsSource.holders(exposure: walletLive.exposure,
                                                      acting: walletLive.acting)
        if !holders.isEmpty {
                            WalletPermissionsCard(holders: holders)
                    .modifier(rowEntrance(1))
                    .padding(.bottom, DS.Space.s3)
        }
    }

    /// The `Permissions` scope's OTHER list — everything that can act as one
    /// of your wallets (prd §514).
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
            || walletLive.acting.contains(where: { $0.modulesUnreadable || $0.keystorePartial }) {
            Section {
                WalletActingPartiesRows(holders: holders, acting: walletLive.acting)
                    .modifier(rowEntrance(2))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(WalletCardStyle.rowInsets)
            }
        }
    }

    @ViewBuilder
    var walletApprovalsSection: some View {
        if !walletLive.exposure.isEmpty {
            Section {
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
                .id(Self.approvalsAnchor)
                .modifier(rowEntrance(2))
                .listRowBackground(Color.clear)
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

    @ViewBuilder
    var walletDeFiSection: some View {
        if hasLendingCard {
            Section {
                WalletLendingCard(aave: walletLive.positions, morpho: walletLive.morpho)
                    // The risk strip's Aave and Morpho dots land here (§417).
                    .id(Self.lendingAnchor)
                    // Same reveal the balance card and holdings treemap wear —
                    // lending is usually the last of the live reads to land, so
                    // it gets the deepest stagger.
                    .modifier(rowEntrance(2))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(WalletCardStyle.rowInsets)
            }
        }
    }

    /// Liquidity — Uniswap V3 positions for the wallets in scope (2026-07-30),
    /// a SIBLING to `walletDeFiSection`, not a third row inside it: lending
    /// asks "is it safe", a liquidity position asks "is it working" — a
    /// different subject earns a different card (see `WalletLiquidityCard`'s
    /// own doc comment). Nothing renders without a position.
    @ViewBuilder
    var walletLiquiditySection: some View {
        if !walletLive.uniswap.isEmpty {
            Section {
                WalletLiquidityCard(book: walletLive.uniswap)
                    .modifier(rowEntrance(3))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(WalletCardStyle.rowInsets)
            }
        }
    }

    /// Perps — Hyperliquid's open positions for the wallets in scope
    /// (2026-07-31). A SIBLING to lending and liquidity for the reason
    /// `WalletPerpsCard`'s own doc gives at length: a perp is not lending, so
    /// filing it under a card headed "Lending" would make the label wrong to
    /// buy one fewer surface. Nothing renders without a position.
    @ViewBuilder
    var walletPerpsSection: some View {
        if !walletLive.hyperliquid.positions.isEmpty {
            Section {
                WalletPerpsCard(book: walletLive.hyperliquid)
                    // The risk strip's perp dots land here (§417).
                    .id(Self.perpsAnchor)
                    .modifier(rowEntrance(4))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(WalletCardStyle.rowInsets)
            }
        }
    }

    /// How many deadlines the room shows at once. Small on purpose: this is
    /// the head of a history feed, not an agenda.
    static let walletUpcomingRows = 3

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
    func walletUpcoming(_ visible: [Thing]) -> [Thing] {
        let now = Date.now
        return Array(visible.live
            .filter { ($0.dueAt ?? .distantPast) > now }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
            .prefix(Self.walletUpcomingRows))
    }

    /// "Coming up" — the room's deadlines, in its own card and its own row
    /// shape. Renders nothing when nothing is due, like every other section
    /// here (the honesty floor: no empty parcel holding a slot).
    ///
    /// A card rather than bare rows on the page, even though these ARE landed
    /// things and the room's other cards are live state. What decides it is
    /// what the reader is being asked to do: everything below is history to
    /// scroll, and this is a standing fact to act on — the same register as
    /// the cards above, and putting it on the page would make it read as the
    /// top of the stream, which is exactly the misreading that buried these
    /// rows in the first place.
    @ViewBuilder
    func walletComingUpSection(_ upcoming: [Thing]) -> some View {
        if !upcoming.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    // No label of its own since 2026-08-20: the group header
                    // directly above says "Coming up", and this card is the
                    // only thing under it (§208 — never say one thing twice).
                    // Every other card here keeps its label, because every
                    // other card has siblings to be told apart from.
                    //
                    // The rail says what the rows can't: whether these are
                    // bunched or spread (prd §417). Dates are read here, while
                    // the models are known live, and handed on as plain values
                    // — `WalletRunwayRail` never holds a `Thing` (the build-188
                    // leaf rule).
                    WalletRunwayRail(dates: upcoming.compactMap { $0.isLive ? $0.dueAt : nil })
                        .padding(.bottom, 2)
                    // `keyed` for identity + `live` inside the closure before
                    // any stored read (corollaries 1 and 3): this is a derived
                    // array, and a heal's delete can land in the same graph
                    // update that re-evaluates this closure.
                    ForEach(upcoming.keyed) { row in
                        if let thing = row.live {
                            Button {
                                DSHaptic.selection()
                                feedSheet = .thing(thing, walk: .none)
                            } label: {
                                WalletRow(mark: .kind(thing.kind),
                                          title: thing.title,
                                          subtitle: Self.dueLine(thing))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(WalletCardStyle.pad)
                .dsWidgetSurface(fillOpacity: Self.walletCardFill)
                .modifier(rowEntrance(5))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(WalletCardStyle.rowInsets)
            }
        }
    }

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

    /// The wallet stream's preview rows, with routine transfers folded
    /// (2026-07-31).
    ///
    /// The preview is five rows over a room whose stream mixes two very
    /// different kinds of event: transfers, which a busy wallet produces by
    /// the dozen and which ask nothing of anyone, and the rare rows that carry
    /// a decision — a fresh approval, a liquidation crossing, a Privacy Pools
    /// clear. Straight chronology lets the first kind evict the second, so on
    /// an active wallet the one row worth acting on is behind "See all" and
    /// the preview is five variations of "Sent 0.1 ETH".
    ///
    /// So a RUN of consecutive routine transfers collapses into a single
    /// counted row, and the slots that frees go to whatever the run was
    /// burying. Nothing is dropped or hidden: the fold states its own count,
    /// the stream door below still totals the room unfolded, and the history
    /// screen behind it lists every row as it always did.
    ///
    /// Only a run of `walletFoldMin`+ folds — collapsing two rows into a row
    /// that says "2 transfers" saves nothing and costs the two titles.
    static let walletFoldMin = 3

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
                    ? { route.pushBridge(.walletHistory(scope: selectedWallet)) }
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

    func walletStreamRows(_ things: [Thing]) -> [FeedRow] {
        var rows: [FeedRow] = []
        var run: [Thing] = []
        func flush() {
            guard !run.isEmpty else { return }
            if run.count >= Self.walletFoldMin, let newest = run.first {
                // Never ambient: these are transactions, which `tier` files as
                // concerning you by definition. Stated rather than derived
                // because this fold is the Wallet ROOM's, where §378's weight
                // axis does not run at all — the flag exists so the payload is
                // honest if it ever does.
                rows.append(.bundle(source: "Wallet",
                                    word: String(localized: "transfers"),
                                    count: run.count, newest: newest.capturedAt, art: [],
                                    ambient: false))
            } else {
                rows += run.map(FeedRow.single)
            }
            run = []
        }
        for thing in things {
            if Self.isRoutineTransfer(thing) {
                // A run never crosses midnight. The fold takes its date from
                // its newest member, so a run spanning three days would file
                // all of them under "Today" — a day header that lies about
                // what's under it, to save two rows. Same-day only.
                if let open = run.first,
                   !Self.groupingCalendar.isDate(open.capturedAt, inSameDayAs: thing.capturedAt) {
                    flush()
                }
                run.append(thing)
            } else {
                flush()
                rows.append(.single(thing))
            }
            // Stop once the folded list can fill the preview — a run still
            // open may yet grow, so the loop runs one flush past the cap and
            // the prefix below does the real trimming.
            if rows.count > Self.walletPreviewRows { break }
        }
        flush()
        return Array(rows.prefix(Self.walletPreviewRows))
    }

    /// A plain value transfer — the only thing this room folds.
    ///
    /// Deliberately an ALLOW-list, not "anything that isn't interesting":
    /// every other row in this room is recognized by its own `sourceRef`
    /// namespace (`wallet:approval:`, `wallet:permit2:`, `hyperliquid:*`,
    /// `aerodrome:*`) and stands alone, so a bridge added tomorrow is
    /// unfoldable by default rather than silently swept into a count. A
    /// flagged transfer (poisoning, a spoofed symbol) is never routine, and
    /// neither is anything carrying a deadline.
    static func isRoutineTransfer(_ thing: Thing) -> Bool {
        guard thing.isLive, thing.kind == .transaction, !thing.isFlagged,
              thing.dueAt == nil, let ref = thing.sourceRef,
              ref.hasPrefix("wallet:")
        else { return false }
        return !ref.hasPrefix("wallet:approval:") && !ref.hasPrefix("wallet:permit2:")
    }

    /// The stream preview's day sections, over folded rows.
    ///
    /// A near-twin of `groupedSections`/`daySection`, and separate on purpose:
    /// those speak `[Thing]`, and a fold is not a thing. Same guards
    /// throughout — `live` re-checked inside the content closure, identity off
    /// `FeedRow`'s stored id, never the model.
    @ViewBuilder
    func walletStreamSections(_ rows: [FeedRow], nextEventID: UUID?) -> some View {
        let groups = walletStreamDays(rows)
        // The same boundary the rest of the feed draws, over `FeedRow`'s own
        // stored dates — dropping it here would have quietly cost this room
        // its "new since" divider.
        let boundary = boundaryID(in: groups)
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
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    Text(label).dsText(.heading22).foregroundStyle(DS.textPrimary)
                }
                .textCase(nil)
                .padding(.leading, DS.Space.s4)
                // The FIRST day heading sits directly under the scope
                // switcher, which already carries its own bottom inset — the
                // macro pad belongs BETWEEN days, not above the first one, and
                // spending it there opened a ~45pt dead band on Activity that
                // Home (whose lead section is a small header) never had.
                .padding(.top, groupIndex == 0 ? DS.Space.s1 : DS.Space.s6)
                .padding(.bottom, DS.Space.s1)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                ForEach(Array(dayRows.enumerated()), id: \.element.id) { i, row in
                    if row.id == boundary { newSinceDivider }
                    switch row.kind {
                    case .single(let item):
                        // `live` INSIDE the closure, before any read
                        // (corollary 3): this re-evaluates against the array
                        // it already holds when a heal's delete lands.
                        if let thing = item.live {
                            shapedListRow(thing, index: i, nextEventID: nextEventID,
                                          position: positions[i])
                        }
                    case .bundle(_, let word, let count, let newest, _):
                        // The fold's door is the history screen, NOT
                        // `bundleListRow`'s source-filter tap: this room IS
                        // the Wallet source, so filtering to it would be a
                        // control that does nothing (the honesty rule's
                        // dead-control clause).
                        Button {
                            DSHaptic.selection()
                            route.pushBridge(.walletHistory(scope: selectedWallet))
                        } label: {
                            WalletRow(mark: .symbol("arrow.left.arrow.right", tint: DS.tint),
                                      title: String(localized: "\(count) \(word)"),
                                      subtitle: Self.foldSubline(newest))
                        }
                        .buttonStyle(.plain)
                        .modifier(rowEntrance(i))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(.init(top: DS.Space.s2,
                                             leading: DS.Space.s4 + DS.Space.s3,
                                             bottom: DS.Space.s2,
                                             trailing: DS.Space.s4 + DS.Space.s3))
                    case .strip(_, let word, let count, let newest, _):
                        // Drawn like `.bundle` above, and for that case's own
                        // reason rather than by copying it: the generic
                        // `stripListRow` opens the source filter, and this room
                        // IS the Wallet source, so that tap would be a control
                        // that does nothing. The door is the history screen.
                        // The tiles are dropped with it — a strip earns its
                        // picture row by having pictures, and a run of
                        // transactions has none to show.
                        Button {
                            DSHaptic.selection()
                            route.pushBridge(.walletHistory(scope: selectedWallet))
                        } label: {
                            WalletRow(mark: .symbol("arrow.left.arrow.right", tint: DS.tint),
                                      title: String(localized: "\(count) \(word)"),
                                      subtitle: Self.foldSubline(newest))
                        }
                        .buttonStyle(.plain)
                        .modifier(rowEntrance(i))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(.init(top: DS.Space.s2,
                                             leading: DS.Space.s4 + DS.Space.s3,
                                             bottom: DS.Space.s2,
                                             trailing: DS.Space.s4 + DS.Space.s3))
                    }
                }
            }
        }
    }

    /// "Most recent 2:14 PM" — a fold has no one title, so its subline says
    /// where in the day the run starts, which is the only thing the rows it
    /// replaced all agreed on.
    static func foldSubline(_ newest: Date) -> String {
        String(localized: "Most recent \(newest.formatted(date: .omitted, time: .shortened))")
    }

    /// Day groups over folded rows, newest first — `dayGroups`' rule
    /// (including its "drop what's still ahead" clause, which is now genuinely
    /// true here: anything future-dated was promoted to Coming up above).
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
    @ViewBuilder
    func walletSeeAllSection(total: Int) -> some View {
        if total > Self.walletPreviewRows {
            Section {
                WalletSeeAllRow(count: total) {
                    route.pushBridge(.walletHistory(scope: selectedWallet))
                }
                .listRowSeparator(.hidden)
                // On the page itself, not in a card — a quiet continuation
                // line, not another surface (user, 2026-07-20, twice).
                .listRowBackground(Color.clear)
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
                    // at `heading22` on Lending's and Approvals' anatomy, and
                    // the same pass put a 22pt "What you hold" header directly
                    // above this card: two display lines stacked, then the
                    // map's own eyebrow saying the header's words again. The
                    // reading moved down to `holdingsTail`, beside the stables
                    // line it always belonged with; the header is the card's
                    // title and always was.
                    GenRender(id: "root", els: blockStream.els)
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
