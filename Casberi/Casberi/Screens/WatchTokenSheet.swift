import SwiftUI

/// WATCH A TOKEN (prd §1632 item 4): the Wallet's Follow tray (`WalletFollowSheet`)
/// for tokens. Before you type, what your account holds and you don't watch
/// yet; as you type, a name or a ticker asks CoinGecko and a pasted contract
/// asks every chain, and only a priced token is offered. A tap watches it and
/// ticks the row; the tray stays open (§1164).
///
/// **A row says its own outcome (2026-11-01, user: "inactive plus signs").**
/// The tray opens with the keyboard up, and the toast stands 140pt above the
/// bottom edge, under the keyboard, so a flash from here is never seen. A
/// holding's plus turns to a spinner while it looks, to a tick when it lands,
/// and its line says "No price" when nothing prices it; a tap then tries again.
///
/// Optional environment only: on Mac Catalyst a sheet's content is evaluated
/// where the presenter's `.environment` has not reached (prd §872).
struct WatchTokenSheet: View {
    /// One holding of your own account: its dollars, and the ids it can be
    /// watched under, best first (`WatchlistRules.holdingIDs`).
    struct Held: Equatable {
        let symbol: String
        let usd: Double
        let ids: [String]
    }

    /// What your account holds, largest first (`walletHeldTokens`).
    let held: [Held]

    @Environment(ShellChrome.self) private var chrome: ShellChrome?

    @State private var query = ""
    @State private var found: [(token: WatchedToken, quote: WatchlistRules.Quote)] = []
    @State private var foundFor = ""
    @State private var searching = false
    @State private var justWatched: String? = nil
    /// Holdings being looked up, and the ones nothing priced, by symbol.
    @State private var looking: Set<String> = []
    @State private var unpriced: Set<String> = []
    /// Holdings watched while the tray is open: they stay, ticked (§1164).
    @State private var watchedHere: Set<String> = []
    @FocusState private var fieldFocused: Bool

    private var list: Watchlist { Watchlist.shared }
    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        DSTray(title: String(localized: "Watch a token"), height: 640, detents: [.large], scrollsItself: true) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if trimmed.isEmpty { before } else { typed }
                }
                .padding(.bottom, 96)
            }
            .scrollDismissesKeyboard(.interactively)
            .dsFindField { field }
        }
        .task(id: trimmed) { await search() }
        .onAppear {
            #if DEBUG
            // The sim draws no keyboard: `-watchlistSearch` types for it.
            if let words = UserDefaults.standard.string(forKey: "watchlistSearch"), !words.isEmpty {
                query = words
                NSLog("watchlistSearch: %@", words)
            }
            #endif
            fieldFocused = true
        }
    }

    private var field: some View {
        DSTraySearchField(placeholder: String(localized: "A name, a ticker or an address"),
                          text: $query, focus: $fieldFocused, searching: searching,
                          submitLabel: .done) {
            if UIPasteboard.general.hasStrings {
                PasteButton(payloadType: String.self) { strings in
                    if let s = strings.first { query = s }
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.circle)
                .tint(DS.pickInk)
                .frame(minWidth: 44, minHeight: 44)
            }
        }
    }

    // MARK: - Before you type

    /// What your account holds that you don't watch, largest first; one
    /// watched here stays, ticked.
    @ViewBuilder private var before: some View {
        let watchedSymbols = Set(list.tokens.map { $0.symbol.uppercased() })
        let offered = held.filter { !watchedSymbols.contains($0.symbol) || watchedHere.contains($0.symbol) }
            .prefix(WatchlistRules.searchCap)
        ForEach(Array(offered), id: \.symbol) { h in
            row(symbol: h.symbol,
                line: unpriced.contains(h.symbol) ? String(localized: "No price")
                                                  : String(localized: "You hold \(WalletValue.payment(h.usd))"),
                on: watchedSymbols.contains(h.symbol), busy: looking.contains(h.symbol)) { await watchHeld(h) }
        }
    }

    // MARK: - As you type

    @ViewBuilder private var typed: some View {
        if foundFor == trimmed, !searching {
            if found.isEmpty {
                DSFootnote(Text(DemoMode.isActive
                                ? String(localized: "Searching works once you leave the demo.")
                                : String(localized: "No priced token by that name.")))
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.top, DS.Space.s4)
            }
            ForEach(found, id: \.token.id) { hit in
                row(symbol: hit.token.symbol,
                    line: "\(WatchlistRules.line(for: hit.token)) · \(PriceCommentary.money(hit.quote.price))",
                    on: list.contains(hit.token.id), key: hit.token.id) { watch(hit.token) }
            }
        }
    }

    private func row(symbol: String, line: String, on: Bool, busy: Bool = false, key: String? = nil,
                     act: @escaping () async -> Void) -> some View {
        HStack(spacing: DS.Space.s3) {
            AssetMark(name: symbol, size: DS.Face.list)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: symbol).dsText(.body17)
                    .foregroundStyle(DS.textPrimary).lineLimit(1)
                Text(verbatim: on ? String(localized: "Watching") : line)
                    .dsText(.subhead12).foregroundStyle(DS.textTertiary).lineLimit(1)
            }
            Spacer(minLength: DS.Space.s2)
            Button {
                Task { await act() }
            } label: {
                if busy {
                    DSSpinner().frame(minWidth: 44, minHeight: 44)
                } else {
                    DSFollowMark(on: on, dimmed: false, bounce: justWatched == (key ?? symbol))
                }
            }
            .buttonStyle(PressSpring())
            .disabled(on || busy)
            .accessibilityLabel(Text(on ? String(localized: "Watching \(symbol)")
                                        : String(localized: "Watch \(symbol)")))
        }
        .frame(minHeight: DSFeed.headHeight)
        .padding(.horizontal, DS.Space.s4)
    }

    // MARK: - Watching

    private func watch(_ token: WatchedToken) {
        guard !list.contains(token.id) else { return }
        list.watch(token)
        justWatched = token.id
        chrome?.flash(String(localized: "Watching \(token.symbol)"), tone: .success)
    }

    /// A holding is watched as what you hold: its coin, else the contract
    /// your account holds it at, whichever DeFiLlama prices first; only a
    /// holding with neither asks the search for the coin wearing its ticker.
    private func watchHeld(_ h: Held) async {
        guard !looking.contains(h.symbol) else { return }
        guard !DemoMode.isActive else {
            chrome?.flash(String(localized: "Watching works once you leave the demo."))
            return
        }
        looking.insert(h.symbol)
        unpriced.remove(h.symbol)
        defer { looking.remove(h.symbol) }
        var picked: WatchedToken?
        if !h.ids.isEmpty {
            let quotes = await WatchlistPrices.read(h.ids)
            if let id = h.ids.first(where: { quotes[$0] != nil }) {
                picked = WatchedToken(id: id, symbol: h.symbol, name: h.symbol)
            }
        }
        if picked == nil {
            let hits = await WatchlistPrices.search(h.symbol)
            picked = hits.first(where: { $0.token.symbol.uppercased() == h.symbol })?.token
        }
        guard let token = picked else {
            withAnimation(DS.Motion.standard) { _ = unpriced.insert(h.symbol) }
            chrome?.flash(String(localized: "No priced token named \(h.symbol)."))
            #if DEBUG
            NSLog("watchHeld| %@ | none | %@", h.symbol, h.ids.joined(separator: ","))
            #endif
            return
        }
        watchedHere.insert(h.symbol)
        watch(token)
        // The row's bounce is keyed by symbol; `watch` keys it by id.
        justWatched = h.symbol
        #if DEBUG
        NSLog("watchHeld| %@ | %@", h.symbol, token.id)
        #endif
    }

    // MARK: - Reading

    private func search() async {
        let q = trimmed
        guard !q.isEmpty else { found = []; foundFor = ""; searching = false; return }
        // The demo reaches nothing (§483).
        guard !DemoMode.isActive else { found = []; foundFor = q; searching = false; return }
        // After a pause (prd §1171): never a request per keystroke.
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        searching = true
        let hits = await WatchlistPrices.search(q)
        guard !Task.isCancelled else { return }
        withAnimation(DS.Motion.standard) {
            found = hits
            foundFor = q
        }
        searching = false
        #if DEBUG
        NSLog("watchlistSearch| %@ | %@", q, hits.map { "\($0.token.symbol)=\($0.token.id)" }.joined(separator: ","))
        #endif
    }
}
