import SwiftUI

/// **THE WATCHLIST ON THE WALLET (prd §1632).** Yours, apart from Following:
/// open on Home under the doors (five tokens, then "All N tokens"), every
/// token on its page, and one token's price, chart and what you hold on its
/// own. The store is `Watchlist`, the prices `WatchlistPrices`, the search
/// `WatchTokenSheet`.
extension FeedScreen {

    /// Home draws it on All and on Yours, never on Following or with an app
    /// picked: it is no account's (prd §1632 item 2, §1491's rule).
    var walletWatchlistShows: Bool {
        guard !walletOnFollowing, selectedSeat == nil else { return false }
        if walletOnAll { return true }
        guard let yours = YourAccountDemo.shownAddress, let scope = chrome.walletScope else { return false }
        return WalletWatch.sameAddress(scope, yours)
    }

    /// What your own account holds, by symbol, in dollars: the line a
    /// watched token you hold wears. Your Casberi account only (§1526: only
    /// it is yours), never a wallet you follow.
    var walletHeldSymbols: [String: Double] {
        var out: [String: Double] = [:]
        for position in portfolio?.positions ?? [] {
            let mine = position.holders.filter { YourAccountDemo.isYours($0.address) }.reduce(0) { $0 + $1.usd }
            if mine > 0 { out[position.symbol.uppercased(), default: 0] += mine }
        }
        return out
    }

    /// What the Watch a token tray offers before you type: each holding of
    /// your own account, largest first, with the ids it can be watched under
    /// (`WatchlistRules.holdingIDs`), so a tap watches what you hold rather
    /// than whatever a search finds wearing its ticker.
    var walletHeldTokens: [WatchTokenSheet.Held] {
        var usd: [String: Double] = [:]
        var contracts: [String: [(key: String, usd: Double)]] = [:]
        var route: [String: String] = [:]
        for position in portfolio?.positions ?? [] {
            let mine = position.holders.filter { YourAccountDemo.isYours($0.address) }.reduce(0) { $0 + $1.usd }
            guard mine > 0 else { continue }
            let symbol = position.symbol.uppercased()
            usd[symbol, default: 0] += mine
            contracts[symbol, default: []] += position.parts
                .filter { YourAccountDemo.isYours($0.holder) }
                .map { (key: $0.key, usd: $0.usd) }
            if route[symbol] == nil, let r = position.route { route[symbol] = r }
        }
        return usd.sorted { $0.value > $1.value }.map { symbol, dollars in
            let keys = Dictionary((contracts[symbol] ?? []).map { ($0.key, $0.usd) }, uniquingKeysWith: +)
                .sorted { $0.value > $1.value }
                .map(\.key)
            return WatchTokenSheet.Held(
                symbol: symbol, usd: dollars,
                ids: WatchlistRules.holdingIDs(symbol: symbol, contracts: keys, route: route[symbol],
                                               coingecko: MainnetPrices.ids,
                                               llamaChains: DefiLlamaPrices.chainKey))
        }
    }

    // MARK: - Home

    /// **ONE DOOR, LIKE PERMISSIONS (prd §1632 item 2, user: "the watchlist
    /// could be a row like permissions … and show an up down percentage of
    /// the change … that would keep home clean").** It trails the day's
    /// biggest mover in its ink ("HYPE −4.6%"), or the count when nothing
    /// moved; nothing watched, the verb, which opens the search at once.
    @ViewBuilder
    var walletWatchlistHomeSection: some View {
        let tokens = Watchlist.shared.tokens
        walletDoorsSection {
            if tokens.isEmpty {
                walletDoor(.watchlist, name: String(localized: "Watch a token"),
                           act: { feedSheet = .watchToken })
            } else if let mover = WatchlistRules.biggestMover(tokens, quotes: WatchlistPrices.shared.quotes) {
                walletDoor(.watchlist, word: "\(mover.symbol) \(mover.change.words)",
                           wordTone: mover.change.tone == .up ? DS.confirmInk : DS.destructiveInk)
            } else {
                walletDoor(.watchlist, figure: "\(tokens.count)")
            }
        }
        .task(id: tokens.map(\.id)) { await WatchlistPrices.shared.refreshIfStale(tokens) }
    }

    // MARK: - The Watchlist page

    @ViewBuilder
    var walletWatchlistPage: some View {
        let tokens = Watchlist.shared.tokens
        let held = walletHeldSymbols
        Section {
            DSPushRow(title: Text("Watch a token"), tint: DS.pickInk, opens: false) {
                DSHaptic.selection()
                feedSheet = .watchToken
            } leading: {
                walletDoorLead(ScopeTileGlyph.new)
            }
            .walletListRow()
            ForEach(tokens) { token in
                watchlistRow(token, held: held)
            }
        }
        .task(id: tokens.map(\.id)) { await WatchlistPrices.shared.refreshIfStale(tokens) }
    }

    // MARK: - One token

    @ViewBuilder
    var walletWatchedTokenPage: some View {
        if let token = Watchlist.shared.token(chrome.watchedTokenID) {
            let held = walletHeldSymbols[token.symbol.uppercased()]
            Section {
                DSFeedRow(name: String(localized: "You hold"), trailingBesideLine: true) {
                    EmptyView()
                } trailing: {
                    walletRowFigure(held.map(WalletValue.payment) ?? String(localized: "None"),
                                    tone: held == nil ? DS.textSecondary : DS.textPrimary)
                }
                .walletListRow()
                DSFeedRow(name: WatchlistRules.network(of: token.id) == nil
                                ? String(localized: "Coin") : String(localized: "Network"),
                          trailingBesideLine: true) {
                    EmptyView()
                } trailing: {
                    walletRowFigure(WatchlistRules.line(for: token), tone: DS.textSecondary)
                }
                .walletListRow()
            }
            Section {
                DSPushRow(title: Text("Stop watching"), tint: DS.pickInk, opens: false) {
                    DSHaptic.selection()
                    stopWatching(token)
                } leading: {
                    walletDoorLead("minus")
                }
                .walletListRow()
            }
        } else {
            walletSkeletonRowsSection
        }
    }

    // MARK: - The boxes

    @ViewBuilder
    func walletWatchlistFigure(_ section: WalletSection) -> some View {
        if section == .watchedToken, let token = Watchlist.shared.token(chrome.watchedTokenID) {
            TokenChartView(memoryKey: "watch.range.\(token.id)",
                           fetch: { (range: TokenRange) in
                               // The demo reaches nothing (§217): its own invented curve.
                               if DemoMode.isActive { return await WatchlistPrices.demoChart(id: token.id, range: range) }
                               return await WatchlistPrices.chart(id: token.id, range: range)
                           },
                           hero: true,
                           object: (name: token.name, symbol: token.symbol)) {
                EmptyView()
            }
            .environment(\.priceBoxed, true)
            .id(token.id)
        } else {
            let tokens = Watchlist.shared.tokens
            DSFigureReading(number: "\(tokens.count)",
                            caption: watchlistCaption(tokens.count))
        }
    }

    /// "tokens you watch", and when the prices are older than the window,
    /// when they were read (prd §1632 item 8).
    private func watchlistCaption(_ count: Int) -> String {
        let words = count == 1 ? String(localized: "token you watch") : String(localized: "tokens you watch")
        let prices = WatchlistPrices.shared
        guard count > 0, let at = prices.readAt,
              WatchlistRules.isStale(readAt: at, now: .now) else { return words }
        return words + " · " + String(localized: "prices from \(at.formatted(date: .omitted, time: .shortened))")
    }

    // MARK: - The row

    /// The ticker, under it what you hold or where it lives, the price over
    /// the day's change; a tap opens its page, the long press holds Move to
    /// top and Stop watching.
    func watchlistRow(_ token: WatchedToken, held: [String: Double]) -> some View {
        let quote = WatchlistPrices.shared.quotes[token.id]
        let line = held[token.symbol.uppercased()].map {
            String(localized: "You hold \(WalletValue.payment($0))")
        } ?? WatchlistRules.line(for: token)
        return Button {
            DSHaptic.selection()
            chrome.watchedTokenID = token.id
            chrome.walletSection = .watchedToken
        } label: {
            // The day's change rides the line, in its ink, so the row keeps
            // the one 44pt head every Wallet row has (§1482).
            DSFeedRow(name: token.symbol, line: watchlistLine(line, change: quote?.change)) {
                AssetMark(name: token.symbol, size: DS.Face.row)
            } trailing: {
                walletRowFigure(quote.map { PriceCommentary.money($0.price) } ?? "—",
                                tone: quote == nil ? DS.textTertiary : DS.textPrimary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .contextMenu {
            if Watchlist.shared.tokens.first?.id != token.id {
                Button { Watchlist.shared.moveToTop(token.id) } label: {
                    Label(String(localized: "Move to top"), systemImage: "arrow.up.to.line")
                }
            }
            Button(role: .destructive) { stopWatching(token) } label: {
                Label(String(localized: "Stop watching"), systemImage: "minus.circle")
            }
        }
        .walletListRow()
    }

    /// "Bitcoin · +0.3%": the change green or red, grey with no sign when it
    /// rounds to zero (§83).
    private func watchlistLine(_ words: String, change: Double?) -> Text {
        guard let change else { return Text(verbatim: words) }
        let c = WatchlistRules.change(change)
        let ink = c.tone == .up ? DS.confirmInk : c.tone == .down ? DS.destructiveInk : DS.textSecondary
        return Text(verbatim: words + " · ") + Text(verbatim: c.words).foregroundStyle(ink)
    }

    func stopWatching(_ token: WatchedToken) {
        Watchlist.shared.stopWatching(token.id)
        chrome.flash(String(localized: "Stopped watching \(token.symbol)"))
        if chrome.walletSection == .watchedToken, chrome.watchedTokenID == token.id {
            chrome.walletSection = .watchlist
            chrome.watchedTokenID = nil
        }
    }
}
