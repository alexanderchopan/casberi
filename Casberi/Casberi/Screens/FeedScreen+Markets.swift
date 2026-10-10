import SwiftUI
import SwiftData

// THE MARKETS ROOM (prd §1081, §1171b): the categories in the box, the
// watchlist under one sort menu, and Watchlist · Alerts · New on the bar.
extension FeedScreen {
    /// The watched rows: Markets' rows that are not a fired alert.
    func marketsWatches(_ visible: [Thing]) -> [Thing] {
        visible.live.filter { !PriceAlertStore.isAlertRow($0) }
    }

    /// THE BOX IS THE CATEGORIES (prd §1138, §1171b): A–Z, a glyph and a
    /// name each, no figure and no colour (user: "the categories w/ no
    /// numbers, just their glyph and name"); Watchlist and Alerts ride the bar.
    /// Pressing one lists it below; the box never moves. It replaced the
    /// watchlist's heat map (§1081) and the category bar.
    var marketsTilesSection: some View {
        // Two across, each glyph and its word on one line, as Settings'
        // counts stand (prd §1167, user: "organize the markets header in
        // same way you did settings").
        // On the phone Watchlist and Alerts stand in the box (prd §1209a):
        // the bar that held them is the band's search now, which adds.
        let tiles = DSScopeDock<TokensScope>.atBottom(roomSizeClass)
            ? [TokensScope.watchlist, .alerts] + TokensScope.box : TokensScope.box
        return Section {
            DSCountGrid(items: tiles.count) {
                ForEach(tiles) { tile in
                    DSCountTile(count: nil, label: tile.label, glyph: tile.glyph,
                                isOn: tile == chrome.tokensScope, inline: true) { pickTokensScope(tile) }
                }
            }
            .feedRowBackground()
            .listRowInsets(.init(top: DS.Space.s2, leading: DSRoomChassis.inset,
                                 bottom: DSRoomChassis.leadGap, trailing: DSRoomChassis.inset))
            .listRowSeparator(.hidden)
        }
        // The tray's search can open a company or New from any room (prd
        // §1185), so it asks; the room raises once it stands. The box stands
        // on every Markets tile, so the ask is heard whichever is picked.
        .onChange(of: chrome.marketsRequest, initial: true) { _, request in
            guard let request, isActive else { return }
            chrome.marketsRequest = nil
            switch request {
            case .company(let company): openCompany(company)
            case .lookUp: feedSheet = .watchAdd
            }
        }
    }

    /// "Watchlist" and its order, one menu, on the rows' line (prd §1081:
    /// the three chips on the account page became this).
    var marketsListHead: some View {
        Section {
            HStack {
                Text("Following")
                    .dsText(.heading20)
                    .foregroundStyle(DS.textPrimary)
                Spacer(minLength: 0)
                Menu {
                    ForEach(TokenWatchSortMode.allCases, id: \.self) { mode in
                        Button {
                            withAnimation(DS.Motion.standard) { TokenWatchOrder.shared.setMode(mode) }
                        } label: {
                            if TokenWatchOrder.shared.mode == mode {
                                Label(mode.label, systemImage: "checkmark")
                            } else {
                                Text(mode.label)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(TokenWatchOrder.shared.mode.short).dsText(.body17)
                        Image(systemName: "chevron.down").dsGlyph(.caption)
                    }
                    .foregroundStyle(DS.tint)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(Text("Order: \(TokenWatchOrder.shared.mode.label)"))
            }
            .feedRowBackground()
            .listRowInsets(.init(top: DS.Space.s2, leading: DSRoomChassis.rowInset,
                                 bottom: 0, trailing: DSRoomChassis.rowInset))
            .listRowSeparator(.hidden)
        }
    }

    /// The Watchlist tile: the box, the tiles where the rail stands, the
    /// list's head, then the rows in the chosen order.
    @ViewBuilder
    func marketsWatchlistSections(_ visible: [Thing], nextEventID: UUID?) -> some View {
        let watches = marketsWatches(visible)
        marketsTilesSection
        // You's tiles under the box (prd §1136 item 1); Search rides the
        // floating bar on the phone, or the strip below beside the rail.
        youTilesSection(.markets)
        tokensInlineTiles
        // THE VERB LEADS THE LIST (prd §1230), as every Following and
        // Subscriptions list's does.
        Section {
            DSDoorRow(icon: "plus", title: Text("Follow a company")) {
                feedSheet = .watchAdd
            }
            .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.rowInset,
                                      bottom: 0, trailing: DSRoomChassis.rowInset))
            .feedRowBackground()
            .listRowSeparator(.hidden)
        }
        if watches.count > 1 { marketsListHead }
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
        case "new", "add", "search": feedSheet = .watchAdd
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
        let watches = marketsWatches(visible)
        marketsTilesSection
        youTilesSection(.markets)
        tokensInlineTiles
        let byRef = Dictionary(watches.compactMap { t in t.sourceRef.map { ($0, t) } },
                               uniquingKeysWith: { a, _ in a })
        let alerts = PriceAlertStore.shared.alerts.filter { byRef[$0.ref] != nil }
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
        let fired = visible.live.filter(PriceAlertStore.isAlertRow)
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
                          onWhite: watched.flatMap { StockWatch.symbol(of: $0) } != nil)
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
                PriceAlertStore.shared.remove(alert.id)
            } label: {
                Label("Delete alert", systemImage: "trash")
            }
        }
        .feedRowBackground()
        .listRowInsets(.init(top: Self.rowAir, leading: DSRoomChassis.rowInset,
                             bottom: Self.rowAir, trailing: DSRoomChassis.rowInset))
        .listRowSeparator(.hidden)
    }

    // MARK: - The index (prd §1082)

    /// A category's companies as an index under the box's tiles: From your
    /// apps, Everything else and Not traded (`MarketsIndex.sections`), each row starred in one tap.
    @ViewBuilder
    func marketsIndexSections(_ scope: TokensScope, visible: [Thing]) -> some View {
        let pack = scope.pack
        let quotes = CompanyQuotes.shared
        let connected = connectedSeatNames
        let byName = Dictionary(pack.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        let split = MarketsIndex.sections(pack.map(MarketsWatch.entry), connected: connected)
        let watched = MarketsWatch.watchedTickers(visible)
        // The box is the tiles on every Markets page (prd §1138): the pack's
        // own heat map and its lede gave way to it.
        marketsTilesSection
            .task(id: scope.id) { await quotes.load(pack) }
        youTilesSection(.markets)
        tokensInlineTiles
        indexSection(String(localized: "From your apps"), split.yours, byName: byName,
                     connected: connected, watched: watched, watchAll: true)
        indexSection(split.yours.isEmpty ? scope.label : String(localized: "Everything else"),
                     split.rest, byName: byName, connected: connected, watched: watched, watchAll: false)
        indexSection(String(localized: "Not traded"), split.untraded, byName: byName,
                     connected: connected, watched: watched, watchAll: false)
    }

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
                HStack {
                    Text(title).dsText(.heading20).foregroundStyle(DS.textPrimary)
                    Spacer(minLength: 0)
                    if watchAll, unwatched.count > 1 {
                        Button {
                            watchAllCompanies(unwatched)
                        } label: {
                            Text("Follow all \(unwatched.count)").dsText(.body17)
                                .foregroundStyle(DS.tint)
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
                           closes: pulse?.closes ?? [],
                           line: marketsLine(thing, price: price, quoteCap: quote?.marketCap,
                                             pulse: pulse, stock: stock),
                           isStock: stock != nil,
                           glyph: stock.flatMap(WatchFace.systemMark(forTicker:)))
        if let stock {
            let company = CompanyPacks.Company(name: TokensAsk.name(of: thing.title),
                                               listing: .stock(stock), seats: [TokenWatch.source])
            row.task(id: stock) { await CompanyQuotes.shared.load([company]) }
        } else {
            row
        }
    }

    /// The one line a watched row says (`WatchLine`): your alert, what you
    /// hold, since you watched, then the market's facts.
    private func marketsLine(_ thing: Thing, price: Double?, quoteCap: Double?,
                             pulse: TokenPulse.Pulse?, stock: String?) -> WatchLine.Line? {
        let alert = thing.sourceRef.flatMap { PriceAlertStore.shared.lineAlert(for: $0) }
        let alertText: String? = alert.map { a in
            a.kind == .move ? String(localized: "a \(Int((a.target * 100).rounded()))% move")
                            : TokenChartStyle.priceText(a.target)
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

    /// Unwatches a row from its long press: its alerts go with it, and the
    /// toast can put it back (prd §1081).
    func unwatch(_ thing: Thing) {
        guard thing.isLive else { return }
        let ref = thing.sourceRef
        let title = TokensAsk.name(of: thing.title)
        if let ref {
            TokenWatchOrder.shared.remove(ref)
            PriceAlertStore.shared.removeAll(ref: ref)
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
