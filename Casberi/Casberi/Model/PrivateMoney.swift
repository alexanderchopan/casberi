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
        /// The private root whose account holds it (`PrivateRoot.id`, prd
        /// §1562); nil for the device-only account notes were made in before.
        var root: String? = nil
        /// The yield pool's share token the note holds (prd §1563): then
        /// `amount` is SHARES at `decimals` (18), and what it is worth in
        /// `symbol` is `worth(_:rates:)`. Nil for a plain note (Sepolia).
        var share: String? = nil
        var id: String { commitment }
    }

    /// What a note is worth in its token, base units at the token's own
    /// decimals: a plain note its amount; a yield note its shares at the
    /// share's live exchange rate (`rates`, by lower-cased share: the
    /// token's units per whole share), so the yield earned is in the value.
    /// Before a rate is read, the shares themselves at their decimals — never
    /// more than the note holds, since a share only rises.
    static func worth(_ note: Note, rates: [String: String]) -> (amount: String, decimals: Int) {
        guard let share = note.share, let pool = PrivacyNetwork.forChain(note.chainId)?.yieldPool(for: share),
              let rate = rates[share.lowercased()],
              let value = PrivateYield.underlying(shares: note.amount, exchangeRate: rate, shareDecimals: pool.shareDecimals)
        else {
            guard note.share != nil, let pool = PrivacyNetwork.forChain(note.chainId)?.yieldPool(for: note.share ?? ""),
                  pool.underlyingDecimals < pool.shareDecimals,
                  let units = Decimal(string: note.amount) else { return (note.amount, note.decimals) }
            // USDC's shares have 18 places and USDC 6: the shares as USDC,
            // at the token's decimals, until the rate is read.
            return (plain(units / pow10(pool.shareDecimals - pool.underlyingDecimals)), pool.underlyingDecimals)
        }
        return (value, pool.underlyingDecimals)
    }

    /// What one account holds approved on `chainId`, by account: a private
    /// send spends from one account (one withdrawal cannot join two).
    static func spendableByAccount(_ notes: [Note], chainId: Int, symbol: String = "ETH",
                                   rates: [String: String] = [:]) -> [(root: String?, amount: String)] {
        let roots = notes.map(\.root).reduce(into: [String?]()) { if !$0.contains($1) { $0.append($1) } }
        return roots.map { r in (r, spendable(notes.filter { $0.root == r }, chainId: chainId, symbol: symbol, rates: rates)) }
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

    /// `poi_required` is not approved either (prd §1561): 0xBow wants a proof
    /// this app cannot give, so it is drawn as refused, and asked again.
    static func kind(_ status: Status) -> Row.Kind {
        switch status {
        case .approved: .held
        case .waiting: .waiting
        case .rejected, .needsProof: .refused
        }
    }

    /// Whether the ASP may still change its answer: waiting, or wanting a proof.
    static func asksASP(_ status: Status) -> Bool { status == .waiting || status == .needsProof }

    /// One row per token, state and network: what is private first, then
    /// what is waiting, then what was refused; tokens A–Z within each.
    static func rows(_ notes: [Note], rates: [String: String] = [:]) -> [Row] {
        var sums: [String: (kind: Row.Kind, symbol: String, chain: Int, sum: Decimal, decimals: Int, since: Date)] = [:]
        for note in notes {
            let w = worth(note, rates: rates)
            guard let value = Decimal(string: w.amount), value > 0 else { continue }
            let k = kind(note.status)
            let key = "\(k.rawValue):\(note.symbol):\(note.chainId)"
            if let had = sums[key] {
                sums[key] = (k, note.symbol, note.chainId, had.sum + value, w.decimals, min(had.since, note.at))
            } else {
                sums[key] = (k, note.symbol, note.chainId, value, w.decimals, note.at)
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

    /// A private move's transaction on its network's Etherscan.
    static func explorerTx(_ hash: String, chainId: Int) -> String {
        (chainId == 1 ? "https://etherscan.io/tx/" : "https://sepolia.etherscan.io/tx/") + hash
    }

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
    static func worthUSD(_ notes: [Note], prices: [String: Double], rates: [String: String] = [:]) -> Double {
        notes.reduce(0) { sum, note in
            let w = worth(note, rates: rates)
            guard note.status == .approved, !testnets.contains(note.chainId),
                  let price = prices[note.symbol.lowercased()], let units = Decimal(string: w.amount) else { return sum }
            let whole = NSDecimalNumber(decimal: units / pow10(w.decimals)).doubleValue
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
        notes.contains { asksASP($0.status) }
    }

    // MARK: - Needs you (prd §1561)

    /// A deposit Wallet › Needs you shows: waiting for 0xBow's approval (the
    /// amber clock, "Since 2:14 PM"), or not approved (red), whose act is Take
    /// it back — the ragequit, a public exit to the address it came from.
    /// Take it back is offered too on a deposit that has waited past
    /// `takeBackAfter`. An approved note asks nothing: it leaves.
    struct Ask: Equatable, Identifiable {
        enum Kind: Equatable { case waiting, refused }
        let note: Note
        let kind: Kind
        let canTakeBack: Bool
        var id: String { note.commitment }
        /// In the token: a yield note's shares at the share's own decimals
        /// (USDC's 18 shown as USDC), never more than it is worth.
        var figure: String {
            let w = PrivateMoney.worth(note, rates: [:])
            return PrivateMoney.figure(w.amount, decimals: w.decimals, symbol: note.symbol)
        }

        var title: String {
            switch kind {
            case .waiting: String(localized: "\(figure) waiting for approval")
            case .refused: String(localized: "\(figure) not approved")
            }
        }
    }

    static let takeBackAfter: TimeInterval = 7 * 86_400

    /// One ask per note the ASP has not approved, refused first, then the
    /// oldest first.
    static func asks(_ notes: [Note], now: Date) -> [Ask] {
        notes.compactMap { note -> Ask? in
            guard let units = Decimal(string: note.amount), units > 0 else { return nil }
            switch note.status {
            case .approved: return nil
            case .waiting:
                return Ask(note: note, kind: .waiting, canTakeBack: now.timeIntervalSince(note.at) > takeBackAfter)
            case .rejected, .needsProof:
                return Ask(note: note, kind: .refused, canTakeBack: true)
            }
        }
        .sorted { ($0.kind == .refused ? 0 : 1, $0.note.at) < ($1.kind == .refused ? 0 : 1, $1.note.at) }
    }

    /// "Since 2:14 PM" today, "Since Oct 19" before.
    static func since(_ at: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let shown = calendar.isDate(at, inSameDayAs: now)
            ? at.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone))
            : at.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).month(.abbreviated).day())
        return String(localized: "Since \(shown)")
    }

    /// A taken-back deposit's Activity row, with no verb: "0.0001 ETH back to ...DeBb".
    static func takenBackTitle(figure: String, to owner: String) -> String {
        String(localized: "\(figure) back to \(owner)")
    }

    /// Round-ups moved in together (prd §1561), with no verb.
    static func roundUpsTitle(figure: String) -> String {
        String(localized: "\(figure) round-ups to private")
    }

    // MARK: - Amounts

    /// "0.001 ETH": base units at the token's decimals, at most six places,
    /// no trailing zeros.
    static func figure(_ amount: String, decimals: Int, symbol: String) -> String {
        guard let shown = number(amount, decimals: decimals) else { return symbol }
        return "\(shown) \(symbol)"
    }

    /// The figure's number alone ("0.0412"), at most `places` places.
    static func number(_ amount: String, decimals: Int, places: Int = 6) -> String? {
        guard let units = Decimal(string: amount) else { return nil }
        return (units / pow10(decimals)).formatted(.number.precision(.fractionLength(0...places)))
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
    static let ladder = ["0.00001", "0.00005", "0.0001", "0.0005", "0.001", "0.005", "0.01", "0.05"]

    /// On Ethereum (prd §1563): money, not test money — from the pool's
    /// smallest deposit (0.004 ETH, `Entrypoint.assets`) up.
    static let mainnetLadder = ["0.001", "0.005", "0.01", "0.025", "0.05", "0.1", "0.25", "0.5", "1"]

    /// USDC on Ethereum (prd §1567): ppUSDC's smallest deposit is 10 shares
    /// (about $10.05 at the rate read 2026-10-26), so the ladder starts there
    /// and the minimum, read live, takes out a step it does not cover.
    static let usdcLadder = ["10", "20", "50", "100", "250", "500", "1000", "2500"]

    // MARK: - Balance to balance (prd §1567)

    /// `Keystore.viewingKeys(address)`: the public viewing key an owner
    /// registered, or zero for an address with no private account.
    static func viewingKeyCall(owner: String) -> String? {
        guard isAddress(owner) else { return nil }
        return "0x03bb850a" + String(repeating: "0", count: 24) + owner.dropFirst(2).lowercased()
    }

    /// Whether the keystore's answer names a viewing key: a whole word, not
    /// zero. A zero key is no private account (the SDK refuses one, and
    /// encrypting to it would be readable by anyone); an unreadable answer is
    /// not one either, so the send pays out publicly.
    static func hasViewingKey(_ answer: String?) -> Bool {
        guard let answer, answer.hasPrefix("0x") else { return false }
        let body = answer.dropFirst(2)
        return body.count == 64 && body.allSatisfy(\.isHexDigit) && body.contains { $0 != "0" }
    }

    /// The amounts on `ladder` the balance covers with `reserve` kept back,
    /// none under `minimum` (base units: the pool's smallest deposit).
    static func choices(balance: String, reserve: String, decimals: Int = 18,
                        ladder: [String] = ladder, minimum: String = "0") -> [String] {
        guard let have = Decimal(string: balance), let keep = Decimal(string: reserve),
              let floor = Decimal(string: minimum) else { return [] }
        return ladder.filter { step in
            guard let units = baseUnits(step, decimals: decimals).flatMap({ Decimal(string: $0) }) else { return false }
            return units + keep <= have && units >= floor
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

    // MARK: - Sending from it (prd §1554)

    /// What 0xBow's relayer charges for ETH (`/v1/details/evm/<chain>`): a
    /// share in basis points, plus a fixed amount in base units.
    struct RelayerTerms: Equatable {
        let feeBPS: Int
        let fixed: String
    }

    /// The Sepolia relayer's terms as read 2026-10-26, for the amounts until
    /// its own answer lands.
    static let measuredTerms = RelayerTerms(feeBPS: 10, fixed: "21000")

    /// The relayer's terms for ETH, or nil when the answer names none.
    static func relayerTerms(_ data: Data) -> RelayerTerms? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = json["assets"] as? [[String: Any]],
              let eth = assets.first(where: { ($0["ticker"] as? String)?.uppercased() == "ETH" }) else { return nil }
        let bps = Int((eth["feeBPS"] as? String) ?? "") ?? (eth["feeBPS"] as? Int) ?? 0
        let fixed = (eth["fixedFeeAmount"] as? String).flatMap { $0.allSatisfy(\.isNumber) && !$0.isEmpty ? $0 : nil } ?? "0"
        return RelayerTerms(feeBPS: bps, fixed: fixed)
    }

    /// The relayer's fee on `amount` (base units): its share, rounded up, plus
    /// the fixed part. Base units, decimal.
    static func relayFee(_ amount: String, terms: RelayerTerms) -> String {
        guard let units = Decimal(string: amount), let fixed = Decimal(string: terms.fixed) else { return "0" }
        var share = units * Decimal(terms.feeBPS) / 10_000
        var up = Decimal()
        NSDecimalRound(&up, &share, 0, .up)
        return plain(up + fixed)
    }

    /// A 0x-hex quantity as decimal digits ("0x38d7ea4c68000" → "1000000000000000"); "0" for anything else.
    static func decimal(hex: String) -> String {
        guard hex.hasPrefix("0x"), hex.count > 2 else { return "0" }
        var digits: [Int] = [0]
        for c in hex.dropFirst(2) {
            guard let v = c.hexDigitValue else { return "0" }
            var carry = v
            for i in stride(from: digits.count - 1, through: 0, by: -1) {
                let x = digits[i] * 16 + carry
                digits[i] = x % 10
                carry = x / 10
            }
            while carry > 0 { digits.insert(carry % 10, at: 0); carry /= 10 }
        }
        let s = digits.map(String.init).joined().drop { $0 == "0" }
        return s.isEmpty ? "0" : String(s)
    }

    // MARK: - In Activity (prd §1554)

    /// A private move's Activity row: `private:<tx hash>`, never a
    /// `privacypools:` ref (the Privacy Pools seat reads those as its own).
    static let activityPrefix = "private:"

    static func isActivity(_ ref: String?) -> Bool { ref?.hasPrefix(activityPrefix) == true }

    /// The row's words, with no verb (the Activity rule): "0.001 ETH to your
    /// private balance" moving in, "0.001 ETH to ...a3f1" sent from it.
    static func activityTitle(figure: String, to recipient: String?) -> String {
        guard let recipient else { return String(localized: "\(figure) to your private balance") }
        return String(localized: "\(figure) to \(recipient)")
    }

    /// A plain EVM address: 0x and forty hex digits.
    static func isAddress(_ s: String) -> Bool {
        s.range(of: #"^0x[0-9a-fA-F]{40}$"#, options: .regularExpression) != nil
    }

    /// What the approved notes on `chainId` hold, base units: the private
    /// money a send can spend. A note waiting for approval is not spendable.
    static func spendable(_ notes: [Note], chainId: Int, symbol: String = "ETH", rates: [String: String] = [:]) -> String {
        plain(notes.filter { $0.status == .approved && $0.chainId == chainId && $0.symbol == symbol }
            .compactMap { Decimal(string: worth($0, rates: rates).amount) }.reduce(0, +))
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
