import Foundation

/// **THE DEMO'S OWN ACCOUNT (prd §1475, user, 2026-10-23: "In the demo these
/// are empty. need to have seeded data so user can see what things are
/// like").** The demo is one person's life (§1026); now that person has an
/// account too, so Move, Security's box and Your account's rows draw what
/// they would hold: dollars and ETH on Base, MAG7 on Robinhood Chain, a
/// Signer, a $100 monthly limit, round-ups to ETH.
///
/// It is never a key. Nothing here can sign, and every act that would send,
/// swap, buy or change a key says it works once you leave the demo, as the
/// demo's other acts do (§83: a control that looks live says what it is).
/// It reaches nothing: holdings, Relay's list and a swap's estimate are read
/// off the table below, never a node, so the demo's reach ledger stays
/// empty.
enum YourAccountDemo {
    typealias Op = YourAccountOp
    typealias Held = YourAccountTokens.Held
    typealias Listed = YourAccountTokens.Listed

    /// On while the demo is: the person's real account, if any, stands aside.
    static var isOn: Bool { DemoMode.isActive }

    /// A demo address no key can sign for.
    static let address = "0xDE70a11ce0C4F7e2b9a1D3C5e7F90B2D4a6c8e01"
    /// The demo person's Signer, a wallet of their own.
    static let signer = "0x5A1E7C93b0d24F86a1C3E5b7d9f0A2C4E6B8d203"

    static func isDemo(_ account: String) -> Bool {
        isOn && account.caseInsensitiveCompare(address) == .orderedSame
    }

    /// The account the screens show: the demo's in the demo, else this phone's.
    static var shownAddress: String? { isOn ? address : YourAccountKey.address }

    /// This phone's own account, or the demo's while the demo is on.
    static func isYours(_ account: String) -> Bool {
        [YourAccountKey.address, shownAddress].compactMap { $0 }
            .contains { WalletWatch.sameAddress($0, account) }
    }

    static let cbBTC = Op.Token(symbol: "cbBTC", decimals: 8, contract: "0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf")
    static let aero = Op.Token(symbol: "AERO", decimals: 18, contract: "0x940181a94A35A4569E4529A3CDfB74e38FD98631")
    static let mag7 = Op.Token(symbol: "MAG7", decimals: 18, contract: "0x152f7613f362Abf1C05DB2EF2D6ef220302bf840")

    /// One price a whole token, in dollars, for every token the demo names.
    static func price(_ token: Op.Token) -> Double? {
        switch token.symbol.uppercased() {
        case "ETH": 3_850
        case "USDC", "USDG": 1
        case "CBBTC": 108_000
        case "AERO": 0.92
        case "MAG7": 41.5
        default: nil
        }
    }

    static func held(on net: Op.Network) -> [Held] {
        func h(_ token: Op.Token, _ whole: String) -> Held {
            let units = (Decimal(string: whole) ?? 0) * pow(10, token.decimals)
            var rounded = Decimal(), value = units
            NSDecimalRound(&rounded, &value, 0, .down)
            return Held(token: token, units: NSDecimalNumber(decimal: rounded).stringValue, price: price(token))
        }
        switch net.chainId {
        case Op.base.chainId:
            return [h(Op.dollar(on: net), "248.40"), h(Op.eth, "0.0842"), h(cbBTC, "0.0011")]
        case Op.robinhood.chainId:
            return [h(Op.dollar(on: net), "62.00"), h(mag7, "3.2"), h(Op.eth, "0.0031")]
        case Op.ethereum.chainId:
            return [h(Op.eth, "0.021")]
        default:
            return []
        }
    }

    /// What the swap picker offers in the demo: what it holds, and a few more.
    static func list(_ net: Op.Network) -> [Listed] {
        var out = held(on: net).map { Listed(token: $0.token, name: name($0.token), onList: true) }
        if net.chainId == Op.base.chainId { out.append(Listed(token: aero, name: "Aerodrome", onList: true)) }
        return out
    }

    private static func name(_ token: Op.Token) -> String {
        switch token.symbol.uppercased() {
        case "ETH": "Ether"
        case "USDC": "USD Coin"
        case "USDG": "Global Dollar"
        case "CBBTC": "Coinbase Wrapped BTC"
        case "MAG7": "MAG7 Index"
        default: token.symbol
        }
    }

    /// A swap's estimate off the table: the sold dollars at the bought price,
    /// less Relay's usual few tenths of a percent. It carries no calls, and
    /// the sentence never signs in the demo.
    static func quote(sell: Op.Token, buy: Op.Token, amount: String) -> YourAccountSwap.Quote? {
        guard let sp = price(sell), let bp = price(buy), bp > 0,
              let units = Decimal(string: amount) else { return nil }
        let dollars = (units / pow(10, sell.decimals)) * Decimal(sp)
        func base(_ d: Decimal) -> String {
            var r = Decimal(), v = d * pow(10, buy.decimals) / Decimal(bp)
            NSDecimalRound(&r, &v, 0, .down)
            return NSDecimalNumber(decimal: r).stringValue
        }
        return YourAccountSwap.Quote(sellAmount: amount, buyAmount: base(dollars * Decimal(0.997)),
                                     minimumBuy: base(dollars * Decimal(0.99)), fee: "0",
                                     requestId: nil, calls: [])
    }

    /// The demo's round-ups: to the next $1, buying ETH on Base.
    static var roundUps: RoundUps.Setting { RoundUps.Setting(on: true, step: 1, target: .ethOnBase) }

    /// Security's box (§1462): the demo's limit, Signer and round-ups.
    static var facts: YourAccountFacts {
        YourAccountFacts(limitDollars: 100, limitPeriod: MoveSecurity.LimitPeriod.month.word,
                         signers: 1, roundUpStep: 1, roundUpSymbol: "ETH")
    }

    /// The demo's plan, for Your account's rows: $100 of each coin a month.
    static func plan(on net: Op.Network) -> YourAccount7579.Plan {
        YourAccountChain.limitPlan(on: net, dollars: 100, ethPrice: price(Op.eth),
                                   minutes: MoveSecurity.LimitPeriod.month.minutes)
    }

    // MARK: - Details (prd §1509)

    /// The demo's next nonce and the key its next move moves to, as Details
    /// and Raw transaction draw them.
    static let previewNonce: UInt64 = 14
    static let previewKey = 5
    /// A public key that is no key of anyone's: two fixed words, so the
    /// demo's calldata is the encoders' own bytes and never this phone's.
    static var previewKeyXY: (x: [UInt8], y: [UInt8]) {
        (Keccak256.hash(Array("casberi demo key x".utf8)), Keccak256.hash(Array("casberi demo key y".utf8)))
    }

    /// The most a unit of gas costs on each network, in wei: fees of about
    /// a cent on Base and Robinhood and a dollar or two on Ethereum.
    static func previewMaxFee(on net: Op.Network) -> UInt64 {
        switch net.chainId {
        case Op.ethereum.chainId: 700_000_000
        case Op.robinhood.chainId: 4_000_000
        default: 5_000_000
        }
    }

    /// Relay's usual fee on a swap, four hundredths of a percent of it.
    static func relayFee(_ sold: String) -> String {
        guard let units = Decimal(string: sold) else { return "0" }
        var r = Decimal(), v = units * Decimal(string: "0.0004")!
        NSDecimalRound(&r, &v, 0, .down)
        return NSDecimalNumber(decimal: r).stringValue
    }

    /// What every act says in the demo.
    static var actsLater: String { String(localized: "This works once you leave the demo.") }
}
