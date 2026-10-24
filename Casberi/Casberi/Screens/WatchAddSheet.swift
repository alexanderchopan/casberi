import SwiftUI
import SwiftData

/// MARKETS' FOLLOW (prd §1081, §1391): keep a company, a coin or a stock, one
/// tap a star, without leaving the room.
///
/// **THE TRAY IS THE PACKS (prd §1391, user: "we don't need search b/c we
/// have a tab bar w/ search").** It opens on what your Wallet holds that you
/// don't follow yet, then the eight packs as groups, the companies behind
/// your apps first in each, every traded one a row with its star; the
/// untraded are not listed, since there is nothing to follow. It has no
/// field: the tab bar's Search is the one place to look anything up (§1171,
/// §1185), and since §1467 that Search asks the market itself, so nothing is
/// handed here. The sheet stays open, so you can keep several.
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

    var body: some View {
        DSTray(title: String(localized: "Follow"), height: 640, detents: [.large], scrollsItself: true) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    packs
                }
                .padding(.bottom, 96)
            }
        }
        .task { await loadSuggestions() }
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
                DSFollowMark(on: on, bounce: justStarred == id)
            }
            .buttonStyle(PressSpring())
            .accessibilityLabel(Text(on ? String(localized: "Stop following \(label)")
                                        : String(localized: "Follow \(label)")))
            .accessibilityAddTraits(on ? .isSelected : [])
        }
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
