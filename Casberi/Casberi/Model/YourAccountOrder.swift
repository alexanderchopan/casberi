import Foundation

/// **A LIMIT ORDER IS SWAP'S LAST WORD (prd §1673).** "Swap 1 ETH on Base for
/// USDC on Base when ETH is $2,400": a CoW Protocol order the account
/// PRE-SIGNS, filled by CoW's solvers when the price is there, never below it.
///
/// The order is built HERE — the account as owner and receiver, the whole
/// amount sold, at least the price's amount back, all or nothing, a week to
/// fill — and its id (`digest ‖ owner ‖ validTo`) is computed here with
/// `CowOrder.digest` (§1285, §1430: measured byte for byte against CoW's own
/// answer on Base). CoW's API is told the order and must answer with that
/// same id; the account then signs one operation that wraps exactly the ETH
/// sold (CoW trades WETH), approves exactly the amount sold to CoW's vault
/// relayer and calls `setPreSignature(uid, true)`. Cancel is
/// `invalidateOrder(uid)` on the same contract: the worst CoW can do is not
/// fill.
///
/// The price arithmetic is digit arithmetic on decimal strings, so an amount
/// with 18 decimals never meets a floating point.
///
/// Pure (Foundation, `CowOrder`, `SafeABI`, `Keccak256`, `YourAccount`'s
/// encoders), so `limit-order-selftest.sh` compiles it whole.
enum YourAccountOrder {
    typealias Op = YourAccountOp

    /// CoW's vault relayer, the one address an approval goes to — the same
    /// on every chain CoW settles on (`vaultRelayer()` of the settlement).
    static let vaultRelayer = "0xC92E8bdf79f0507f65a392b0ab4667716BFE0110"

    /// CoW's placeholder for a buy paid out in ETH.
    static let nativeETH = "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

    /// A week to fill unless the person picks another (prd §1673 item 5).
    static let defaultSeconds: UInt32 = 7 * 24 * 3600

    /// How long an order may wait, as the "Until" word offers it: a day, a
    /// week, a month (prd §1673 item 5).
    static let expiries: [UInt32] = [24 * 3600, 7 * 24 * 3600, 30 * 24 * 3600]

    static func expiryWords(_ seconds: UInt32) -> String {
        switch seconds {
        case 24 * 3600: String(localized: "A day")
        case 7 * 24 * 3600: String(localized: "A week")
        case 30 * 24 * 3600: String(localized: "A month")
        default: String(localized: "\(seconds / 86_400) days")
        }
    }

    /// CoW's limit-order fee, read off its form 2026-11-02 (prd §1673 item 4).
    static let feeWords = "0.02%"

    /// Wrapped ETH, which CoW trades in place of ETH.
    static func weth(chainId: Int) -> String? {
        switch chainId {
        case 1: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
        case 8453: "0x4200000000000000000000000000000000000006"
        default: nil
        }
    }

    /// Where CoW settles of the account's networks: Base and Ethereum.
    static func supported(_ network: Op.Network) -> Bool {
        CowOrder.apiNetwork[network.chainId] != nil && weth(chainId: network.chainId) != nil
    }

    /// Who made the order, for CoW's records.
    static let appData = #"{"appCode":"Casberi","metadata":{},"version":"1.3.0"}"#
    static var appDataHash: [UInt8] { Keccak256.hash(Array(appData.utf8)) }

    /// The token CoW is told about: WETH when selling ETH; CoW's native
    /// placeholder when buying it (paid out as ETH).
    static func cowToken(_ token: Op.Token, on network: Op.Network, selling: Bool) -> String? {
        if let contract = token.contract { return contract.lowercased() }
        return selling ? weth(chainId: network.chainId)?.lowercased() : nativeETH
    }

    // MARK: - Which token the price is of

    private static let dollarSymbols: Set<String> = ["USDC", "USDG", "USDT", "DAI", "USDBC", "USDS"]

    /// A dollar: the network's own, or one of the common stablecoins.
    static func isDollar(_ token: Op.Token, on network: Op.Network) -> Bool {
        if let c = token.contract, c.lowercased() == network.dollar.lowercased() { return true }
        return dollarSymbols.contains(token.symbol.uppercased())
    }

    /// "when ETH is …": the token that is not a dollar; when neither is, the
    /// one bought; nil when both are (a dollar for a dollar has no price).
    static func priced(sell: Op.Token, buy: Op.Token, on network: Op.Network) -> Op.Token? {
        let s = isDollar(sell, on: network), b = isDollar(buy, on: network)
        if s && b { return nil }
        if s { return buy }
        if b { return sell }
        return buy
    }

    /// Whether the sentence draws "when" at all (prd §1673 items 2, 6):
    /// one network, one CoW settles on, and a price to state.
    static func offersWhen(sell: Op.Token, buy: Op.Token, from: Op.Network, to: Op.Network) -> Bool {
        from == to && supported(from) && sell != buy && priced(sell: sell, buy: buy, on: from) != nil
    }

    // MARK: - The price, typed

    /// A typed price or percent: digits with at most one point, commas
    /// dropped, a sign allowed for a percent. Nil for anything else.
    struct Decimal: Equatable {
        /// The digits with the point taken out.
        let digits: String
        /// How many of them follow the point.
        let places: Int
        let negative: Bool

        static func parse(_ text: String, signed: Bool = false) -> Decimal? {
            var t = text.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
                .replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
            var negative = false
            if signed, let f = t.first, f == "-" || f == "−" || f == "+" { negative = f != "+"; t.removeFirst() }
            let parts = t.split(separator: ".", omittingEmptySubsequences: false)
            guard !t.isEmpty, parts.count <= 2, parts.allSatisfy({ $0.allSatisfy(\.isDigitASCII) }),
                  !(parts.first?.isEmpty ?? true) || parts.count == 2 && !parts[1].isEmpty else { return nil }
            let whole = String(parts[0]), frac = parts.count == 2 ? String(parts[1]) : ""
            let digits = String((whole + frac).drop { $0 == "0" })
            return Decimal(digits: digits.isEmpty ? "0" : digits, places: frac.count, negative: negative)
        }

        var isZero: Bool { digits == "0" }
    }

    // MARK: - Digit arithmetic

    /// a × b, both non-negative decimal integers.
    static func times(_ a: String, _ b: String) -> String {
        let x = a.reversed().compactMap(\.wholeNumberValue), y = b.reversed().compactMap(\.wholeNumberValue)
        guard !x.isEmpty, !y.isEmpty else { return "0" }
        var out = Array(repeating: 0, count: x.count + y.count)
        for (i, dx) in x.enumerated() {
            var carry = 0
            for (j, dy) in y.enumerated() {
                let v = out[i + j] + dx * dy + carry
                out[i + j] = v % 10
                carry = v / 10
            }
            var k = i + y.count
            while carry > 0 { let v = out[k] + carry; out[k] = v % 10; carry = v / 10; k += 1 }
        }
        let text = String(out.reversed().map { Character(String($0)) }).drop { $0 == "0" }
        return text.isEmpty ? "0" : String(text)
    }

    /// a × 10^n.
    static func shiftUp(_ a: String, _ n: Int) -> String { a == "0" ? "0" : a + String(repeating: "0", count: max(0, n)) }

    /// ⌊a ÷ 10^n⌋.
    static func shiftDown(_ a: String, _ n: Int) -> String {
        guard n > 0 else { return a }
        return a.count > n ? String(a.dropLast(n)) : "0"
    }

    /// ⌊a ÷ d⌋ for a divisor that fits a machine word.
    static func divided(_ a: String, by d: UInt64) -> String? {
        guard d > 0 else { return nil }
        var out = ""
        var rem: UInt64 = 0
        for ch in a {
            guard let v = ch.wholeNumberValue else { return nil }
            let (m, o1) = rem.multipliedReportingOverflow(by: 10)
            let (n, o2) = m.addingReportingOverflow(UInt64(v))
            guard !o1, !o2 else { return nil }
            out.append(Character(String(n / d)))
            rem = n % d
        }
        let text = out.drop { $0 == "0" }
        return text.isEmpty ? "0" : String(text)
    }

    // MARK: - What comes back at that price

    /// At least what `sellUnits` of `sell` must buy of `buy` when the priced
    /// token is at `price` dollars (prd §1673 item 3). When neither token is
    /// a dollar the price is of the token bought, and the sold token's dollar
    /// price NOW (`sellDollars`, kept to eight places) turns it into a rate:
    /// the rate is fixed when the order is placed.
    static func buyUnits(sellUnits: String, sell: Op.Token, buy: Op.Token, on network: Op.Network,
                         price: Decimal, sellDollars: Double? = nil) -> String? {
        guard !price.isZero, !price.negative, sellUnits.allSatisfy(\.isDigitASCII), !sellUnits.isEmpty,
              let pricedToken = priced(sell: sell, buy: buy, on: network) else { return nil }
        let sellIsDollar = isDollar(sell, on: network)
        let out: String
        if pricedToken == sell && !sellIsDollar && isDollar(buy, on: network) {
            // Selling the priced token for dollars: S × P.
            out = shiftDown(shiftUp(times(sellUnits, price.digits), buy.decimals), price.places + sell.decimals)
        } else if sellIsDollar {
            // Selling dollars for the priced token: S ÷ P.
            guard let p = UInt64(price.digits),
                  let q = divided(shiftUp(sellUnits, price.places + buy.decimals), by: p) else { return nil }
            out = shiftDown(q, sell.decimals)
        } else {
            // Neither a dollar: S × (what the sold token is worth now) ÷ P.
            guard let dollars = sellDollars, dollars > 0, dollars.isFinite,
                  let worth = Decimal.parse(String(format: "%.8f", dollars)),
                  let p = UInt64(price.digits),
                  let q = divided(shiftUp(times(sellUnits, worth.digits), price.places + buy.decimals), by: p)
            else { return nil }
            out = shiftDown(q, worth.places + sell.decimals)
        }
        return out == "0" ? nil : out
    }

    /// The price a percent from today's names, to two places (cents), or to
    /// four significant figures under a dollar: what the order is placed at.
    static func price(percent: Decimal, from now: Double) -> Decimal? {
        guard now > 0, now.isFinite, let pct = Double(percent.digits) else { return nil }
        let shift = pow(10, Double(percent.places))
        let factor = 1 + (percent.negative ? -1 : 1) * (pct / shift) / 100
        guard factor > 0 else { return nil }
        let value = now * factor
        let places = value >= 1 ? 2 : max(2, 3 - Int(floor(log10(value))))
        return Decimal.parse(String(format: "%.\(places)f", value))
    }

    /// How far a price is from today's, "+6.8%" / "−3.1%", one place.
    static func percentWords(_ price: Double, from now: Double) -> String? {
        guard now > 0, price > 0 else { return nil }
        let pct = (price / now - 1) * 100
        let rounded = (pct * 10).rounded() / 10
        if rounded == 0 { return "0%" }
        return (rounded > 0 ? "+" : "−") + String(format: "%.1f", abs(rounded)) + "%"
    }

    /// A typed price as a number, for the line's percent and words.
    static func value(_ d: Decimal) -> Double? {
        guard let n = Double(d.digits) else { return nil }
        return (d.negative ? -1 : 1) * n / pow(10, Double(d.places))
    }

    // MARK: - The order

    /// The order the account pre-signs: sell all of `sellUnits`, at least
    /// `buyUnits` back, all or nothing, until `validTo`.
    static func order(sell: Op.Token, buy: Op.Token, on network: Op.Network, account: String,
                      sellUnits: String, buyUnits: String, validTo: UInt32) -> CowOrder.Order? {
        guard let sellToken = cowToken(sell, on: network, selling: true),
              let buyToken = cowToken(buy, on: network, selling: false),
              let sellAmount = SafeABI.word(uint256: sellUnits),
              let buyAmount = SafeABI.word(uint256: buyUnits),
              let zero = SafeABI.word(uint256: "0") else { return nil }
        return CowOrder.Order(sellToken: sellToken, buyToken: buyToken, receiver: account.lowercased(),
                              sellAmount: sellAmount, buyAmount: buyAmount, validTo: validTo,
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
    static func orderBody(_ order: CowOrder.Order, owner: String) -> [String: Any] {
        [
            "sellToken": order.sellToken, "buyToken": order.buyToken, "receiver": order.receiver ?? owner,
            "sellAmount": Op.decimal(order.sellAmount), "buyAmount": Op.decimal(order.buyAmount),
            "validTo": Int(order.validTo), "feeAmount": "0", "kind": order.kind,
            "partiallyFillable": order.partiallyFillable,
            "sellTokenBalance": order.sellTokenBalance, "buyTokenBalance": order.buyTokenBalance,
            "signingScheme": "presign", "signature": "0x", "from": owner,
            "appData": appData, "appDataHash": SafeABI.hex(appDataHash),
        ]
    }

    // MARK: - The account's calls

    /// Wrap exactly the ETH sold, approve exactly what is sold to the vault
    /// relayer, pre-sign the order. Nothing else, nowhere else.
    static func calls(order: CowOrder.Order, uid: [UInt8], sellingETH: Bool, network: Op.Network) -> [(to: String, data: String, value: String)]? {
        guard uid.count == 56, let wethAddress = weth(chainId: network.chainId) else { return nil }
        var out: [(to: String, data: String, value: String)] = []
        let sold = Op.decimal(order.sellAmount)
        if sellingETH {
            guard order.sellToken.lowercased() == wethAddress.lowercased() else { return nil }
            out.append((wethAddress, SafeABI.hex(YourAccount.sel("deposit()")), sold))
        }
        let approve = YourAccount.sel("approve(address,uint256)") + YourAccount.w(vaultRelayer) + order.sellAmount
        out.append((order.sellToken, SafeABI.hex(approve), "0"))
        out.append((CowOrder.settlement, SafeABI.hex(preSignature(uid)), "0"))
        return out
    }

    static func preSignature(_ uid: [UInt8]) -> [UInt8] {
        YourAccount.sel("setPreSignature(bytes,bool)") + YourAccount.w(64) + YourAccount.w(1) + YourAccount.dynamic(uid)
    }

    /// Cancel: `invalidateOrder(uid)` on the settlement, the owner's own call.
    static func cancelCalls(uid: [UInt8]) -> [(to: String, data: String, value: String)]? {
        guard uid.count == 56 else { return nil }
        let data = YourAccount.sel("invalidateOrder(bytes)") + YourAccount.w(32) + YourAccount.dynamic(uid)
        return [(CowOrder.settlement, SafeABI.hex(data), "0")]
    }
}

private extension Character {
    var isDigitASCII: Bool { isASCII && isNumber }
}
