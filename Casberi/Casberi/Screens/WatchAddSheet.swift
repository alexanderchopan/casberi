import SwiftUI
import SwiftData

/// MARKETS' ADD (prd §1081): find a token or a stock and keep it, one tap a
/// star, without leaving the room.
///
/// Before you type, what the app already knows you care about: what your
/// Wallet holds that you don't watch yet, the tickers your feed keeps saying,
/// and what you searched for last. As you type, tokens (each naming its chain
/// and its liquidity, so the real one stands out from a copy wearing its
/// name) and then stocks. The field sits at the bottom, on glass, where the
/// thumb is (prd §752). The sheet stays open, so you can keep several.
///
/// Optional environment only: on Mac Catalyst a sheet's content is evaluated
/// where the presenter's `.environment` has not reached (prd §872).
struct WatchAddSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ShellChrome.self) private var chrome: ShellChrome?
    @Environment(BridgeStore.self) private var store: BridgeStore?

    @State private var query = ""
    @State private var tokens: [TokenWatch.Resolved] = []
    @State private var stocks: [StockWatch.Resolved] = []
    @State private var searching = false
    @State private var chain: String? = nil
    @State private var stocksOnly = false
    @State private var watched: Set<String> = []
    @State private var watchedSymbols: Set<String> = []
    @State private var fromWallet: [TokenWatch.Resolved] = []
    @State private var mentioned: [(symbol: String, count: Int)] = []
    @State private var recents: [String] = []
    @State private var justStarred: String? = nil
    @FocusState private var fieldFocused: Bool

    private static let recentsKey = "markets.add.recents"

    var body: some View {
        DSTray(title: String(localized: "Watch"), height: 640, detents: [.large]) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        suggestions
                    } else {
                        results
                    }
                }
                .padding(.bottom, 96)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) { field }
        }
        .task { await loadSuggestions() }
        .task(id: query) { await search() }
        .onAppear { fieldFocused = true }
    }

    // MARK: - The field, at the bottom on glass

    private var field: some View {
        HStack(spacing: DS.Space.s2) {
            Image(systemName: "magnifyingglass")
                .dsGlyph(.subhead)
                .foregroundStyle(DS.textSecondary)
            TextField(String(localized: "Name, ticker or address"), text: $query)
                .dsText(.body17)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($fieldFocused)
            if searching { DSSpinner(size: .small) }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .dsGlyph(.body)
                        .foregroundStyle(DS.textTertiary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(PressSpring())
                .accessibilityLabel(Text("Clear"))
            }
        }
        .padding(.leading, DS.Space.s4)
        .padding(.trailing, DS.Space.s1)
        .frame(height: 52)
        .dsGlass(cornerRadius: 26)
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s2)
    }

    // MARK: - Before you type

    @ViewBuilder private var suggestions: some View {
        let wallet = fromWallet.filter { !watched.contains(ref(of: $0)) }
        if !wallet.isEmpty {
            head(String(localized: "From your Wallet"))
            ForEach(wallet) { token in tokenRow(token) }
        }
        if !mentioned.isEmpty {
            head(String(localized: "In your feed"))
            ForEach(mentioned, id: \.symbol) { item in
                Button {
                    query = item.symbol
                } label: {
                    HStack(spacing: DS.Space.s3) {
                        WatchFace(url: nil, lettered: item.symbol)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: "$\(item.symbol)").dsText(.body17).foregroundStyle(DS.textPrimary)
                            Text(item.count == 1 ? String(localized: "In 1 post this week")
                                                 : String(localized: "In \(item.count) posts this week"))
                                .dsText(.subhead12).foregroundStyle(DS.textTertiary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "magnifyingglass").dsGlyph(.subhead).foregroundStyle(DS.tint)
                    }
                    .frame(minHeight: 60)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPress())
                .padding(.horizontal, DS.Space.s4)
            }
        }
        if !recents.isEmpty {
            head(String(localized: "Recent"))
            ForEach(recents, id: \.self) { recent in
                Button {
                    query = recent
                } label: {
                    HStack(spacing: DS.Space.s3) {
                        Image(systemName: "clock.arrow.circlepath")
                            .dsGlyph(.subhead).foregroundStyle(DS.textTertiary)
                            .frame(width: DS.Face.rowCircle)
                        Text(verbatim: recent).dsText(.body17).foregroundStyle(DS.textPrimary)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPress())
                .padding(.horizontal, DS.Space.s4)
            }
        }
        if wallet.isEmpty && mentioned.isEmpty && recents.isEmpty {
            footnote
        }
    }

    /// The sheet's one explaining sentence (prd §748), whichever it is now.
    private var footnote: some View {
        let text: Text = if DemoMode.isActive && !query.isEmpty {
            Text("Search works once you leave the demo.")
        } else if query.isEmpty {
            Text("Search by name, ticker, or paste a contract address on any chain.")
        } else {
            Text("Nothing by that name. Try a ticker, or paste the contract address.")
        }
        return DSFootnote(text)
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, DS.Space.s4)
    }

    // MARK: - As you type

    @ViewBuilder private var results: some View {
        // The index first (prd §1082): a company, its ticker, or an app it
        // makes — "slack" finds Salesforce — instant, from the catalogue.
        let indexHits = Array(MarketsIndex.search(query, in: TokensScope.everyCompany.map(MarketsWatch.entry))
            .prefix(5))
        let byName = Dictionary(TokensScope.everyCompany.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        let companies = indexHits.compactMap { byName[$0.name] }
        if !companies.isEmpty {
            head(String(localized: "Behind your apps"))
            ForEach(companies) { company in
                let on = company.listing.ticker.map { watchedSymbols.contains($0.uppercased()) } ?? false
                IndexRow(company: company, apps: company.seats,
                         quote: CompanyQuotes.shared.quote(company.listing), watched: on,
                         star: company.listing == .unlisted ? nil : { toggle(company: company, on: on) })
                    .padding(.horizontal, DS.Space.s4)
            }
        }
        let chains = Array(Set(tokens.map(\.chain))).sorted()
        let shownTokens = stocksOnly ? [] : tokens.filter { chain == nil || $0.chain == chain }
        let shownStocks = chain == nil ? stocks : []
        if !shownTokens.isEmpty || chains.count > 1 {
            HStack {
                head(String(localized: "Tokens"))
                Spacer(minLength: 0)
                if chains.count > 1 || !stocks.isEmpty {
                    filterMenu(chains)
                        .padding(.trailing, DS.Space.s4)
                }
            }
            ForEach(shownTokens) { token in tokenRow(token) }
        }
        if !shownStocks.isEmpty {
            head(String(localized: "Stocks"))
            ForEach(shownStocks) { stock in stockRow(stock) }
        }
        if DemoMode.isActive || (!searching && tokens.isEmpty && stocks.isEmpty && companies.isEmpty) {
            footnote
        }
    }

    private func filterMenu(_ chains: [String]) -> some View {
        Menu {
            Button {
                chain = nil; stocksOnly = false
            } label: {
                if chain == nil && !stocksOnly { Label("All chains", systemImage: "checkmark") }
                else { Text("All chains") }
            }
            ForEach(chains, id: \.self) { c in
                Button {
                    chain = c; stocksOnly = false
                } label: {
                    if chain == c { Label(Self.chainName(c), systemImage: "checkmark") }
                    else { Text(Self.chainName(c)) }
                }
            }
            if !stocks.isEmpty {
                Button {
                    chain = nil; stocksOnly = true
                } label: {
                    if stocksOnly { Label("Stocks only", systemImage: "checkmark") }
                    else { Text("Stocks only") }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(stocksOnly ? String(localized: "Stocks only")
                     : chain.map(Self.chainName) ?? String(localized: "All chains"))
                    .dsText(.body17)
                Image(systemName: "chevron.down").dsGlyph(.caption)
            }
            .foregroundStyle(DS.tint)
            .frame(minHeight: 44)
        }
    }

    private func head(_ title: String) -> some View {
        Text(title)
            .dsText(.label12)
            .foregroundStyle(DS.textTertiary)
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, DS.Space.s4)
            .padding(.bottom, DS.Space.s1)
    }

    // MARK: - Rows

    private func tokenRow(_ token: TokenWatch.Resolved) -> some View {
        let key = ref(of: token)
        let line = [Self.chainName(token.chain),
                    token.liquidityUsd.map { String(localized: "\(TokenStats.compact($0)) liquidity") }
                        ?? token.marketCap.map { String(localized: "\(TokenStats.compact($0)) cap") }]
            .compactMap(\.self).joined(separator: " · ")
        return resultRow(id: key, face: WatchFace(url: token.imageURL, lettered: token.symbol),
                         name: token.name, line: line,
                         price: token.priceUsd.flatMap(Double.init), change: token.change24h,
                         label: "\(token.name) on \(Self.chainName(token.chain))") {
            toggle(token: token)
        }
    }

    private func stockRow(_ stock: StockWatch.Resolved) -> some View {
        let key = StockWatch.symbolRef(stock.symbol)
        let quote = CompanyQuotes.shared.quote(.stock(stock.symbol))
        let line = [stock.symbol, stock.exchange.capitalized,
                    quote?.marketCap.map { String(localized: "\(TokenStats.compact($0)) cap") }]
            .compactMap(\.self).joined(separator: " · ")
        return resultRow(id: key,
                         face: WatchFace(url: StockWatch.logoURL(stock.symbol), lettered: stock.symbol,
                                         onWhite: true),
                         name: stock.title, line: line,
                         price: quote?.price, change: quote?.change, label: stock.title) {
            toggle(stock: stock)
        }
    }

    private func resultRow(id: String, face: WatchFace, name: String, line: String,
                           price: Double?, change: Double?, label: String,
                           toggle: @escaping () -> Void) -> some View {
        let on = watched.contains(id)
        return HStack(spacing: DS.Space.s3) {
            face
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: name).dsText(.body17).fontWeight(.semibold)
                    .foregroundStyle(DS.textPrimary).lineLimit(1)
                Text(verbatim: line).dsText(.subhead12).foregroundStyle(DS.textTertiary).lineLimit(1)
            }
            Spacer(minLength: DS.Space.s2)
            VStack(alignment: .trailing, spacing: 1) {
                if let price {
                    Text(TokenChartStyle.priceText(price))
                        .dsText(.price17).monospacedDigit().foregroundStyle(DS.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                if let change {
                    let flat = TokenChartStyle.isFlat(change)
                    Text(TokenChartStyle.changeText(change))
                        .dsText(.subhead12).fontWeight(.semibold).monospacedDigit()
                        .foregroundStyle(flat ? DS.textTertiary : (change > 0 ? DS.confirmInk : DS.destructiveInk))
                }
            }
            Button(action: toggle) {
                Image(systemName: on ? "star.fill" : "star")
                    .dsGlyph(.title, weight: .regular)
                    .foregroundStyle(on ? DS.brand : DS.textTertiary)
                    .symbolEffect(.bounce, value: justStarred == id)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressSpring())
            .accessibilityLabel(Text(on ? String(localized: "Stop watching \(label)")
                                        : String(localized: "Watch \(label)")))
            .accessibilityAddTraits(on ? .isSelected : [])
        }
        .frame(minHeight: 64)
        .padding(.horizontal, DS.Space.s4)
    }

    // MARK: - Keeping

    private func ref(of token: TokenWatch.Resolved) -> String {
        "tokens:\(token.chain):\(token.address.lowercased())"
    }

    private func toggle(company: CompanyPacks.Company, on: Bool) {
        guard let ticker = company.listing.ticker?.uppercased() else { return }
        if on {
            MarketsWatch.unwatch(company, context: modelContext)
            watchedSymbols.remove(ticker)
            DSHaptic.tap()
            return
        }
        Task {
            switch await MarketsWatch.watch(company, context: modelContext) {
            case .success(let thing):
                watchedSymbols.insert(ticker)
                if let ref = thing.sourceRef { landed(key: ref, thing: thing) }
            case .failure(let why):
                DSHaptic.failure()
                chrome?.flash(why.message)
            }
        }
    }

    private func toggle(token: TokenWatch.Resolved) {
        let key = ref(of: token)
        if watched.contains(key) {
            remove(ref: key)
            return
        }
        guard let thing = TokenWatch.add(token, context: modelContext) else { return }
        landed(key: key, thing: thing)
    }

    private func toggle(stock: StockWatch.Resolved) {
        let key = StockWatch.symbolRef(stock.symbol)
        if watched.contains(key) {
            remove(ref: key)
            return
        }
        guard let thing = StockWatch.add(stock, context: modelContext) else { return }
        landed(key: key, thing: thing)
    }

    /// The save lands (prd §1081): the star fills with a bounce and the
    /// success buzz, and the toast names it with an Undo.
    private func landed(key: String, thing: Thing) {
        watched.insert(key)
        justStarred = key
        DSHaptic.success()
        remember(query)
        if let store { TokenWatch.registerBridge(store: store, context: modelContext) }
        let name = TokensAsk.name(of: thing.title)
        chrome?.flash(String(localized: "Watching \(name)"),
                      action: .init(label: String(localized: "Undo")) { [key] in remove(ref: key) })
    }

    private func remove(ref key: String) {
        let source = TokenWatch.source
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate {
            $0.source == source && $0.sourceRef == key
        })
        for thing in (try? modelContext.fetch(descriptor)) ?? [] where thing.isLive {
            SpotlightIndex.remove(ids: [thing.id])
            modelContext.delete(thing)
        }
        modelContext.saveHonestly()
        TokenWatchOrder.shared.remove(key)
        PriceAlertStore.shared.removeAll(ref: key)
        watched.remove(key)
        DSHaptic.tap()
    }

    // MARK: - Reading

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let hits = MarketsIndex.search(q, in: TokensScope.everyCompany.map(MarketsWatch.entry)).prefix(5)
        let names = Set(hits.map(\.name))
        Task { await CompanyQuotes.shared.load(TokensScope.everyCompany.filter { names.contains($0.name) }) }
        // The demo reaches nothing (its pour is not your things to add to).
        guard !q.isEmpty, !DemoMode.isActive else {
            tokens = []; stocks = []; searching = false
            return
        }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        searching = true
        async let t = TokenWatch.search(q, limit: 8)
        async let s = StockWatch.search(q, limit: 4)
        let (foundTokens, foundStocks) = await (t, s)
        guard !Task.isCancelled else { return }
        tokens = foundTokens
        stocks = foundStocks
        searching = false
        if let c = chain, !foundTokens.contains(where: { $0.chain == c }) { chain = nil }
        let companies = foundStocks.map {
            CompanyPacks.Company(name: $0.title, listing: .stock($0.symbol), seats: [])
        }
        await CompanyQuotes.shared.load(companies)
    }

    private func loadSuggestions() async {
        let source = TokenWatch.source
        let all = (try? modelContext.fetch(FetchDescriptor<Thing>(predicate: #Predicate {
            $0.source == source
        }))) ?? []
        let live = all.filter(\.isLive)
        watched = Set(live.compactMap(\.sourceRef))
        watchedSymbols = Set(live.compactMap { $0.authorHandle?.uppercased() })
        recents = UserDefaults.standard.data(forKey: Self.recentsKey)
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        mentioned = mentionedInFeed()
        // What the Wallet holds and you don't watch: the three biggest,
        // resolved by contract to the exact token on its chain.
        guard !DemoMode.isActive else { return }
        let holdings = await WalletIngest.lastKnownHoldings()
            .filter { $0.contract != nil }
            .prefix(6)
        var found: [TokenWatch.Resolved] = []
        for holding in holdings where found.count < 3 {
            guard let contract = holding.contract else { continue }
            let match = await TokenWatch.search(contract, limit: 3).first {
                $0.address.lowercased() == contract.lowercased()
            }
            if let match, !watched.contains(ref(of: match)) { found.append(match) }
        }
        fromWallet = found
    }

    /// The tickers your feed said this week (`$PEPE`), most said first, not
    /// counting what you already watch. A ticker is only a name, so a tap
    /// searches it rather than watching a guess.
    private func mentionedInFeed() -> [(symbol: String, count: Int)] {
        var d = FetchDescriptor<Thing>(sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        d.fetchLimit = 400
        let weekAgo = Date.now.addingTimeInterval(-7 * 86_400)
        let recent = ((try? modelContext.fetch(d)) ?? []).filter {
            $0.isLive && $0.capturedAt > weekAgo && $0.source != TokenWatch.source
        }
        var counts: [String: Int] = [:]
        let pattern = /\$([A-Za-z][A-Za-z0-9]{1,9})\b/
        for thing in recent {
            let text = [thing.title, thing.postText ?? ""].joined(separator: " ")
            var seen = Set<String>()
            for match in text.matches(of: pattern) {
                let symbol = String(match.1).uppercased()
                guard seen.insert(symbol).inserted, !watchedSymbols.contains(symbol) else { continue }
                counts[symbol, default: 0] += 1
            }
        }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(3).map { ($0.key, $0.value) }
    }

    private func remember(_ raw: String) {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        recents = Array(([q] + recents.filter { $0.caseInsensitiveCompare(q) != .orderedSame }).prefix(5))
        if let data = try? JSONEncoder().encode(recents) {
            DefaultsWrite.set(data, forKey: Self.recentsKey)
        }
    }

    static func chainName(_ id: String) -> String {
        switch id {
        case "ethereum": "Ethereum"
        case "solana":   "Solana"
        case "base":     "Base"
        case "arbitrum": "Arbitrum"
        case "bsc":      "BNB Chain"
        case "polygon":  "Polygon"
        case "optimism": "Optimism"
        case "avalanche": "Avalanche"
        case "hyperevm": "HyperEVM"
        default:         id.prefix(1).uppercased() + id.dropFirst()
        }
    }
}
