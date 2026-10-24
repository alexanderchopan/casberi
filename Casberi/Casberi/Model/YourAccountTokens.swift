import Foundation

/// **WHAT THE SENTENCE OFFERS (prd §1438)** — the tokens Move's sentence
/// picks from.
///
/// *With* is what the account holds on one network: ETH and USDC, read off
/// the chain every time, and every other token the Wallet's last reading saw
/// at this address (`WalletIngest.lastKnownHoldings(owner:)`), each read back
/// off the chain for its exact balance before it is offered. A token is
/// priced only by that reading (dollars over amount); one it never priced
/// offers no dollars.
///
/// *For* is Relay's token search (prd §1440): with nothing typed, what you
/// hold and the main tokens Relay verifies (§1488); its matches as you type,
/// each marked verified or not.
/// A pasted address Relay does not know is read off the chain (`symbol()`,
/// `decimals()`) and says it is "Not verified by Relay", so a look-alike
/// never passes as the real one.
enum YourAccountTokens {
    typealias Op = YourAccountOp

    struct Listed: Equatable, Identifiable, Sendable {
        let token: Op.Token
        let name: String
        /// Verified by Relay. One that is not is still offered, and said
        /// to be not.
        let onList: Bool
        var id: String { token.contract?.lowercased() ?? token.symbol }
    }

    struct Held: Equatable, Identifiable, Sendable {
        let token: Op.Token
        /// Exact, in base units, as the chain answered.
        let units: String
        /// Dollars for one whole token, from the Wallet's last reading.
        let price: Double?
        var id: String { token.contract?.lowercased() ?? token.symbol }
        var usd: Double? { price.map { Op.dollars(units, decimals: token.decimals, price: $0) } }
    }

    // MARK: - Relay's search

    @MainActor private static var lists: [Int: (tokens: [Listed], at: Date)] = [:]

    /// Relay's tokens on `net` matching `term`, verified first; with nothing
    /// typed, its list for the network, ETH first, kept an hour. Empty where
    /// the account does not swap (a test network).
    @MainActor
    static func list(_ net: Op.Network, term: String = "") async -> [Listed] {
        guard YourAccountSwap.supported(net) else { return [] }
        // The demo asks Relay nothing (§1475): its own few tokens.
        if YourAccountDemo.isOn {
            let q = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return YourAccountDemo.list(net).filter {
                q.isEmpty || $0.token.symbol.lowercased().contains(q) || $0.name.lowercased().contains(q)
            }
        }
        let q = term.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty, let cached = lists[net.chainId], cached.at.timeIntervalSinceNow > -3_600 { return cached.tokens }
        var seen: Set<String> = []
        var out: [Listed] = q.isEmpty ? [Listed(token: Op.eth, name: "Ether", onList: true)] : []
        if q.isEmpty { seen.insert(Op.eth.symbol) }
        for c in await YourAccountChain.relayCurrencies(net, term: q) {
            guard let address = c["address"] as? String,
                  let symbol = c["symbol"] as? String, !symbol.isEmpty, symbol.count <= 16,
                  let decimals = c["decimals"] as? Int, (0...36).contains(decimals) else { continue }
            let verified = ((c["metadata"] as? [String: Any])?["verified"] as? Bool) ?? false
            let token: Op.Token
            if address.lowercased() == YourAccountSwap.native {
                token = Op.eth
            } else {
                guard ENS.isHexAddress(address) else { continue }
                token = Op.Token(symbol: symbol, decimals: decimals, contract: EIP55.checksum(address))
            }
            let id = token.contract?.lowercased() ?? token.symbol
            guard seen.insert(id).inserted else { continue }
            out.append(Listed(token: token, name: (c["name"] as? String) ?? symbol, onList: verified))
        }
        // Verified first, each group in Relay's order.
        out = out.filter(\.onList) + out.filter { !$0.onList }
        if q.isEmpty, out.count > 1 { lists[net.chainId] = (out, .now) }
        return out
    }

    /// A pasted contract: CoW's entry when it lists it, else what the chain
    /// says its symbol and decimals are, marked not on the list.
    @MainActor
    static func lookUp(_ address: String, on net: Op.Network) async -> Listed? {
        guard ENS.isHexAddress(address) else { return nil }
        if let known = await list(net, term: address).first(where: { $0.token.contract?.lowercased() == address.lowercased() }) {
            return known
        }
        guard let token = await readToken(address, on: net) else { return nil }
        return Listed(token: token, name: token.symbol, onList: false)
    }

    private static func readToken(_ address: String, on net: Op.Network) async -> Op.Token? {
        async let symbolHex = try? YourAccountChain.ethCall(net, to: address, data: YourAccount.sel("symbol()"))
        async let decimalsHex = try? YourAccountChain.ethCall(net, to: address, data: YourAccount.sel("decimals()"))
        guard let s = await symbolHex, let symbol = Op.abiString(s),
              let d = await decimalsHex, let decimals = Op.decimal(hexQuantity: d).flatMap({ Int($0) }),
              (0...36).contains(decimals) else { return nil }
        return Op.Token(symbol: symbol, decimals: decimals, contract: EIP55.checksum(address))
    }

    /// The tokens For offers with nothing typed (prd §1488): the money
    /// people swap between, verified by Relay. Anything else is a search.
    static let main: Set<String> = ["ETH", "WETH", "USDC", "USDT", "DAI", "EURC", "CBBTC", "WBTC", "CBETH", "WSTETH"]

    /// What a search in For shows: with nothing typed, what you hold then
    /// the main tokens Relay verifies; typed, symbols that start with it,
    /// then names that hold it, what you hold first in each. Forty at most.
    static func matches(_ query: String, in list: [Listed], held: [Held]) -> [Listed] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let heldIDs = Set(held.map(\.id))
        let mine = held.map { h in list.first { $0.id == h.id } ?? Listed(token: h.token, name: h.token.symbol, onList: false) }
        guard !q.isEmpty else {
            let head = list.filter { !heldIDs.contains($0.id) && $0.onList && main.contains($0.token.symbol.uppercased()) }
            return Array((mine + head).prefix(40))
        }
        func rank(_ l: Listed) -> Int? {
            let symbol = l.token.symbol.lowercased(), name = l.name.lowercased()
            if symbol == q { return 0 }
            if symbol.hasPrefix(q) { return 1 }
            if name.hasPrefix(q) { return 2 }
            if name.contains(q) || symbol.contains(q) { return 3 }
            return nil
        }
        let pool = mine + list.filter { !heldIDs.contains($0.id) }
        return pool.compactMap { l in rank(l).map { (l, $0, heldIDs.contains(l.id) ? 0 : 1) } }
            .sorted { ($0.1, $0.2) < ($1.1, $1.2) }
            .prefix(40)
            .map(\.0)
    }

    // MARK: - What a swap bought

    private struct Kept: Codable { let symbol: String; let decimals: Int; let contract: String? }
    private static func boughtKey(_ net: Op.Network) -> String { "yourAccount.bought.\(net.chainId)" }

    /// A token a swap paid the account (§1442l), read as a candidate holding
    /// until the Wallet's own reading lists it: the sentence can spend what it
    /// just bought. Twenty at most, newest kept.
    static func remember(_ token: Op.Token, on net: Op.Network) {
        guard token.contract != nil else { return }
        var kept = remembered(on: net).filter { $0 != token }
        kept.insert(token, at: 0)
        let stored = kept.prefix(20).map { Kept(symbol: $0.symbol, decimals: $0.decimals, contract: $0.contract) }
        if let data = try? JSONEncoder().encode(Array(stored)) { UserDefaults.standard.set(data, forKey: boughtKey(net)) }
    }

    static func remembered(on net: Op.Network) -> [Op.Token] {
        guard let data = UserDefaults.standard.data(forKey: boughtKey(net)),
              let kept = try? JSONDecoder().decode([Kept].self, from: data) else { return [] }
        return kept.map { Op.Token(symbol: $0.symbol, decimals: $0.decimals, contract: $0.contract) }
    }

    // MARK: - What you hold

    /// The account's tokens on `net` with something in them, biggest first.
    @MainActor
    static func held(_ account: String, on net: Op.Network) async -> [Held] {
        // The demo's account holds the demo's table, read off no node (§1475).
        if YourAccountDemo.isDemo(account) { return YourAccountDemo.held(on: net) }
        let reading = await WalletIngest.lastKnownHoldings(owner: account)
            .filter { $0.network == Op.appName(net) }
        func price(_ token: Op.Token) -> Double? {
            let row = reading.first { r in
                token.contract.map { r.contract?.lowercased() == $0.lowercased() }
                    ?? (r.contract == nil && r.symbol.uppercased() == token.symbol.uppercased())
            }
            guard let row, let amount = row.amount, amount > 0, row.usd > 0 else { return nil }
            return row.usd / amount
        }
        var candidates = Op.tokens(on: net)
        for token in remembered(on: net) where !candidates.contains(token) { candidates.append(token) }
        let listed = await list(net)
        for r in reading.prefix(30) {
            guard let contract = r.contract, ENS.isHexAddress(contract),
                  !candidates.contains(where: { $0.contract?.lowercased() == contract.lowercased() }) else { continue }
            if let known = listed.first(where: { $0.token.contract?.lowercased() == contract.lowercased() }) {
                candidates.append(known.token)
            } else if let token = await readToken(contract, on: net) {
                candidates.append(token)
            }
        }
        let tokens = candidates
        var found: [Held] = []
        await withTaskGroup(of: Held?.self) { group in
            for token in tokens {
                group.addTask {
                    guard let units = await YourAccountChain.balance(net, token, of: account), units != "0" else { return nil }
                    return Held(token: token, units: units, price: nil)
                }
            }
            for await h in group { if let h { found.append(h) } }
        }
        #if DEBUG
        let samples = await sampleHoldings(on: net)
        found = found.filter { h in !samples.contains { $0.token == h.token } } + samples
        #endif
        // A token the Wallet has not priced asks Relay, so dollars always work.
        var priced: [Held] = []
        await withTaskGroup(of: Held.self) { group in
            for h in found {
                let known = price(h.token)
                group.addTask {
                    let p: Double? = if let known { known } else { await YourAccountChain.relayPrice(net, h.token) }
                    return Held(token: h.token, units: h.units, price: p)
                }
            }
            for await h in group { priced.append(h) }
        }
        return priced
            .sorted { ($0.usd ?? -1, $0.token.symbol) > ($1.usd ?? -1, $1.token.symbol) }
    }

    #if DEBUG
    /// `-moveHoldings "<chainId>:<SYMBOL>:<amount>[,…]"` (DEBUG): pretend the
    /// account holds these, in place of what it really holds of each, so the sentence's lists, dollars, quotes and Add
    /// can be tried on a simulator with no funded account (user, 2026-10-20:
    /// "i can't try a batch swap b/c we don't have tokens"). Relay quotes an
    /// account that cannot pay; the simulation before Face ID refuses to sign
    /// one, so nothing pretended can leave.
    @MainActor
    private static func sampleHoldings(on net: Op.Network) async -> [Held] {
        guard let spec = UserDefaults.standard.string(forKey: "moveHoldings"), !spec.isEmpty else { return [] }
        var out: [Held] = []
        for part in spec.split(separator: ",") {
            let f = part.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
            guard f.count == 3, Int(f[0]) == net.chainId else { continue }
            let symbol = f[1].uppercased()
            var token = Op.tokens(on: net).first { $0.symbol.uppercased() == symbol }
            if token == nil {
                token = (await list(net)).first { $0.token.symbol.uppercased() == symbol && $0.onList }?.token
            }
            guard let token,
                  let units = Op.baseUnits(f[2], decimals: token.decimals), units != "0" else { continue }
            out.append(Held(token: token, units: units, price: nil))
        }
        NSLog("moveHoldings: %d on %@", out.count, net.name)
        return out
    }
    #endif
}
