import SwiftUI
import SwiftData

// MARKETS, THE WALLET'S TILE (prd §1081, §1171b; in place since §1337): the
// categories in the Wallet's box, the watchlist under one sort menu.
extension FeedScreen {
    /// The watched rows: Markets' rows that are not a fired alert.
    func marketsWatches(_ visible: [Thing]) -> [Thing] {
        visible.live.filter { !PriceAlertStore.isAlertRow($0) }
    }

    /// Whether `thing` draws as Markets' own row here (prd §1337): a Markets
    /// row in the Wallet's Markets tile, the one page that lists them.
    func drawsMarketsRow(_ thing: Thing) -> Bool {
        source == CategoryFold.walletRoom && thing.source == TokenWatch.source
    }

    /// **MARKETS OPENS IN PLACE (prd §1337, user: "it should open in place
    /// not the overlay. it's jarring").** Its room's box (prd §1138, §1167:
    /// the categories A–Z with Following and Alerts first, a glyph and a name
    /// each, two across) is the Wallet's box while Markets is picked, the way
    /// Security's checkup stands there: the Wallet's row stays under it with
    /// Markets lit, and pressing a tile lists it below.
    @ViewBuilder
    var walletMarketsFigure: some View {
        // **THE BOX IS WHAT YOU WATCH, TODAY (prd §1479 item 7, retiring
        // §1391's sectors box):** every watched coin and stock one tile, the
        // day's move its wash and edge — the treemap Holdings draws, sized
        // alike because a watch is not a holding. The category boxes are
        // deleted; their companies are From your apps, under the watchlist.
        let watches = marketsWatches(walletMarketsRows)
        let moves = Dictionary(watches.compactMap { thing -> (String, Double)? in
            guard let change = Self.watchChange(thing) else { return nil }
            return (HoldingMoves.key(TokensAsk.name(of: thing.title)), change)
        }, uniquingKeysWith: { a, _ in a })
        HoldingsTreemap(total: watches.count == 1 ? String(localized: "1 watched")
                                                  : String(localized: "\(watches.count) watched"),
                        holdings: watches.map {
                            .init(id: TokensAsk.name(of: $0.title), usd: 1, route: nil, display: "")
                        },
                        showsShares: false)
            .environment(\.holdingsDayMoves, moves)
        // Markets' rows are a different source from the Wallet's, so the
        // tile reads them here, keyed on their own count and the corpus
        // signal (a SQL COUNT, no model built), never in a body (§628).
        .task(id: walletMarketsKey) { loadWalletMarkets() }
        // Every pack's quotes, one pack at a time so the burst is a pack's
        // (prd §1391): the box's moves fill in as each lands; a pack read
        // in the last ten minutes costs nothing (`CompanyQuotes.freshFor`).
        .task {
            for scope in TokensScope.box { await CompanyQuotes.shared.load(scope.pack) }
        }
        // The tray's search can open a company or New from any room (prd
        // §1185), so it asks; the tile raises once it stands, whichever of
        // its lists is picked.
        .onChange(of: chrome.marketsRequest, initial: true) { _, _ in takeMarketsRequest() }
        .onChange(of: isActive) { _, _ in takeMarketsRequest() }
    }

    /// The Markets tile's reading key: Markets' own row count and the
    /// corpus signal. Read only while the tile is picked (its figure is the
    /// one caller), so no other page pays the COUNT.
    var walletMarketsKey: Corpus.Revision {
        Corpus.revision(in: modelContext, source: TokenWatch.source)
    }

    /// Markets' rows, as its room's query read them: newest first, bounded
    /// like a source room, surfaced by the one rule.
    func loadWalletMarkets() {
        let markets = TokenWatch.source
        var d = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { $0.source == markets },
                                       sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        d.fetchLimit = Self.sourceRoomFetchLimit
        walletMarketsRows = Corpus.surfaced((try? modelContext.fetch(d)) ?? [], room: markets)
    }

    private func takeMarketsRequest() {
        guard let request = chrome.marketsRequest, isActive else { return }
        chrome.marketsRequest = nil
        switch request {
        case .company(let company): openCompany(company)
        }
    }

    /// Under the Wallet's row while Markets is picked (prd §1337): what you
    /// follow, the alerts, or a category's companies — the lists its room
    /// drew under its box.
    @ViewBuilder
    func walletMarketsSections(nextEventID: UUID?) -> some View {
        let rows = walletMarketsRows.live
        if chrome.tokensScope == .alerts {
            marketsAlertsSections(rows, nextEventID: nextEventID)
        } else {
            marketsWatchlistSections(rows, nextEventID: nextEventID)
            // **FROM YOUR APPS (prd §1479 item 7):** the index's one part
            // that is yours — the companies behind the apps you connected,
            // one list, no category boxes. Search finds any other company.
            marketsFromYourAppsSection(visible: rows)
        }
    }

    /// "Watchlist" and its order, one menu, on the rows' line (prd §1081:
    /// the three chips on the account page became this).
    var marketsListHead: some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
                // The Feed's section name (prd §1268): a pink glyph first.
                Image(systemName: ScopeTileGlyph.watch)
                    .dsGlyph(.body)
                    .foregroundStyle(DS.brandInk)
                    .accessibilityHidden(true)
                // **FOLLOWING · ALERTS ARE THE HEAD'S TWO WORDS (prd §1391):**
                // the Feed's choice grammar (§1251), the picked word in the
                // head ink, the other grey; an alert is one more place to
                // go, in no colour of its own. The Movers menu is deleted:
                // the box says who moved, the list keeps your order.
                ForEach([TokensScope.watchlist, .alerts]) { choice in
                    let on = chrome.tokensScope == choice
                    Button {
                        DSHaptic.selection()
                        withAnimation(DS.Motion.standard) { chrome.tokensScope = choice }
                    } label: {
                        Text(verbatim: choice.label)
                            .dsText(.heading20)
                            .foregroundStyle(on ? DS.headInk : DS.textTertiary)
                            .lineLimit(1)
                    }
                    .buttonStyle(RowPress())
                    .accessibilityAddTraits(on ? [.isSelected] : [])
                }
                Spacer(minLength: 0)
                // Follow, from the head's + (prd §1386), the one word (prd
                // §1391, user: "could we just say follow? its follow a
                // market regardless").
                Button {
                    DSHaptic.selection()
                    feedSheet = .watchAdd
                } label: {
                    Image(systemName: "plus")
                        .dsGlyph(.body, weight: .regular)
                        .foregroundStyle(DS.brandInk)
                        .frame(width: DS.Hit.min, height: DS.Hit.min)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressSpring())
                .accessibilityLabel(Text("Follow"))
            }
            .feedRowBackground()
            .listRowInsets(.init(top: DS.Space.s2, leading: DSRoomChassis.rowInset,
                                 bottom: 0, trailing: DSRoomChassis.rowInset))
            .listRowSeparator(.hidden)
        }
    }

    /// The Following list: its head, Follow a company, gas, then the rows
    /// in the chosen order.
    @ViewBuilder
    func marketsWatchlistSections(_ visible: [Thing], nextEventID: UUID?) -> some View {
        let watches = marketsWatches(visible)
        // The head always stands: it carries the + (prd §1386), so the
        // "Follow a company" row that led the list (§1230) is deleted.
        marketsListHead
        // Gas at the head of the list (prd §1250): Ethereum and Base, stamped
        // by age as a price is, its menu the gas alerts.
        Section {
            MarketsGasHead(gas: MarketsGas.shared)
                .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.rowInset,
                                          bottom: 0, trailing: DSRoomChassis.rowInset))
                .feedRowBackground()
                .listRowSeparator(.hidden)
        }
        .task { await MarketsGas.shared.load() }
        // An empty list says so in the one wording every Follow list uses
        // (prd §1230); the verb above starts it.
        if watches.isEmpty {
            Section {
                Text("Nothing followed yet")
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
                    .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DSRoomChassis.rowInset,
                                              bottom: DS.Space.s2, trailing: DSRoomChassis.rowInset))
                    .feedRowBackground()
                    .listRowSeparator(.hidden)
            }
        }
        watchlistSection(watches, nextEventID: nextEventID)
            .task(id: watches.count) {
                held = await WalletIngest.lastKnownHeld()
                #if DEBUG
                marketsProbe()
                #endif
            }
    }

    #if DEBUG
    /// `-marketsScope alerts|<Category>|new` — land on a tile, or raise New,
    /// at mount (prd §1081, §1171b; NSLogs `marketsScope:`). Once per launch.
    private func marketsProbe() {
        guard !Self.marketsProbed,
              let raw = UserDefaults.standard.string(forKey: "marketsScope") else { return }
        Self.marketsProbed = true
        NSLog("[Casberi] marketsScope: %@", raw)
        switch raw {
        case "alerts":        chrome.tokensScope = .alerts
        case "new", "add": feedSheet = .watchAdd
        default:
            // A category's index by its name (`Work`).
            if let scope = TokensScope.all.first(where: { $0.category == raw }) {
                chrome.tokensScope = scope
            }
        }
    }
    #endif

    /// The Alerts tile (prd §1081): the alerts you set, each with its switch,
    /// newest first, then the ones that went off, as the rows they landed.
    @ViewBuilder
    func marketsAlertsSections(_ visible: [Thing], nextEventID: UUID?) -> some View {
        // The same head, Alerts picked (prd §1391).
        marketsListHead
        let watches = marketsWatches(visible)
        let byRef = Dictionary(watches.compactMap { t in t.sourceRef.map { ($0, t) } },
                               uniquingKeysWith: { a, _ in a })
        // A gas alert watches a chain, not a row (prd §1250).
        let alerts = PriceAlertStore.shared.alerts
            .filter { byRef[$0.ref] != nil || GasPrice.network(fromRef: $0.ref) != nil }
            .sorted { $0.createdAt > $1.createdAt }
        if alerts.isEmpty {
            Section {
                DSSkeletonRows(label: Text("No alerts yet."))
                    .feedRowBackground()
                    .listRowSeparator(.hidden)
                DSFootnote(Text("Open something you follow to set an alert."))
                    .feedRowBackground()
                    .listRowSeparator(.hidden)
                    .listRowInsets(.init(top: 0, leading: DSRoomChassis.rowInset,
                                         bottom: 0, trailing: DSRoomChassis.rowInset))
            }
        } else {
            Section {
                ForEach(alerts) { alert in
                    marketsAlertRow(alert, watched: byRef[alert.ref])
                }
            }
        }
        // Only an alert that still stands has a history (prd §1467): a row
        // whose alert is gone names nothing on this list.
        let fired = visible.live.filter { PriceAlertStore.isAlertRow($0) && PriceAlertStore.shared.stands($0) }
        if !fired.isEmpty {
            groupedSections([(String(localized: "Went off"), fired)],
                            nextEventID: nextEventID, dated: false)
        }
    }

    private func marketsAlertRow(_ alert: PriceAlert, watched: Thing?) -> some View {
        let price = watched.flatMap { PriceAlertStore.reading(for: $0)?.price }
        let open = { if let watched, watched.isLive { openThing(watched) } }
        return HStack(spacing: DS.Space.s3) {
            HStack(spacing: DS.Space.s3) {
                WatchFace(url: watched.flatMap(marketsLogo), lettered: alert.name,
                          onWhite: watched.flatMap { StockWatch.symbol(of: $0) } != nil,
                          // A gas alert's face is the pump (prd §1250): it watches a chain.
                          symbol: alert.kind == .gasBelow ? MarketsGasHead.glyph : nil)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: alert.name).dsText(.body17).foregroundStyle(DS.textPrimary)
                        .dsCardLead(Text("Opens its page"), perform: open)
                    Text("\(WatchAlertsSection.title(alert))\(WatchAlertsSection.subtitle(alert, price: price).map { " · " + $0 } ?? "")")
                        .dsText(.subhead12).foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: open)
            Toggle(isOn: Binding(get: { alert.on },
                                 set: { PriceAlertStore.shared.set(alert.id, on: $0); DSHaptic.selection() })) {
                Text(WatchAlertsSection.title(alert))
            }
            .labelsHidden()
        }
        .contextMenu {
            Button(role: .destructive) {
                PriceAlertStore.shared.remove(alert.id, context: modelContext)
            } label: {
                Label("Delete alert", systemImage: "trash")
            }
        }
        .feedRowBackground()
        .listRowInsets(.init(top: Self.rowAir, leading: DSRoomChassis.rowInset,
                             bottom: Self.rowAir, trailing: DSRoomChassis.rowInset))
        .listRowSeparator(.hidden)
    }

    // MARK: - From your apps (prd §1479 item 7)

    /// The companies behind the apps you connected, across every category,
    /// each once with all its apps — one list under the watchlist, starred in
    /// one tap. Nothing when no app you connected is made by a listed company.
    @ViewBuilder
    func marketsFromYourAppsSection(visible: [Thing]) -> some View {
        let pack = TokensScope.box.flatMap(\.pack)
        let connected = connectedSeatNames
        let byName = Dictionary(pack.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        let merged = MarketsIndex.merged(TokensScope.box.map { $0.pack.map(MarketsWatch.entry) })
        let split = MarketsIndex.sections(merged, connected: connected)
        indexSection(String(localized: "From your apps"), split.yours, byName: byName,
                     connected: connected, watched: MarketsWatch.watchedTickers(visible), watchAll: true)
    }

    // MARK: - The index (prd §1082)

    @ViewBuilder
    private func indexSection(_ title: String, _ entries: [MarketsIndex.Entry],
                              byName: [String: CompanyPacks.Company], connected: Set<String>,
                              watched: Set<String>, watchAll: Bool) -> some View {
        let companies = entries.compactMap { byName[$0.name] }
        if !companies.isEmpty {
            let unwatched = companies.filter { c in
                c.listing.ticker.map { !watched.contains($0.uppercased()) } ?? false
            }
            Section {
                HStack(spacing: DS.Space.s2) {
                    Image(systemName: "building.2")
                        .dsGlyph(.body)
                        .foregroundStyle(DS.brandInk)
                        .frame(width: DSRoomChassis.headGlyph)
                        .accessibilityHidden(true)
                    Text(title).dsText(.heading20).foregroundStyle(DS.headInk)
                    Spacer(minLength: 0)
                    if watchAll, unwatched.count > 1 {
                        Button {
                            watchAllCompanies(unwatched)
                        } label: {
                            Text("Follow all \(unwatched.count)").dsText(.body17)
                                .foregroundStyle(DS.pickInk)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPress())
                    }
                }
                .feedRowBackground()
                .listRowSeparator(.hidden)
                .listRowInsets(.init(top: DS.Space.s4, leading: DSRoomChassis.rowInset,
                                     bottom: 0, trailing: DSRoomChassis.rowInset))
                ForEach(companies) { company in
                    let isWatched = company.listing.ticker.map { watched.contains($0.uppercased()) } ?? false
                    Button {
                        openCompany(company)
                    } label: {
                        IndexRow(company: company,
                                 apps: MarketsIndex.appsLine(MarketsWatch.entry(company), connected: connected),
                                 quote: CompanyQuotes.shared.quote(company.listing),
                                 watched: isWatched,
                                 star: company.listing == .unlisted ? nil : { toggleCompany(company, watched: isWatched) })
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPress())
                    .feedRowBackground()
                    .listRowSeparator(.hidden)
                    .listRowInsets(.init(top: Self.rowAir, leading: DSRoomChassis.rowInset,
                                         bottom: Self.rowAir, trailing: DSRoomChassis.rowInset))
                }
            }
        }
    }

    /// A watched company opens its own page (alerts and all); one you don't
    /// watch opens `CompanySheet`.
    func openCompany(_ company: CompanyPacks.Company) {
        if let thing = MarketsWatch.watchedThing(company, context: modelContext) {
            openThing(thing)
        } else if company.listing != .unlisted {
            feedSheet = .company(company)
        }
    }

    private func toggleCompany(_ company: CompanyPacks.Company, watched: Bool) {
        if watched {
            MarketsWatch.unwatch(company, context: modelContext)
            DSHaptic.tap()
            chrome.flash(String(localized: "Stopped following \(company.name)"))
            return
        }
        Task {
            switch await MarketsWatch.watch(company, context: modelContext) {
            case .success:
                DSHaptic.success()
                chrome.flash(String(localized: "Following \(company.name)"),
                             action: .init(label: String(localized: "Undo")) {
                                 MarketsWatch.unwatch(company, context: modelContext)
                             })
            case .failure(let why):
                DSHaptic.failure()
                chrome.flash(why.message)
            }
        }
    }

    private func watchAllCompanies(_ companies: [CompanyPacks.Company]) {
        Task {
            var landed = 0
            for company in companies {
                if case .success = await MarketsWatch.watch(company, context: modelContext) { landed += 1 }
            }
            DSHaptic.success()
            chrome.flash(landed == companies.count
                         ? String(localized: "Following \(landed)")
                         : String(localized: "Following \(landed) of \(companies.count)"))
        }
    }

    /// A watched row's face: a token's own logo, a stock's from its ticker.
    func marketsLogo(_ thing: Thing) -> String? {
        if let image = thing.previewImageURL, !image.isEmpty { return image }
        // The demo reaches nothing: a stock keeps its lettered mark there.
        guard !DemoMode.isActive else { return nil }
        return StockWatch.symbol(of: thing).flatMap(StockWatch.logoURL)
    }

    /// One watched row in the room (prd §1081).
    @ViewBuilder
    func marketsRow(_ thing: Thing) -> some View {
        let pulse = TokenPulse.shared.pulse(for: thing)
        let stock = StockWatch.symbol(of: thing)
        let quote = stock.flatMap { CompanyQuotes.shared.quote(.stock($0)) }
        let price = pulse?.price ?? quote?.price
        let row = WatchRow(name: TokensAsk.name(of: thing.title),
                           logo: marketsLogo(thing),
                           lettered: thing.authorHandle ?? TokensAsk.name(of: thing.title),
                           price: price,
                           change: Self.watchChange(thing),
                           // A stock's day line (prd §1250), Yahoo's day closes
                           // read off the body and drawn as a token's.
                           closes: pulse?.closes ?? TokenPulse.shared.stockLine(for: thing) ?? [],
                           line: marketsLine(thing, price: price, quoteCap: quote?.marketCap,
                                             pulse: pulse, stock: stock),
                           isStock: stock != nil,
                           glyph: stock.flatMap(WatchFace.systemMark(forTicker:)))
        if let stock, let ref = thing.sourceRef {
            let company = CompanyPacks.Company(name: TokensAsk.name(of: thing.title),
                                               listing: .stock(stock), seats: [TokenWatch.source])
            row.task(id: stock) {
                await CompanyQuotes.shared.load([company])
                await TokenPulse.shared.loadStockLine(ref: ref, symbol: stock)
            }
        } else {
            row
        }
    }

    /// Pin to Lock Screen, from a row's long press (prd §1250): one row's
    /// price as a Live Activity, replacing any other; the same item unpins.
    func pinToLockScreen(_ thing: Thing) {
        guard thing.isLive, let ref = thing.sourceRef else { return }
        let name = TokensAsk.name(of: thing.title)
        if PriceActivityDriver.pinnedRef == ref {
            Task { await PriceActivityDriver.unpin() }
            DSHaptic.tap()
            chrome.flash(String(localized: "Unpinned \(name)"))
            return
        }
        Task {
            switch await PriceActivityDriver.pin(thing) {
            case .pinned:
                DSHaptic.success()
                chrome.flash(String(localized: "\(name) is on your Lock Screen"))
            case .off:
                DSHaptic.failure()
                chrome.flash(String(localized: "Turn on Live Activities for Casberi in Settings"))
            case .unread:
                DSHaptic.failure()
                chrome.flash(String(localized: "No price read for \(name) yet"))
            }
        }
    }

    /// The one line a watched row says (`WatchLine`): your alert, what you
    /// hold, since you watched, then the market's facts.
    private func marketsLine(_ thing: Thing, price: Double?, quoteCap: Double?,
                             pulse: TokenPulse.Pulse?, stock: String?) -> WatchLine.Line? {
        let alert = thing.sourceRef.flatMap { PriceAlertStore.shared.lineAlert(for: $0) }
        let alertText: String? = alert.map { a in
            switch a.kind {
            case .move:          String(localized: "a \(WatchAlertsSection.movePercentText(a.target)) move")
            case .volume:        String(localized: "\(TokenStats.compact(a.target)) volume")
            case .above, .below: TokenChartStyle.priceText(a.target)
            case .gasBelow:      GasPrice.text(a.target)
            }
        }
        let holding = marketsHolding(thing).map { TokenStats.compact($0) }
        let since = WatchLine.since(anchor: thing.watchPriceUsd, price: price)
        let symbol = thing.authorHandle ?? TokensAsk.symbol(of: thing.title)
        let cap = pulse?.marketCap ?? quoteCap
        // A stock's exchange is the tag `StockWatch.add` stamps in capitals.
        let exchange = thing.tags.first {
            $0 != "Watchlist" && $0 == $0.uppercased() && $0.count <= 8 && $0 != symbol.uppercased()
        }
        let facts = [symbol, stock == nil ? nil : exchange.map { $0.capitalized },
                     cap.map { "\(TokenStats.compact($0)) cap" }]
            .compactMap(\.self).joined(separator: " · ")
        return WatchLine.pick(alertTarget: alertText, holding: holding,
                              sinceWatched: since, facts: facts)
    }

    /// What the Wallet last read you hold of a watched token, in dollars:
    /// by contract, else by the household coins' symbol (ETH, BTC and SOL
    /// are watched as their wrapped form and held natively). Never a stock.
    private func marketsHolding(_ thing: Thing) -> Double? {
        guard StockWatch.symbol(of: thing) == nil, let ref = thing.sourceRef else { return nil }
        let address = ref.split(separator: ":").last.map { String($0).lowercased() } ?? ""
        if let usd = held.byContract[address], usd >= 1 { return usd }
        let symbol = (thing.authorHandle ?? "").uppercased()
        if ["ETH", "BTC", "SOL"].contains(symbol), let usd = held.bySymbol[symbol], usd >= 1 { return usd }
        return nil
    }

    /// Deletes a Went off row from its long press (user, 2026-10-17): the
    /// row alone, never the alert that landed it.
    func removeAlertRow(_ thing: Thing) {
        guard thing.isLive, PriceAlertStore.isAlertRow(thing) else { return }
        PriceAlertStore.deleteRow(thing, context: modelContext)
        DSHaptic.tap()
    }

    /// Unwatches a row from its long press: its alerts go with it, and the
    /// toast can put it back (prd §1081).
    func unwatch(_ thing: Thing) {
        guard thing.isLive else { return }
        let ref = thing.sourceRef
        let title = TokensAsk.name(of: thing.title)
        if let ref {
            TokenWatchOrder.shared.remove(ref)
            PriceAlertStore.shared.removeAll(ref: ref, context: modelContext)
        }
        SpotlightIndex.remove(ids: [thing.id])
        modelContext.delete(thing)
        modelContext.saveHonestly()
        DSHaptic.tap()
        chrome.flash(String(localized: "Stopped following \(title)"))
    }

    /// Moves a row to the top of "My order", switching to it (prd §1081): a
    /// row moved to the top of a list sorted by movers would not stay there.
    func moveToTop(_ thing: Thing, in visible: [Thing]) {
        guard thing.isLive, let ref = thing.sourceRef else { return }
        let ordered = TokenWatchOrder.shared.apply(marketsWatches(visible), sourceRef: \.sourceRef,
                                                   change24h: Self.watchChange)
        var refs = ordered.compactMap(\.sourceRef).filter { $0 != ref }
        refs.insert(ref, at: 0)
        TokenWatchOrder.shared.saveManual(refs)
        withAnimation(DS.Motion.standard) { TokenWatchOrder.shared.setMode(.manual) }
        DSHaptic.tap()
    }
}

extension TokenWatchSortMode {
    /// The sort menu's own word, short enough for the list's head.
    var short: String {
        switch self {
        case .movers: String(localized: "Movers")
        case .manual: String(localized: "My order")
        case .recent: String(localized: "Newest")
        }
    }
}
