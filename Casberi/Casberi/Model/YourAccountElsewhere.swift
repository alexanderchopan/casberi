import Foundation

/// **RECEIVE FROM ANOTHER NETWORK (prd §1453, widened by §1470).** Someone
/// with money on a network your account does not use — Arbitrum, Optimism,
/// Polygon, an exchange that withdraws only there — sends it to an address
/// Relay gives for that route, and Relay brings it to your account on Base,
/// Ethereum or Robinhood Chain, seconds later. Keyless: EVM networks only
/// (Solana and Bitcoin need a Relay key, declined: user, 2026-10-21, "i
/// don't want an api key").
///
/// Two blanks (prd §1470, user: "send anything and receive usdc"): WHAT THEY
/// SEND is any coin Relay bridges from their network — its own coin where
/// Relay bridges it, and every ERC-20 it lists there (USDC, USDT, DAI, USDe,
/// PYUSD, cbBTC…) — and WHAT YOU RECEIVE is your pick on your network, the
/// network's dollar unless they send ETH, which lands as ETH. Relay swaps on
/// the way, at the price when it lands.
///
/// Each route's address is Relay's open deposit address, reusable for that
/// route (Relay's docs), and a fresh quote hands out a new one, so the first
/// one this phone was given is kept per route and shown again: the address
/// you saved for "USDT from Arbitrum, as USDC on Base" stays that address.
/// A route is the pair: what they send and what arrives are different
/// addresses.
enum YourAccountElsewhere {
    typealias Op = YourAccountOp

    /// A coin Relay bridges from an origin network.
    struct Coin: Identifiable, Equatable, Hashable, Sendable {
        let symbol: String
        /// Relay's address for it; `YourAccountSwap.native` for the network's own coin.
        let address: String
        let decimals: Int
        var id: String { address.lowercased() }
        var isNative: Bool { address.lowercased() == YourAccountSwap.native }
    }

    struct Network: Identifiable, Equatable, Hashable, Sendable {
        let id: Int
        let name: String
        /// What Relay bridges from here, its own coin first, then A–Z.
        let coins: [Coin]

        /// What to offer first on this network: what was being sent before,
        /// where this network has it too; else USDC; else its first coin.
        func coin(like before: Coin?) -> Coin? {
            if let before, let same = coins.first(where: { $0.symbol == before.symbol }) { return same }
            return coins.first { $0.symbol == "USDC" } ?? coins.first
        }
    }

    struct Route: Equatable, Sendable {
        let from: Network
        /// What they send.
        let token: Coin
        let to: Op.Network
        /// What arrives in your account.
        let arrives: Op.Token
        let address: String
        let feeUSD: Double?
        let seconds: Int?
        /// Relay swaps on the way, at the price when it lands.
        var converts: Bool { token.symbol != arrives.symbol }
    }

    /// What arrives unless you pick: ETH for ETH (every account network's
    /// coin is ETH), else the network's dollar — USDC, or Robinhood Chain's
    /// USDG (user, 2026-10-22: "send anything and receive usdc").
    static func defaultArrival(for coin: Coin, on net: Op.Network) -> Op.Token {
        coin.isNative && coin.symbol == "ETH" ? Op.eth : Op.dollar(on: net)
    }

    @MainActor private static var listed: (networks: [Network], at: Date)?

    /// Networks Relay still lists that are closing down, left out so no one
    /// sends money onto them (prd §1485): Abstract (2741).
    static let closing: Set<Int> = [2741]

    /// Relay's EVM networks that take deposit addresses, without the
    /// account's own (those take your own address), A–Z; each with the coins
    /// Relay bridges from it (`supportsBridging`, the coin's own flag — POL on
    /// Polygon is listed and not bridged, measured 2026-10-22).
    @MainActor
    static func networks() async -> [Network] {
        if let listed, listed.at.timeIntervalSinceNow > -3_600, !listed.networks.isEmpty { return listed.networks }
        let own = Set(Op.networks.map(\.chainId))
        var out: [Network] = []
        for c in await YourAccountChain.relayChains() {
            guard (c["vmType"] as? String) == "evm", (c["depositAddressEnabled"] as? Bool) == true,
                  (c["disabled"] as? Bool) != true, let id = c["id"] as? Int, !own.contains(id), !closing.contains(id),
                  let name = (c["displayName"] as? String) ?? (c["name"] as? String) else { continue }
            let tags = (c["tags"] as? [String]) ?? []
            guard !tags.contains("testnet") else { continue }
            let coins = Self.coins(of: c)
            guard !coins.isEmpty else { continue }
            out.append(Network(id: id, name: name, coins: coins))
        }
        out.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if !out.isEmpty { listed = (out, .now) }
        return out
    }

    /// The coins Relay bridges from one of its chain records: the native
    /// coin when its own `supportsBridging` allows, then every ERC-20 with a
    /// sound address and decimals, A–Z. Pure, for the self-test.
    static func coins(of chain: [String: Any]) -> [Coin] {
        func coin(_ c: [String: Any], native: Bool) -> Coin? {
            guard (c["supportsBridging"] as? Bool) != false,
                  let symbol = c["symbol"] as? String, !symbol.isEmpty, symbol.count <= 16,
                  let decimals = c["decimals"] as? Int, (0...36).contains(decimals),
                  let address = c["address"] as? String else { return nil }
            if native {
                guard address.lowercased() == YourAccountSwap.native else { return nil }
                return Coin(symbol: symbol, address: YourAccountSwap.native, decimals: decimals)
            }
            guard ENS.isHexAddress(address), address.lowercased() != YourAccountSwap.native else { return nil }
            return Coin(symbol: symbol, address: EIP55.checksum(address), decimals: decimals)
        }
        var out: [Coin] = []
        if let n = (chain["currency"] as? [String: Any]).flatMap({ coin($0, native: true) }) { out.append(n) }
        var seen = Set(out.map(\.id))
        let erc20 = ((chain["erc20Currencies"] as? [[String: Any]]) ?? [])
            .compactMap { coin($0, native: false) }
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.symbol.localizedCaseInsensitiveCompare($1.symbol) == .orderedAscending }
        return out + erc20
    }

    private struct Kept: Codable { let address: String; let fee: Double?; let seconds: Int? }

    /// One address per PAIR: what they send and what arrives (prd §1470).
    static func keptKey(_ account: String, _ from: Int, _ token: Coin, _ to: Int, _ arrives: Op.Token) -> String {
        "yourAccount.elsewhere.\(account.lowercased()).\(from).\(token.id).\(to).\(YourAccountSwap.currency(arrives).lowercased())"
    }

    /// The amount a route's quote names — an open address takes any amount
    /// on its route, but Relay will not quote under about $0.05 or beyond a
    /// pool's depth: a small fraction of a chain's own coin or a bitcoin,
    /// ten of anything else (a dollar, mostly). Pure, for the self-test.
    static func quoteAmount(_ coin: Coin) -> String {
        let whole = Decimal(sign: .plus, exponent: coin.decimals, significand: 1)
        let units: Decimal
        if coin.isNative { units = whole * Decimal(string: "0.005")! }
        else if coin.symbol.uppercased().contains("BTC") { units = whole * Decimal(string: "0.0005")! }
        else { units = whole * 10 }
        var rounded = Decimal()
        var source = units
        NSDecimalRound(&rounded, &source, 0, .down)
        return "\(rounded)"
    }

    /// The route's address: the one kept for it, else Relay's, checked
    /// (`YourAccountChain.depositAddress`) and kept.
    static func route(from: Network, token: Coin, to net: Op.Network, arrives: Op.Token? = nil, account: String) async throws -> Route {
        let arrives = arrives ?? defaultArrival(for: token, on: net)
        let key = keptKey(account, from.id, token, net.chainId, arrives)
        if let data = UserDefaults.standard.data(forKey: key), let kept = try? JSONDecoder().decode(Kept.self, from: data) {
            return Route(from: from, token: token, to: net, arrives: arrives,
                         address: kept.address, feeUSD: kept.fee, seconds: kept.seconds)
        }
        guard from.coins.contains(token) else {
            throw YourAccountChain.Failure(message: String(localized: "Relay does not take \(token.symbol) from \(from.name)"))
        }
        let target = RoundUps.Target(chainId: net.chainId, address: YourAccountSwap.currency(arrives),
                                     symbol: arrives.symbol, decimals: arrives.decimals, network: net.name)
        let deposit = try await YourAccountChain.depositAddress(fromChain: from.id, currency: token.address, to: target,
                                                                amount: quoteAmount(token), account: account, name: from.name)
        if let data = try? JSONEncoder().encode(Kept(address: deposit.address, fee: deposit.feeUSD, seconds: deposit.seconds)) {
            UserDefaults.standard.set(data, forKey: key)
        }
        return Route(from: from, token: token, to: net, arrives: arrives,
                     address: deposit.address, feeUSD: deposit.feeUSD, seconds: deposit.seconds)
    }
}
