import SwiftUI
import SwiftData

// THE MARKETS ROOM (prd §1081): the day as a heat map in the box, the
// watchlist under one sort menu, the Alerts tile, and Add as the last tile.
extension FeedScreen {
    /// The watched rows: Markets' rows that are not a fired alert.
    func marketsWatches(_ visible: [Thing]) -> [Thing] {
        visible.live.filter { !PriceAlertStore.isAlertRow($0) }
    }

    /// A watched row's move for the span the box is on: the day from the
    /// pulse or quote every row already reads, a week or a month from
    /// `WatchRanges` once read.
    func marketsChange(_ thing: Thing) -> Double? {
        guard watchSpan != .day else { return Self.watchChange(thing) }
        return thing.sourceRef.flatMap { WatchRanges.shared.change(ref: $0, span: watchSpan) }
    }

    /// The box: the watchlist's span as a heat map, in the lead's exact
    /// geometry and on nothing (the tiles are the colour, prd §1081).
    @ViewBuilder
    func marketsHeatSection(_ watches: [Thing]) -> some View {
        let moves = watches.compactMap { thing -> (id: String, symbol: String, change: Double)? in
            guard let change = marketsChange(thing) else { return nil }
            let symbol = thing.authorHandle.flatMap { $0.isEmpty ? nil : $0 }
                ?? TokensAsk.symbol(of: thing.title)
            return (thing.id.uuidString, symbol, change)
        }
        let changes = moves.map(\.change)
        Section {
            WatchHeatBox(tiles: WatchHeat.tiles(moves),
                         up: changes.filter { !TokenChartStyle.isFlat($0) && $0 > 0 }.count,
                         down: changes.filter { !TokenChartStyle.isFlat($0) && $0 < 0 }.count,
                         watched: watches.count,
                         span: $watchSpan) { id in
                if let thing = watches.first(where: { $0.isLive && $0.id.uuidString == id }) {
                    openThing(thing)
                }
            }
            .frame(maxWidth: .infinity, minHeight: DSRoomChassis.leadBox,
                   maxHeight: DSRoomChassis.leadBox, alignment: .topLeading)
            // **IN THE WELL, AT EVERY ROOM'S HEIGHT (prd §1102, user: "the
            // markets card is not the same height as all the other screens").**
            // §1081 drew the map on nothing at the bare `leadBox`, 32pt short
            // of every other lead; it takes the head's well now.
            .dsRoomHeadBlock()
            .listRowBackground(Color.clear)
            .listRowInsets(.init(top: DS.Space.s2, leading: DSRoomChassis.inset,
                                 bottom: DSRoomChassis.leadGap, trailing: DSRoomChassis.inset))
            .listRowSeparator(.hidden)
        }
        .task(id: "\(watchSpan.rawValue)|\(watches.count)") {
            await WatchRanges.shared.load(watches, span: watchSpan)
        }
    }

    /// "Watchlist" and its order, one menu, on the rows' line (prd §1081:
    /// the three chips on the account page became this).
    var marketsListHead: some View {
        Section {
            HStack {
                Text("Watchlist")
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
            .listRowBackground(Color.clear)
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
        if !watches.isEmpty { marketsHeatSection(watches) }
        tokensInlineTiles
        if watches.count > 1 { marketsListHead }
        watchlistSection(watches, nextEventID: nextEventID)
            .task(id: watches.count) {
                held = await WalletIngest.lastKnownHeld()
                #if DEBUG
                marketsProbe()
                #endif
            }
    }

    #if DEBUG
    /// `-marketsScope alerts|all|<Category>|search` — land on a tile, or raise Search,
    /// at mount (prd §1081; NSLogs `marketsScope:`). Once per launch.
    private func marketsProbe() {
        guard !Self.marketsProbed,
              let raw = UserDefaults.standard.string(forKey: "marketsScope") else { return }
        Self.marketsProbed = true
        NSLog("[Casberi] marketsScope: %@", raw)
        switch raw {
        case "alerts":        chrome.tokensScope = .alerts
        case "add", "search": feedSheet = .watchAdd
        case "all":           chrome.tokensScope = .everything
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
        if !watches.isEmpty { marketsHeatSection(watches) }
        tokensInlineTiles
        let byRef = Dictionary(watches.compactMap { t in t.sourceRef.map { ($0, t) } },
                               uniquingKeysWith: { a, _ in a })
        let alerts = PriceAlertStore.shared.alerts.filter { byRef[$0.ref] != nil }
            .sorted { $0.createdAt > $1.createdAt }
        if alerts.isEmpty {
            Section {
                DSSkeletonRows(label: Text("No alerts yet."))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                DSFootnote(Text("Open something you follow to set an alert."))
                    .listRowBackground(Color.clear)
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
        .listRowBackground(Color.clear)
        .listRowInsets(.init(top: Self.rowAir, leading: DSRoomChassis.rowInset,
                             bottom: Self.rowAir, trailing: DSRoomChassis.rowInset))
        .listRowSeparator(.hidden)
    }

    // MARK: - The index (prd §1082)

    /// A category's companies, or all of them, as an index: the day's heat
    /// map of what trades, then From your apps, Everything else and Not
    /// traded (`MarketsIndex.sections`), each row starred in one tap.
    @ViewBuilder
    func marketsIndexSections(_ scope: TokensScope, visible: [Thing]) -> some View {
        let pack = scope.pack
        let quotes = CompanyQuotes.shared
        let connected = connectedSeatNames
        let byName = Dictionary(pack.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        let split = MarketsIndex.sections(pack.map(MarketsWatch.entry), connected: connected)
        let watched = MarketsWatch.watchedTickers(visible)
        let moves = pack.compactMap { company -> (id: String, symbol: String, change: Double)? in
            guard let ticker = company.listing.ticker,
                  let change = quotes.quote(company.listing)?.change else { return nil }
            return (company.name, ticker, change)
        }
        Group {
            if moves.isEmpty {
                ledeSection(CompanyPackLede(name: scope.label, companies: pack, quotes: quotes))
            } else {
                let changes = moves.map(\.change)
                Section {
                    WatchHeatBox(tiles: WatchHeat.tiles(moves),
                                 up: changes.filter { !TokenChartStyle.isFlat($0) && $0 > 0 }.count,
                                 down: changes.filter { !TokenChartStyle.isFlat($0) && $0 < 0 }.count,
                                 watched: pack.count, span: .constant(.day), showsSpans: false) { name in
                        if let company = byName[name] { openCompany(company) }
                    }
                    .frame(maxWidth: .infinity, minHeight: DSRoomChassis.leadBox,
                           maxHeight: DSRoomChassis.leadBox, alignment: .topLeading)
                    .dsRoomHeadBlock()   // the well, as the watchlist's (prd §1102)
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: DS.Space.s2, leading: DSRoomChassis.inset,
                                         bottom: DSRoomChassis.leadGap, trailing: DSRoomChassis.inset))
                    .listRowSeparator(.hidden)
                }
            }
        }
        .task(id: scope.id) { await quotes.load(pack) }
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
                .listRowBackground(Color.clear)
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
                    .listRowBackground(Color.clear)
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
                           change: marketsChange(thing),
                           closes: watchSpan == .day ? (pulse?.closes ?? []) : [],
                           line: marketsLine(thing, price: price, quoteCap: quote?.marketCap,
                                             pulse: pulse, stock: stock),
                           isStock: stock != nil)
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
