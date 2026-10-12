import Foundation

/// The app half of `CowOrder` (prd §1285): before the Safe sign block draws a
/// transaction that pre-signs a CoW order, ask CoW's public API for the order
/// by its id, keep it only if `CowOrder.verify` proves it hashes to that id,
/// and read its tokens' decimals off the chain the signer already reads. A
/// failure anywhere leaves the reading exactly as it was (§1282's owner and
/// expiry), never a guess.
enum CowOrders {
    /// The native-coin placeholder CoW uses for a buy token paid out in ETH.
    static let native = "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

    /// At most this many orders are fetched for one transaction; a batch
    /// pre-signing more keeps §1282's reading for the rest.
    private static let maxOrders = 4

    // MARK: - Verified orders, kept for the session

    /// Orders already proven against their ids, by id. An order's terms never
    /// change once signed, so a verified one is kept for the session and the
    /// queue's titles and the sign block share one fetch. Read from the
    /// sweep and the signer, so it sits behind a lock; nothing is persisted.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var proven: [String: (chainId: Int, order: CowOrder.Order)] = [:]

    static func cached(_ uid: [UInt8], chainId: Int) -> CowOrder.Order? {
        lock.lock(); defer { lock.unlock() }
        guard let hit = proven[SafeABI.hex(uid)], hit.chainId == chainId else { return nil }
        return hit.order
    }

    /// The order behind `uid`, proven, fetching it once if it is not kept.
    static func verified(_ uid: [UInt8], chainId: Int) async -> CowOrder.Order? {
        if let hit = cached(uid, chainId: chainId) { return hit }
        guard let url = CowOrder.url(chainId: chainId, uid: uid),
              let json = await IngestSupport.getJSON(url, service: "Wallet DeFi & Safe") as? [String: Any],
              let order = CowOrder.verify(json: json, uid: uid, chainId: chainId)
        else { return nil }
        lock.lock(); proven[SafeABI.hex(uid)] = (chainId, order); lock.unlock()
        return order
    }

    /// The pre-signatures in a transaction as Safe's gateway lists it.
    static func preSignatures(in tx: [String: Any]) -> [(uid: [UInt8], signed: Bool)] {
        guard let to = tx["to"] as? String, let data = tx["data"] as? String, data.count > 10 else { return [] }
        let reading = SafeCalldata.read(data: data, to: to, value: (tx["value"] as? String) ?? "0", safe: "",
                                        operation: SafeGatewayShape.int(tx["operation"]) ?? 0)
        return CowOrder.preSignatures(to: to, data: data, reading: reading)
    }

    /// For the queue's sweep (prd §1285): proves the orders a pass's
    /// transactions pre-sign, at most `maxOrders` new fetches a pass, and
    /// returns their tokens so the pass reads their decimals with the rest.
    static func prefetch(_ txs: [[String: Any]], chainId: Int) async -> Set<String> {
        var tokens = Set<String>()
        var fetched = 0
        for call in txs.flatMap(preSignatures(in:)) {
            if cached(call.uid, chainId: chainId) == nil {
                guard fetched < maxOrders else { continue }
                fetched += 1
            }
            if let order = await verified(call.uid, chainId: chainId) {
                tokens.formUnion([order.sellToken, order.buyToken].filter { $0 != native })
            }
        }
        return tokens
    }

    /// A queue row's phrase for a transaction that pre-signs one proven
    /// order (`CowOrder.queueTitle`), or nil.
    static func title(_ tx: [String: Any], chainId: Int, token: (String) -> ClearSign.Token?) -> String? {
        guard let to = tx["to"] as? String, let data = tx["data"] as? String else { return nil }
        return CowOrder.queueTitle(to: to, data: data, value: (tx["value"] as? String) ?? "0",
                                   operation: SafeGatewayShape.int(tx["operation"]) ?? 0,
                                   order: { cached($0, chainId: chainId) }, token: token)
    }

    // MARK: - The sign block

    static func enrich(_ reading: SafeCalldata, to: String, data: String, safe: String,
                       chainId: Int, network: String?, nativeSymbol: String) async -> SafeCalldata {
        let calls = CowOrder.preSignatures(to: to, data: data, reading: reading)
        guard !calls.isEmpty else { return reading }
        var verified: [String: CowOrder.Order] = [:]
        for call in calls.prefix(maxOrders) {
            guard let order = await self.verified(call.uid, chainId: chainId) else { continue }
            verified[SafeABI.hex(call.uid)] = order
        }
        guard !verified.isEmpty else { return reading }
        var tokens: [String: ClearSign.Token] = [native: ClearSign.Token(ticker: nativeSymbol, decimals: 18)]
        if let network {
            for token in Set(verified.values.flatMap { [$0.sellToken, $0.buyToken] }) where token != native {
                let fact = await WalletApprovals.tokenFacts(network: network, contract: token)
                if let symbol = fact.symbol, let decimals = fact.decimals {
                    tokens[token] = ClearSign.Token(ticker: symbol, decimals: decimals)
                }
            }
        }
        return CowOrder.enrich(reading, to: to, data: data, safe: safe, verified: verified,
                               token: { tokens[$0.lowercased()] },
                               address: { WalletIngest.canonicalName(for: $0) ?? WalletStore.shortAddress(EIP55.checksum($0)) },
                               date: { $0.formatted(date: .abbreviated, time: .shortened) })
    }

    #if DEBUG
    /// `-cowOrderProbe "<chainId>:<0x order id>"` — the sign block's CoW path
    /// for one order, headless: fetched, verified, and the reading it draws.
    static func probe(_ spec: String) async -> [String] {
        let parts = spec.split(separator: ":").map(String.init)
        guard parts.count == 2, let chainId = Int(parts[0]), let uid = SafeABI.hexBytes(parts[1]), uid.count == 56,
              let url = CowOrder.url(chainId: chainId, uid: uid) else { return ["bad spec"] }
        guard let json = await IngestSupport.getJSON(url, service: "Wallet DeFi & Safe") as? [String: Any] else { return ["UNREACHABLE"] }
        guard CowOrder.verify(json: json, uid: uid, chainId: chainId) != nil else { return ["fetched, NOT VERIFIED"] }
        let data = "0xec6cb13f" + String(repeating: "0", count: 62) + "40" + String(repeating: "0", count: 63) + "1"
            + String(repeating: "0", count: 62) + "38" + SafeABI.hex(uid).dropFirst(2) + String(repeating: "0", count: 16)
        let owner = SafeABI.hex(Array(uid[32..<52]))
        let out = await enrich(.undecoded(selector: "0xec6cb13f"), to: CowOrder.settlement, data: data, safe: owner,
                               chainId: chainId, network: chainId == 1 ? "eth-mainnet" : nil, nativeSymbol: "ETH")
        guard case .described(let r) = out else { return ["verified, NOT DRAWN"] }
        return ["verified | \(r.headline)"] + r.lines.map { "\($0.label) = \($0.value)" }
    }
    #endif
}
