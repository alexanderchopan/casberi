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
/// *For* is Uniswap's open token list (prd §1542, `OpenTokenList`, was
/// Relay's search): the network's tokens on it with nothing typed, the ones
/// matching as you type. A pasted address the list does not carry is read
/// off the chain (`symbol()`, `decimals()`) and says it is "Not on Uniswap's
/// list", so a look-alike never passes as the real one.
enum YourAccountTokens {
    typealias Op = YourAccountOp

    struct Listed: Equatable, Identifiable, Sendable {
        let token: Op.Token
        let name: String
        /// On Uniswap's token list. One that is not is still offered, and
        /// said to be not.
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

    // MARK: - The open list

    /// The list's tokens per network, read once a day.
    @MainActor private static var open: (tokens: [Int: [OpenTokenList.Entry]], at: Date)?
    /// The one read in flight: three networks asking at once fetch it once.
    @MainActor private static var reading: Task<[Int: [OpenTokenList.Entry]], Never>?

    /// Uniswap's list, fetched once a day (it is about 860 KB), the
    /// account's networks only. Empty when it could not be read: For then
    /// offers what you hold, and typed or pasted contracts read off the chain.
    @MainActor
    private static func openList() async -> [Int: [OpenTokenList.Entry]] {
        if let open, open.at.timeIntervalSinceNow > -86_400, !open.tokens.isEmpty { return open.tokens }
        if let reading { return await reading.value }
        let task = Task { @MainActor () -> [Int: [OpenTokenList.Entry]] in
            guard let url = URL(string: OpenTokenList.url),
                  let (data, http) = await IngestSupport.sendRequest(URLRequest(url: url), service: "Your account"),
                  http.statusCode == 200 else { return [:] }
            let chains = Set(Op.networks.filter { !$0.isTest }.map(\.chainId))
            return OpenTokenList.parse(data, chains: chains)
        }
        reading = task
        let tokens = await task.value
        reading = nil
        guard !tokens.isEmpty else { return open?.tokens ?? [:] }
        open = (tokens, .now)
        return tokens
    }

    /// The list's tokens on `net` matching `term`; with nothing typed, the
    /// network's whole list, ETH first. Empty where the account does not swap
    /// (a test network).
    @MainActor
    static func list(_ net: Op.Network, term: String = "") async -> [Listed] {
        guard YourAccountSwap.supported(net) else { return [] }
        // The demo asks for nothing (§1475): its own few tokens.
        if YourAccountDemo.isOn {
            let q = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return YourAccountDemo.list(net).filter {
                q.isEmpty || $0.token.symbol.lowercased().contains(q) || $0.name.lowercased().contains(q)
            }
        }
        let q = term.trimmingCharacters(in: .whitespacesAndNewlines)
        let weth = YourAccountSwap.book(net.chainId)?.weth
        var out: [Listed] = q.isEmpty || "ether".contains(q.lowercased()) || Op.eth.symbol.lowercased().hasPrefix(q.lowercased())
            ? [Listed(token: Op.eth, name: "Ether", onList: true)] : []
        let found = OpenTokenList.search(await openList()[net.chainId] ?? [], q).filter { $0.address != weth }
        for e in found {
            out.append(Listed(token: Op.Token(symbol: e.symbol, decimals: e.decimals, contract: EIP55.checksum(e.address)),
                              name: e.name, onList: true))
        }
        // A listed token's logo goes to the icon book (prd §1534), so its row
        // draws its picture rather than its initials: the stablecoins For
        // offers unasked, and what a search finds. Never the whole list: its
        // pictures would crowd the holdings' own out of the book, and every
        // token on it would count as marked (`major`).
        let pictured = q.isEmpty ? found.filter { stablecoins.contains($0.symbol.uppercased()) } : Array(found.prefix(40))
        TokenIconBook.fill(pictured.compactMap { e in e.logo.map { (e.symbol, $0) } })
        return out
    }

    /// A pasted contract: the list's entry when it carries it, else what the
    /// chain says its symbol and decimals are, marked not on the list.
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

    /// The stablecoins For offers with nothing typed (prd §1532), mark or
    /// no mark. Uppercase.
    static let stablecoins: Set<String> = [
        "USDC", "USDT", "USDT0", "DAI", "USDS", "PYUSD", "USDG", "USDE", "FDUSD",
        "EURC", "GHO", "FRAX", "LUSD", "CRVUSD", "RLUSD", "USD1", "USDBC", "TUSD",
    ]

    /// **ONLY THE TOKENS YOU WOULD KNOW, UNASKED (prd §1532, user: "why don't
    /// we just show stablecoins, and ones we have icons for").** The list
    /// for a network runs to hundreds of tokens, many with no name anyone
    /// recognises. With nothing typed, For offers what is on Uniswap's list
    /// AND is a stablecoin or wears a mark (`marked`, the app's own artwork
    /// or the icon book). Typed words and a pasted contract still reach
    /// every token, and what you hold always shows.
    static func major(_ l: Listed, marked: (String) -> Bool) -> Bool {
        l.onList && (stablecoins.contains(l.token.symbol.uppercased()) || marked(l.token.symbol))
    }

    /// What a search in For shows: with nothing typed, what you hold then
    /// the list's head (only what `shows` keeps); typed, symbols that start
    /// with it, then names that hold it, what you hold first in each. Forty
    /// at most.
    static func matches(_ query: String, in list: [Listed], held: [Held],
                        shows: (Listed) -> Bool = { _ in true }) -> [Listed] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let heldIDs = Set(held.map(\.id))
        let mine = held.map { h in list.first { $0.id == h.id } ?? Listed(token: h.token, name: h.token.symbol, onList: false) }
        guard !q.isEmpty else {
            return Array((mine + list.filter { !heldIDs.contains($0.id) && shows($0) }).prefix(40))
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
        await read(account, on: net) ?? []
    }

    /// `held`, or nil when no node answered for any token: a read that
    /// failed is not an empty account (user: "i have money in my account
    /// but casberi says i can't receive or swap").
    @MainActor
    static func read(_ account: String, on net: Op.Network) async -> [Held]? {
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
        // **ONE ROW PER TOKEN (prd §1494, user: "here it is showing USDG
        // twice").** A token is its contract, whatever its spelling: the
        // network's dollar is written checksummed and a remembered buy as
        // the list spelled it, so whole-value equality let USDG in twice.
        func has(_ token: Op.Token) -> Bool {
            candidates.contains { $0.contract?.lowercased() == token.contract?.lowercased() }
        }
        for token in remembered(on: net) where !has(token) { candidates.append(token) }
        let listed = await list(net)
        var unread: [String] = []
        for r in reading.prefix(30) {
            guard let contract = r.contract, ENS.isHexAddress(contract),
                  !candidates.contains(where: { $0.contract?.lowercased() == contract.lowercased() }),
                  !unread.contains(where: { $0.lowercased() == contract.lowercased() }) else { continue }
            if let known = listed.first(where: { $0.token.contract?.lowercased() == contract.lowercased() }) {
                candidates.append(known.token)
            } else {
                unread.append(contract)
            }
        }
        // The list's strangers read off the chain at once (prd §1601), not
        // one after another.
        let strangers = await withTaskGroup(of: (Int, Op.Token?).self) { group in
            for (i, contract) in unread.enumerated() { group.addTask { (i, await readToken(contract, on: net)) } }
            var out: [Int: Op.Token] = [:]
            for await (i, token) in group { if let token { out[i] = token } }
            return out
        }
        candidates += unread.indices.compactMap { strangers[$0] }
        var (found, answered) = await balances(account, candidates, on: net)
        #if DEBUG
        let samples = await sampleHoldings(on: net)
        found = found.filter { h in !samples.contains { $0.token == h.token } } + samples
        if !samples.isEmpty { answered = true }
        #endif
        guard answered else { return nil }
        // A token the Wallet has not priced is priced off the pools (prd §1542).
        var priced: [Held] = []
        await withTaskGroup(of: Held.self) { group in
            for h in found {
                let known = price(h.token)
                group.addTask {
                    let p: Double? = if let known { known } else { await YourAccountChain.exchangePrice(net, h.token) }
                    return Held(token: h.token, units: h.units, price: p)
                }
            }
            for await h in group { priced.append(h) }
        }
        var seen = Set<String>()
        return priced
            .sorted { ($0.usd ?? -1, $0.token.symbol) > ($1.usd ?? -1, $1.token.symbol) }
            .filter { seen.insert($0.id).inserted }
    }

    /// **EVERY BALANCE IN ONE CALL (prd §1601, user: "it takes way too long
    /// … to read networks").** One `eth_call` per token was a request over
    /// Tor each, all on one circuit, which a node answers with 429s in a
    /// burst (prd §1597); Multicall3 asks for all of them at once, ETH through
    /// its `getEthBalance`. A network the pools are not read on, or a call
    /// that fails, is read token by token as before. `answered` is false
    /// only when no node answered at all.
    private static func balances(_ account: String, _ tokens: [Op.Token], on net: Op.Network) async -> (held: [Held], answered: Bool) {
        if YourAccountSwap.book(net.chainId) != nil, !tokens.isEmpty {
            let owner = YourAccount.w(account)
            let calls = tokens.map { token -> (to: String, data: [UInt8]) in
                token.contract.map { ($0, YourAccount.sel("balanceOf(address)") + owner) }
                    ?? (YourAccountSwap.multicall3, YourAccount.sel("getEthBalance(address)") + owner)
            }
            if let answers = try? await YourAccountChain.aggregate(net, calls) {
                let held = zip(tokens, answers).compactMap { token, answer -> Held? in
                    guard answer.ok, answer.data.count >= 32,
                          let units = Op.decimal(hexQuantity: SafeABI.hex(Array(answer.data.prefix(32)))), units != "0" else { return nil }
                    return Held(token: token, units: units, price: nil)
                }
                return (held, true)
            }
        }
        var found: [Held] = []
        var answered = false
        await withTaskGroup(of: (answered: Bool, held: Held?).self) { group in
            for token in tokens {
                group.addTask {
                    guard let units = await YourAccountChain.balance(net, token, of: account) else { return (false, nil) }
                    return (true, units == "0" ? nil : Held(token: token, units: units, price: nil))
                }
            }
            for await r in group {
                answered = answered || r.answered
                if let h = r.held { found.append(h) }
            }
        }
        return (found, answered)
    }

    #if DEBUG
    /// `-moveHoldings "<chainId>:<SYMBOL>:<amount>[,…]"` (DEBUG): pretend the
    /// account holds these, in place of what it really holds of each, so the sentence's lists, dollars, quotes and Add
    /// can be tried on a simulator with no funded account (user, 2026-10-20:
    /// "i can't try a batch swap b/c we don't have tokens"). The pools quote
    /// any amount; the simulation before Face ID refuses to sign what the
    /// account cannot pay, so nothing pretended can leave.
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
