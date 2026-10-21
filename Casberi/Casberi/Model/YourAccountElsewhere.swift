import Foundation

/// **RECEIVE FROM ANOTHER NETWORK (prd §1453).** Someone with USDC or ETH on
/// a network your account does not use — Arbitrum, Optimism, Polygon, an
/// exchange that withdraws only there — sends it to an address Relay gives
/// for that route, and Relay brings it to your account on Base, as the same
/// token, seconds later. Keyless: EVM networks only (Solana and Bitcoin need
/// a Relay key, declined: user, 2026-10-21, "i don't want an api key").
///
/// Each route's address is Relay's open deposit address, reusable for that
/// route (Relay's docs), and a fresh quote hands out a new one, so the first
/// one this phone was given is kept per route and shown again: the address
/// you saved for "USDC from Arbitrum" stays that address.
enum YourAccountElsewhere {
    typealias Op = YourAccountOp

    struct Network: Identifiable, Equatable, Hashable, Sendable {
        let id: Int
        let name: String
        let usdc: String?
        /// Its own coin is ETH, so ETH sent there arrives as ETH.
        let ethNative: Bool
    }

    struct Route: Equatable, Sendable {
        let from: Network
        let token: String
        let to: Op.Network
        /// What arrives: the network's dollar (USDC, or Robinhood Chain's
        /// USDG) for USDC, ETH for ETH.
        let arrives: String
        let address: String
        let feeUSD: Double?
        let seconds: Int?
    }

    @MainActor private static var listed: (networks: [Network], at: Date)?

    /// Relay's EVM networks that take deposit addresses, without the
    /// account's own (those take your own address), A–Z.
    @MainActor
    static func networks() async -> [Network] {
        if let listed, listed.at.timeIntervalSinceNow > -3_600, !listed.networks.isEmpty { return listed.networks }
        let own = Set(Op.networks.map(\.chainId))
        var out: [Network] = []
        for c in await YourAccountChain.relayChains() {
            guard (c["vmType"] as? String) == "evm", (c["depositAddressEnabled"] as? Bool) == true,
                  (c["disabled"] as? Bool) != true, let id = c["id"] as? Int, !own.contains(id),
                  let name = (c["displayName"] as? String) ?? (c["name"] as? String) else { continue }
            let tags = (c["tags"] as? [String]) ?? []
            guard !tags.contains("testnet") else { continue }
            let usdc = ((c["erc20Currencies"] as? [[String: Any]]) ?? [])
                .first { ($0["symbol"] as? String) == "USDC" && ($0["supportsBridging"] as? Bool) != false }?["address"] as? String
            let eth = ((c["currency"] as? [String: Any])?["symbol"] as? String) == "ETH"
            guard usdc != nil || eth else { continue }
            out.append(Network(id: id, name: name, usdc: usdc, ethNative: eth))
        }
        out.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if !out.isEmpty { listed = (out, .now) }
        return out
    }

    private struct Kept: Codable { let address: String; let fee: Double?; let seconds: Int? }

    private static func keptKey(_ account: String, _ from: Int, _ token: String, _ to: Int) -> String {
        "yourAccount.elsewhere.\(account.lowercased()).\(from).\(token).\(to)"
    }

    /// The route's address: the one kept for it, else Relay's, checked
    /// (`YourAccountChain.depositAddress`) and kept.
    static func route(from: Network, token: String, to net: Op.Network, account: String) async throws -> Route {
        let key = keptKey(account, from.id, token, net.chainId)
        if let data = UserDefaults.standard.data(forKey: key), let kept = try? JSONDecoder().decode(Kept.self, from: data) {
            return Route(from: from, token: token, to: net, arrives: token == "USDC" ? net.dollarSymbol : token,
                         address: kept.address, feeUSD: kept.fee, seconds: kept.seconds)
        }
        let usdc = token == "USDC"
        guard let origin = usdc ? from.usdc : YourAccountSwap.native, usdc || from.ethNative else {
            throw YourAccountChain.Failure(message: String(localized: "Relay does not take \(token) from \(from.name)"))
        }
        let target = RoundUps.Target(chainId: net.chainId, address: usdc ? net.dollar : YourAccountSwap.native,
                                     symbol: usdc ? net.dollarSymbol : token, decimals: usdc ? 6 : 18, network: net.name)
        // An open address takes any amount on its route; the quote names one.
        let deposit = try await YourAccountChain.depositAddress(fromChain: from.id, currency: origin, to: target,
                                                                amount: usdc ? "10000000" : "5000000000000000",
                                                                account: account, name: from.name)
        if let data = try? JSONEncoder().encode(Kept(address: deposit.address, fee: deposit.feeUSD, seconds: deposit.seconds)) {
            UserDefaults.standard.set(data, forKey: key)
        }
        return Route(from: from, token: token, to: net, arrives: target.symbol,
                     address: deposit.address, feeUSD: deposit.feeUSD, seconds: deposit.seconds)
    }
}
