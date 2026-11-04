import Foundation

/// **PRIVACY, BY NYMIS (prd §1701).** What an EVM address gives away, read
/// by Nymis (nymis.io) when you tap Scan on Wallet › Threats, and drawn as
/// Casberi's own sheet: Nymis's reading, then its findings. No score
/// anywhere (user, 2026-11-04: "i would like it to NOT have their score").
///
/// Nymis has no public API for a phone (their own answer, 2026-11-04: the
/// Privacy Score API is server-to-server, behind a private key). So the scan
/// goes the way a visitor's does, and only on a tap:
///
/// 1. `analyzeURL` loads in a hidden web view; Nymis's own page starts the
///    scan. A plain GET draws the loading page and starts nothing (measured).
/// 2. `progressURL` answers `status`, `stage` and `scanId` by ADDRESS, so a
///    scan started on one launch is picked up on the next. It runs on
///    Nymis's side to the end with nobody on the page (measured: 270s, the
///    page closed 2s in).
/// 3. Once `completed`, `reportURL(scanId)` serves the report as one HTML
///    page whose React payload carries a `sidebar` object: the summary, the
///    exchanges, the related-address counts, the per-category deductions and
///    the coverage warning. That object is the whole reading.
///
/// Neither door is documented, so every parse here fails closed: a shape
/// that changed reads as nil, the row says the scan failed, and nothing is
/// ever made up. Reports expire after 30 minutes (Nymis), so the reading is
/// kept on the phone.
///
/// Foundation-only: `nymis-selftest.sh` compiles this file whole.
enum NymisScan {

    static let host = "nymis.io"

    /// A 0x address of 40 hex digits; anything else never reaches a URL.
    static func isEVMAddress(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.count == 42, t.lowercased().hasPrefix("0x") else { return false }
        return t.dropFirst(2).allSatisfy(\.isHexDigit)
    }

    /// The one key a reading and a scan are filed under.
    static func key(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespaces).lowercased()
    }

    static func analyzeURL(_ address: String) -> URL? {
        guard isEVMAddress(address) else { return nil }
        return URL(string: "https://\(host)/analyze/\(key(address))")
    }

    static func progressURL(_ address: String) -> URL? {
        guard isEVMAddress(address) else { return nil }
        return URL(string: "https://\(host)/api/scan-progress/legacy/\(key(address))")
    }

    /// A scan id is a UUID (measured); anything else is refused.
    static func reportURL(scanID: String) -> URL? {
        guard UUID(uuidString: scanID) != nil else { return nil }
        return URL(string: "https://\(host)/scan/\(scanID.lowercased())")
    }

    // MARK: - Progress

    enum Status: String, Equatable {
        /// No scan on Nymis's side for this address.
        case none
        case running
        case completed
        case failed
    }

    struct Progress: Equatable {
        let status: Status
        /// Nymis's stage id, e.g. `checking-related-wallets`.
        let stage: String?
        let scanID: String?
        let startedAt: Date?
        let completedAt: Date?
    }

    /// The progress endpoint's answer. Nil for a body that is not its shape.
    /// A `status` of null is no scan; an unknown word is a failure, never a
    /// success.
    static func progress(from data: Data) -> Progress? {
        (try? JSONSerialization.jsonObject(with: data)).flatMap(progress(json:))
    }

    static func progress(json any: Any) -> Progress? {
        guard let json = any as? [String: Any], json.keys.contains("status") else { return nil }
        let raw = json["status"] as? String
        let status: Status
        switch raw {
        case nil: status = .none
        case "running", "queued", "pending", "started": status = .running
        case "completed": status = .completed
        default: status = .failed
        }
        let stage = (json["stage"] as? [String: Any])?["stage"] as? String
        func date(_ key: String) -> Date? {
            (json[key] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        }
        return Progress(status: status, stage: stage,
                        scanID: json["scanId"] as? String,
                        startedAt: date("startedAt"), completedAt: date("completedAt"))
    }

    /// A stage id in words: Nymis's own (`checking-related-wallets` →
    /// "Checking related wallets"), so the row says what Nymis is doing in
    /// Nymis's terms. Nil for nothing to say.
    static func stageWords(_ stage: String?) -> String? {
        guard let stage, !stage.isEmpty else { return nil }
        let words = stage.split(separator: "-").map(String.init)
        guard let first = words.first else { return nil }
        let rest = words.dropFirst().map { $0 == "cex" ? "exchange" : $0 }
        let head = first.prefix(1).uppercased() + first.dropFirst()
        return ([head] + rest).joined(separator: " ")
    }

    // MARK: - The reading

    struct Finding: Codable, Equatable, Hashable, Sendable {
        let label: String
        let value: String
    }

    struct Reading: Codable, Equatable, Sendable {
        let address: String
        /// Nymis's summary, in their words.
        let summary: String
        /// What gives the address away, most first: the row's line.
        let gives: [String]
        /// The sheet's label/value rows, in order.
        let findings: [Finding]
        /// True when Nymis said its read was incomplete.
        let partial: Bool
        let scannedAt: Date
    }

    /// The report page's reading, or nil when its shape is not the one
    /// measured. `scannedAt` is the scan's own completion time.
    static func reading(fromReportHTML html: String, address: String, scannedAt: Date) -> Reading? {
        let flight = flightText(html)
        guard let sidebar = object(after: "\"sidebar\":", in: flight) as? [String: Any],
              let summary = (sidebar["walletSummary"] as? String).map(unescaped),
              !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let deltas = (sidebar["categoryScoreDeltas"] as? [String: Any] ?? [:])
            .compactMap { key, value -> (String, Double)? in
                guard let n = value as? NSNumber, n.doubleValue < 0 else { return nil }
                return (key, n.doubleValue)
            }
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0 < $1.0 }
        let gives = deltas.compactMap { categoryWords[$0.0] }

        var findings: [Finding] = []
        let related = (sidebar["relatedWalletCount"] as? NSNumber)?.intValue ?? 0
        if related > 0 {
            let named = (sidebar["identifiedRelatedWalletCount"] as? NSNumber)?.intValue ?? 0
            findings.append(Finding(label: "Related addresses",
                                    value: named > 0 ? "\(related), \(named) named" : "\(related)"))
        }
        let exchanges = (sidebar["financialNames"] as? [String] ?? [])
            .map(unescaped).filter { !$0.isEmpty && !$0.hasPrefix("$") }
        if !exchanges.isEmpty {
            findings.append(Finding(label: "Exchanges", value: exchanges.joined(separator: ", ")))
        }
        let identity = identityPlatforms(flight)
        if !identity.isEmpty {
            findings.append(Finding(label: "Identity", value: identity.joined(separator: ", ")))
        }
        if let safes = safeCount(sidebar), safes > 0 {
            findings.append(Finding(label: "Signs for", value: safes == 1 ? "1 Safe" : "\(safes) Safes"))
        }
        let deployed = (sidebar["directContractDeploymentCount"] as? NSNumber)?.intValue ?? 0
        if deployed > 0 {
            findings.append(Finding(label: "Contracts deployed", value: "\(deployed)"))
        }
        if let span = activeSpan(first: sidebar["firstActivity"] as? String,
                                 last: sidebar["lastActivity"] as? String) {
            findings.append(Finding(label: "Active", value: span))
        }

        let warning = (sidebar["coverageWarning"] as? String) ?? ""
        return Reading(address: key(address), summary: unescaped(summary), gives: gives,
                       findings: findings,
                       partial: !warning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       scannedAt: scannedAt)
    }

    /// Nymis's categories in the row's words. A key not here is left out of
    /// the line rather than shown as Nymis's code.
    static let categoryWords: [String: String] = [
        "relatedWallets": "related addresses",
        "kycServices": "exchanges",
        "publicIdentity": "identity",
        "safeSigner": "Safe signing",
    ]

    /// The row's line: "Related addresses, exchanges, identity". Nil when
    /// nothing costs the address anything.
    static func rowLine(_ reading: Reading) -> String? {
        guard let first = reading.gives.first else { return nil }
        let head = first.prefix(1).uppercased() + first.dropFirst()
        return ([head] + reading.gives.dropFirst()).joined(separator: ", ")
    }

    // MARK: - Reading the page

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
        return a == b ? a : "\(a) to \(b)"
    }
}
