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
/// It reaches nothing: holdings, Uniswap's list and a swap's estimate are read
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
    /// A token two days old that Uniswap's list does not carry (prd §1513's demo).
    static let pepe2 = Op.Token(symbol: "PEPE2", decimals: 18, contract: "0x9e7ac1d2b3f4e5a6b7c8d9e0f1a2b3c4d5e6f702")

    /// One price a whole token, in dollars, for every token the demo names.
    static func price(_ token: Op.Token) -> Double? {
        switch token.symbol.uppercased() {
        case "ETH": 3_850
        case "USDC", "USDG": 1
        case "CBBTC": 108_000
        case "AERO": 0.92
        case "MAG7": 41.5
        case "PEPE2": 0.0000012
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
            // AERO and PEPE2 are the demo's dust (prd §1537): Sweep takes
            // the first and leaves the second, which Uniswap's list does not carry.
            return [h(Op.dollar(on: net), "248.40"), h(Op.eth, "0.0842"), h(cbBTC, "0.0011"),
                    h(aero, "0.6"), h(pepe2, "200000")]
        case Op.robinhood.chainId:
            return [h(Op.dollar(on: net), "62.00"), h(mag7, "3.2"), h(Op.eth, "0.0031")]
        case Op.ethereum.chainId:
            return [h(Op.eth, "0.021")]
        default:
            return []
        }
    }

    /// The demo account's dollars across its networks (prd §1614): the demo's
    /// holdings read never reads this address, so the Safe pick's figure adds
    /// it, as a real install's read already counts your account.
    static var totalUSD: Double {
        Op.networks.flatMap(held(on:)).reduce(0) { sum, h in
            guard let price = h.price, let units = Decimal(string: h.units) else { return sum }
            return sum + NSDecimalNumber(decimal: units / pow(10, h.token.decimals)).doubleValue * price
        }
    }

    /// What the swap picker offers in the demo: what it holds, and a few more.
    static func list(_ net: Op.Network) -> [Listed] {
        // The dust is listed below as Uniswap's list carries it: PEPE2 is not on it.
        var out = held(on: net).filter { $0.token != aero && $0.token != pepe2 }
            .map { Listed(token: $0.token, name: name($0.token), onList: true) }
        if net.chainId == Op.base.chainId {
            out.append(Listed(token: aero, name: "Aerodrome", onList: true))
            out.append(Listed(token: pepe2, name: "Pepe 2", onList: false))
        }
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
    /// less a pool's usual few tenths of a percent, on Base's Uniswap 0.05%
    /// pool. It carries no calls, and the sentence never signs in the demo.
    static func quote(sell: Op.Token, buy: Op.Token, amount: String) -> YourAccountSwap.Quote? {
        guard let sp = price(sell), let bp = price(buy), bp > 0,
              let units = Decimal(string: amount) else { return nil }
        let dollars = (units / pow(10, sell.decimals)) * Decimal(sp)
        func base(_ d: Decimal) -> String {
            var r = Decimal(), v = d * pow(10, buy.decimals) / Decimal(bp)
            NSDecimalRound(&r, &v, 0, .down)
            return NSDecimalNumber(decimal: r).stringValue
        }
        let book = YourAccountSwap.base
        let hop = YourAccountSwap.Hop(from: sell.contract?.lowercased() ?? book.weth, to: buy.contract?.lowercased() ?? book.weth,
                                      step: 500)
        return YourAccountSwap.Quote(sellAmount: amount, buyAmount: base(dollars * Decimal(0.997)),
                                     minimumBuy: base(dollars * Decimal(0.99)),
                                     route: YourAccountSwap.Route(venue: book.venues[0], hops: [hop]), calls: [])
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

    // MARK: - Warnings (prd §1513)

    /// The demo person's history and the addresses each warning needs: one
    /// they paid on Oct 3, one that imitates it, one GoPlus reports, one whose
    /// token refuses the transfer, and one never paid.
    static let paid = "0x71c7656ec7ab88b098defb751b7401b5f6d849a2"
    static let paidOn = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 10, day: 3).date ?? .now
    static let imitator = "0x5e1f7a3b9c0d2e4f6a8b0c2d4e6f8a0b2c4d49a2"
    static let reported = "0xd9a1b5c3e7f09a2b4c6d8e0f1a3b5c7d9e1f07fe"
    static let refusing = "0xbad0c0ffee00000000000000000000000000bad1"
    static let stranger = "0x2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e"

    /// What Move's checks find in the demo, off this table, never a service.
    static func findings(to: [String], token: YourAccountTokens.Listed?) -> (findings: [MoveWarnings.Finding], checkedWith: [String]) {
        var out: [MoveWarnings.Finding] = []
        for a in to.map({ $0.lowercased() }) {
            switch a {
            case reported: out.append(.scam(address: a, sources: "SlowMist, ScamSniffer")); out.append(.firstSend)
            case imitator: out.append(.lookalike(of: paid, name: nil, paid: paidOn))
            case paid, refusing: break
            default: out.append(.firstSend)
            }
        }
        if let token, token.token == pepe2 {
            out.append(.contract(token: true, unverified: !token.onList, ageDays: 2, neverUsed: true))
        }
        return (out, [String(localized: "GoPlus's reports (SlowMist, ScamSniffer)")])
    }

    // MARK: - The recovery check (prd §1515)

    /// The demo's key is due, so Needs you shows the row.
    static let recoveryCheckDue = true

    /// The demo's check off the table: an owner on Base and Ethereum, not on
    /// Robinhood yet (the canvas's figure 13); `failing` makes Ethereum
    /// refuse it, for the red sentence.
    static func recoveryResult(failing: Bool) -> YourAccountRecoveryCheck.Result {
        YourAccountRecoveryCheck.Result(keyPresent: true, signed: true, networks: [
            .init(name: Op.base.name, chainId: Op.base.chainId, standing: .owner),
            .init(name: Op.ethereum.name, chainId: Op.ethereum.chainId, standing: failing ? .notOwner : .owner),
            .init(name: Op.robinhood.name, chainId: Op.robinhood.chainId, standing: .notOnYet),
        ], at: .now)
    }

    // MARK: - Your own node (prd §1517)

    /// The demo's node on Base, as the canvas draws it; the rest on the list.
    static var ownNode: OwnNode.Settings {
        OwnNode.Settings(on: true, nodes: [String(Op.base.chainId): "https://base.mynode.home:8545"])
    }
    static var ownNodeVerdicts: [Int: OwnNode.Verdict] {
        [Op.base.chainId: .answers(chainId: Op.base.chainId, block: 31_882_104)]
    }

    /// What every act says in the demo.
    static var actsLater: String { String(localized: "This works once you leave the demo.") }
}
