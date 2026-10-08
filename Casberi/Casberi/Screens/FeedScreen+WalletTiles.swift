import SwiftUI
import SwiftData

// The wallet's tiles section and the readings it draws from, split out of
// FeedScreen.swift (prd §718). Nothing here changed but the file it lives
// in and, where another file reads a member, its access level.
extension FeedScreen {
    /// The wallet this room is scoped to (prd §128, widened by §356) — nil is
    /// "All". Scopes the balance lede, holdings treemap, NFT strip and the
    /// rows to one watched wallet.
    ///
    /// **A window onto `ShellChrome.walletScope`, not `@State`, and that is
    /// the whole of §356.** It used to be `@State` here, which made it a
    /// property of ONE room: `MainSurface` gives its single `FeedScreen` an
    /// `.id(filter.source)`, so moving to Peer destroys this screen and every
    /// bit of its state — which is why the scope silently evaporated on a room
    /// change and why no wallet room but the balance room could be narrowed at
    /// all. Held on the shell, one scope now spans the whole category.
    ///
    /// **An ADDRESS only (prd §1048b).** The menu also picks an app the Wallet
    /// folded in (`RoomAccounts`), scoped as `seat:<name>`; every reader of
    /// this property means an address, so a seat reads as nil here and as
    /// `selectedSeat` below.
    var selectedWallet: String? {
        get { RoomAccounts.isSeat(chrome.walletScope) ? nil : chrome.walletScope }
        nonmutating set { chrome.walletScope = newValue }
    }

    /// The app the menu picked, when it picked an app rather than an address.
    ///
    /// Nil once the app is disconnected: a pick that is no longer in the menu
    /// reads as All, as an unwatched address does (`onChange(of: wallet.addresses)`).
    var selectedSeat: RoomAccounts.Seat? {
        guard let seat = RoomAccounts.seat(chrome.roomScope(source), in: source),
              RoomAccounts.isConnected(seat, names: connectedSeatNames) else { return nil }
        return seat
    }

    /// The portfolio the box and Holdings state: the whole read, or the picked
    /// app's slice of it (prd §1048b). Sliced HERE as well as when the read
    /// lands, because a read that landed before the pick would otherwise put
    /// the whole Wallet's total under one app's name (measured: "$44K" over
    /// Gnosis Pay, which holds nothing in the total). `scoped` is idempotent.
    var portfolioShown: WalletPortfolio? {
        guard let seat = selectedSeat else { return portfolio }
        guard let slice = portfolio.map({ Self.slice($0, for: seat) }), !slice.isEmpty else { return nil }
        return slice
    }

    /// Whether an app the menu picked records a balance line of its own:
    /// Privy, whose store notes its shown total per read (prd §1194). Every
    /// other app's money is read with no history, so it draws no line.
    func seatKeepsLine(_ seat: RoomAccounts.Seat) -> Bool {
        seat.source == PrivyHomeFeed.source
    }

    func seatValueSamples(_ seat: RoomAccounts.Seat) -> [WalletStore.ValueSample] {
        seatKeepsLine(seat) ? PrivyHomeStore.shared.valueSamples : []
    }

    /// An app's share of the Wallet's money. A Safe is an account (prd
    /// §1069): its money is what its addresses hold, which no holder prefix
    /// names.
    static func slice(_ whole: WalletPortfolio, for seat: RoomAccounts.Seat) -> WalletPortfolio {
        seat.source == SafeBridge.sourceName
            ? whole.scoped(toAddresses: SafeBridge.detectedAddresses())
            : whole.scoped(to: seat)
    }

    /// The catalogue names of every connected or attention-needing seat.
    var connectedSeatNames: Set<String> {
        Set(bridges.bridges.filter { $0.status != .paused }.map(\.name))
    }

    /// WHAT IS NOT IN THE WALLET TOTAL, in words (prd §827, §828) — nil when
    /// every followed chain answered and priced.
    var walletTotalNote: String? {
        var parts: [String] = []
        if !unreadableChains.isEmpty {
            parts.append(String(localized: "No answer from \(unreadableChains.joined(separator: ", "))"))
        }
        if !unpricedChains.isEmpty {
            parts.append(String(localized: "Couldn't price \(unpricedChains.joined(separator: ", "))"))
        }
        // Cash in a currency Kraken can't price (prd §1048). Combined read
        // only, so a scoped page never carries it.
        if selectedWallet == nil, let cash = portfolio?.unpricedCash, !cash.isEmpty {
            parts.append(String(localized: "Couldn't price \(cash.joined(separator: ", "))"))
        }
        // A card balance owed (prd §1078): money the total leaves out on
        // purpose, named beside it. The combined page only.
        if selectedWallet == nil, selectedSeat == nil, let owed = portfolio?.owed, !owed.isEmpty {
            parts.append(owed.joined(separator: ", "))
        }
        guard !parts.isEmpty else { return nil }
        return String(localized: "\(parts.joined(separator: "; ")) — not in this total")
    }

    /// The portfolio's own value-history line (2026-07-18), leading the
    /// treemap — real samples off `WalletStore.combinedValueSamples()`
    /// (recorded on every real holdings fetch since a wallet was watched, not
    /// synthesized). Empty (no section) until two aligned samples exist.
    /// How many transactions the feed previews before handing off to the
    /// history page (2026-07-20). Five is the count that still reads as "here's
    /// what's new" rather than a log — the reads above it are the point of this
    /// screen, and an unbounded stream buried all four of them.
    static let walletPreviewRows = 12

    /// How many transactions lead the room from inside the balance card
    /// (2026-08-18, user ruling — the answer to "the transactions are at the
    /// end"). THREE, and the number is the whole design: it is what fits above
    /// the fold under a shortened chart, and the moment it grows it stops
    /// being a glance and becomes the stream a second time.
    ///
    /// The two rejected fixes are worth recording, because both were drawn
    /// before this one won. FOLDING the standing cards (Liquidity, Perps, a
    /// changeless Approvals into one "Positions" card) buys the same height
    /// and costs a room the user likes: "don't collapse the rest of the
    /// stuff." MOVING the whole stream up front-loads a room that may hold
    /// hundreds of rows, and re-litigates the load-bearing hero → ink →
    /// treemap adjacency below. A three-row card costs ~140pt, hides nothing
    /// (every row it takes is still one tap away, and the rest of the stream
    /// still reads below), and leaves every card in the room exactly where it
    /// was.
    private static let walletTodayRows = 3

    /// The wallet room's two cards are TRANSLUCENT (prd §160): they sit on the
    /// crown pour, and an opaque surface would punch a hole in the one
    /// atmospheric move the shell makes. One constant so the balance card and
    /// the holdings card can never drift apart.
    // ONE source (2026-08-22). This was its own `0.82`, a second copy of
    // `WalletCardStyle.fill` sitting in a different file — which is how a
    // room ends up at two opacities, the exact drift that type's own doc
    // was written to prevent.
    static let walletCardFill = WalletCardStyle.fill

    /// The balance CARD, then Worth a look as a quiet line beneath it — the two
    /// questions a wallet screen answers at a glance ("what's it worth", "is it
    /// okay").
    ///
    /// The card is prd §160 (2026-07-21, user: "i like both boxed"), amending
    /// §146/§151's page-set headline: the room's crown is already a parade of
    /// rounded shapes (source chips, wallet switcher pills, sync capsule), so
    /// the argument that a free-set number reads as "the room's voice" lost to
    /// the argument that a boxed one is easier to SCAN — parcels beat strata
    /// when the eye is looking for sections. The number keeps every ounce of
    /// its weight (the crown rung, the pour behind it, the delta and mover with it);
    /// it just gets an edge. Translucent so the crown pour still travels under
    /// it rather than being punched out.
    ///
    /// Rendered FLAT (§gotchas' eager-head law): a plain VStack of two shallow
    /// pieces, no generic widget path. Either can be absent — no balance until
    /// two value samples exist, no warnings line when there's nothing wrong —
    /// and with both absent the section renders nothing at all rather than an
    /// empty row (the same honesty floor every section here keeps).
    /// - Parameters:
    ///   - latest: the newest stream rows, led from inside this card
    ///     (`walletTodayCard`). Named apart from the balance's own `total`
    ///     below, which is money — these two numbers count different things
    ///     and a shadowed name here would be a silent wrong figure.
    ///   - streamTotal: how many rows the stream holds in all, for the card's
    ///     own door.
    // **NOT `private` (prd §747).** The crown rides the account card now, and
    // that card is built in `FeedScreen+WalletRoom.swift` — `private` is
    // file-scoped in Swift, so an extension in another file cannot see it.
    @ViewBuilder
    func walletTilesSection(_ visible: [Thing],
                                    latest: [Thing] = [],
                                    streamTotal: Int = 0,
                                    // **THE SPARKLINE IS HOME'S VISUAL, not the
                                    // room's furniture (prd §483, user ruling:
                                    // "above the toggles is always a visual of
                                    // some kind and then a list below it").**
                                    // Every scope owns one drawing and one
                                    // list; Home's drawing happens to be the
                                    // line. In every other scope the line steps
                                    // aside for that scope's own figure, so the
                                    // room never stacks two large drawings.
                                    drawsChart: Bool = true) -> some View {
        // Scoped to the selected wallet's own value line, else the combined
        // portfolio line (prd §128). Both start honest — nil until two aligned
        // samples exist (TokenChart.from guards ≥2) — but the NUMBER no longer
        // waits on them (prd §155): the live total leads, the line joins.
        // An app the menu picked has no recorded line of its own (samples are
        // per watched address), so its box states the number and draws no
        // line rather than the whole Wallet's under one app's name.
        // Privy records its shown total per read (prd §1194), so its pick
        // draws that line.
        let samples = selectedSeat.map(seatValueSamples)
            ?? selectedWallet.map { wallet.valueSamples(forAddress: $0) }
                ?? wallet.combinedValueSamples()
        let ranges = WalletRange.offered(for: samples)
        let active = ranges.contains(balanceRange) ? balanceRange
            : WalletRange.remembered(offered: ranges)
        let windowed = active.clip(samples)
        let chart = TokenChart.from(samples: windowed)
        let total = portfolioShown.map(\.totalUSD).flatMap { $0 > 0 ? $0 : nil }
        // The addresses' readings say nothing about an app the menu picked.
        let warnings = selectedSeat == nil ? walletLive.warnings : []
        let chips = selectedSeat == nil ? walletFaceChipEntries : []
        // Gathered ONCE — the gate below and the strip inside both read it,
        // and a computed property would re-walk every book on each body pass.
        let composition = selectedSeat == nil ? walletComposition : WalletComposition()
        // The composition earns the card on its own (prd §240): a wallet whose
        // money is entirely in protocols — everything supplied to Aave, or a
        // Hyperliquid account with an empty EVM wallet — has no priced
        // holdings and no warnings, so without this the one surface that
        // states its money would never render at all.
        // `latest` joins the gate for the same reason `composition` did: a
        // wallet with no priced holdings, no line and no warning still has
        // transactions, and without this the one card that shows them would
        // never render at all.
        if chart != nil || total != nil || !warnings.isEmpty || !composition.isEmpty
            || !latest.isEmpty {
                            // ONE card (prd §212, 2026-07-25) — the balance, the per-wallet
                // split, and the security read. Three parcels of equal weight
                // until this pass, and they were never three subjects: "what's
                // it worth", "whose is it", "is it okay" are the questions of a
                // single glance at a single number.
                //
                // **The MONEY half now wears the bright card** (2026-08-15) and
                // the rest of that card stays ink, which splits §212's single
                // parcel in two. The reason is the one this pass keeps
                // arriving at: colour is information, so it may only cover the
                // rows it is true of. "What's it worth" is the reading this
                // room exists for and is the app's most natural home for the
                // Messages register — one hero number over one list is what
                // §212 built. "Is it okay" is a WARNING, and a saturated card
                // under "this grant reaches $4,120" dresses it as a
                // celebration; §83's honesty rule forbids exactly that kind of
                // true-sounding surface. So the split is not two subjects
                // after all — it is one subject and one caution about it, and
                // they were never the same glance.
                //
                // The two still read as one system: same corner radius, same
                // insets, stacked with the section's own spacing, so this is
                // one card that changed weight partway down rather than the
                // six parcels §212 collapsed.
                // ONE list row still, and that outer stack is what keeps it
                // one: two siblings under a `Section` are two rows, each
                // taking the List's own background and insets, which would
                // undo both the card geometry and the entrance below.
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                // Guarded as a whole for the same reason the caution block
                // below is: the section renders whenever ANY of its four
                // inputs exist, so a wallet whose money is entirely in
                // protocols (§240's own case — no priced holdings, no line)
                // would otherwise paint a bright card with nothing in it.
                if chart != nil || total != nil {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    do {
                        // The headline is a READ, not a door (prd §208,
                        // 2026-07-25): the multi-wallet "All" view used to open
                        // a separate "Across your wallets" sheet, but that sheet
                        // re-showed this very number and line before getting to
                        // its only unique content — the per-wallet split — which
                        // now lives in this same card as face chips. No door, no
                        // chevron; the number just states itself.
                        // "Wallets" only when that's all it is (2026-07-31).
                        // This number merges connected exchange balances and
                        // staked-validator ETH (§163), and a caption naming
                        // wallets over a total that isn't only wallets is the
                        // honesty rule's own failure mode — a true-sounding
                        // phrase that isn't describing what it counts.
                        // "Accounts" is the word that covers both without
                        // claiming the app knows what to call each one.
                        // `chips`, gathered once at the top of this section —
                        // it walks the portfolio's holders, so re-deriving it
                        // here would do that twice per body pass.
                        let hasBreakdown = !chips.isEmpty && selectedWallet == nil
                        // SCOPED, THIS LINE IS THE WALLET'S NAME (prd §450).
                        // The rail above stopped captioning its faces on the
                        // strength of this slot existing — so when it is set,
                        // it outranks both of the descriptive captions below,
                        // and the chevron stays away for the reason it always
                        // did (`hasBreakdown` is false while scoped: there is
                        // no split behind a single wallet to open).
                        //
                        // A single-wallet install has no rail at all
                        // (`WalletScopeRail.shows` wants > 1 watched) and no
                        // scope, so it keeps "Balance" exactly as before.
                        let scoped = selectedWallet.map {
                            WalletScopeRail.caption(for: $0, in: wallet.addresses)
                        }
                        WalletBalanceHeadline(
                            total: total,
                            chart: chart,
                            marks: drawsChart
                                ? walletMarks(dates: windowed.map(\.at), things: visible)
                                : [],
                            // ALWAYS "accounts", never "wallets" (user ruling,
                            // prd §483, 2026-08-26). This forked on whether any
                            // holder was an EXCHANGE — "accounts" when one was,
                            // "wallets" when they were all self-custodied — a
                            // distinction the person reading it never asked for
                            // and which made the same line change wording on
                            // them when they connected a venue. "Accounts" is
                            // true of both, and it is the noun the rail
                            // directly below now uses for the same faces.
                            // **THE CAPTION NAMES THE SCOPE, OR SAYS NOTHING**
                            // (user, prd §483: *"should we get rid of this
                            // since user is on 'All'? is it redundant?"* — yes).
                            // Scoped, this is the wallet's own name and is the
                            // only place it appears (§450). Unscoped it read
                            // "Across your accounts", which is precisely what
                            // the lit "All" on the rail below already says —
                            // and a bare figure is what Apple Card and Stocks
                            // both show. Dropping it also buys back a row
                            // toward getting three transactions above the fold.
                            //
                            // "Balance" survives for the single-wallet install,
                            // which has no rail at all (`WalletScopeRail.shows`
                            // wants > 1) and so has nothing else naming it.
                            caption: scoped?.name ?? selectedSeat?.name
                                ?? (hasBreakdown ? "" : String(localized: "Balance")),
                            captionAddress: selectedWallet,
                            captionDetail: scoped?.detail,
                            // An empty caption must take NO height, or dropping
                            // the word leaves its row behind — a 20pt gap under
                            // the venue rail with nothing in it.
                            hidesEmptyCaption: true,
                            awaitsLine: selectedSeat.map(seatKeepsLine) ?? true,
                            // No mover line and a shorter chart — see the
                            // parameters' own docs (prd §483).
                            mover: nil,
                            // THE DATE, WHEN THERE IS ONE (prd §825). Non-nil
                            // only while the crown is standing on the wallets'
                            // last known reading because the chains could not
                            // be reached — see `WalletIngest.portfolioRead`.
                            asOf: portfolio?.asOf,
                            // WHAT IS NOT IN THIS NUMBER (prd §827).
                            // Two facts, two sentences (prd §828): a chain that
                            // did not answer, and one that answered and could
                            // not be priced. Both are out of the number.
                            note: walletTotalNote,
                            // The window as words (prd §920) — the same pass
                            // `RoomHomeCrown` makes.
                            window: drawsChart ? active.windowWord(since: windowed.first?.at) : nil,
                            drawsChart: drawsChart,
                            drawsReading: drawsChart,
                            // **DERIVED, not 96 (prd §588).** §483 set this
                            // to 96 to buy a third transaction row; §588 buys
                            // that row back from the row itself instead, and
                            // gives the line the box. A literal here is a
                            // second copy of `visualSlot`'s arithmetic that
                            // cannot know when the box moves — which is
                            // exactly how a grown box leaves dead air under a
                            // drawing that never heard about it.
                            //
                            // **AND THE CHIPS ARE PAID FOR (2026-09-14, user:
                            // "7d and watched is clipping").** This read the
                            // bare `crownChart` constant, which budgets the
                            // chrome §688 measured BEFORE the range chips
                            // existed — so the line took the whole box and the
                            // track below it ran out through `DSRoomSlot`'s
                            // clip. The predicate is `WalletBalanceHeadline`'s
                            // own gate for drawing them, not a second guess at
                            // it.
                            chartHeight: DSRoomChassis.crownChart(chips: ranges.count > 1),
                            ranges: ranges,
                            range: active,
                            onPickRange: { r in
                                balanceRange = r
                                r.remember()
                            },
                            onOpen: nil,
                            // FALSE again (2026-08-16): the hero has no
                            // coloured ground to sit on, so the line takes
                            // back its own direction accent — the whole
                            // reason `onColor` whitened it was that red on
                            // saturated blue measured ~1.35:1, and there is
                            // no blue now. The flag survives for any future
                            // caller that does paint a ground.
                            onColor: false,
                            onOpenMark: { id in
                                // `.none`: a mark on a hero is not a list.
                                feedSheet = visible.first { $0.id == id }
                                    .map { .thing($0, walk: .none) }
                            })
                    }
                    // Whose the number is (prd §212) — only unscoped and only
                    // with more than one wallet carrying a real line, exactly
                    // the guard the retired "Each wallet" card kept. A tap
                    // scopes the whole feed, the move the switcher bar makes.
                    // THE VALUE PILLS ARE GONE (user ruling, prd §483,
                    // 2026-08-26: *"drop the value pills"*). They named each
                    // wallet's own total under the crown — and once the scope
                    // rail moved out of the pinned chrome and into the content
                    // directly below, the room drew the same wallets twice, in
                    // two adjacent rows of faces. That is the "we cannot have
                    // four rows of chips" complaint reappearing one level down.
                    //
                    // The rail is the row that survives because it is the
                    // INTERACTIVE one: it scopes, it carries the book door, and
                    // the figure each pill used to state is the crown directly
                    // above it once a face is picked. What is genuinely lost is
                    // every wallet's total AT A GLANCE, without picking — say so
                    // rather than pretend the move was free. §212's "whose the
                    // number is" question is now answered by the rail's lit
                    // face rather than by a row of figures.
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // NO HORIZONTAL PADDING (2026-08-22). It carried s4, which put
                // the hero's figure 36pt from the screen edge — the line every
                // CARD's text sits on, because a card adds its own s4 inside
                // the row's own s4. But this hero has no card, and the room's
                // other chrome-less text — the group headers below — sits at
                // 18. Two bare elements on two different margins is the kind of
                // misalignment you see before you can name it. The number now
                // leads on the same line as the headings that follow it, which
                // is where a bare hero sits in Stocks and in Apple Card.
                // NO TOP PADDING (prd §953): the crown lives in the chassis'
                // fixed box, which is its own air — the top s2 put the Wallet's
                // number 8pt below every devnet crown and every section's
                // figure. The bottom s2 went with it: the box holds the height.
                // (Deleting this modifier once "crashed the Wallet on open" —
                // a stale incremental build, not this code: docs/gotchas.md,
                // "a `some View` changed in one file".)
                // NO GROUND AT ALL (2026-08-16, the Apple redraw — retiring
                // the `DS.tint` card this carried for a day). Apple has never
                // shipped a balance inside a coloured card: Apple Card's sits
                // on a plain surface, Stocks' quote on black. The figure, the
                // move and the chart ARE the hero; a container around them was
                // the app claiming emphasis the content already had. It also
                // ends the two-blues problem by deletion — the only blue left
                // in the room is chrome — and it restores something the card
                // structurally prevented: on a DOWN day this hero is red, top
                // to bottom, because every colour on it now comes from the
                // data rather than from the surface.
                }

                // WHAT JUST HAPPENED, directly under the number it moved
                // (2026-08-18, user ruling). The room's transactions used to
                // begin after ten standing cards, so on a busy wallet the one
                // thing a wallet app gets opened for was two screens down. This
                // is the whole fix, and deliberately the SMALLEST one that
                // works: three rows, nothing else folded, every card below
                // exactly where it was.
                //
                // ABOVE the caution block on purpose. That block's own ordering
                // note (below) is about the hero and the TREEMAP reading as one
                // blue mass with no ink between them — still true, and now
                // doubly satisfied, since this card is ink too. What it is not
                // is a reason to seat a security warning between the balance
                // and the transactions that moved it: this card and the hero
                // are one glance ("it moved — here's what moved"), and the
                // caution answers a different question.
                if !latest.isEmpty {
                    walletTodayCard(latest, streamTotal: streamTotal)
                }

                // …and the caution presses back in ink. ORDERING IS
                // LOAD-BEARING (2026-08-15, wallet cohesion pass): this ink
                // card sits BETWEEN the bright hero above and the holdings
                // treemap below, and that is not incidental — the hero is the
                // room's one bright object, the treemap is a large blue-ish
                // figure, and without ink between them the two read as one
                // oversized blue mass. A future reshuffle that puts the
                // treemap directly under the hero should re-litigate that
                // adjacency, not inherit it. GUARDED as a whole,
                // which it never had to be while it shared the balance's card:
                // an unguarded empty stack used to cost nothing, and now it
                // would draw a surface with nothing on it for every wallet
                // that holds no protocol position and has no warning — which
                // is most of them.
                }
                // Each piece arrives on its own clock — the balance reads off
                // already-recorded samples (instant) while warnings/holdings/
                // lending wait on live reads (2026-07-20: "balance shows then
                // the others pop in but looks unintentional"). The card is one
                // entrance now that the three ride inside it; the pieces still
                // appear as they land, they just no longer each stage a
                // separate surface into the room.
                .modifier(rowEntrance(0))
        } else {
            // **A ROOM WITH NOTHING TO READ SAYS WHAT IT WOULD HOLD (prd §761,
            // user: "re empty wallet head pls fix").** The gate above is an
            // honesty floor — no balance, no line, no warning, no composition,
            // no recent row, so nothing is drawn rather than a card with
            // nothing in it — and for as long as the crown sat inside
            // `DSRoomSlot`'s reserved 300pt box, "nothing" rendered as 300pt of
            // black at the top of the room — and it still is, because §760
            // put that box back so every room's lead is one height. What was
            // missing was never the box; it was the words inside it.
            //
            // §611's mechanism is the answer and it already had a hole where
            // `.home` should be: every OTHER scope states what it would hold
            // through `WalletSection.emptyHeadline`/`emptyBody`, and Home
            // returned nil for both on the premise that the room always has a
            // crown. The words live there now, so the room explains itself in
            // the one register §611 wrote and a harness can mutation-test them.
            //
            // `padded: false` because this crown sets no horizontal padding of
            // its own, so the scope slot's pad would put these words 16pt right
            // of the balance they stand in for. The HEIGHT is not switched: the
            // 300pt box is Home's again (§760) and this fills it.
            WalletScopeEmptyFigure(section: .home, padded: false)
                .modifier(rowEntrance(0))
        }
    }

    /// The transactions that landed inside the drawn window, placed against it
    /// (prd §155, 2026-07-21). A balance line conflates two different stories —
    /// prices moved, and money moved in or out — and the app holds both halves;
    /// this is the one that ties them together, so a step in the line can be
    /// read back to the send that caused it.
    ///
    /// Only things that fall BETWEEN the first and last sample are marked:
    /// a transaction from before the record began has no place on the line, and
    /// inventing one at the left edge would claim it caused a move the line
    /// never saw. Capped at the most recent ten — beyond that the punctuation
    /// becomes a second series and the line stops being readable.
    private func walletMarks(dates: [Date], things: [Thing]) -> [TokenChartMark] {
        guard dates.count >= 2, let first = dates.first, let last = dates.last else { return [] }
        return things
            .filter { $0.kind == .transaction && $0.capturedAt >= first && $0.capturedAt <= last }
            .prefix(10)
            .compactMap { thing in
                guard let i = dates.lastIndex(where: { $0 <= thing.capturedAt }) else { return nil }
                let next = min(i + 1, dates.count - 1)
                let span = dates[next].timeIntervalSince(dates[i])
                let t = span > 0 ? thing.capturedAt.timeIntervalSince(dates[i]) / span : 0
                return TokenChartMark(id: thing.id, x: Double(i) + min(max(t, 0), 1),
                                      label: thing.title)
            }
    }

    /// "Mostly ETH · +$310" — the top attributed mover, in the scope the feed
    /// is standing in (prd §155). The delta pill says the line moved; this says
    /// what moved it, off the same per-token snapshots. nil whenever the record
    /// can't attribute honestly yet — most of all on a young history, where no
    /// snapshot pair exists to difference. (This line is now the only "what
    /// moved" surface; the combined sheet that carried a fuller table retired
    /// with prd §208.)
    private func moverLine() -> String? {
        guard let top = wallet.holdingsDeltas(forAddress: selectedWallet).first else { return nil }
        let sign = top.delta >= 0 ? "+" : "−"
        return String(localized: "Mostly \(top.symbol) · \(sign)\(TokenStats.compact(abs(top.delta)))")
    }

    /// What's in protocols, for the balance card's composition strip (prd
    /// §240). Pure arithmetic over books `loadWalletLive` already fetched —
    /// no network of its own, and it follows the feed's wallet scope for free
    /// because `WalletWatch.liveState` reads every book at that same scope.
    var walletComposition: WalletComposition {
        WalletComposition.from(aave: walletLive.positions,
                               morpho: walletLive.morpho,
                               uniswap: walletLive.uniswap,
                               hyperliquid: walletLive.hyperliquid,
                               aerodrome: walletLive.aerodrome,
                               worldApp: walletLive.worldApp,
                               etherfiCash: walletLive.etherfiCash,
                               etherfiUnstake: walletLive.etherfiUnstake)
    }

    /// The per-wallet split as chip entries (prd §212, 2026-07-25) — value
    /// types keyed by address, so the ForEach behind them never reads a live
    /// `@Model` (the crash class the CLAUDE.md ForEach rule guards).
    ///
    /// It rode a card of its own from §208 until this pass: face, name, total,
    /// an 80pt sparkline and a delta pill per wallet. Same source, same guard
    /// (≥2 aligned samples, >1 wallet watched) — the sparkline and the name
    /// drop out, because at 80pt the line was decoration and tapping a chip
    /// scopes the feed to that wallet, where the line is drawn full-width as
    /// the room's own headline.
    ///
    /// VENUES JOIN THEM (2026-07-31). The number these sit under is
    /// `portfolio.totalUSD`, which has merged connected exchange balances and
    /// staked-validator ETH since §163 — so a strip built only from watched
    /// wallets decomposed a fraction of it without saying so, and worst
    /// exactly where it mattered most: someone whose main holding is on an
    /// exchange is the case that ruling exists for. A venue contributes a chip
    /// with no delta, since the value line is recorded per watched wallet and
    /// a venue has no history to difference (see `WalletFaceChips.Entry`).
    ///
    /// The wallet chips still read their own recorded lines rather than the
    /// portfolio's per-wallet figures — that's unchanged, and it's why the
    /// chips have never claimed to SUM to the number above them. They answer
    /// "whose", not "how it adds up".
    private var walletFaceChipEntries: [WalletFaceChips.Entry] {
        let venues = walletVenueChipEntries
        // One wallet and no venue means there is nothing to decompose. One
        // wallet WITH a venue still splits into two places, so the strip earns
        // its keep — the old bare `> 1` guard would have hidden exactly the
        // Coinbase-plus-one-wallet case this pass is about.
        guard wallet.addresses.count > 1 || !venues.isEmpty else { return [] }
        let wallets: [WalletFaceChips.Entry] = wallet.addresses.compactMap { addr in
            let samples = wallet.valueSamples(forAddress: addr.address)
            guard samples.count >= 2, let first = samples.first?.usd,
                  let last = samples.last?.usd else { return nil }
            return WalletFaceChips.Entry(id: addr.address, value: last,
                                         change: first > 0 ? (last - first) / first : 0)
        }
        // Still nothing to split if the wallets have no lines yet and there's
        // no venue beside them — one lone chip under a number says nothing the
        // number didn't.
        guard wallets.count + venues.count > 1 else { return [] }
        return wallets + venues
    }

    /// The exchange/validator half of the strip, biggest first — floored so a
    /// few cents left on an exchange doesn't earn a chip beside real wallets.
    private var walletVenueChipEntries: [WalletFaceChips.Entry] {
        // Scoped to ONE wallet, the question is that wallet's, and a venue
        // isn't part of the answer — the same reason `WalletIngest` only
        // merges venues into the combined read.
        guard selectedWallet == nil, let portfolio else { return [] }
        return portfolio.venueTotals
            .filter { $0.usd >= WalletIngest.holdingFloor }
            .map { WalletFaceChips.Entry(id: $0.address, value: $0.usd,
                                         change: nil, venueLabel: $0.label) }
    }
}
