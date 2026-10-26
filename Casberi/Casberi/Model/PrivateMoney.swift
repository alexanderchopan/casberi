import Foundation

/// **MOVE TO PRIVATE, AND WHAT IS PRIVATE (prd §1554).**
///
/// What the Wallet shows of Privacy Pools v2 (prd §1541): each deposit you
/// make is a NOTE, kept here by its public parts (commitment, label, the
/// label's hash, the amount, the transaction) and never its secret, which
/// lives only in the engine's page. A note is waiting until 0xBow's ASP
/// approves its label; approved, it is private money; rejected, it can only
/// go back. Holdings draws one row per token and state: "ETH, private",
/// "ETH, moving in", "ETH, not approved".
///
/// Pure (Foundation only): `scripts/private-money-selftest.sh` compiles it.
enum PrivateMoney {

    /// What 0xBow's ASP says of a label (`/labels/<Poseidon(label)>/status`).
    enum Status: String, Codable, Equatable {
        /// `pending`, and `unknown` (the ASP has not read the deposit yet):
        /// both are waiting, the row's one word for it.
        case waiting
        case approved
        case rejected
        /// `poi_required`: the ASP wants more before it approves.
        case needsProof
    }

    struct Note: Codable, Equatable, Identifiable {
        let commitment: String
        /// 0x-hex, as the engine returns it.
        let label: String
        /// Poseidon(label), decimal: the ASP's id for it. Never the label.
        let labelHash: String
        let symbol: String
        /// Base units, decimal.
        let amount: String
        let decimals: Int
        let chainId: Int
        /// The deposit's transaction hash.
        let tx: String
        let at: Date
        var status: Status
        var id: String { commitment }
    }

    /// The ASP's answer, or nil when it is not one (a page, an error): an
    /// unreadable answer changes nothing. `unknown` is waiting, because a
    /// deposit the ASP has not indexed yet reads `unknown` for a minute.
    static func status(asp data: Data) -> Status? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let word = (json["status"] as? String)?.lowercased() else { return nil }
        switch word {
        case "pending", "unknown": return .waiting
        case "approved": return .approved
        case "rejected", "declined": return .rejected
        case "poi_required": return .needsProof
        default: return nil
        }
    }

    /// The ASP's address for a label: by its HASH, never the label (asked
    /// with the raw label an approved deposit reads `unknown` forever).
    static func statusURL(aspUrl: String, labelHash: String) -> URL? {
        guard labelHash.range(of: #"^[0-9]{1,80}$"#, options: .regularExpression) != nil else { return nil }
        return URL(string: aspUrl + "/labels/" + labelHash + "/status")
    }

    // MARK: - Rows

    struct Row: Equatable, Identifiable {
        enum Kind: Int, Equatable { case held, waiting, refused }
        let kind: Kind
        let symbol: String
        /// The network its notes are on: a row is one token in one state on one network.
        let chainId: Int
        /// Base units, decimal: the sum of its notes.
        let amount: String
        let decimals: Int
        /// The oldest note in a waiting row: since when.
        let since: Date?
        var id: String { "\(kind.rawValue):\(symbol):\(chainId)" }

        var title: String {
            switch kind {
            case .held: String(localized: "\(symbol), private")
            case .waiting: String(localized: "\(symbol), moving in")
            case .refused: String(localized: "\(symbol), not approved")
            }
        }
    }

    static func kind(_ status: Status) -> Row.Kind {
        switch status {
        case .approved: .held
        case .waiting, .needsProof: .waiting
        case .rejected: .refused
        }
    }

    /// One row per token, state and network: what is private first, then
    /// what is waiting, then what was refused; tokens A–Z within each.
    static func rows(_ notes: [Note]) -> [Row] {
        var sums: [String: (kind: Row.Kind, symbol: String, chain: Int, sum: Decimal, decimals: Int, since: Date)] = [:]
        for note in notes {
            guard let value = Decimal(string: note.amount), value > 0 else { continue }
            let k = kind(note.status)
            let key = "\(k.rawValue):\(note.symbol):\(note.chainId)"
            if let had = sums[key] {
                sums[key] = (k, note.symbol, note.chainId, had.sum + value, note.decimals, min(had.since, note.at))
            } else {
                sums[key] = (k, note.symbol, note.chainId, value, note.decimals, note.at)
            }
        }
        return sums.values
            .sorted { ($0.kind.rawValue, $0.symbol, $0.chain) < ($1.kind.rawValue, $1.symbol, $1.chain) }
            .map { Row(kind: $0.kind, symbol: $0.symbol, chainId: $0.chain, amount: plain($0.sum), decimals: $0.decimals,
                       since: $0.kind == .waiting ? $0.since : nil) }
    }

    // MARK: - In the Wallet's number (prd §1554)

    /// Private money's one position in the portfolio: one block in the
    /// Holdings box and one share of the total, never folded into the token
    /// it is, so the Tokens rows (public balances) count nothing twice.
    static let walletSymbol = "Private"
    /// Its holder in the portfolio: a place, not a wallet and not an app
    /// (`WalletPortfolio.privateHolderID` spells the same word).
    static let holderID = "private"

    /// Networks whose coins have no value: their notes count nothing in the
    /// total (test money states its quantity, never dollars, §949).
    static let testnets: Set<Int> = [11_155_111]

    static func network(_ chainId: Int) -> String {
        switch chainId {
        case 1: "Ethereum"
        case 8453: "Base"
        case 11_155_111: "Sepolia"
        default: "Chain \(chainId)"
        }
    }

    /// What the private notes are worth in dollars at `prices` (USD per unit,
    /// by lower-cased symbol): APPROVED notes only — a deposit waiting for
    /// approval is not spendable yet, so it counts once approved — and never
    /// a test network's. A token with no price counts nothing.
    static func worthUSD(_ notes: [Note], prices: [String: Double]) -> Double {
        notes.reduce(0) { sum, note in
            guard note.status == .approved, !testnets.contains(note.chainId),
                  let price = prices[note.symbol.lowercased()], let units = Decimal(string: note.amount) else { return sum }
            let whole = NSDecimalNumber(decimal: units / pow10(note.decimals)).doubleValue
            return sum + whole * price
        }
    }

    /// One row's dollars, or nil where it states its quantity instead (test
    /// money, or a token with no price).
    static func rowUSD(_ row: Row, prices: [String: Double]) -> Double? {
        guard !testnets.contains(row.chainId), let price = prices[row.symbol.lowercased()],
              let units = Decimal(string: row.amount) else { return nil }
        return NSDecimalNumber(decimal: units / pow10(row.decimals)).doubleValue * price
    }

    /// The private total per token, approved notes only.
    static func held(_ notes: [Note], symbol: String) -> Decimal {
        notes.filter { $0.status == .approved && $0.symbol == symbol }
            .compactMap { Decimal(string: $0.amount) }.reduce(0, +)
    }

    /// Whether any note still waits on the ASP: the store asks again.
    static func anyWaiting(_ notes: [Note]) -> Bool {
        notes.contains { kind($0.status) == .waiting }
    }

    // MARK: - Amounts

    /// "0.001 ETH": base units at the token's decimals, at most six places,
    /// no trailing zeros.
    static func figure(_ amount: String, decimals: Int, symbol: String) -> String {
        guard let shown = number(amount, decimals: decimals) else { return symbol }
        return "\(shown) \(symbol)"
    }

    /// The figure's number alone ("0.0412").
    static func number(_ amount: String, decimals: Int) -> String? {
        guard let units = Decimal(string: amount) else { return nil }
        return (units / pow10(decimals)).formatted(.number.precision(.fractionLength(0...6)))
    }

    /// A decimal amount ("0.001") in base units, decimal; nil for anything
    /// that is not a positive amount with no more places than the token has.
    static func baseUnits(_ amount: String, decimals: Int) -> String? {
        guard amount.range(of: #"^[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil else { return nil }
        let parts = amount.split(separator: ".", omittingEmptySubsequences: false)
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        guard fraction.count <= decimals else { return nil }
        let digits = String(parts[0]) + fraction + String(repeating: "0", count: decimals - fraction.count)
        let trimmed = digits.drop { $0 == "0" }
        return trimmed.isEmpty ? nil : String(trimmed)
    }

    /// A decimal base-unit amount as the 0x-hex a transaction carries.
    static func hex(_ amount: String) -> String? {
        guard amount.range(of: #"^[0-9]{1,78}$"#, options: .regularExpression) != nil else { return nil }
        var digits = amount.compactMap { $0.wholeNumberValue }
        var out: [Character] = []
        while !(digits.isEmpty || digits.allSatisfy { $0 == 0 }) {
            var rest: [Int] = [], carry = 0
            for d in digits {
                let cur = carry * 10 + d
                let q = cur / 16
                carry = cur % 16
                if !rest.isEmpty || q > 0 { rest.append(q) }
            }
            out.append(Character(String(carry, radix: 16)))
            digits = rest
        }
        return "0x" + (out.isEmpty ? "0" : String(out.reversed()))
    }

    /// The amounts Move to private offers, in ETH: the ones the account can
    /// move and still pay the gas (`reserve`, base units).
    static let ladder = ["0.0001", "0.0005", "0.001", "0.005", "0.01", "0.05"]

    static func choices(balance: String, reserve: String, decimals: Int = 18) -> [String] {
        guard let have = Decimal(string: balance), let keep = Decimal(string: reserve) else { return [] }
        return ladder.filter { step in
            guard let units = baseUnits(step, decimals: decimals).flatMap({ Decimal(string: $0) }) else { return false }
            return units + keep <= have
        }
    }

    /// What a first move pays in gas at `gasPrice` (base units, decimal):
    /// registration's two transactions (645k + 135k measured) and the
    /// deposit (904k), with room over the estimate, at twice the price.
    static let gasBudget: Decimal = 2_200_000

    static func reserve(gasPrice: String) -> String? {
        guard let price = Decimal(string: gasPrice) else { return nil }
        return plain(gasBudget * price * 2)
    }

    private static func pow10(_ n: Int) -> Decimal {
        var d = Decimal(1)
        for _ in 0..<max(n, 0) { d *= 10 }
        return d
    }

    /// A whole Decimal as plain digits ("1000000000000000"), never "1e15".
    static func plain(_ d: Decimal) -> String {
        var value = d
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .down)
        return NSDecimalNumber(decimal: rounded).stringValue
    }
}
