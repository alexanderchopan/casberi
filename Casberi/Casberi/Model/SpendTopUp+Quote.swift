import Foundation

/// The swap Spend signs before it pays (prd §1666): what `held` sells for at
/// least `cost` USDC on Base, quoted by the pools (and Across, from
/// Ethereum), proven by the same simulation every swap is before Face ID.
extension SpendTopUp {
    typealias Op = YourAccountOp
    typealias Chain = YourAccountChain

    static func pays(_ token: Op.Token, on net: Op.Network) -> Bool {
        !net.isTest && pays(contract: token.contract, dollar: net.dollar, chainId: net.chainId)
    }

    static func direct(_ token: Op.Token, on net: Op.Network) -> Bool {
        !net.isTest && direct(contract: token.contract, dollar: net.dollar, chainId: net.chainId)
    }

    /// What `held` would sell for `cost`, at its last price, for the line
    /// before anything is asked; nil with no price.
    static func estimate(cost: String, held: YourAccountTokens.Held, on net: Op.Network) -> String? {
        let price = held.token.contract?.lowercased() == net.dollar.lowercased() ? 1 : held.price
        return price.flatMap { estimate(cost: cost, price: $0, decimals: held.token.decimals) }
    }

    /// **THE SWAP FIRST.** `held` sold for at least `cost` USDC on Base: its
    /// price from the Wallet's reading (else the pools'), 3% over, quoted; a
    /// minimum still short is asked once more for proportionally more.
    @MainActor
    static func swap(cost: String, held: YourAccountTokens.Held, on net: Op.Network, account: String) async throws -> Chain.Swap {
        let base = Op.base
        let usdc = Op.dollar(on: base)
        var price = held.token.contract?.lowercased() == net.dollar.lowercased() ? 1 : held.price
        if price == nil { price = await Chain.exchangePrice(net, held.token) }
        guard let price, var sell = estimate(cost: cost, price: price, decimals: held.token.decimals) else {
            throw Chain.Failure(message: String(localized: "No price for \(held.token.symbol) on \(net.name)"))
        }
        func quote(_ amount: String) async throws -> YourAccountSwap.Quote {
            net == base
                ? try await Chain.swapQuote(net, sell: held.token, buy: usdc, amount: amount, account: account)
                : try await Chain.crossQuote(net, to: base, sell: held.token, buy: usdc, amount: amount, account: account)
        }
        var q = try await quote(sell)
        if !covers(minimum: q.minimumBuy, cost: cost) {
            guard let more = rescale(sold: sell, minimum: q.minimumBuy, cost: cost) else {
                throw Chain.Failure(message: String(localized: "No pool pays enough USDC for this"))
            }
            sell = more
            q = try await quote(sell)
            guard covers(minimum: q.minimumBuy, cost: cost) else {
                throw Chain.Failure(message: String(localized: "The price moved. Try again"))
            }
        }
        guard Op.atMost(sell, held.units) else {
            throw Chain.Failure(message: String(localized: "Not enough \(held.token.symbol) on \(net.name)"))
        }
        return Chain.Swap(network: net, sell: held.token, buy: usdc, amount: sell, quote: q, to: net == base ? nil : base)
    }

    /// Waits until the account holds at least `cost` USDC on Base: read every
    /// five seconds, for fifteen minutes at most (Across fills in seconds to
    /// minutes). False when it never arrived.
    @MainActor
    static func arrived(cost: String, account: String) async -> Bool {
        let base = Op.base, usdc = Op.dollar(on: base).contract?.lowercased()
        let until = Date().addingTimeInterval(15 * 60)
        while !Task.isCancelled, Date() < until {
            let held = await YourAccountTokens.held(account, on: base)
            if let have = held.first(where: { $0.token.contract?.lowercased() == usdc }), Op.atMost(cost, have.units) { return true }
            try? await Task.sleep(for: .seconds(5))
        }
        return false
    }
}
