import Foundation

/// A CoW Protocol order the Safe sign block can state in full, because it is
/// PROVEN to be the order being signed (2026-10-12, prd §1285).
///
/// A Safe pre-signs a CoW order with `setPreSignature(orderUid, true)` on the
/// settlement contract. The calldata carries only the order's id:
/// `digest (32) ‖ owner (20) ‖ validTo (4)`, where `digest` is the EIP-712
/// hash of the order under the domain ("Gnosis Protocol", "v2", chain,
/// settlement). So the order's terms come from CoW's API, and this file
/// re-hashes them HERE: an order is drawn only when its own digest equals the
/// id's and its `validTo` equals the id's last four bytes. A server that
/// answers with anything else — a different amount, another receiver — fails
/// the hash, and the sign block says exactly what it said before (§1282: the
/// owner and the expiry). MEASURED 2026-10-12: nine orders off the settlement
/// contract's `Trade` events, all nine hashed to their ids.
///
/// Pure (Foundation, `Keccak256`, `SafeABI`), so `cow-order-selftest.sh`
/// compiles it whole against saved API replies.
enum CowOrder {
    static let settlement = "0x9008d19f58aabd9ed0d60971565aa8510560ab41"

    /// The API's name for each chain the Safe room reads and CoW settles on.
    static let apiNetwork: [Int: String] = [1: "mainnet", 100: "xdai", 137: "polygon",
                                            8453: "base", 42161: "arbitrum_one"]

    static func url(chainId: Int, uid: [UInt8]) -> URL? {
        guard let net = apiNetwork[chainId], uid.count == 56 else { return nil }
        return URL(string: "https://api.cow.fi/\(net)/api/v1/orders/0x\(SafeABI.hex(uid).dropFirst(2))")
    }

    struct Order: Equatable {
        let sellToken: String
        let buyToken: String
        /// nil = the order's owner (the zero address, as signed).
        let receiver: String?
        let sellAmount: [UInt8]
        let buyAmount: [UInt8]
        let validTo: UInt32
        let appData: [UInt8]
        let feeAmount: [UInt8]
        let kind: String
        let partiallyFillable: Bool
        let sellTokenBalance: String
        let buyTokenBalance: String
    }

    // MARK: - The id

    struct UID: Equatable {
        let digest: [UInt8]
        let owner: String
        let validTo: UInt32
    }

    static func uid(_ bytes: [UInt8]) -> UID? {
        guard bytes.count == 56 else { return nil }
        let t = bytes[52..<56].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        return UID(digest: Array(bytes[0..<32]), owner: SafeABI.hex(Array(bytes[32..<52])), validTo: t)
    }

    /// `setPreSignature(bytes orderUid, bool signed)`'s arguments, or nil for
    /// any other call or any calldata that does not decode exactly.
    static func preSignature(_ data: [UInt8]) -> (uid: [UInt8], signed: Bool)? {
        guard data.count >= 4 + 96,
              SafeABI.hex(Array(data.prefix(4))) == SafeABI.hex(Array(Keccak256.hash(Array("setPreSignature(bytes,bool)".utf8)).prefix(4)))
        else { return nil }
        let args = Array(data.dropFirst(4))
        func small(_ at: Int) -> Int? {
            guard args.count - 32 >= at, args[at..<(at + 24)].allSatisfy({ $0 == 0 }) else { return nil }
            return args[(at + 24)..<(at + 32)].reduce(0) { $0 << 8 | Int($1) }
        }
        guard let offset = small(0), offset == 64, let flag = small(32), flag <= 1,
              let length = small(64), length == 56, args.count - 96 >= 56 else { return nil }
        return (Array(args[96..<152]), flag == 1)
    }

    // MARK: - The terms, read strictly

    /// The API's order, every signed field present and well formed, or nil.
    static func parse(_ json: [String: Any]) -> Order? {
        func address(_ k: String) -> String? {
            guard let s = (json[k] as? String)?.lowercased(), s.hasPrefix("0x"), s.count == 42,
                  s.dropFirst(2).allSatisfy(\.isHexDigit) else { return nil }
            return s
        }
        func amount(_ k: String) -> [UInt8]? {
            guard let s = json[k] as? String, !s.isEmpty, s.allSatisfy(\.isNumber) else { return nil }
            return SafeABI.word(uint256: s)
        }
        guard let sell = address("sellToken"), let buy = address("buyToken"),
              let sellAmount = amount("sellAmount"), let buyAmount = amount("buyAmount"),
              let fee = amount("feeAmount"),
              let validTo = (json["validTo"] as? NSNumber)?.int64Value, validTo >= 0, validTo <= Int64(UInt32.max),
              let appHex = json["appData"] as? String, let app = SafeABI.hexBytes(appHex), app.count == 32,
              let kind = json["kind"] as? String, ["sell", "buy"].contains(kind),
              let partial = json["partiallyFillable"] as? Bool,
              let sellBalance = json["sellTokenBalance"] as? String, ["erc20", "external", "internal"].contains(sellBalance),
              let buyBalance = json["buyTokenBalance"] as? String, ["erc20", "internal"].contains(buyBalance)
        else { return nil }
        let receiver: String?
        if json["receiver"] == nil || json["receiver"] is NSNull { receiver = nil }
        else {
            guard let r = address("receiver") else { return nil }
            receiver = r == "0x" + String(repeating: "0", count: 40) ? nil : r
        }
        return Order(sellToken: sell, buyToken: buy, receiver: receiver, sellAmount: sellAmount, buyAmount: buyAmount,
                     validTo: UInt32(validTo), appData: app, feeAmount: fee, kind: kind, partiallyFillable: partial,
                     sellTokenBalance: sellBalance, buyTokenBalance: buyBalance)
    }

    // MARK: - The hash

    private static func k(_ s: String) -> [UInt8] { Keccak256.hash(Array(s.utf8)) }
    private static func word(_ n: UInt64) -> [UInt8] { Array(repeating: 0, count: 24) + withUnsafeBytes(of: n.bigEndian, Array.init) }
    private static func word(address: String) -> [UInt8]? { SafeABI.word(address: address) }

    static func digest(_ o: Order, chainId: Int) -> [UInt8]? {
        let domainType = k("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
        let orderType = k("Order(address sellToken,address buyToken,address receiver,uint256 sellAmount,uint256 buyAmount,uint32 validTo,bytes32 appData,uint256 feeAmount,string kind,bool partiallyFillable,string sellTokenBalance,string buyTokenBalance)")
        guard chainId > 0, let settle = word(address: settlement),
              let sell = word(address: o.sellToken), let buy = word(address: o.buyToken),
              let receiver = word(address: o.receiver ?? "0x" + String(repeating: "0", count: 40))
        else { return nil }
        let domain = Keccak256.hash(domainType + k("Gnosis Protocol") + k("v2") + word(UInt64(chainId)) + settle)
        let structHash = Keccak256.hash(orderType + sell + buy + receiver + o.sellAmount + o.buyAmount
            + word(UInt64(o.validTo)) + o.appData + o.feeAmount + k(o.kind)
            + word(o.partiallyFillable ? 1 : 0) + k(o.sellTokenBalance) + k(o.buyTokenBalance))
        return Keccak256.hash([0x19, 0x01] + domain + structHash)
    }

    /// The API's answer as the order being signed, or nil unless it hashes to
    /// the id and expires when the id says. A receiver the API filled in as
    /// the owner is tried as the zero address it was signed as.
    static func verify(json: [String: Any], uid bytes: [UInt8], chainId: Int) -> Order? {
        guard let id = uid(bytes), let order = parse(json), order.validTo == id.validTo else { return nil }
        if digest(order, chainId: chainId) == id.digest { return order }
        if order.receiver == id.owner.lowercased() {
            let signed = Order(sellToken: order.sellToken, buyToken: order.buyToken, receiver: nil,
                               sellAmount: order.sellAmount, buyAmount: order.buyAmount, validTo: order.validTo,
                               appData: order.appData, feeAmount: order.feeAmount, kind: order.kind,
                               partiallyFillable: order.partiallyFillable,
                               sellTokenBalance: order.sellTokenBalance, buyTokenBalance: order.buyTokenBalance)
            if digest(signed, chainId: chainId) == id.digest { return signed }
        }
        return nil
    }

    // MARK: - The words

    /// An amount in a token's units: "166", "1.004078716069741972". Without
    /// decimals it is base units and kept out of any sentence.
    static func units(_ word: [UInt8], decimals: Int) -> String {
        let digits = SafeCalldata.decimal(word)
        guard decimals > 0 else { return digits }
        let padded = String(repeating: "0", count: max(0, decimals + 1 - digits.count)) + digits
        let whole = padded.dropLast(decimals)
        var fraction = String(padded.suffix(decimals))
        while fraction.hasSuffix("0") { fraction.removeLast() }
        return fraction.isEmpty ? String(whole) : "\(whole).\(fraction)"
    }

    /// The sign block's reading of a verified pre-signature. `token` names a
    /// token with its decimals when they are known; `address` names anything
    /// else; `safe` is the account signing.
    static func reading(_ o: Order, uid bytes: [UInt8], signed: Bool, safe: String,
                        token: (String) -> ClearSign.Token?, address: (String) -> String,
                        date: (Date) -> String) -> ClearSign.Reading? {
        guard let id = uid(bytes) else { return nil }
        func phrase(_ amount: [UInt8], _ t: String) -> (text: String, clean: Bool) {
            if let known = token(t) { return ("\(units(amount, decimals: known.decimals)) \(known.ticker)", true) }
            return ("\(SafeCalldata.decimal(amount)) base units of \(address(t))", false)
        }
        let sell = phrase(o.sellAmount, o.sellToken), buy = phrase(o.buyAmount, o.buyToken)
        let isSell = o.kind == "sell"
        let sentence = sell.clean && buy.clean
            ? (isSell ? "Sell \(sell.text) for at least \(buy.text)" : "Buy exactly \(buy.text) for at most \(sell.text)")
            : nil
        var lines: [ClearSign.Reading.Line] = [
            .init(label: "Approval", value: signed ? "Approve the order" : "Withdraw approval"),
            .init(label: isSell ? "Sell" : "Pay at most", value: sell.text),
            .init(label: isSell ? "Receive at least" : "Buy exactly", value: buy.text),
        ]
        let owner = id.owner.lowercased()
        let receiver = o.receiver ?? owner
        lines.append(.init(label: "Paid to", value: receiver == safe.lowercased() ? "this Safe" : address(receiver)))
        if owner != safe.lowercased() { lines.append(.init(label: "Order owner", value: address(owner))) }
        if !o.feeAmount.allSatisfy({ $0 == 0 }) { lines.append(.init(label: "Fee", value: phrase(o.feeAmount, o.sellToken).text)) }
        lines.append(.init(label: "Fills", value: o.partiallyFillable ? "In parts" : "All at once"))
        lines.append(.init(label: "Valid until", value: date(Date(timeIntervalSince1970: TimeInterval(o.validTo)))))
        lines.append(.init(label: "Checked", value: "Matches the order id it signs"))
        return ClearSign.Reading(owner: "Casberi", contract: "GPv2Settlement (CoW Protocol)",
                                 intent: signed ? "Sign a CoW Protocol order" : "Withdraw a CoW Protocol order",
                                 sentence: signed ? sentence : nil, lines: lines)
    }

    // MARK: - Where they sit in a Safe transaction

    /// Every order id a transaction pre-signs or withdraws: the call itself,
    /// or each call inside its batch, sent to the settlement contract.
    static func preSignatures(to: String, data: String, reading: SafeCalldata) -> [(uid: [UInt8], signed: Bool)] {
        var out: [(uid: [UInt8], signed: Bool)] = []
        func take(_ to: String, _ data: String) {
            guard to.lowercased() == settlement, let bytes = SafeABI.hexBytes(data),
                  let p = preSignature(bytes) else { return }
            out.append(p)
        }
        if case .batch(let calls) = reading {
            for call in calls where call.operation == 0 { take(call.to, call.data) }
        } else {
            take(to, data)
        }
        return out
    }

    /// The reading with each verified pre-signature stated in full. A call
    /// whose order did not verify keeps the reading it had.
    static func enrich(_ reading: SafeCalldata, to: String, data: String, safe: String,
                       verified: [String: Order], token: (String) -> ClearSign.Token?,
                       address: (String) -> String, date: (Date) -> String) -> SafeCalldata {
        func described(_ to: String, _ data: String, _ fallback: SafeCalldata) -> SafeCalldata {
            guard to.lowercased() == settlement, let bytes = SafeABI.hexBytes(data),
                  let p = preSignature(bytes), let order = verified[SafeABI.hex(p.uid)],
                  let r = CowOrder.reading(order, uid: p.uid, signed: p.signed, safe: safe,
                                           token: token, address: address, date: date)
            else { return fallback }
            return .described(r)
        }
        if case .batch(let calls) = reading {
            return .batch(calls.map { call in
                guard call.operation == 0 else { return call }
                var c = call
                c = SafeCalldata.BatchCall(operation: call.operation, to: call.to, value: call.value,
                                           reading: described(call.to, call.data, call.reading), data: call.data)
                return c
            })
        }
        return described(to, data, reading)
    }
}
