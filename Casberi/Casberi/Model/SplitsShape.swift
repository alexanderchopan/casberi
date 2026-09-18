import Foundation

/// SPLITS — THE PURE HALF (prd §820). Everything the seat decides about a
/// payload, with no network and no store, so `scripts/splits-selftest.sh`
/// compiles this file WHOLE and drives it off the shapes measured on
/// 2026-09-18.
///
/// ## Measured, not remembered (2026-09-18, the person's own Read key)
///
/// Every list answers `{ "data": … }`. `/v1/auth/whoami` →
/// `{orgId, orgName, keyName, scopes: [String], accountCount}`;
/// `/v1/org/accounts` → `[{id, name, address, type, role, isArchived,
/// createdAt}]`; `/v1/org/accounts/{address}/balances` → `[{address, chainId,
/// symbol, decimals, amount (a STRING), usdValue (a number)}]`;
/// `/v1/transactions` → `[{id, status, chainId, smartAccountAddress,
/// smartAccountName, memo, properties, usdDisplayValue, createdAt,
/// transactionTime, title, direction, transactionHash, userOpHash}]` plus
/// `pagination {hasMore, count, cursor}`; `/v1/contacts` → `[{address,
/// label}]`.
///
/// **What was NOT seen**, because the team it was measured on had done
/// nothing: a transaction in any status but `SUCCEEDED`, an outbound one, a
/// non-null `usdDisplayValue`, and any automation. The API's own spec names
/// `CREATED,QUEUED` as the statuses awaiting signatures; every other status
/// is read as unknown and says so rather than being guessed at (§780b).
enum SplitsShape {
    static let source = "Splits"

    static let accountPrefix = "splits:account:"
    static let txPrefix = "splits:tx:"

    static func ref(account address: String) -> String { accountPrefix + address.lowercased() }
    static func ref(transaction id: String) -> String { txPrefix + id }

    // MARK: - Scope

    /// Whether a key's scopes are READ and nothing else. The seat refuses any
    /// other key on save: a Write key can propose a transfer, and the page's
    /// promise is that nothing here can. An empty list is refused too — a
    /// key Splits reports no scope for is not a key we can vouch for.
    static func isReadOnly(_ scopes: [String]) -> Bool {
        let set = Set(scopes.map { $0.lowercased().trimmingCharacters(in: .whitespaces) })
        return set == ["read"]
    }

    // MARK: - Payloads

    struct Whoami: Equatable {
        var orgName: String?
        var scopes: [String]
        var accountCount: Int?
    }

    struct Account: Equatable {
        var address: String
        var name: String?
        var type: String?
        var isArchived: Bool
        var createdAt: Date?
    }

    struct Balance: Equatable {
        var chainId: Int?
        var symbol: String
        var usd: Double?
    }

    struct Transaction: Equatable {
        var id: String
        var status: String
        var direction: String?
        var chainId: Int?
        var account: String?
        var accountName: String?
        var memo: String?
        var title: String?
        var usd: Double?
        var hash: String?
        var at: Date?
    }

    struct Contact: Equatable, Codable {
        var address: String
        var label: String
    }

    /// The `data` array or object every Splits answer wraps its payload in.
    static func data(_ json: Any?) -> Any? { (json as? [String: Any])?["data"] }

    static func whoami(_ json: Any?) -> Whoami? {
        guard let row = data(json) as? [String: Any],
              let scopes = row["scopes"] as? [String] else { return nil }
        return Whoami(orgName: text(row["orgName"]), scopes: scopes,
                      accountCount: row["accountCount"] as? Int)
    }

    static func accounts(_ json: Any?) -> [Account]? {
        guard let rows = data(json) as? [[String: Any]] else { return nil }
        return rows.compactMap { row in
            guard let address = text(row["address"]), isAddress(address) else { return nil }
            return Account(address: address, name: text(row["name"]), type: text(row["type"]),
                           isArchived: (row["isArchived"] as? Bool) ?? false,
                           createdAt: date(row["createdAt"]))
        }
    }

    static func balances(_ json: Any?) -> [Balance]? {
        guard let rows = data(json) as? [[String: Any]] else { return nil }
        return rows.compactMap { row in
            guard let symbol = text(row["symbol"]) else { return nil }
            return Balance(chainId: row["chainId"] as? Int, symbol: symbol, usd: number(row["usdValue"]))
        }
    }

    static func transactions(_ json: Any?) -> (rows: [Transaction], cursor: String?)? {
        guard let rows = data(json) as? [[String: Any]] else { return nil }
        let pagination = (json as? [String: Any])?["pagination"] as? [String: Any]
        let more = (pagination?["hasMore"] as? Bool) ?? false
        let cursor = more ? text(pagination?["cursor"]) : nil
        return (rows.compactMap(transaction(row:)), cursor)
    }

    /// One transaction, as `GET /v1/transactions/{id}` answers it — the
    /// same row shape, wrapped in `data` as an object.
    static func transaction(_ json: Any?) -> Transaction? {
        (data(json) as? [String: Any]).flatMap(transaction(row:))
    }

    static func transaction(row: [String: Any]) -> Transaction? {
        guard let id = text(row["id"]) else { return nil }
        return Transaction(
            id: id,
            status: text(row["status"]) ?? "",
            direction: text(row["direction"]),
            chainId: row["chainId"] as? Int,
            account: text(row["smartAccountAddress"]),
            accountName: text(row["smartAccountName"]),
            memo: text(row["memo"]),
            title: text(row["title"]),
            usd: usd(row["usdDisplayValue"]),
            hash: text(row["transactionHash"]),
            at: date(row["transactionTime"]) ?? date(row["createdAt"]))
    }

    /// A query VALUE, escaped strictly: `.urlQueryAllowed` leaves `+`, `&`,
    /// `=` and `/` alone, and an opaque base64 cursor holds all of them.
    static func queryValue(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    static func contacts(_ json: Any?) -> [Contact]? {
        guard let rows = data(json) as? [[String: Any]] else { return nil }
        return rows.compactMap { row in
            guard let address = text(row["address"]), isAddress(address),
                  let label = text(row["label"]) else { return nil }
            return Contact(address: address, label: label)
        }
    }

    /// The top-level key names of a payload's first row — what the page says
    /// when a shape could not be read (§780b), never a value.
    static func keyNames(_ json: Any?) -> [String] {
        let payload = data(json) ?? json
        if let row = (payload as? [[String: Any]])?.first { return row.keys.sorted() }
        if let row = payload as? [String: Any] { return row.keys.sorted() }
        return []
    }

    // MARK: - Stage

    /// A Splits transaction is a PROPOSAL until enough signers approve it.
    enum Stage: Equatable {
        case done
        /// `CREATED` or `QUEUED` — the two the API's own spec names as
        /// awaiting signature.
        case waiting
        /// Anything that names a failure, a cancel or an expiry.
        case notExecuted
        /// A status this seat has never seen. Drawn with no stage word
        /// rather than guessed into one of the three above.
        case unknown
    }

    static func stage(_ status: String) -> Stage {
        let s = status.uppercased()
        switch s {
        case "SUCCEEDED", "SUCCESS", "EXECUTED", "COMPLETED", "CONFIRMED": return .done
        case "CREATED", "QUEUED": return .waiting
        default:
            for word in ["FAIL", "CANCEL", "REVERT", "REJECT", "EXPIR", "DROP"] where s.contains(word) {
                return .notExecuted
            }
            return .unknown
        }
    }

    // MARK: - Dust

    /// Whether a transaction is dust nobody asked for — the two measured on a
    /// brand-new team were exactly this: inbound, under a cent, from an
    /// address that had never been paid (the address-poisoning shape).
    /// Outbound is never dust: anything this team SENT is its own act.
    /// Splits' own title spells the under-a-cent case as "<$0.01".
    static func isDust(_ tx: Transaction) -> Bool {
        guard tx.direction?.lowercased() == "inbound" else { return false }
        if let usd = tx.usd { return usd < 0.01 }
        return tx.title?.contains("<$0.01") == true
    }

    // MARK: - The row

    /// Splits' own title ("Received 5,000 USDC from Acme") — it already names
    /// the amount, the token and the counterparty, by CONTACT name where the
    /// team has one. An abnormal stage LEADS, for `WiseShape.rowTitle`'s
    /// reason: the title is clamped at 80 characters from the end.
    static func rowTitle(_ tx: Transaction) -> String {
        let base = tx.title ?? fallbackTitle(tx)
        switch stage(tx.status) {
        case .done, .unknown: return base
        case .waiting:        return String(localized: "Waiting for signatures · \(base)")
        case .notExecuted:    return String(localized: "Not executed · \(base)")
        }
    }

    static func fallbackTitle(_ tx: Transaction) -> String {
        switch tx.direction?.lowercased() {
        case "inbound":  return String(localized: "Received")
        case "outbound": return String(localized: "Sent")
        default:         return String(localized: "Transaction")
        }
    }

    static func tags(_ tx: Transaction) -> [String] {
        var out = [String(localized: "Transfer")]
        switch stage(tx.status) {
        case .done, .unknown: break
        case .waiting:        out.append(waitingTag)
        case .notExecuted:    out.append(String(localized: "Not executed"))
        }
        return out
    }

    /// The tag the Queue tile reads, and its attention dot — a proposal
    /// waiting on signatures, the one thing in this room somebody has to act
    /// on. A scheduled payment lands as one (Splits drafts each occurrence).
    static let waitingTag = "Waiting"

    /// "received" / "sent" — `Thing.transferDirection`'s vocabulary.
    static func direction(_ tx: Transaction) -> String? {
        switch tx.direction?.lowercased() {
        case "inbound":  return "received"
        case "outbound": return "sent"
        default:         return nil
        }
    }

    /// An account row's line. Splits' `type` is NOT drawn: it was measured as
    /// `SPLITS_VAULT_V1`, a contract version rather than a word a person uses.
    static func accountLine(_ account: Account) -> String {
        account.isArchived ? String(localized: "Archived account") : String(localized: "Account")
    }

    // MARK: - Standing

    /// The team's total across the accounts read, and how many carried a
    /// priced balance. A balance Splits could not price is left out of the
    /// total, never counted as zero.
    static func total(_ balances: [[Balance]]) -> Double? {
        let priced = balances.flatMap { $0 }.compactMap(\.usd)
        return priced.isEmpty ? nil : priced.reduce(0, +)
    }

    // MARK: - Primitives

    static func text(_ raw: Any?) -> String? {
        guard let s = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty else { return nil }
        return s
    }

    static func isAddress(_ s: String) -> Bool {
        s.count == 42 && s.lowercased().hasPrefix("0x")
            && s.dropFirst(2).allSatisfy(\.isHexDigit)
    }

    static func number(_ raw: Any?) -> Double? {
        if let d = raw as? Double { return d }
        if let i = raw as? Int { return Double(i) }
        if let s = text(raw) { return Double(s) }
        return nil
    }

    /// `usdDisplayValue` is a DISPLAY string in the spec ("$1,234.56" or a
    /// bare number) and has only ever been seen null. Digits, one point and a
    /// sign are kept; a "<$0.01" answers 0 so the dust test reads it as dust.
    static func usd(_ raw: Any?) -> Double? {
        if let n = raw as? Double { return n }
        if let n = raw as? Int { return Double(n) }
        guard let s = text(raw) else { return nil }
        if s.hasPrefix("<") { return 0 }
        let kept = s.filter { $0.isNumber || $0 == "." || $0 == "-" }
        return Double(kept)
    }

    static func date(_ raw: Any?) -> Date? {
        guard let s = text(raw) else { return nil }
        return isoFractional.date(from: s) ?? iso.date(from: s)
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
