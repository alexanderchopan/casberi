import Foundation
import WalletConnectSign

/// Receive › From another wallet, live (prd §1506): the connection, the
/// read, the routes and the sends. The plan itself is `WalletSweep`'s.
///
/// The connection is its own, never `WalletConnectBridge.readOnlyNamespaces()`
/// (that one asks for nothing, §112): one method, `eth_sendTransaction`, on
/// the networks below, through `YourAccountSignerLink`'s proposal. Each send
/// is one request the other wallet approves or refuses; Casberi signs
/// nothing and holds no key of it. UNMEASURED: which wallets agree to every
/// network asked, and how each words a refusal.
enum WalletSweepLive {
    typealias Op = YourAccountOp

    static let method = "eth_sendTransaction"
    /// The networks a sweep asks to send on: your account's own Base and
    /// Ethereum, and the three most wallets hold money on. Robinhood is not
    /// asked yet: few wallets know it, and an unknown network can refuse the
    /// whole connection.
    static let chainIds = [8453, 1, 42161, 10, 137]
    static let yours: Set<Int> = [8453, 1]

    /// The network names `WalletApprovals.rpcRead` and Zerion use.
    static func networkID(_ chainId: Int) -> String? {
        switch chainId {
        case 1: "eth-mainnet"
        case 8453: "base-mainnet"
        case 42161: "arb-mainnet"
        case 10: "opt-mainnet"
        case 137: "matic-mainnet"
        default: nil
        }
    }

    static func networkName(_ chainId: Int) -> String {
        switch chainId {
        case 1: "Ethereum"
        case 8453: "Base"
        case 42161: "Arbitrum"
        case 10: "Optimism"
        case 137: "Polygon"
        default: "network \(chainId)"
        }
    }

    // MARK: - The read

    /// What `address` holds on `chains`, each amount read off the chain in
    /// base units (Zerion's is rounded, and a send of more than the balance
    /// is refused). Zerion says what is there and prices it.
    static func holdings(of address: String, on chains: Set<Int>) async -> [WalletSweep.Holding] {
        let networks = Set(chains.compactMap(networkID))
        guard let listed = await ZerionAPI.holdings(address: address, networks: networks) else { return [] }
        var out: [WalletSweep.Holding] = []
        for item in listed {
            guard let price = item.price, price > 0,
                  let chainId = WalletApprovals.chainId(forNetwork: item.network), chains.contains(chainId)
            else { continue }
            if let contract = item.contract {
                guard WalletSweep.isAddress(contract),
                      let decimals = await tokenDecimals(contract, on: item.network),
                      let raw = await tokenBalance(contract, of: address, on: item.network), raw != "0"
                else { continue }
                out.append(.init(chainId: chainId, networkName: networkName(chainId), symbol: item.symbol,
                                 contract: contract, decimals: decimals, raw: raw,
                                 usd: WalletSweep.amount(raw, decimals: decimals) * price))
            } else {
                guard let hex = await WalletApprovals.rpcRead(network: item.network, method: "eth_getBalance",
                                                              params: [address, "latest"]) as? String,
                      let raw = WalletSweep.decimal(fromHex: hex), raw != "0" else { continue }
                out.append(.init(chainId: chainId, networkName: networkName(chainId), symbol: item.symbol,
                                 contract: nil, decimals: 18, raw: raw,
                                 usd: WalletSweep.amount(raw, decimals: 18) * price))
            }
        }
        return out
    }

    private static func tokenBalance(_ contract: String, of owner: String, on network: String) async -> String? {
        let data = "0x70a08231" + String(repeating: "0", count: 24) + owner.dropFirst(2).lowercased()
        guard let hex = await WalletApprovals.rpcRead(network: network, method: "eth_call",
                                                      params: [["to": contract, "data": data], "latest"]) as? String
        else { return nil }
        return WalletSweep.decimal(fromHex: hex)
    }

    private static func tokenDecimals(_ contract: String, on network: String) async -> Int? {
        guard let hex = await WalletApprovals.rpcRead(network: network, method: "eth_call",
                                                      params: [["to": contract, "data": "0x313ce567"], "latest"]) as? String,
              let digits = WalletSweep.decimal(fromHex: hex), let n = Int(digits), (0...36).contains(n)
        else { return nil }
        return n
    }

    /// Wei per gas on each network, read now.
    static func gasPrices(_ chains: Set<Int>) async -> [Int: Decimal] {
        var out: [Int: Decimal] = [:]
        for chain in chains {
            guard let network = networkID(chain),
                  let hex = await WalletApprovals.rpcRead(network: network, method: "eth_gasPrice", params: []) as? String,
                  let digits = WalletSweep.decimal(fromHex: hex), let wei = Decimal(string: digits) else { continue }
            out[chain] = wei
        }
        return out
    }

    // MARK: - The plan, with its routes

    /// The plan for `address`, every Relay leg given its deposit address on
    /// Base; a route Relay refuses stays, named.
    @MainActor
    static func plan(for address: String, on chains: Set<Int>, account: String) async -> WalletSweep.Plan {
        async let held = holdings(of: address, on: chains)
        async let gas = gasPrices(chains)
        let relay = await YourAccountElsewhere.networks()
        func coin(_ chain: Int, _ contract: String?) -> (YourAccountElsewhere.Network, YourAccountElsewhere.Coin)? {
            guard let net = relay.first(where: { $0.id == chain }) else { return nil }
            let want = (contract ?? YourAccountSwap.native).lowercased()
            return net.coins.first { $0.address.lowercased() == want }.map { (net, $0) }
        }
        var plan = WalletSweep.plan(await held, yours: yours, relayable: { coin($0, $1) != nil }, gasPrice: await gas)
        var legs: [WalletSweep.Leg] = []
        for var leg in plan.legs {
            if yours.contains(leg.holding.chainId) { legs.append(leg); continue }
            guard let (net, token) = coin(leg.holding.chainId, leg.holding.contract),
                  let route = try? await YourAccountElsewhere.route(from: net, token: token, to: Op.base, account: account)
            else { plan.stays.append((leg.holding, .noRoute)); continue }
            leg.way = .relay(address: route.address, arrives: route.arrives.symbol)
            legs.append(leg)
        }
        plan.legs = legs
        return plan
    }

    // MARK: - The sends

    /// One send asked of the other wallet; its transaction hash, or why not.
    static func send(_ leg: WalletSweep.Leg, over pairing: YourAccountSignerLink.Pairing,
                     account: String) async throws -> String {
        let chainId = leg.holding.chainId
        guard pairing.chainIds.contains(chainId), let chain = Blockchain("eip155:\(chainId)"),
              let tx = WalletSweep.transaction(leg, from: pairing.signer,
                                               to: WalletSweep.destination(leg, account: account))
        else { throw YourAccountSignerLink.Failure.unavailable }
        let request = try Request(topic: pairing.topic, method: method, params: AnyCodable([tx]), chainId: chain)
        async let answer = YourAccountSignerLink.response(to: request.id, timeout: .seconds(300))
        try await Sign.instance.request(params: request)
        guard let result = await answer else { throw YourAccountSignerLink.Failure.timedOut }
        switch result {
        case .error(let error):
            throw YourAccountSignerLink.Failure.refused(error.message)
        case .response(let value):
            guard let hash = try? value.get(String.self), hash.hasPrefix("0x") else {
                throw YourAccountSignerLink.Failure.malformedSignature
            }
            return hash
        }
    }
}
