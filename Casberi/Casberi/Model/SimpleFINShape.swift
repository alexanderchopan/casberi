import Foundation

/// SIMPLEFIN — THE PURE HALF (prd §1663). Everything the seat decides about a
/// token or a payload, with no network and no store, so
/// `scripts/simplefin-selftest.sh` compiles this file WHOLE and drives it off
/// the shapes measured on 2026-11-02.
///
/// ## Measured, not remembered (2026-11-02, the bridge's own demo token)
///
/// The Setup Token is base64 of a claim URL
/// (`https://beta-bridge.simplefin.org/simplefin/claim/DEMO-v2-…`). An empty
/// POST to it answers 200 `text/plain` with the Access URL
/// (`https://<user>:<pass>@beta-bridge.simplefin.org/simplefin`); the same
/// POST again answers 403. `GET <access>/accounts?version=2` with the userinfo
/// as a Basic header answers `{errlist, accounts, connections,
/// x-api-message}`; wrong credentials answer 403.
///
/// - `connections`: `[{conn_id, name, org_id, org_name, org_url, sfin_url}]`.
/// - An account: `{id, name, conn_id, currency, balance, available-balance,
///   balance-date, transactions, holdings}` — balances are STRINGS
///   (`"25767.79"`), `balance-date` an epoch NUMBER.
/// - A transaction: `{id, posted, amount, description, payee, memo,
///   transacted_at, mcc}` — `amount` a signed STRING, `posted` epoch seconds.
///   **Its `id` is unique within its account only** (`"1793606400"` is a
///   transaction in two demo accounts), so a ref names the account too.
/// - With no `start-date` the read holds only what posted since yesterday
///   (`x-api-message` says so), so every read names one.
/// - A window over 45 days answers an `errlist` warning ("exceeds recommended
///   range of 45 days"); over 90 it is capped and says so (`gen.api`).
///
/// **What was NOT seen**, because the demo has none: a credit card's
/// (negative) balance, a pending transaction, a custom-currency URL, a
/// `con.auth` error, a 402, and whether a real bank's rows carry `mcc` at all.
/// The seat says what it does with each rather than guessing (§780b).
enum SimpleFINShape {
    static let source = "SimpleFIN"

    static let txPrefix = "simplefin:txn:"

    /// Where a person makes a Setup Token.
    static let createURL = "https://bridge.simplefin.org/simplefin/create"

    /// The one family of hosts this seat will ever POST a claim to or read
    /// from. A Setup Token is base64 the person pastes, so it can name ANY
    /// address; a token naming another host is refused rather than followed
    /// with the person's banking credentials.
    static let hostFamily = "simplefin.org"

    /// The most a read reaches back, and the window's overlap on every later
    /// read (the bridge's own advice: ~5 days, for rows that post late).
    /// 44, not 45: a read reaching exactly 45 days back answers the "exceeds
    /// recommended range" warning, because seconds pass before it lands
    /// (measured on the demo, 2026-11-02).
    static let windowDays = 44
    static let overlapDays = 5

    /// The bridge expects about 24 reads a day and DISABLES a token that keeps
    /// going past that, so no pass asks sooner than this after the last.
    static let readGap: TimeInterval = 3_600

    // MARK: - The token

    /// A Setup Token's claim URL, or nil when it is not one: base64 (standard
    /// or URL-safe, padded or not) of an https URL on `hostFamily`.
    static func claimURL(fromSetupToken raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard !s.isEmpty, !s.contains("://") else { return nil }
        while s.count % 4 != 0 { s += "=" }
        guard let data = Data(base64Encoded: s),
              let text = String(data: data, encoding: .utf8),
              let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              isAllowed(url) else { return nil }
        return url
    }

    /// The Access URL split into what a request needs: the address with the
    /// credentials taken OUT (so no log, ledger or error ever carries them)
    /// and the Basic header that carries them instead. nil when it is not an
    /// https URL on `hostFamily` with both halves of a credential.
    struct Access: Equatable {
        var base: String
        var authorization: String
    }

    static func access(_ raw: String) -> Access? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var parts = URLComponents(string: text),
              let user = parts.user, !user.isEmpty,
              let password = parts.password, !password.isEmpty else { return nil }
        parts.user = nil
        parts.password = nil
        guard let url = parts.url, isAllowed(url) else { return nil }
        var base = url.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        let pair = Data("\(user):\(password)".utf8).base64EncodedString()
        return Access(base: base, authorization: "Basic \(pair)")
    }

    /// Whether a pasted string is already an Access URL rather than a token:
    /// somebody who claimed theirs elsewhere may paste the URL itself.
    static func isAccessURL(_ raw: String) -> Bool { access(raw) != nil }

    static func isAllowed(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else { return false }
        return host == hostFamily || host.hasSuffix("." + hostFamily)
    }

    // MARK: - The window

    /// The epoch second a read starts from: `windowDays` back on first sight,
    /// else the newest posted row less `overlapDays`, never further back than
    /// the window.
    static func startDate(cursor: Date?, now: Date) -> Int {
        let floor = now.addingTimeInterval(-Double(windowDays) * 86_400)
        let from = cursor.map { $0.addingTimeInterval(-Double(overlapDays) * 86_400) } ?? floor
        return Int(max(from, floor).timeIntervalSince1970)
    }

    /// Whether a pass may ask now. A forced read (the one right after a
    /// connect) always may.
    static func mayRead(lastAsked: Date?, now: Date, force: Bool = false) -> Bool {
        force || lastAsked.map { now.timeIntervalSince($0) >= readGap } ?? true
    }

    // MARK: - The payload

    struct Connection: Equatable {
        var id: String
        var name: String
        var url: String?
    }

    struct Transaction: Equatable {
        var id: String
        var posted: Date?
        var amount: Double?
        var description: String?
        var payee: String?
        var memo: String?
        var pending: Bool
        /// A merchant category code, present on a card purchase. The one sign
        /// the bridge gives that money went to a SHOP rather than to another
        /// account of yours (prd §1663).
        var mcc: String?
    }

    struct Account: Equatable {
        var id: String
        var name: String
        var connID: String?
        /// An ISO code, or nil for a custom currency (a URL), which is never
        /// counted as money.
        var currency: String?
        var balance: Double?
        var available: Double?
        var balanceDate: Date?
        var transactions: [Transaction]
    }

    struct AccountSet: Equatable {
        var connections: [Connection]
        var accounts: [Account]
        /// `errlist`'s messages, and v1's `errors` strings, to be shown.
        var messages: [String]
    }

    static func accountSet(_ json: Any?) -> AccountSet? {
        guard let root = json as? [String: Any],
              let rows = root["accounts"] as? [[String: Any]] else { return nil }
        let connections = (root["connections"] as? [[String: Any]] ?? []).compactMap(connection)
        var messages: [String] = []
        for e in root["errlist"] as? [[String: Any]] ?? [] {
            if let m = text(e["msg"]) { messages.append(m) }
        }
        for e in root["errors"] as? [Any] ?? [] {
            if let m = text(e) { messages.append(m) }
        }
        return AccountSet(connections: connections, accounts: rows.compactMap(account),
                          messages: messages.map(clean).filter { !$0.isEmpty })
    }

    static func connection(_ row: [String: Any]) -> Connection? {
        guard let id = text(row["conn_id"]) else { return nil }
        let name = text(row["org_name"]) ?? text(row["name"]) ?? id
        // The spec calls `org_url` a "domain name"; the demo sends a URL.
        // Either becomes an https door, and anything else none.
        let url = text(row["org_url"]).flatMap { raw -> String? in
            let full = raw.contains("://") ? raw : "https://" + raw
            return URL(string: full)?.scheme?.lowercased() == "https" ? full : nil
        }
        return Connection(id: id, name: name, url: url)
    }

    static func account(_ row: [String: Any]) -> Account? {
        guard let id = text(row["id"]) else { return nil }
        // v1 names the institution in a nested `org` and has no `conn_id`.
        let org = row["org"] as? [String: Any]
        return Account(
            id: id,
            name: text(row["name"]) ?? id,
            connID: text(row["conn_id"]) ?? org.flatMap { text($0["id"]) ?? text($0["domain"]) },
            currency: text(row["currency"]).flatMap { isoCurrency($0) ? $0.uppercased() : nil },
            balance: number(row["balance"]),
            available: number(row["available-balance"]),
            balanceDate: epoch(row["balance-date"]),
            transactions: (row["transactions"] as? [[String: Any]] ?? []).compactMap(transaction))
    }

    static func transaction(_ row: [String: Any]) -> Transaction? {
        guard let id = text(row["id"]) else { return nil }
        let posted = epoch(row["posted"])
        return Transaction(id: id,
                           posted: posted,
                           amount: number(row["amount"]),
                           description: text(row["description"]),
                           payee: text(row["payee"]),
                           memo: text(row["memo"]),
                           // `posted` 0 is the spec's other way to say pending.
                           pending: (row["pending"] as? Bool) ?? (posted == nil),
                           mcc: text(row["mcc"]))
    }

    // MARK: - Shaping

    /// `simplefin:txn:<conn>:<account>:<transaction>`, each part escaped so
    /// an id holding a colon cannot shift the others. The bank (`conn`) leads
    /// because a row's mark is its bank's (`connID(fromRef:)`).
    static func ref(conn: String?, account: String, transaction: String) -> String {
        txPrefix + [conn ?? "", account, transaction].map(escape).joined(separator: ":")
    }

    static func connID(fromRef ref: String?) -> String? {
        guard let ref, ref.hasPrefix(txPrefix) else { return nil }
        return part(0, of: String(ref.dropFirst(txPrefix.count)))
    }

    static let holderPrefix = "cash:simplefin:"

    /// A balance's holder: `cash:simplefin:<conn>:<account>`, so Holdings can
    /// draw its bank's mark from the id alone.
    static func holderID(conn: String?, account: String) -> String {
        holderPrefix + [conn ?? "", account].map(escape).joined(separator: ":")
    }

    static func connID(fromHolder holder: String) -> String? {
        guard holder.hasPrefix(holderPrefix) else { return nil }
        return part(0, of: String(holder.dropFirst(holderPrefix.count)))
    }

    private static func escape(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s
    }

    private static func part(_ i: Int, of joined: String) -> String? {
        let parts = joined.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count > i, let id = String(parts[i]).removingPercentEncoding, !id.isEmpty else { return nil }
        return id
    }

    /// The account as the person knows it: its bank, then the bank's name for
    /// it ("Chase · Total Checking"), unless that name already says the bank
    /// ("SimpleFIN Savings" at "SimpleFIN Bridge").
    static func accountLabel(name: String, institution: String?) -> String {
        guard let institution, !institution.isEmpty else { return name }
        // The bank's first word stands for it only when it names THIS bank:
        // "First", "The", "Bank" are in a hundred banks' names.
        let generic: Set<String> = ["the", "first", "bank", "national", "federal", "credit",
                                    "community", "citizens", "american", "united", "union", "savings"]
        let first = institution.split(separator: " ").first.map(String.init) ?? institution
        let key = generic.contains(first.lowercased()) ? institution : first
        return name.range(of: key, options: .caseInsensitive) != nil ? name : "\(institution) · \(name)"
    }

    /// Where a bank's icon may be: on the bank's OWN site, at the addresses
    /// browsers ask, largest first. https only, and the host only — never a
    /// path from the payload.
    static func iconCandidates(orgURL: String?) -> [URL] {
        guard let orgURL, let url = URL(string: orgURL), url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(), host.contains("."),
              true else { return [] }
        return ["apple-touch-icon.png", "apple-touch-icon-precomposed.png", "favicon.ico"]
            .compactMap { URL(string: "https://\(host)/\($0)") }
    }

    /// The name a row goes by: the payee, else the bank's own description.
    static func label(_ t: Transaction) -> String {
        t.payee ?? t.description ?? String(localized: "Bank transaction")
    }

    /// The bank's statement line under the title, when it says something the
    /// title does not (prd §912's shape): the memo, else the description.
    static func statementLine(_ t: Transaction) -> String? {
        let name = label(t)
        for line in [t.memo, t.description].compactMap({ $0 })
        where line.caseInsensitiveCompare(name) != .orderedSame {
            return line
        }
        return nil
    }

    enum Kind: Equatable {
        /// Money to a shop — `mcc` present, money out.
        case purchase
        /// Money back from a shop — `mcc` present, money in.
        case refund
        /// Money out with no shop named: a bill, a transfer, a card payment.
        case paid
        /// Money in with no shop named: a deposit, a transfer in.
        case received
    }

    static func kind(_ t: Transaction) -> Kind {
        let out = (t.amount ?? 0) < 0
        if t.mcc != nil { return out ? .purchase : .refund }
        return out ? .paid : .received
    }

    /// "Grocery store · $125.50"; money in leads with what it is, for
    /// `AppleWalletBridge.rowTitle`'s reason (`titleLine` eats the end).
    static func rowTitle(_ t: Transaction, money: String) -> String {
        switch kind(t) {
        case .purchase, .paid: return "\(label(t)) · \(money)"
        case .refund:          return String(localized: "Refunded · \(label(t)) · \(money)")
        case .received:        return String(localized: "Received · \(label(t)) · \(money)")
        }
    }

    /// Facet tags (§308). `Purchase` and `Refund` are what Spending and
    /// Subscriptions read: a shop's charge and a shop's credit, never a
    /// transfer between your own accounts, which would count a card's spend
    /// twice — once on the card and again as the payment off checking.
    static func tags(_ t: Transaction) -> [String] {
        switch kind(t) {
        case .purchase: return ["Purchase"]
        case .refund:   return ["Refund"]
        case .paid:     return []
        case .received: return ["Deposit"]
        }
    }

    static func isShopCharge(tags: [String]) -> Bool {
        tags.contains("Purchase") || tags.contains("Refund")
    }

    // MARK: - Parsing primitives

    static func text(_ raw: Any?) -> String? {
        guard let s = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty else { return nil }
        return s
    }

    static func number(_ raw: Any?) -> Double? {
        if let d = raw as? Double { return d }
        if let i = raw as? Int { return Double(i) }
        return text(raw).flatMap(Double.init)
    }

    /// An epoch second, or nil for a missing or zero one (zero is pending).
    static func epoch(_ raw: Any?) -> Date? {
        guard let s = number(raw), s > 0 else { return nil }
        return Date(timeIntervalSince1970: s)
    }

    static func isoCurrency(_ s: String) -> Bool {
        s.count == 3 && s.allSatisfy { $0.isLetter && $0.isASCII }
    }

    /// The spec asks for a message to be sanitized before it is shown: one
    /// line, no markup, bounded.
    static func clean(_ message: String) -> String {
        let flat = message.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
            .components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return flat.count > 200 ? String(flat.prefix(199)) + "…" : flat
    }

    /// The field names a payload carries, sorted — for the probe, which
    /// prints shapes and never values.
    static func keyNames(_ row: [String: Any]?) -> [String] {
        (row.map { Array($0.keys) } ?? []).sorted()
    }
}
