import Foundation

/// **YOUR ACCOUNT'S SWAP (prd §1430) — the order and its bytes.** A swap is
/// a CoW Protocol order the account PRE-SIGNS: CoW's solvers fill it at the
/// best price they find, and the account signs nothing CoW could change.
///
/// The order is built HERE from CoW's quote — the account as owner and
/// receiver, the quote's amounts, the slippage taken off what it receives —
/// and its id (`digest ‖ owner ‖ validTo`) is computed here with
/// `CowOrder.digest`, the hashing §1285 proved on nine real orders. CoW's
/// API is told the order and must answer with that same id; the account then
/// signs one operation that wraps ETH when ETH is sold (CoW trades WETH),
/// approves exactly the amount sold to CoW's vault relayer, and calls the
/// settlement contract's `setPreSignature(uid, true)`. A server that answered
/// with anything else is refused before a prompt: the person approves only
/// the order the page describes.
///
/// Pure (Foundation, `CowOrder`, `SafeABI`); the requests are
/// `YourAccountChain`'s.
enum YourAccountSwap {
    /// CoW's vault relayer, the one address an approval goes to — the same
    /// on every chain CoW settles on.
    static let vaultRelayer = "0xC92E8bdf79f0507f65a392b0ab4667716BFE0110"

    /// CoW's placeholder for a buy paid out in ETH (`CowOrders.native`).
    static let nativeETH = "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

    /// Wrapped ETH, which CoW trades in place of ETH.
    static func weth(chainId: Int) -> String? {
        switch chainId {
        case 1: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
        case 8453: "0x4200000000000000000000000000000000000006"
        default: nil
        }
    }

    /// Where CoW settles: Base and Ethereum (none on Base Sepolia).
    static func supported(_ network: YourAccountOp.Network) -> Bool {
        CowOrder.apiNetwork[network.chainId] != nil && weth(chainId: network.chainId) != nil
    }

    /// Off what it receives: 0.5%, CoW's own default.
    static let slippageBasisPoints = 50

    /// Who made the order, for CoW's records.
    static let appData = #"{"appCode":"Casberi","metadata":{},"version":"1.3.0"}"#
    static var appDataHash: [UInt8] { Keccak256.hash(Array(appData.utf8)) }

    /// The token CoW is told about: WETH when selling ETH; CoW's native
    /// placeholder when buying it (paid out as ETH).
    static func cowToken(_ token: YourAccountOp.Token, on network: YourAccountOp.Network, selling: Bool) -> String? {
        if let contract = token.contract { return contract.lowercased() }
        return selling ? weth(chainId: network.chainId)?.lowercased() : nativeETH
    }

    // MARK: - The quote

    struct Quote: Equatable, Sendable {
        /// What is sold, all of it (the fee is taken from the surplus).
        let sellAmount: String
        /// What the quote says comes back.
        let buyAmount: String
        /// At least this comes back, or the order does not fill.
        let minimumBuy: String
        /// CoW's estimate of the network cost, in the sold token.
        let fee: String
        let validTo: UInt32
        let id: Int?
    }

    /// CoW's quote, read strictly; nil for anything malformed.
    static func quote(from json: [String: Any]) -> Quote? {
        guard let q = json["quote"] as? [String: Any],
              let sell = q["sellAmount"] as? String, sell.allSatisfy(\.isNumber),
              let buy = q["buyAmount"] as? String, buy.allSatisfy(\.isNumber),
              let fee = q["feeAmount"] as? String, fee.allSatisfy(\.isNumber),
              let validTo = (q["validTo"] as? NSNumber)?.int64Value, validTo > 0, validTo <= Int64(UInt32.max),
              let minimum = minus(basisPoints: slippageBasisPoints, of: buy)
        else { return nil }
        return Quote(sellAmount: YourAccountOp.sum(sell, fee), buyAmount: buy, minimumBuy: minimum,
                     fee: fee, validTo: UInt32(validTo), id: (json["id"] as? NSNumber)?.intValue)
    }

    /// `amount` less `bp` basis points, rounded down: digit arithmetic, so a
    /// token with 18 decimals never meets a floating point.
    static func minus(basisPoints bp: Int, of amount: String) -> String? {
        guard !amount.isEmpty, amount.allSatisfy(\.isNumber), (0...10_000).contains(bp) else { return nil }
        // amount × (10000 − bp) ÷ 10000, by long multiplication then division.
        var product: [Int] = Array(repeating: 0, count: amount.count + 5)
        let factor = 10_000 - bp
        var carry = 0
        let digits = amount.reversed().map { Int(String($0))! }
        for i in 0..<product.count {
            let d = i < digits.count ? digits[i] : 0
            let v = d * factor + carry
            product[i] = v % 10
            carry = v / 10
        }
        var text = String(product.reversed().map { Character(String($0)) }).drop { $0 == "0" }
        guard text.count > 4 else { return "0" }
        text = text.dropLast(4)
        return String(text)
    }

    // MARK: - The order

    /// The order the account signs: its terms, as `CowOrder` hashes them.
    static func order(sell: YourAccountOp.Token, buy: YourAccountOp.Token, on network: YourAccountOp.Network,
                      account: String, quote: Quote) -> CowOrder.Order? {
        guard let sellToken = cowToken(sell, on: network, selling: true),
              let buyToken = cowToken(buy, on: network, selling: false),
              let sellAmount = SafeABI.word(uint256: quote.sellAmount),
              let buyAmount = SafeABI.word(uint256: quote.minimumBuy),
              let zero = SafeABI.word(uint256: "0") else { return nil }
        return CowOrder.Order(sellToken: sellToken, buyToken: buyToken, receiver: account.lowercased(),
                              sellAmount: sellAmount, buyAmount: buyAmount, validTo: quote.validTo,
                              appData: appDataHash, feeAmount: zero, kind: "sell", partiallyFillable: false,
                              sellTokenBalance: "erc20", buyTokenBalance: "erc20")
    }

    /// The order's id: its EIP-712 digest, the owner, the expiry.
    static func uid(_ order: CowOrder.Order, owner: String, chainId: Int) -> [UInt8]? {
        guard let digest = CowOrder.digest(order, chainId: chainId),
              let ownerWord = SafeABI.word(address: owner) else { return nil }
        let t = order.validTo
        return digest + Array(ownerWord.suffix(20)) + [UInt8(t >> 24), UInt8(t >> 16 & 0xff), UInt8(t >> 8 & 0xff), UInt8(t & 0xff)]
    }

    /// The body CoW's `POST /orders` takes for this order, pre-signed.
    static func orderBody(_ order: CowOrder.Order, owner: String, quoteId: Int?) -> [String: Any] {
        var body: [String: Any] = [
            "sellToken": order.sellToken, "buyToken": order.buyToken, "receiver": order.receiver ?? owner,
            "sellAmount": SafeCalldata.decimal(order.sellAmount), "buyAmount": SafeCalldata.decimal(order.buyAmount),
            "validTo": Int(order.validTo), "feeAmount": "0", "kind": order.kind,
            "partiallyFillable": order.partiallyFillable,
            "sellTokenBalance": order.sellTokenBalance, "buyTokenBalance": order.buyTokenBalance,
            "signingScheme": "presign", "signature": "0x", "from": owner,
            "appData": appData, "appDataHash": SafeABI.hex(appDataHash),
        ]
        if let quoteId { body["quoteId"] = quoteId }
        return body
    }

    // MARK: - The account's calls

    /// An order CoW has taken under the id this phone computed.
    struct Placed: Equatable {
        let order: CowOrder.Order
        let uid: [UInt8]
        let sellingETH: Bool
    }

    /// Wrap when ETH is sold, approve exactly what is sold, pre-sign the order.
    static func calls(order: CowOrder.Order, uid: [UInt8], sellingETH: Bool, network: YourAccountOp.Network) -> [YourAccountOp.Call]? {
        calls(orders: [Placed(order: order, uid: uid, sellingETH: sellingETH)], network: network)
    }

    /// **EVERY ORDER IN ONE OPERATION (prd §1436, batch swaps).** One wrap for
    /// all the ETH the orders sell, then ONE approval per sold token for the
    /// SUM its orders sell — `approve` replaces the allowance rather than
    /// adding to it, so two approvals of one token would leave the first
    /// order unfillable — then each order's pre-signature, in order.
    static func calls(orders: [Placed], network: YourAccountOp.Network) -> [YourAccountOp.Call]? {
        guard !orders.isEmpty, orders.allSatisfy({ $0.uid.count == 56 }),
              let wethAddress = weth(chainId: network.chainId),
              let zero = SafeABI.word(uint256: "0") else { return nil }
        var out: [YourAccountOp.Call] = []
        let wrapped = orders.filter(\.sellingETH).map(\.order.sellAmount)
        if !wrapped.isEmpty {
            guard let total = total(wrapped) else { return nil }
            out.append(.init(operation: 0, to: wethAddress, value: total, data: YourAccount.sel("deposit()")))
        }
        var tokens: [String] = []
        var sold: [String: [[UInt8]]] = [:]
        for o in orders {
            if sold[o.order.sellToken] == nil { tokens.append(o.order.sellToken) }
            sold[o.order.sellToken, default: []].append(o.order.sellAmount)
        }
        for token in tokens {
            guard let amount = total(sold[token] ?? []) else { return nil }
            let approve = YourAccount.sel("approve(address,uint256)") + YourAccount.w(vaultRelayer) + amount
            out.append(.init(operation: 0, to: token, value: zero, data: approve))
        }
        for o in orders {
            let preSign = YourAccount.sel("setPreSignature(bytes,bool)") + YourAccount.w(64) + YourAccount.w(1)
                + YourAccount.dynamic(o.uid)
            out.append(.init(operation: 0, to: CowOrder.settlement, value: zero, data: preSign))
        }
        return out
    }

    /// The sum of amount words, as a word: digit arithmetic through
    /// `YourAccountOp.sum`, never a machine integer.
    private static func total(_ words: [[UInt8]]) -> [UInt8]? {
        var sum = "0"
        for w in words { sum = YourAccountOp.sum(sum, SafeCalldata.decimal(w)) }
        return SafeABI.word(uint256: sum)
    }
}
