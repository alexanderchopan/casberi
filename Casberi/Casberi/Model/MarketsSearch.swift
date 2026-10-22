import Foundation

/// THE ONE SEARCH ASKS THE MARKET (prd §1467, user: "the solution to search
/// is to make the search bar search tokens"; "if a user pastes a contract
/// address in search what would happen? … if not then we need a search for
/// markets specifically").
///
/// Until now the tab bar's Search looked only at what you have: "pepe" found
/// the PEPE you burned and nothing from the market, a Markets look-up row was
/// offered only when nothing matched and the word was one to five letters,
/// and a pasted contract address was read as a wallet to follow. Now the
/// Markets group asks the market for whatever you typed, after the pause:
///
/// - **Coins** from CoinPaprika's search — the coin itself, with the
///   contracts it is deployed as, so a DEX token that IS the coin folds into
///   it and a pasted contract finds its coin.
/// - **Tokens** from Dexscreener, every one it returns, most liquid first,
///   less the ones that fold into a coin.
/// - **Stocks** from Stocktwits' symbol search — never for an address.
///
/// The group draws `shown` rows, then "Show all N in Markets" grows it in
/// place; the Follow tray keeps no field (§1391) and no hand-off. Pure and
/// Foundation-only: `scripts/markets-selftest.sh` compiles it whole. The
/// reads live in `MarketsSearchRead`.
enum MarketsSearch {

    /// How many market rows the group draws before Show all.
    static let shown = 4
    /// How many coins CoinPaprika is asked for, and how many of them are
    /// priced (one ticker read each).
    static let coinLimit = 6
    static let pricedCoins = 4
    /// How many tokens Dexscreener is asked for: the whole page it returns
    /// (measured 2026-10-21: 30 pairs, 29 tokens for "pepe"), never 8.
    static let tokenLimit = 40
    static let stockLimit = 6

    // MARK: - What the words are

    /// A pasted address: `0x` and forty hex digits, or a base58 mint of
    /// Solana's length. An address is looked up as a contract AND offered as
    /// an account (`RoomsTray.addressHits`), since nothing but the market's
    /// answer tells the two apart.
    static func isAddress(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.count == 42, q.lowercased().hasPrefix("0x") {
            return q.dropFirst(2).allSatisfy(\.isHexDigit)
        }
        guard (32...44).contains(q.count) else { return false }
        let base58 = Set("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
        return q.allSatisfy { base58.contains($0) }
    }

    /// Address equality per family: EVM hex compares case-folded (EIP-55
    /// case is a checksum), base58 compares exactly.
    static func sameAddress(_ a: String, _ b: String) -> Bool {
        a.hasPrefix("0x") ? a.lowercased() == b.lowercased() : a == b
    }

    // MARK: - CoinPaprika's answer

    static func searchURL(_ query: String, limit: Int = coinLimit) -> String? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty,
              let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        // The trailing slash is the endpoint (measured 2026-10-21: without it
        // the host answers 301 Moved Permanently, which a JSON read drops).
        return "https://api.coinpaprika.com/v1/search/?q=\(encoded)&c=currencies&limit=\(limit)"
    }

    struct Contract: Equatable {
        /// Dexscreener's chain id where CoinPaprika's type names one
        /// (`ERC20` → ethereum, `BEP20` → bsc), else nil: compare by address.
        let chain: String?
        let address: String
    }

    struct Coin: Equatable {
        let id: String
        let name: String
        let symbol: String
        let rank: Int
        let contracts: [Contract]
    }

    /// The coins in a search answer: active and ranked (a rank of 0 is a
    /// coin CoinPaprika lists but does not price), in rank order.
    static func coins(from json: Any?) -> [Coin] {
        guard let root = json as? [String: Any],
              let list = root["currencies"] as? [[String: Any]] else { return [] }
        return list.compactMap { c -> Coin? in
            guard let id = c["id"] as? String, !id.isEmpty,
                  let name = c["name"] as? String,
                  let symbol = c["symbol"] as? String,
                  (c["is_active"] as? Bool) ?? true,
                  let rank = c["rank"] as? Int, rank > 0 else { return nil }
            let contracts = ((c["contract_address"] as? [[String: Any]]) ?? []).compactMap { e -> Contract? in
                guard let address = e["address"] as? String, !address.isEmpty else { return nil }
                let chain: String? = switch (e["type"] as? String)?.uppercased() {
                case "ERC20": "ethereum"
                case "BEP20": "bsc"
                default: nil
                }
                return Contract(chain: chain, address: address)
            }
            return Coin(id: id, name: name, symbol: symbol.uppercased(), rank: rank, contracts: contracts)
        }
        .sorted { $0.rank < $1.rank }
    }

    /// The coin a DEX token is, when it is one: its contract on its chain is
    /// among the coin's. A contract whose chain CoinPaprika did not name
    /// matches by address alone.
    static func coin(ofTokenOn chain: String, address: String, among coins: [Coin]) -> Coin? {
        coins.first { coin in
            coin.contracts.contains { c in
                (c.chain == nil || c.chain == chain) && sameAddress(c.address, address)
            }
        }
    }

    // MARK: - The group's order

    /// One market row, by what it is and where it stands in its own list.
    enum Pick: Equatable {
        case coin(Int), token(Int), stock(Int)
    }

    struct Token: Equatable {
        let chain: String
        let address: String
        let liquidity: Double
    }

    /// The order the group draws: for words, the coins (rank order), then
    /// the tokens most liquid first, then the stocks; for an address, the
    /// exact contract leads, then its coin, then the rest. A token that is a
    /// coin in the list folds into the coin.
    static func picks(query: String, coins: [Coin], tokens: [Token], stocks: Int) -> [Pick] {
        let kept = tokens.enumerated().filter { _, t in
            coin(ofTokenOn: t.chain, address: t.address, among: coins) == nil
        }
        let tokenPicks = kept.sorted { $0.element.liquidity > $1.element.liquidity }.map { Pick.token($0.offset) }
        let coinPicks = coins.indices.map { Pick.coin($0) }
        if isAddress(query) {
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let exact = tokens.enumerated().filter { sameAddress($0.element.address, q) }
                .sorted { $0.element.liquidity > $1.element.liquidity }.map { Pick.token($0.offset) }
            let rest = tokenPicks.filter { !exact.contains($0) }
            return exact + coinPicks + rest
        }
        return coinPicks + tokenPicks + (0..<max(0, stocks)).map { Pick.stock($0) }
    }

    /// "Show all N in Markets" and its line: the chains counted, then the
    /// stocks ("Ethereum 9 · Solana 8 · 1 stock").
    static func showAllLine(chains: [(name: String, count: Int)], stocks: Int) -> String {
        var parts = chains.sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
            .map { "\($0.name) \($0.count)" }
        if stocks == 1 { parts.append("1 stock") } else if stocks > 1 { parts.append("\(stocks) stocks") }
        return parts.joined(separator: " · ")
    }
}
