import Foundation

/// **TOKENS YOU HID FROM HOLDINGS (user: "should be able to long press and
/// hide a token").** A hidden token leaves the list, the map and the total;
/// Holdings ends in one row that names how many are hidden and brings each
/// back, so the total never drops a token silently (§83).
///
/// Two kinds of hide (prd §1591). A SYMBOL hides every holding of that name,
/// the portfolio's own identity for a position (`WalletPortfolio.Position.id`).
/// A CONTRACT hides one token on one network, because a spam token wearing a
/// real symbol ("USDC") sums into the real one's row, and hiding it by name
/// would hide your real USDC with it.
enum HiddenTokens {
    static let key = "wallet.hiddenTokens"
    static let contractsKey = "wallet.hiddenTokenContracts"

    /// What a hide or a show acts on.
    enum Target: Equatable {
        case symbol(String)
        case contract(String)
    }

    /// Everything hidden, as one value a screen can hold in state.
    struct Choice: Equatable {
        var symbols: Set<String> = []
        var contracts: Set<String> = []
        var isEmpty: Bool { symbols.isEmpty && contracts.isEmpty }
    }

    static var current: Choice { Choice(symbols: symbols, contracts: contracts) }

    static var symbols: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    static var contracts: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: contractsKey) ?? [])
    }

    static func set(_ target: Target, hidden: Bool) {
        let (defaultsKey, id, all): (String, String, Set<String>) = switch target {
        case .symbol(let symbol): (key, symbol.uppercased(), symbols)
        case .contract(let contract): (contractsKey, contract.lowercased(), contracts)
        }
        var next = all
        if hidden { next.insert(id) } else { next.remove(id) }
        UserDefaults.standard.set(next.sorted(), forKey: defaultsKey)
    }

    /// One token on one network: `<network>:<contract>`, lowercased, with
    /// `native` for the network's own coin. The network is the read's id
    /// (`base-mainnet`), so the same contract on two networks is two keys.
    static func contractKey(network: String, contract: String?) -> String {
        "\(network):\(contract ?? "native")".lowercased()
    }

    /// Where a contract key lives, in words: "Base · ...e07a", or "Base" for
    /// the network's own coin.
    static func place(_ key: String) -> String {
        let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
        let network = parts.first ?? key
        let name = WalletChainStore.selectable.first { $0.id == network }?.name ?? network
        guard parts.count == 2, parts[1] != "native" else { return name }
        return "\(name) · \(AddressTail.short(parts[1]))"
    }
}

extension WalletPortfolio {
    /// One hidden thing as the Hidden row lists it: a whole symbol, or one
    /// contract of it with its place.
    struct HiddenItem: Identifiable, Equatable {
        let target: HiddenTokens.Target
        let symbol: String
        let place: String?
        let usd: Double
        var id: String {
            switch target {
            case .symbol(let s): "symbol:" + s.uppercased()
            case .contract(let c): c
            }
        }
    }

    /// This portfolio without what you hid, its total with it out. A hidden
    /// contract comes off its row and off the wallet that held it; a row with
    /// nothing left goes.
    func hiding(_ choice: HiddenTokens.Choice) -> WalletPortfolio {
        guard !choice.isEmpty else { return self }
        var gone = 0.0
        let kept = positions.compactMap { position -> Position? in
            if choice.symbols.contains(position.symbol.uppercased()) {
                gone += position.usd
                return nil
            }
            let out = position.parts.filter { choice.contracts.contains($0.key) }
            guard !out.isEmpty else { return position }
            let cut = out.reduce(0) { $0 + $1.usd }
            gone += min(cut, position.usd)
            let usd = position.usd - cut
            guard usd > 0.005 else { return nil }
            var cutByHolder: [String: Double] = [:]
            for part in out { cutByHolder[part.holder, default: 0] += part.usd }
            let holders = position.holders.compactMap { holder -> Holder? in
                let left = holder.usd - (cutByHolder[holder.address] ?? 0)
                return left > 0.005 ? Holder(address: holder.address, label: holder.label, usd: left) : nil
            }
            // A route to a contract you hid would open the spam's chart.
            let hiddenAddresses = out.compactMap { $0.key.split(separator: ":").last.map(String.init) }
            let route = position.route.flatMap { route in
                hiddenAddresses.contains { route.lowercased().hasSuffix(":" + $0) } ? nil : route
            }
            return Position(symbol: position.symbol, usd: usd, route: route, holders: holders,
                            parts: position.parts.filter { !choice.contracts.contains($0.key) })
        }
        .sorted { $0.usd > $1.usd }
        guard gone > 0 else { return self }
        var shown = self
        shown.positions = kept
        shown.totalUSD = max(0, totalUSD - gone)
        return shown
    }

    /// What `hiding` took out of this portfolio, for the Hidden row.
    func hiddenItems(_ choice: HiddenTokens.Choice) -> [HiddenItem] {
        guard !choice.isEmpty else { return [] }
        return positions.flatMap { position -> [HiddenItem] in
            if choice.symbols.contains(position.symbol.uppercased()) {
                return [HiddenItem(target: .symbol(position.symbol), symbol: position.symbol,
                                   place: nil, usd: position.usd)]
            }
            return position.contracts.filter { choice.contracts.contains($0.key) }.map {
                HiddenItem(target: .contract($0.key), symbol: position.symbol,
                           place: HiddenTokens.place($0.key), usd: $0.usd)
            }
        }
    }
}
