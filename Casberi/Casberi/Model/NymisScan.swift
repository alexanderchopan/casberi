import Foundation

/// **PRIVACY, BY NYMIS (prd §1701, §1701a).** What an EVM address gives
/// away, read by Nymis (nymis.io) when you tap Scan on Wallet › Threats, and
/// drawn as Casberi's own sheet: Nymis's findings. No score anywhere (user,
/// 2026-11-04: "i would like it to NOT have their score").
///
/// Nymis's public Privacy Score API (their contract, 2026-11-05; §1701a):
///
/// 1. `POST /api/v1/privacy-score` with the address in the JSON BODY, one
///    UUIDv4 `Idempotency-Key` per scan the person asked for, and no API key.
///    202 is a new scan: an opaque `scanId` and a `scanToken`. 200 is a
///    cached result, read at once. A retry with the same key and address
///    reattaches to the same scan for 30 minutes.
/// 2. `GET /api/v1/privacy-score/status/<scanId>` with the token in the
///    `x-scan-token` HEADER, every 10–15 s, until `completed`, `incomplete`
///    or `failed`.
///
/// Neither the address nor the token ever goes in a URL, and the token is
/// never logged. The score and grade in the reply are read by nothing. A
/// reply that is not this shape reads as a failed scan; nothing is made up.
/// Results expire on Nymis's side after 30 minutes, so the reading is kept
/// on the phone.
///
/// Foundation-only: `nymis-selftest.sh` compiles this file whole.
enum NymisScan {

    static let host = "nymis.io"
    static let createURL = URL(string: "https://nymis.io/api/v1/privacy-score")!
    /// Attribution only (Nymis's word); it buys no quota.
    static let partnerID = "casberi"

    /// A 0x address of 40 hex digits; anything else never reaches Nymis.
    static func isEVMAddress(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.count == 42, t.lowercased().hasPrefix("0x") else { return false }
        return t.dropFirst(2).allSatisfy(\.isHexDigit)
    }

    /// The one key a reading and a scan are filed under.
    static func key(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespaces).lowercased()
    }

    // MARK: - Requests

    /// The create call: the address in the body, never the URL.
    static func createRequest(address: String, idempotencyKey: String) -> URLRequest? {
        guard isEVMAddress(address), UUID(uuidString: idempotencyKey) != nil,
              let body = try? JSONSerialization.data(withJSONObject: ["address": key(address)]) else { return nil }
        var request = URLRequest(url: createURL)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(idempotencyKey.lowercased(), forHTTPHeaderField: "Idempotency-Key")
        request.setValue(partnerID, forHTTPHeaderField: "x-partner-id")
        request.timeoutInterval = 30
        return request
    }

    /// The poll: the scan id in the path (a UUID, or refused), the token in
    /// a header.
    static func pollRequest(scanID: String, token: String) -> URLRequest? {
        guard UUID(uuidString: scanID) != nil, !token.isEmpty else { return nil }
        let url = createURL.appendingPathComponent("status").appendingPathComponent(scanID.lowercased())
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(token, forHTTPHeaderField: "x-scan-token")
        request.timeoutInterval = 30
        return request
    }

    // MARK: - Answers

    enum Answer: Equatable {
        /// Still running. The create call hands both; a poll hands neither.
        case processing(scanID: String?, token: String?)
        case read(Reading)
        /// Nymis's limits: try again no sooner than this.
        case busy(until: Date)
        /// No answer, or a server error: ask again next round, same key.
        case retry
        /// Over: a failed scan, an expired one, a refusal, or a shape that
        /// is not Nymis's.
        case failed
    }

    /// One reply, create or poll. `status` is 0 when nothing answered.
    static func answer(status: Int, retryAfter: String?, body: Data?,
                       address: String, now: Date) -> Answer {
        switch status {
        case 0, 500...599: return .retry
        case 429: return .busy(until: now.addingTimeInterval(retrySeconds(retryAfter, now: now)))
        case 200...299: break
        default: return .failed
        }
        guard let body, let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else {
            return .failed
        }
        switch json["status"] as? String {
        case "processing":
            let id = (json["scanId"] as? String).flatMap { UUID(uuidString: $0) != nil ? $0 : nil }
            let token = (json["scanToken"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return .processing(scanID: id, token: token)
        case "completed", "incomplete":
            return reading(json: json, address: address, scannedAt: now).map(Answer.read) ?? .failed
        default:
            return .failed
        }
    }

    /// `Retry-After` in seconds or as an HTTP date; a minute when it is
    /// missing or unreadable, never less than ten seconds, never more than a
    /// day (Nymis's quotas reset at midnight UTC).
    static func retrySeconds(_ header: String?, now: Date) -> TimeInterval {
        let raw = header?.trimmingCharacters(in: .whitespaces) ?? ""
        let seconds: TimeInterval
        if let n = TimeInterval(raw) {
            seconds = n
        } else if let date = httpDate.date(from: raw) {
            seconds = date.timeIntervalSince(now)
        } else {
            seconds = 60
        }
        return min(max(seconds, 10), 24 * 3600)
    }

    private static let httpDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f
    }()

    // MARK: - The reading

    struct Finding: Codable, Equatable, Hashable, Sendable {
        let id: String
        let title: String
        /// Nymis's word; orders the findings, never drawn.
        let severity: String
        let explanation: String
    }

    struct Group: Codable, Equatable, Hashable, Sendable {
        /// Nymis's group: Identity, Financial or Behavioral.
        let name: String
        let findings: [Finding]
    }

    struct Reading: Codable, Equatable, Sendable {
        let address: String
        /// Nymis's groups in Nymis's order, empty ones left out.
        let groups: [Group]
        /// True when Nymis said its read was incomplete or not authoritative.
        var partial: Bool
        let scannedAt: Date
        /// The finished scan's page (prd §1701b): Nymis's summary in their
        /// words, what gives the address away most first, and the facts the
        /// page lists (exchanges, identity platforms, Safes…). Nil when the
        /// page could not be read; the sheet then draws the findings.
        var summary: String? = nil
        var gives: [String]? = nil
        var facts: [Fact]? = nil
        /// The scan Nymis's page is filed under: See more opens it.
        var scanID: String? = nil

        var findings: [Finding] { groups.flatMap(\.findings) }

        /// This reading with the page's, which is the richer of the two.
        func adding(_ page: Page, scanID: String) -> Reading {
            var r = self
            r.summary = page.summary
            r.gives = page.gives
            r.facts = page.facts
            r.scanID = scanID
            r.partial = partial || page.partial
            return r
        }
    }

    /// Nymis's groups, in the order the sheet draws them.
    static let groupNames = ["Identity", "Financial", "Behavioral"]

    /// A finished reply's reading, or nil when it is not Nymis's shape or
    /// answers for another address. The score and grade are never read.
    static func reading(json: [String: Any], address: String, scannedAt: Date) -> Reading? {
        let status = json["status"] as? String
        guard status == "completed" || status == "incomplete" else { return nil }
        if let said = json["address"] as? String, key(said) != key(address) { return nil }
        // An empty list does not prove no exposure (Nymis); the sheet says so.
        let found = json["findings"] as? [String: Any] ?? [:]
        let groups = groupNames.compactMap { name -> Group? in
            let list = (found[name] as? [Any] ?? []).compactMap(finding)
            let ordered = list.enumerated().sorted {
                let a = severityRank($0.element.severity), b = severityRank($1.element.severity)
                return a != b ? a < b : $0.offset < $1.offset
            }.map(\.element)
            return ordered.isEmpty ? nil : Group(name: name, findings: ordered)
        }
        let authoritative = (json["completeness"] as? [String: Any])?["authoritative"] as? Bool
        return Reading(address: key(address), groups: groups,
                       partial: status == "incomplete" || authoritative != true,
                       scannedAt: scannedAt)
    }

    /// One finding, or nil without a title. Evidence is optional (Nymis)
    /// and not drawn.
    static func finding(_ any: Any) -> Finding? {
        guard let f = any as? [String: Any],
              let title = (f["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else { return nil }
        return Finding(id: (f["id"] as? String) ?? title, title: title,
                       severity: (f["severity"] as? String)?.lowercased() ?? "",
                       explanation: ((f["explanation"] as? String) ?? "")
                           .trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func severityRank(_ s: String) -> Int {
        ["critical": 0, "high": 1, "medium": 2, "moderate": 2, "low": 3, "info": 4, "informational": 4][s] ?? 5
    }

    /// The row's line: what the page says gives the address away, most first
    /// ("Related addresses, exchanges, identity"), else Nymis's groups with
    /// findings, most first ("Identity, financial"). Nil when Nymis found
    /// nothing.
    static func rowLine(_ reading: Reading) -> String? {
        if let gives = reading.gives, let first = gives.first {
            let head = first.prefix(1).uppercased() + first.dropFirst()
            return ([head] + gives.dropFirst()).joined(separator: ", ")
        }
        let ordered = reading.groups.enumerated().sorted {
            $0.element.findings.count != $1.element.findings.count
                ? $0.element.findings.count > $1.element.findings.count : $0.offset < $1.offset
        }.map(\.element.name)
        guard let first = ordered.first else { return nil }
        return ([first] + ordered.dropFirst().map { $0.lowercased() }).joined(separator: ", ")
    }
}


// MARK: - The finished scan's page (prd §1701b)

/// The API hands findings and no summary; the scan's own page carries
/// Nymis's reading as people see it on nymis.io: the summary, and the facts
/// (Related addresses, Exchanges, Identity, Signs for, Contracts deployed,
/// Active). So once a scan is read, its page is fetched ONCE, by scan id,
/// and its React payload's `sidebar` object is read (measured 2026-11-04 and
/// again 2026-11-05: a plain GET serves the whole payload). Nothing starts a
/// scan here. Undocumented, so every parse fails closed: a page that changed
/// leaves the API's reading standing, never a made-up one.
extension NymisScan {

    /// The scan's page, by id (a UUID, or refused): what See more opens.
    static func reportURL(scanID: String) -> URL? {
        guard UUID(uuidString: scanID) != nil else { return nil }
        return URL(string: "https://\(host)/scan/\(scanID.lowercased())")
    }

    /// Only for a CACHED result, which the API hands with no scan id: the
    /// finished scan's id by address. The address is public and this asks
    /// nothing new of Nymis; it is the one URL that carries it.
    static func progressURL(_ address: String) -> URL? {
        guard isEVMAddress(address) else { return nil }
        return URL(string: "https://\(host)/api/scan-progress/legacy/\(key(address))")
    }

    /// A completed scan's id from that answer; nil for anything else.
    static func completedScanID(fromProgress data: Data) -> String? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              json["status"] as? String == "completed",
              let id = json["scanId"] as? String, UUID(uuidString: id) != nil else { return nil }
        return id
    }

    struct Fact: Codable, Equatable, Hashable, Sendable {
        let label: String
        let value: String
    }

    struct Page: Equatable, Sendable {
        let summary: String
        let gives: [String]
        let facts: [Fact]
        let partial: Bool
    }

    /// The page's reading, or nil when its shape is not the one measured.
    static func page(fromReportHTML html: String) -> Page? {
        let flight = flightText(html)
        guard let sidebar = object(after: "\"sidebar\":", in: flight) as? [String: Any],
              let summary = (sidebar["walletSummary"] as? String).map(unescaped)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !summary.isEmpty else { return nil }

        let deltas = (sidebar["categoryScoreDeltas"] as? [String: Any] ?? [:])
            .compactMap { key, value -> (String, Double)? in
                guard let n = value as? NSNumber, n.doubleValue < 0 else { return nil }
                return (key, n.doubleValue)
            }
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0 < $1.0 }
        let gives = deltas.compactMap { categoryWords[$0.0] }

        var facts: [Fact] = []
        let related = (sidebar["relatedWalletCount"] as? NSNumber)?.intValue ?? 0
        if related > 0 {
            let named = (sidebar["identifiedRelatedWalletCount"] as? NSNumber)?.intValue ?? 0
            facts.append(Fact(label: String(localized: "Related addresses"),
                              value: named > 0 ? String(localized: "\(related), \(named) named") : "\(related)"))
        }
        let exchanges = (sidebar["financialNames"] as? [String] ?? [])
            .map(unescaped).filter { !$0.isEmpty && !$0.hasPrefix("$") }
        if !exchanges.isEmpty {
            facts.append(Fact(label: String(localized: "Exchanges"), value: exchanges.joined(separator: ", ")))
        }
        let identity = identityPlatforms(flight)
        if !identity.isEmpty {
            facts.append(Fact(label: String(localized: "Identity"), value: identity.joined(separator: ", ")))
        }
        if let safes = safeCount(sidebar), safes > 0 {
            facts.append(Fact(label: String(localized: "Signs for"),
                              value: safes == 1 ? String(localized: "1 Safe") : String(localized: "\(safes) Safes")))
        }
        let deployed = (sidebar["directContractDeploymentCount"] as? NSNumber)?.intValue ?? 0
        if deployed > 0 {
            facts.append(Fact(label: String(localized: "Contracts deployed"), value: "\(deployed)"))
        }
        if let span = activeSpan(first: sidebar["firstActivity"] as? String,
                                 last: sidebar["lastActivity"] as? String) {
            facts.append(Fact(label: String(localized: "Active"), value: span))
        }
        let warning = (sidebar["coverageWarning"] as? String) ?? ""
        return Page(summary: unescaped(summary), gives: gives, facts: facts,
                    partial: !warning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    /// Nymis's page categories in the row's words. A key not here is left
    /// out of the line rather than shown as Nymis's code.
    static let categoryWords: [String: String] = [
        "relatedWallets": String(localized: "related addresses"),
        "kycServices": String(localized: "exchanges"),
        "publicIdentity": String(localized: "identity"),
        "safeSigner": String(localized: "Safe signing"),
    ]

    /// Every `self.__next_f.push([1,"…"])` string literal on the page, decoded
    /// and joined: the React payload the report is drawn from.
    static func flightText(_ html: String) -> String {
        var out = ""
        let marker = "self.__next_f.push([1,\""
        var search = html.startIndex
        while let open = html.range(of: marker, range: search..<html.endIndex) {
            var i = open.upperBound
            var literal = "\""
            var closed = false
            while i < html.endIndex {
                let c = html[i]
                literal.append(c)
                if c == "\\" {
                    let next = html.index(after: i)
                    if next < html.endIndex { literal.append(html[next]); i = html.index(after: next); continue }
                } else if c == "\"" {
                    closed = true
                    i = html.index(after: i)
                    break
                }
                i = html.index(after: i)
            }
            search = i
            guard closed,
                  let data = "[\(literal)]".data(using: .utf8),
                  let decoded = (try? JSONSerialization.jsonObject(with: data)) as? [String] else { continue }
            out += decoded.first ?? ""
        }
        return out
    }

    /// The JSON value that starts right after `marker`, balanced by braces
    /// and brackets outside strings.
    static func object(after marker: String, in text: String) -> Any? {
        guard let start = text.range(of: marker)?.upperBound else { return nil }
        return value(at: start, in: text)
    }

    static func value(at start: String.Index, in text: String) -> Any? {
        var depth = 0
        var inString = false
        var escaped = false
        var i = start
        while i < text.endIndex {
            let c = text[i]
            if inString {
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
            } else if c == "\"" {
                inString = true
            } else if c == "{" || c == "[" {
                depth += 1
            } else if c == "}" || c == "]" {
                depth -= 1
                if depth == 0 {
                    let slice = text[start...i]
                    guard let data = String(slice).data(using: .utf8) else { return nil }
                    return try? JSONSerialization.jsonObject(with: data)
                }
            } else if depth == 0 && !c.isWhitespace {
                return nil
            }
            i = text.index(after: i)
        }
        return nil
    }

    /// React escapes a literal leading `$` as `$$`.
    static func unescaped(_ s: String) -> String {
        s.hasPrefix("$$") ? String(s.dropFirst()) : s
    }

    /// The platforms the address's own identity node names: "X, ENS,
    /// Farcaster, Wei". Read off the graph's first `Identity` node.
    static func identityPlatforms(_ flight: String) -> [String] {
        guard let node = flight.range(of: "\"type\":\"Identity\""),
              let signals = flight.range(of: "\"clusterSignals\":", range: node.upperBound..<flight.endIndex),
              flight.distance(from: node.upperBound, to: signals.lowerBound) < 400,
              let list = value(at: signals.upperBound, in: flight) as? [[String: Any]] else { return [] }
        var seen: [String] = []
        for signal in list {
            guard var label = signal["label"] as? String, !label.isEmpty else { continue }
            if label == "Twitter" || label == "X/Twitter" { label = "X" }
            if !seen.contains(label) { seen.append(label) }
        }
        return seen
    }

    /// "Signer on 3 Safes", from the share card's notes.
    static func safeCount(_ sidebar: [String: Any]) -> Int? {
        let notes = ((sidebar["shareCard"] as? [String: Any])?["notes"] as? [[String: Any]]) ?? []
        for note in notes {
            guard let text = note["text"] as? String, text.hasPrefix("Signer on ") else { continue }
            let digits = text.dropFirst("Signer on ".count).prefix { $0.isNumber }
            return Int(digits)
        }
        return nil
    }

    /// "Apr 2021 to Nov 2026" from Nymis's "Apr 25, 2021" and "Nov 4, 2026";
    /// one month when they meet.
    static func activeSpan(first: String?, last: String?) -> String? {
        func month(_ s: String?) -> String? {
            guard let s else { return nil }
            let parts = s.replacingOccurrences(of: ",", with: "").split(separator: " ")
            guard parts.count == 3, parts[0].count == 3, Int(parts[2]) != nil else { return nil }
            return "\(parts[0]) \(parts[2])"
        }
        guard let a = month(first), let b = month(last) else { return nil }
        return a == b ? a : String(localized: "\(a) to \(b)")
    }
}
