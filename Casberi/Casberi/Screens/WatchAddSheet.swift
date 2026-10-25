import SwiftUI
import SwiftData

/// MARKETS' FOLLOW (prd §1081, §1391, §1522): keep a company, a coin or a
/// stock, one tap a star, without leaving the room.
///
/// **THE TRAY IS THE PACKS, AND ITS FIELD ASKS THE MARKET (prd §1522,
/// user: "markets needs a search page … search bar"; amends §1391's "no
/// field").** Empty, it opens on what your Wallet holds that you don't follow
/// yet, then the eight packs as groups, the companies behind your apps first
/// in each, every traded one a row with its star. Typed, the packs give way
/// to what the words find in two groups, **Stocks** and **Tokens**: the
/// companies by name, ticker or an app they make (`MarketsIndex.matches`)
/// first, then what the market answers (`MarketsSearchRead`, §1467), five
/// each, then Show all — the page the tab bar's four rows could not be. The add flow keeps its field (§1171
/// item 5). The sheet stays open, so you can keep several.
///
/// Optional environment only: on Mac Catalyst a sheet's content is evaluated
/// where the presenter's `.environment` has not reached (prd §872).
struct WatchAddSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ShellChrome.self) private var chrome: ShellChrome?
    @Environment(BridgeStore.self) private var store: BridgeStore?

    @State private var watched: Set<String> = []
    @State private var watchedSymbols: Set<String> = []
    @State private var fromWallet: [TokenWatch.Resolved] = []
    @State private var justStarred: String? = nil
    @State private var query = ""
    @State private var market = MarketsSearchRead.Reading()
    /// The words `market` answers, so an older answer never stands under
    /// newer words.
    @State private var marketFor = ""
    /// The groups opened past their first five, for these words only.
    @State private var expanded: Set<Group> = []
    @FocusState private var fieldFocused: Bool

    private var words: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var asking: Bool { !words.isEmpty && marketFor != words }

    var body: some View {
        DSTray(title: String(localized: "Follow"), height: 640, detents: [.large], scrollsItself: true) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if words.isEmpty { packs } else { found }
                }
                .padding(.bottom, 96)
            }
            .scrollDismissesKeyboard(.interactively)
            .dsFindField {
                DSTraySearchField(placeholder: String(localized: "Coins, tokens, stocks, a contract"),
                                  text: $query, focus: $fieldFocused, searching: asking)
            }
        }
        .task { await loadSuggestions() }
        // The page is a search: the field takes the keyboard once the tray
        // has risen (a focus set during the rise is dropped).
        .task {
            try? await Task.sleep(for: .milliseconds(450))
            fieldFocused = true
        }
        // After a pause, once per words (§1467's read); a newer word cancels.
        .task(id: words) { await readMarket(words) }
        .onChange(of: words) { _, _ in expanded = [] }
    }

    // MARK: - What the words find (prd §1522)

    /// Two groups, Stocks then Tokens (user: "stocks and tokens"): a coin is
    /// a token and a company is its stock, so the groups say what you buy,
    /// never where the answer came from. Five each, then Show all.
    private enum Group: Hashable {
        case stocks, tokens

        var title: String {
            switch self {
            case .stocks: String(localized: "Stocks")
            case .tokens: String(localized: "Tokens")
            }
        }

        var glyph: String {
            switch self {
            case .stocks: "chart.line.uptrend.xyaxis"
            case .tokens: "circle.hexagongrid"
            }
        }
    }

    private enum Row: Identifiable {
        case company(CompanyPacks.Company)
        case market(MarketsSearchRead.Hit)

        var id: String {
            switch self {
            case .company(let company): "company:" + company.name
            case .market(let hit): "market:" + hit.ref
            }
        }
    }

    static let shownPerGroup = 5

    /// What the words found, by group: the index's companies first (a stock
    /// by its ticker, a coin-listed company by its coin), then the market's
    /// answer in §1467's order. A stock or a coin a company row already
    /// names stands once.
    private func rows(_ group: Group) -> [Row] {
        let companies = MarketsSearch.isAddress(words) ? [] : TokensScope.everyCompany.filter {
            $0.listing != .unlisted && MarketsIndex.matches(words, MarketsWatch.entry($0))
        }
        let tickers = Set(companies.compactMap { $0.listing.ticker?.uppercased() })
        let coins = Set(companies.compactMap { company -> String? in
            if case .token(_, let id) = company.listing { return id }
            return nil
        })
        let hits = marketFor == words ? market.hits : []
        switch group {
        case .stocks:
            let listed = companies.filter { if case .stock = $0.listing { true } else { false } }
            let stocks = hits.filter { hit in
                if case .stock(let symbol, _) = hit.kind { return !tickers.contains(symbol.uppercased()) }
                return false
            }
            return listed.map(Row.company) + stocks.map(Row.market)
        case .tokens:
            let listed = companies.filter { if case .token = $0.listing { true } else { false } }
            let tokens = hits.filter { hit in
                switch hit.kind {
                case .coin(let id, _): return !coins.contains(id)
                case .token: return true
                case .stock: return false
                }
            }
            return listed.map(Row.company) + tokens.map(Row.market)
        }
    }

    @ViewBuilder private var found: some View {
        let groups = [Group.stocks, .tokens].map { ($0, rows($0)) }
        ForEach(groups, id: \.0) { group, rows in
            if !rows.isEmpty {
                let open = expanded.contains(group) || rows.count <= Self.shownPerGroup + 1
                DSTrayGroup(group.title, glyph: group.glyph) {
                    ForEach(open ? rows : Array(rows.prefix(Self.shownPerGroup))) { row in rowView(row) }
                    if !open { showAll(group, count: rows.count) }
                }
            }
        }
        if marketFor == words, groups.allSatisfy({ $0.1.isEmpty }) {
            // The demo never asks the market (§1467), so it cannot say the
            // market has nothing (§83).
            Text(DemoMode.isActive ? String(localized: "The demo doesn’t ask the market")
                                   : String(localized: "Nothing in the market for “\(words)”"))
                .dsText(.body17)
                .foregroundStyle(DS.textTertiary)
                .padding(.horizontal, DS.Space.s4)
                .padding(.vertical, DS.Space.s4)
        }
    }

    @ViewBuilder private func rowView(_ row: Row) -> some View {
        switch row {
        case .company(let company):
            let on = company.listing.ticker.map { watchedSymbols.contains($0.uppercased()) } ?? false
            IndexRow(company: company,
                     apps: MarketsIndex.appsLine(MarketsWatch.entry(company), connected: connected),
                     quote: CompanyQuotes.shared.quote(company.listing), watched: on,
                     star: { toggle(company: company, on: on) })
                .padding(.horizontal, DS.Space.s4)
                .task { await CompanyQuotes.shared.load([company]) }
        case .market(let hit):
            marketRow(hit)
        }
    }

    /// "Show all 40 tokens", opening the group in place.
    private func showAll(_ group: Group, count: Int) -> some View {
        Button {
            DSHaptic.selection()
            withAnimation(DS.Motion.standard) { _ = expanded.insert(group) }
        } label: {
            HStack(spacing: DS.Space.s3) {
                Text(group == .stocks ? String(localized: "Show all \(count) stocks")
                                      : String(localized: "Show all \(count) tokens"))
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
                Spacer(minLength: DS.Space.s2)
                Image(systemName: "chevron.down")
                    .dsGlyph(.subhead)
                    .foregroundStyle(DS.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: DS.Hit.min)
            .padding(.horizontal, DS.Space.s4)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
    }

    private func marketRow(_ hit: MarketsSearchRead.Hit) -> some View {
        resultRow(id: hit.ref, face: WatchFace(url: hit.imageURL, lettered: hit.lettered, onWhite: hit.onWhite),
                  name: hit.name, line: hit.line, price: hit.price, change: hit.change, label: hit.name) {
            if watched.contains(hit.ref) {
                remove(ref: hit.ref)
            } else if let thing = MarketsSearchRead.follow(hit, context: modelContext) {
                landed(key: thing.sourceRef ?? hit.ref, thing: thing)
            }
        }
    }

    private func readMarket(_ asked: String) async {
        guard !asked.isEmpty else { return }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        let reading = await MarketsSearchRead.read(asked)
        guard !Task.isCancelled, words == asked else { return }
        market = reading
        marketFor = asked
    }

    // MARK: - The packs

    /// The apps you connected, by catalogue name: a company behind one leads
    /// its pack (`MarketsIndex.sections`).
    private var connected: Set<String> {
        Set(store?.bridges.filter { $0.status != .paused }.map(\.name) ?? [])
    }

    @ViewBuilder private var packs: some View {
        let wallet = fromWallet.filter { !watched.contains(ref(of: $0)) }
        if !wallet.isEmpty {
            DSTrayGroup(String(localized: "From your Wallet"), glyph: "wallet.bifold") {
                ForEach(wallet) { token in tokenRow(token) }
            }
        }
        let connected = self.connected
        ForEach(TokensScope.box) { scope in
            let pack = scope.pack
            let byName = Dictionary(pack.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
            let split = MarketsIndex.sections(pack.map(MarketsWatch.entry), connected: connected)
            // Yours first, then the rest; nothing untraded, since there is
            // nothing to follow there.
            let companies = (split.yours + split.rest).compactMap { byName[$0.name] }
            if !companies.isEmpty {
                DSTrayGroup(scope.label, glyph: scope.glyph) {
                    ForEach(companies) { company in
                        let on = company.listing.ticker.map { watchedSymbols.contains($0.uppercased()) } ?? false
                        IndexRow(company: company,
                                 apps: MarketsIndex.appsLine(MarketsWatch.entry(company), connected: connected),
                                 quote: CompanyQuotes.shared.quote(company.listing), watched: on,
                                 star: company.listing == .unlisted ? nil : { toggle(company: company, on: on) })
                            .padding(.horizontal, DS.Space.s4)
                    }
                }
                .task { await CompanyQuotes.shared.load(companies) }
            }
        }
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

    private func resultRow(id: String, face: WatchFace, name: String, line: String,
                           price: Double?, change: Double?, label: String,
                           toggle: @escaping () -> Void) -> some View {
        let on = watched.contains(id)
        return HStack(spacing: DS.Space.s3) {
            face
            VStack(alignment: .leading, spacing: 2) {
                // A market row's words wrap rather than cut (prd §1467): a
                // tiny price is long, and the name beside it was "Purple Pe…".
                Text(verbatim: name).dsText(.body17).fontWeight(.semibold)
                    .foregroundStyle(DS.textPrimary).lineLimit(2)
                Text(verbatim: line).dsText(.subhead12).foregroundStyle(DS.textTertiary).lineLimit(2)
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
                DSFollowMark(on: on, bounce: justStarred == id)
            }
            .buttonStyle(PressSpring())
            .accessibilityLabel(Text(on ? String(localized: "Stop following \(label)")
                                        : String(localized: "Follow \(label)")))
            .accessibilityAddTraits(on ? .isSelected : [])
        }
        // A wrapped name keeps air above and below (a one-line row is the
        // head height either way).
        .padding(.vertical, DS.Space.s2)
        .frame(minHeight: DSFeed.headHeight)
        .padding(.horizontal, DS.Space.s4)
    }

    // MARK: - Keeping

    /// The ref a token's follow lands under: a household coin's wrapped
    /// token is followed as the coin (prd §1250, `TokenWatch.add`).
    private func ref(of token: TokenWatch.Resolved) -> String { MarketsSearchRead.tokenRef(token) }

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
        landed(key: thing.sourceRef ?? key, thing: thing)
    }

    /// The save lands (prd §1081): the star fills with a bounce and the
    /// success buzz, and the toast names it with an Undo.
    private func landed(key: String, thing: Thing) {
        watched.insert(key)
        justStarred = key
        DSHaptic.success()
        if let store { TokenWatch.registerBridge(store: store, context: modelContext) }
        let name = TokensAsk.name(of: thing.title)
        chrome?.flash(String(localized: "Following \(name)"),
                      action: .init(label: String(localized: "Undo")) { [key] in remove(ref: key) })
    }

    private func remove(ref key: String) {
        MarketsWatch.unfollow(ref: key, context: modelContext)
        watched.remove(key)
        DSHaptic.tap()
    }

    // MARK: - Reading

    private func loadSuggestions() async {
        let source = TokenWatch.source
        let all = (try? modelContext.fetch(FetchDescriptor<Thing>(predicate: #Predicate {
            $0.source == source
        }))) ?? []
        let live = all.filter(\.isLive)
        watched = Set(live.compactMap(\.sourceRef))
        watchedSymbols = Set(live.compactMap { $0.authorHandle?.uppercased() })
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
