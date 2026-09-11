import Foundation

/// **WHAT AN ADDRESS HOLDS BESIDES THE CHAIN'S OWN COIN (prd §688).**
///
/// The three ethrex devnets each read one number per account — `eth_getBalance`
/// — so every room's Holdings scope had exactly one asset to show and drew a
/// split by ADDRESS instead. That was recorded in three places as "this chain
/// has one asset", and it was wrong: measured 2026-09-11 against the live
/// chains, Hegotá Frames carries `YDS` and `DAI`, Hegotá UTXO carries `BONUS`,
/// `PEPE` and `SHIB`, and the app simply never asked. (Hegotá Privacy really
/// does carry none — only system predeploys — which is a fact about that chain
/// and is stated in its room rather than assumed for the family.)
///
/// **DISCOVERY IS PER ADDRESS, NOT PER CHAIN.** The obvious read is "every
/// Transfer log ever, then group by contract" — 14,392 logs on the privacy
/// chain today and unbounded tomorrow. Filtering on the ADDRESS instead
/// (`topics: [Transfer, from]` and `[Transfer, nil, to]`) returns exactly the
/// tokens this account has ever touched, which is the set a balance read could
/// possibly be non-zero for: **a token you have never sent or received cannot
/// be in your wallet.** Two requests per address, and the cost is proportional
/// to what you watch rather than to the chain.
///
/// **A ZERO BALANCE IS NOT A HOLDING.** An address that once received a token
/// and spent all of it keeps its Transfer logs forever; listing it at 0 would
/// fill Holdings with things you do not have. Zeroes are dropped, and an
/// address that holds no token at all reports none — which is a real answer
/// the room states in a line, never a one-cell treemap at 100% (§610).
///
/// **NOTHING HERE IS MONEY.** These are test tokens on a devnet with no market
/// and no price; a symbol and a quantity is the whole of what is known, exactly
/// as `FramesMoney` says of the native coin. No sorting by value, no share of a
/// portfolio, no dollar anywhere.
enum DevnetTokens {

    /// One token an address actually holds.
    struct Holding: Equatable, Sendable, Identifiable, Codable {
        var id: String { contract.lowercased() }
        /// The token contract.
        let contract: String
        /// Its own `symbol()`, or nil when the call did not answer — a token
        /// that cannot name itself is still a holding, and the room shows its
        /// short address rather than inventing a name.
        let symbol: String?
        /// Its own `decimals()`. **18 is NOT assumed on a failed read**: a
        /// 6-decimal token rendered at 18 reads as a millionth of itself, so a
        /// token whose decimals did not answer keeps nil and the room draws the
        /// raw quantity rather than a wrong one.
        let decimals: Int?
        /// The raw balance, in the token's own smallest unit.
        let raw: Decimal

        /// The quantity as a number, or nil where `decimals` did not read.
        var amount: Double? {
            guard let decimals else { return nil }
            var divisor = Decimal(1)
            for _ in 0..<max(0, decimals) { divisor *= 10 }
            return NSDecimalNumber(decimal: raw / divisor).doubleValue
        }
    }

    /// `Transfer(address,address,uint256)`.
    static let transferTopic =
        "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

    /// Contracts whose Transfer logs are the chain's own plumbing rather than a
    /// token anybody holds — measured on all three devnets, where they are the
    /// two addresses every account's log history contains.
    static let systemContracts: Set<String> = [
        "0xfffffffffffffffffffffffffffffffffffffffe",
        "0x00000000a11acc355c0de0000a11acc355c0de00",
    ]

    /// An address padded to a 32-byte log topic.
    static func topic(_ address: String) -> String {
        let bare = address.hasPrefix("0x") ? String(address.dropFirst(2)) : address
        return "0x" + String(repeating: "0", count: max(0, 64 - bare.count)) + bare.lowercased()
    }

    /// `balanceOf(address)` / `symbol()` / `decimals()` calldata.
    static func balanceOfData(_ address: String) -> String {
        let bare = address.hasPrefix("0x") ? String(address.dropFirst(2)) : address
        return "0x70a08231" + String(repeating: "0", count: max(0, 64 - bare.count)) + bare.lowercased()
    }
    static let symbolData = "0x95d89b41"
    static let decimalsData = "0x313ce567"

    /// The contracts an address has ever sent or received, from its own logs.
    /// Deduplicated, lowercased, system contracts removed.
    static func contracts(in logs: [[String: Any]]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for log in logs {
            guard let address = (log["address"] as? String)?.lowercased(),
                  !systemContracts.contains(address),
                  !seen.contains(address) else { continue }
            seen.insert(address)
            out.append(address)
        }
        return out
    }

    /// A `bytes`-returning `eth_call` result decoded as a string — the ABI's
    /// offset/length/data triple. Nil on anything that does not parse, which
    /// includes the several tokens that answer `symbol()` with a `bytes32`.
    static func decodeString(_ hex: String?) -> String? {
        guard let hex else { return nil }
        let body = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        guard body.count >= 128 else { return nil }
        let start = body.index(body.startIndex, offsetBy: 64)
        let lengthHex = String(body[start..<body.index(start, offsetBy: 64)])
        guard let length = Int(lengthHex, radix: 16), length > 0,
              body.count >= 128 + length * 2 else { return nil }
        let dataStart = body.index(body.startIndex, offsetBy: 128)
        let data = String(body[dataStart..<body.index(dataStart, offsetBy: length * 2)])
        var bytes: [UInt8] = []
        var i = data.startIndex
        while i < data.endIndex {
            let j = data.index(i, offsetBy: 2)
            guard let b = UInt8(data[i..<j], radix: 16) else { return nil }
            bytes.append(b)
            i = j
        }
        let text = String(decoding: bytes, as: UTF8.self)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// A hex quantity as a `Decimal`, exactly — **never a `Double`**. A token
    /// balance is up to 2^256 and a `Double` has 53 bits of mantissa, so the
    /// obvious parse silently rounds the low digits off every balance it
    /// touches. `FramesRoom.curve` paid for this once already.
    static func decimal(fromHex raw: String?) -> Decimal? {
        guard let raw else { return nil }
        let body = raw.hasPrefix("0x") ? String(raw.dropFirst(2)) : raw
        guard !body.isEmpty, body.count <= 64 else { return nil }
        var out = Decimal(0)
        for ch in body {
            guard let digit = ch.hexDigitValue else { return nil }
            out = out * 16 + Decimal(digit)
        }
        return out
    }

    /// Read what one address holds.
    ///
    /// `call` is the room's own JSON-RPC door, handed in rather than reached
    /// for, so this file stays chain-agnostic and every bridge keeps its own
    /// host list, failover and logging.
    static func holdings(address: String,
                         cap: Int = 12,
                         call: (String, [Any]) async -> Any?) async -> [Holding] {
        async let out = call("eth_getLogs", [["fromBlock": "0x0", "toBlock": "latest",
                                              "topics": [transferTopic, topic(address)]]])
        async let into = call("eth_getLogs", [["fromBlock": "0x0", "toBlock": "latest",
                                               "topics": [transferTopic, NSNull(), topic(address)]]])
        let logs = ((await out) as? [[String: Any]] ?? []) + ((await into) as? [[String: Any]] ?? [])
        var found: [Holding] = []
        // Bounded: an address that has touched dozens of tokens is a test
        // harness, not a person, and the treemap draws six cells anyway.
        for contract in contracts(in: logs).prefix(cap) {
            guard let raw = decimal(fromHex: await call(
                    "eth_call", [["to": contract, "data": balanceOfData(address)], "latest"]) as? String),
                  raw > 0 else { continue }
            let symbol = decodeString(await call(
                "eth_call", [["to": contract, "data": symbolData], "latest"]) as? String)
            let decimals = (decimal(fromHex: await call(
                "eth_call", [["to": contract, "data": decimalsData], "latest"]) as? String))
                .map { NSDecimalNumber(decimal: $0).intValue }
            found.append(Holding(contract: contract, symbol: symbol,
                                 decimals: decimals, raw: raw))
        }
        // Biggest quantity first. NOT "by value" — there is none — so this is
        // a ranking of amounts within each token's own unit, which is the only
        // order the data supports and is stated as such in the room.
        return found.sorted { ($0.amount ?? 0) > ($1.amount ?? 0) }
    }
}
