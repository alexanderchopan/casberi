import Foundation

/// **PRIVACY, BY NYMIS (prd §1701, §1701a, §1701c).** What an EVM address gives
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
///    `x-scan-token` HEADER, every 30 s, then 60 s past five minutes (§1701d), until `completed`, `incomplete`
///    or `failed`.
/// 3. Nymis's summaries come on the same poll (their client-mode contract,
///    2026-11-06; §1701c): once scored, `summaryStatus` is `pending`, then
///    `ready` with `summaries.overview` and `summaries.financial`, or
///    `unavailable`. Polled every 5 s for at most 30 s after scoring.
/// 4. The finished reply carries `facts` (Nymis release d216e66, §1701d):
///    exchanges and payment services, public identity, the report's selected
///    related addresses (at most five), Safes signed for, contracts deployed,
///    the observed activity span, and the unranked categories that gave the
///    address away. Deterministic, never AI text, and not exhaustive.
///
/// That is all Casberi reads. Nymis's web reports and its legacy and
/// internal endpoints are never called (§1701c, Nymis: "Do not scrape web
/// reports or call legacy/internal endpoints"); See more OPENS the report for
/// the person and reads nothing.
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
        /// Scored. `summaryPending`: Nymis is still writing its summaries,
        /// which a poll of the same scan hands within 30 s.
        case read(Reading, summaryPending: Bool)
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
            guard let r = reading(json: json, address: address, scannedAt: now) else { return .failed }
            return .read(r, summaryPending: json["summaryStatus"] as? String == "pending")
        default:
            return .failed
        }
    }

    /// How long to wait before polling a running scan again (Nymis, §1701d):
    /// every 30 s for its first five minutes, then every 60 s. A heavy
    /// wallet can take several minutes.
    static func pollInterval(age: TimeInterval) -> TimeInterval {
        age < 5 * 60 ? 30 : 60
    }

    /// Nymis's per-scan budget: 30 requests in all, retries included, and
    /// nothing past 25 minutes from the first ask (its token lasts about 30).
    static let requestBudget = 30
    static let maxAge: TimeInterval = 25 * 60
    /// What the row promises while a scan runs ("takes a few minutes"); past
    /// it, the line says a busy wallet takes longer. Nymis's own fast-poll
    /// window, and one measured scan ended at 270 s (§1701 item 5).
    static let fewMinutes: TimeInterval = 5 * 60

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

    // MARK: - A refusal, as Nymis said it

    /// One 429 on one line, so it can be handed to Nymis as it came (Nymis,
    /// relayed by the user 2026-11-11: "share the error code returned by
    /// Nymis"): the body's code and message, `Retry-After`, every rate-limit
    /// header and the request's id. Only those fields are read: the body's
    /// other keys are dropped, and an address in any of them reads `0x…`.
    static func refusalLine(phase: String, retryAfter: String?,
                            headers: [AnyHashable: Any], body: Data?) -> String {
        var parts = ["nymis| 429", phase]
        if let body, let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] {
            // Flat (`code`, `message`) or nested under `error`.
            let nested = json["error"] as? [String: Any] ?? [:]
            for key in ["code", "errorCode", "error", "message", "detail", "reason"] {
                guard let value = refusalWord(json[key] ?? nested[key]) else { continue }
                parts.append("\(key)=\(value)")
            }
        } else if let body, let text = String(data: body, encoding: .utf8), let value = refusalWord(text) {
            parts.append("body=\(value)")
        }
        if let value = refusalWord(retryAfter) { parts.append("retry-after=\(value)") }
        let named = headers.compactMap { pair -> (String, String)? in
            guard let name = (pair.key as? String)?.lowercased(),
                  name.contains("ratelimit") || name.contains("rate-limit") || refusalHeaders.contains(name),
                  let word = refusalWord(pair.value) else { return nil }
            return (name, word)
        }
        parts += named.sorted { $0.0 < $1.0 }.map { "\($0.0)=\($0.1)" }
        return parts.joined(separator: " | ")
    }

    /// The headers that name the request to Nymis's own logs.
    static let refusalHeaders: Set<String> = ["date", "x-request-id", "request-id", "cf-ray", "x-vercel-id"]

    /// A string or a number, one line, at most 160 characters, no address.
    private static func refusalWord(_ value: Any?) -> String? {
        guard let value else { return nil }
        let raw: String
        switch value {
        case let s as String: raw = s
        case let n as NSNumber: raw = n.stringValue
        default: return nil
        }
        let line = raw.replacingOccurrences(of: #"0x[0-9a-fA-F]{40}"#, with: "0x…", options: .regularExpression)
            .replacingOccurrences(of: #"[\r\n|]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return line.isEmpty ? nil : String(line.prefix(160))
    }

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

    /// One label/value row of Nymis's facts (§1701d; the scan page's,
    /// §1701b, on a reading stored before §1701c).
    struct Fact: Codable, Equatable, Hashable, Sendable {
        let label: String
        let value: String
        /// "related" on the Related addresses row: the selected addresses
        /// are drawn under it.
        var kind: String? = nil
    }

    /// One of the report's selected related addresses (§1701d). Drawn by the
    /// sheet, which shortens the address.
    struct Related: Codable, Equatable, Hashable, Sendable {
        let address: String
        let name: String?
        /// "Polymarket", in Casberi's spelling of the platform.
        let platform: String?
        /// Observed transfers between the two, when Nymis can count them.
        let transfers: Int?
    }

    struct Reading: Codable, Equatable, Sendable {
        let address: String
        /// Nymis's groups in Nymis's order, empty ones left out.
        let groups: [Group]
        /// True only when Nymis said `incomplete` (§1701c): a non-
        /// authoritative score or partial coverage alone is not a warning.
        var partial: Bool
        let scannedAt: Date
        /// Nymis's summaries in their words (§1701c): what the address gives
        /// away, then its money trail. Nil until Nymis has written them, or
        /// when it could not.
        var overview: String? = nil
        var financial: String? = nil
        /// Nymis's word on an incomplete scan, drawn only when it is a
        /// sentence (a code like `provider_timeout` is not).
        var reason: String? = nil
        /// The scan Nymis files the report under: See more opens it.
        var scanID: String? = nil
        /// The scan page's summary (§1701b), on a reading stored before
        /// §1701c. Nothing writes it now.
        var summary: String? = nil
        /// What gave the address away, in the row's words (§1701d's
        /// `privacyContributors`; §1701b's page before it). Nil when Nymis
        /// named none, as on an incomplete scan.
        var gives: [String]? = nil
        /// Nymis's facts as label/value rows (§1701d), empty ones left out.
        var facts: [Fact]? = nil
        var related: [Related]? = nil

        var findings: [Finding] { groups.flatMap(\.findings) }

        /// This reading with the summaries a later poll handed.
        func adding(summariesOf later: Reading) -> Reading {
            var r = self
            r.overview = later.overview
            r.financial = later.financial
            if r.facts == nil, later.facts != nil {
                r.facts = later.facts
                r.related = later.related
                r.gives = later.gives
            }
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
        // Summaries only when Nymis says they are ready; an unknown source
        // or status never hides the findings.
        let summaries = json["summaryStatus"] as? String == "ready"
            ? json["summaries"] as? [String: Any] : nil
        let reason = (json["reason"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let read = facts(json["facts"])
        return Reading(address: key(address), groups: groups,
                       partial: status == "incomplete",
                       scannedAt: scannedAt,
                       overview: summaryText(summaries?["overview"]),
                       financial: summaryText(summaries?["financial"]),
                       reason: reason.flatMap { $0.contains(" ") ? $0 : nil },
                       scanID: (json["scanId"] as? String).flatMap { UUID(uuidString: $0) != nil ? $0.lowercased() : nil },
                       gives: read?.gives,
                       facts: read?.facts,
                       related: read?.related)
    }

    // MARK: - Facts (§1701d)

    struct FactsRead: Equatable {
        let facts: [Fact]
        let related: [Related]
        let gives: [String]?
    }

    /// Nymis's `facts`, as the rows §1701 ruled: Related addresses, Exchanges
    /// and payments, Identity, Signs for, Contracts deployed, Active. An empty
    /// list or a null count draws no row: no evidence surfaced is not proof
    /// of none. Nil when the reply carries no facts object.
    static func facts(_ any: Any?, locale: Locale = .current) -> FactsRead? {
        guard let f = any as? [String: Any] else { return nil }
        var rows: [Fact] = []

        let set = f["relatedAddresses"] as? [String: Any] ?? [:]
        let related = (set["records"] as? [Any] ?? []).compactMap(relatedRecord)
        let selected = (set["selectedCount"] as? NSNumber)?.intValue ?? related.count
        if selected > 0 {
            let named = (set["namedSelectedCount"] as? NSNumber)?.intValue ?? 0
            rows.append(Fact(label: String(localized: "Related addresses"),
                             value: named > 0 ? String(localized: "\(selected), \(named) named") : "\(selected)",
                             kind: "related"))
        }
        var services: [String] = []
        for any in f["kycServices"] as? [Any] ?? [] {
            guard let name = trimmed((any as? [String: Any])?["name"]), !services.contains(name) else { continue }
            services.append(name)
        }
        if !services.isEmpty {
            rows.append(Fact(label: String(localized: "Exchanges and payments"), value: services.joined(separator: ", ")))
        }
        var platforms: [String] = []
        for any in f["publicIdentity"] as? [Any] ?? [] {
            guard let raw = trimmed((any as? [String: Any])?["platform"]) else { continue }
            let platform = platformName(raw)
            if !platforms.contains(platform) { platforms.append(platform) }
        }
        if !platforms.isEmpty {
            rows.append(Fact(label: String(localized: "Identity"), value: platforms.joined(separator: ", ")))
        }
        if let safes = ((f["safeSigner"] as? [String: Any])?["count"] as? NSNumber)?.intValue, safes > 0 {
            rows.append(Fact(label: String(localized: "Signs for"),
                             value: safes == 1 ? String(localized: "1 Safe") : String(localized: "\(safes) Safes")))
        }
        if let deployed = ((f["contractsDeployed"] as? [String: Any])?["count"] as? NSNumber)?.intValue, deployed > 0 {
            rows.append(Fact(label: String(localized: "Contracts deployed"), value: "\(deployed)"))
        }
        let activity = f["activity"] as? [String: Any] ?? [:]
        if let span = activeSpan(first: activity["firstObservedAt"] as? String,
                                 last: activity["lastObservedAt"] as? String, locale: locale) {
            rows.append(Fact(label: String(localized: "Active"), value: span))
        }
        // Unranked (Nymis), so the row's words keep Casberi's order; a key
        // Casberi has no words for is left out rather than shown as a code.
        let keys = Set((f["privacyContributors"] as? [Any] ?? []).compactMap { $0 as? String })
        let gives = categoryOrder.filter(keys.contains).compactMap { categoryWords[$0] }
        return FactsRead(facts: rows, related: related, gives: gives.isEmpty ? nil : gives)
    }

    /// One selected related address, or nil without a 0x address.
    static func relatedRecord(_ any: Any) -> Related? {
        guard let r = any as? [String: Any], let address = trimmed(r["address"]),
              isEVMAddress(address) else { return nil }
        let count = (r["transactionCount"] as? NSNumber)?.intValue
        return Related(address: key(address), name: trimmed(r["name"]),
                       platform: trimmed(r["profilePlatform"]).map(platformName),
                       transfers: count.flatMap { $0 > 0 ? $0 : nil })
    }

    /// Nymis's platform word in Casberi's spelling.
    static func platformName(_ raw: String) -> String {
        switch raw.lowercased() {
        case "twitter", "x", "x/twitter": return "X"
        case "ens": return "ENS"
        case "github": return "GitHub"
        case "": return raw
        default: return raw.prefix(1).uppercased() + raw.dropFirst()
        }
    }

    static func trimmed(_ any: Any?) -> String? {
        guard let s = (any as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    /// The row's words for Nymis's category keys, in the order the row says
    /// them.
    static let categoryOrder = ["relatedWallets", "kycServices", "publicIdentity", "safeSigner"]
    static let categoryWords: [String: String] = [
        "relatedWallets": String(localized: "related addresses"),
        "kycServices": String(localized: "exchanges"),
        "publicIdentity": String(localized: "identity"),
        "safeSigner": String(localized: "Safe signing"),
    ]

    /// "Apr 2021 to Nov 2026" from Nymis's ISO 8601 times, read in UTC;
    /// one month when they meet; nil when either is missing or unreadable.
    static func activeSpan(first: String?, last: String?, locale: Locale = .current) -> String? {
        func date(_ s: String?) -> Date? {
            guard let s else { return nil }
            let plain = ISO8601DateFormatter()
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return fractional.date(from: s) ?? plain.date(from: s)
        }
        guard let a = date(first), let b = date(last) else { return nil }
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate("MMMyyyy")
        let from = f.string(from: a), to = f.string(from: b)
        return from == to ? from : String(localized: "\(from) to \(to)")
    }

    /// One summary's `text`, trimmed; nil when empty or not Nymis's shape.
    static func summaryText(_ any: Any?) -> String? {
        guard let text = ((any as? [String: Any])?["text"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
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

    /// The row's line: what gave the address away ("Related addresses,
    /// exchanges, identity"; §1701d, or a stored page reading's, §1701b),
    /// else Nymis's groups with findings, most first ("Identity,
    /// financial"). Nil when Nymis found nothing.
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

    /// The scan's report on nymis.io, by id (a UUID, or refused): what See
    /// more OPENS for the person. Casberi never fetches it (§1701c).
    static func reportURL(scanID: String) -> URL? {
        guard UUID(uuidString: scanID) != nil else { return nil }
        return URL(string: "https://\(host)/scan/\(scanID.lowercased())")
    }
}
