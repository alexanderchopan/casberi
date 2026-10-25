import Foundation

/// **RECEIVE FROM ANOTHER WALLET (prd §1506).** What a wallet of your own
/// elsewhere holds, sorted into what moves to your account and what stays,
/// and the transactions that wallet is asked to send. Pure: amounts are
/// base-unit decimal strings, so `wallet-sweep-selftest.sh` reads it with no
/// network and no SwiftUI.
///
/// - A coin already on one of your account's networks goes straight to your
///   address there: a plain transfer.
/// - A coin elsewhere goes to the Relay deposit address for its route (the
///   address "Receive from another network" shows), and arrives on Base.
/// - Each network's own coin goes LAST and leaves what that network's sends
///   cost, with room to spare; a network without enough of it for its sends
///   moves nothing, and says so.
/// - Under `floorUSD` (Relay's routes under `relayFloorUSD`) stays, named.
///
/// Casberi signs nothing here: the other wallet is asked, and signs or not.
enum WalletSweep {

    /// One coin the other wallet holds, read off the chain.
    struct Holding: Equatable, Sendable, Identifiable {
        let chainId: Int
        let networkName: String
        let symbol: String
        /// nil for the network's own coin.
        let contract: String?
        let decimals: Int
        /// Base units, a decimal string.
        let raw: String
        let usd: Double
        var id: String { "\(chainId):\(contract?.lowercased() ?? "native")" }
        var isNative: Bool { contract == nil }
    }

    enum Way: Equatable, Sendable {
        /// Straight to your account on this network.
        case direct
        /// Through Relay: send to this deposit address; it lands on your
        /// account's network as `arrives`.
        case relay(address: String, arrives: String)
    }

    /// One send the other wallet is asked for.
    struct Leg: Equatable, Sendable, Identifiable {
        let holding: Holding
        /// What it sends, base units: the whole holding, or the network's
        /// own coin less what the sends cost.
        let amount: String
        let usd: Double
        var way: Way
        var id: String { holding.id }
    }

    enum Stay: Equatable, Sendable {
        case tooSmall
        /// Relay does not bridge it from that network.
        case noRoute
        /// That network's own coin would not cover the sends.
        case noGas
        /// Kept to pay for the sends.
        case forGas
    }

    struct Plan: Equatable, Sendable {
        var legs: [Leg]
        var stays: [(Holding, Stay)]
        var totalUSD: Double { legs.reduce(0) { $0 + $1.usd } }
        static func == (a: Plan, b: Plan) -> Bool {
            a.legs == b.legs && a.stays.map(\.0) == b.stays.map(\.0) && a.stays.map(\.1) == b.stays.map(\.1)
        }
    }

    static let floorUSD = 1.0
    /// Relay's deposit routes refuse small amounts (prd §1485); under this,
    /// a coin is not sent to one.
    static let relayFloorUSD = 5.0
    /// Gas units a send is costed at: a token transfer, the coin's own.
    static let tokenGas: Decimal = 65_000
    static let nativeGas: Decimal = 21_000
    /// Headroom over the costed gas, for the price moving between the read
    /// and the last approval.
    static let gasHeadroom: Decimal = 3
    /// The least an ETH network keeps, whatever its gas price reads: an OP
    /// network's L1 fee is not in `eth_gasPrice` (0.00002 ETH).
    static let ethFloorWei: Decimal = 20_000_000_000_000

    /// `holdings` sorted into sends and stays. `yours` are the networks your
    /// account has its own address on; `relayable(chainId, contract)` says
    /// whether Relay bridges that coin from there; `gasPrice` is wei per gas
    /// by network.
    static func plan(_ holdings: [Holding], yours: Set<Int>,
                     relayable: (Int, String?) -> Bool,
                     gasPrice: [Int: Decimal]) -> Plan {
        var legs: [Leg] = []
        var stays: [(Holding, Stay)] = []
        let byNetwork = Dictionary(grouping: holdings, by: \.chainId)
        // Your own networks first, then the most money first.
        let order = byNetwork.keys.sorted { a, b in
            let ya = yours.contains(a), yb = yours.contains(b)
            if ya != yb { return ya }
            let ua = byNetwork[a]!.reduce(0) { $0 + $1.usd }, ub = byNetwork[b]!.reduce(0) { $0 + $1.usd }
            return ua != ub ? ua > ub : a < b
        }
        for chain in order {
            let here = byNetwork[chain]!.sorted { $0.usd != $1.usd ? $0.usd > $1.usd : $0.symbol < $1.symbol }
            let direct = yours.contains(chain)
            let floor = direct ? floorUSD : relayFloorUSD
            var tokens: [Holding] = []
            for h in here where !h.isNative {
                if h.usd < floor { stays.append((h, .tooSmall)) }
                else if !direct && !relayable(chain, h.contract) { stays.append((h, .noRoute)) }
                else { tokens.append(h) }
            }
            let native = here.first { $0.isNative }
            let nativeRaw = native.flatMap { Decimal(string: $0.raw) } ?? 0
            let price = gasPrice[chain] ?? 0
            let tokenCost = price * tokenGas * Decimal(tokens.count) * gasHeadroom
            // No gas price read, or not enough of the coin for the tokens:
            // nothing on this network can be sent.
            guard price > 0, nativeRaw >= tokenCost else {
                for h in tokens { stays.append((h, .noGas)) }
                if let native { stays.append((native, native.usd < floor ? .tooSmall : .noGas)) }
                continue
            }
            for h in tokens { legs.append(Leg(holding: h, amount: h.raw, usd: h.usd, way: .direct)) }
            guard let native else { continue }
            var reserve = tokenCost + price * nativeGas * gasHeadroom
            if native.symbol == "ETH" { reserve = max(reserve, ethFloorWei + tokenCost) }
            let left = nativeRaw - reserve
            let leftUSD = nativeRaw > 0 ? native.usd * NSDecimalNumber(decimal: left / nativeRaw).doubleValue : 0
            if left <= 0 || leftUSD < floor {
                stays.append((native, nativeRaw > 0 && left > 0 ? .tooSmall : .forGas))
            } else if !direct && !relayable(chain, nil) {
                stays.append((native, .noRoute))
            } else {
                legs.append(Leg(holding: native, amount: integer(left), usd: leftUSD, way: .direct))
            }
        }
        return Plan(legs: legs, stays: stays)
    }

    // MARK: - The transaction asked for

    /// `eth_sendTransaction`'s one parameter: `from` sends `leg` to `to`
    /// (your address on a direct leg, the deposit address on a Relay one).
    static func transaction(_ leg: Leg, from: String, to: String) -> [String: String]? {
        guard isAddress(from), isAddress(to), let amount = hexQuantity(leg.amount) else { return nil }
        if let contract = leg.holding.contract {
            guard isAddress(contract), let data = transferData(to: to, amount: leg.amount) else { return nil }
            return ["from": from, "to": contract, "data": data, "value": "0x0"]
        }
        return ["from": from, "to": to, "data": "0x", "value": amount]
    }

    /// Where a leg goes: your account, or its route's deposit address.
    static func destination(_ leg: Leg, account: String) -> String {
        if case .relay(let address, _) = leg.way { return address }
        return account
    }

    /// `transfer(address,uint256)`: 0xa9059cbb, the address and the amount,
    /// each a 32-byte word.
    static func transferData(to: String, amount: String) -> String? {
        guard isAddress(to), let word = uint256Word(amount) else { return nil }
        let address = String(repeating: "0", count: 24) + to.dropFirst(2).lowercased()
        return "0xa9059cbb" + address + word
    }

    static func isAddress(_ s: String) -> Bool {
        s.hasPrefix("0x") && s.count == 42 && s.dropFirst(2).allSatisfy(\.isHexDigit)
    }

    // MARK: - Base units

    /// A base-unit decimal string as 64 hex digits; nil past 38 digits
    /// (no real balance is that large, and `Decimal` is exact only that far).
    static func uint256Word(_ decimal: String) -> String? {
        guard let hex = hexDigits(decimal) else { return nil }
        return String(repeating: "0", count: max(0, 64 - hex.count)) + hex
    }

    /// A JSON-RPC quantity: "0x" and the shortest hex, "0x0" for zero.
    static func hexQuantity(_ decimal: String) -> String? {
        hexDigits(decimal).map { "0x" + ($0.isEmpty ? "0" : $0) }
    }

    private static func hexDigits(_ decimal: String) -> String? {
        guard !decimal.isEmpty, decimal.count <= 38, decimal.allSatisfy(\.isNumber),
              var n = Decimal(string: decimal) else { return nil }
        let digits = Array("0123456789abcdef")
        var out = ""
        while n > 0 {
            var q = n / 16
            var whole = Decimal()
            NSDecimalRound(&whole, &q, 0, .down)
            let r = NSDecimalNumber(decimal: n - whole * 16).intValue
            out = String(digits[r]) + out
            n = whole
        }
        return out
    }

    /// A JSON-RPC hex quantity as a base-unit decimal string.
    static func decimal(fromHex hex: String) -> String? {
        let body = hex.hasPrefix("0x") ? hex.dropFirst(2) : Substring(hex)
        let trimmed = body.drop { $0 == "0" }
        guard body.allSatisfy(\.isHexDigit), trimmed.count <= 31 else { return nil }
        var n = Decimal()
        for c in trimmed { n = n * 16 + Decimal(Int(String(c), radix: 16)!) }
        return integer(n)
    }

    /// A whole `Decimal` as digits, no grouping or exponent.
    static func integer(_ d: Decimal) -> String {
        var d = d, whole = Decimal()
        NSDecimalRound(&whole, &d, 0, .down)
        return NSDecimalNumber(decimal: whole).stringValue
    }

    /// Base units as the coin's own amount, for the words ("0.4 ETH").
    static func amount(_ raw: String, decimals: Int) -> Double {
        guard let d = Decimal(string: raw) else { return 0 }
        return NSDecimalNumber(decimal: d / pow(10, decimals)).doubleValue
    }
}
