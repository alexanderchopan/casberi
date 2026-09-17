import Foundation

/// Safe's Client Gateway speaks a different dialect from the transaction
/// service, and this file is the whole translation (prd §789b).
///
/// **Why there is a translation rather than a rewrite.** The readers above it
/// — `SafeBridge.describe`, `SafeSigner.transaction(from:)`, the confirmation
/// walk, the pending-duration line — have been parsing the transaction
/// service's row shape since §652, and that parsing is correct and covered.
/// So the edge adapts to the shape the app already reads, and everything
/// inland is untouched. One file to get right, and it is Foundation-only, so
/// `safe-gateway-selftest.sh` compiles it whole and drives it without a
/// network.
///
/// **The four differences that would each fail SILENTLY**, measured on a real
/// Safe with a real pending queue (§789b point 6) rather than read off the
/// spec:
///
/// 1. An address is `{value, name, logoUri}`, not a bare string — but not
///    always: `gasToken` arrives bare while `refundReceiver` beside it is
///    wrapped. Read either, or an owner set silently becomes empty.
/// 2. An absent guard is `null`, where the service sends the zero address.
///    `SafeBridge` already maps the zero address to nil, so both must land on
///    nil or a Safe with no guard reads as a Safe with one.
/// 3. A time is milliseconds since the epoch, where the service sends
///    ISO 8601 and `ClaudeImport.parseDate` expects it. An Int handed to that
///    parser is nil, and nil is "no date", which is not an error anywhere.
/// 4. The queued LIST carries `methodName`/`actionCount` but no
///    `dataDecoded`, so the batch reading §652 built needs the per-transaction
///    detail. That is the one place this host costs more requests than the
///    service, and it is per PENDING TRANSACTION, not per Safe.
enum SafeGatewayShape {

    // MARK: - Scalars

    /// An address from either dialect: `{value: "0x…"}` or `"0x…"`.
    /// Anything else is nil rather than a guess.
    static func address(_ any: Any?) -> String? {
        if let s = any as? String { return s.isEmpty ? nil : s }
        if let o = any as? [String: Any], let v = o["value"] as? String {
            return v.isEmpty ? nil : v
        }
        return nil
    }

    static func addresses(_ any: Any?) -> [String] {
        guard let rows = any as? [Any] else { return [] }
        return rows.compactMap { address($0) }
    }

    /// An Int from either an Int, an NSNumber or a decimal string — the
    /// service sends `nonce` both ways across serializer versions, and the
    /// gateway sends it as an Int.
    static func int(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let n = any as? NSNumber { return n.intValue }
        if let s = any as? String { return Int(s) }
        return nil
    }

    /// Milliseconds since the epoch → the ISO 8601 spelling
    /// `ClaudeImport.parseDate` reads. Emitted without fractional seconds
    /// because that parser's plain formatter takes it and its fractional one
    /// is the fallback, never the other way round.
    static func iso8601(millis: Any?) -> String? {
        guard let ms = int(millis) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return f.string(from: Date(timeIntervalSince1970: Double(ms) / 1000))
    }

    // MARK: - GET /v1/chains/{id}/safes/{addr}

    struct Detail: Equatable {
        let nonce: Int
        let threshold: Int
        let owners: [String]   // lowercased, sorted
        let modules: [String]  // lowercased, sorted
        let guardAddr: String? // lowercased; nil for none
    }

    private static let zeroAddress = "0x0000000000000000000000000000000000000000"

    /// nil when the body is not a Safe's state at all — an owner set is the
    /// one field a Safe always has, so a body without one is not an empty
    /// Safe, it is a body we did not understand (§83).
    static func detail(_ root: Any?) -> Detail? {
        guard let root = root as? [String: Any] else { return nil }
        let owners = addresses(root["owners"]).map { $0.lowercased() }.sorted()
        guard !owners.isEmpty else { return nil }
        let raw = address(root["guard"])?.lowercased()
        return Detail(
            nonce: int(root["nonce"]) ?? 0,
            threshold: int(root["threshold"]) ?? 0,
            owners: owners,
            modules: addresses(root["modules"]).map { $0.lowercased() }.sorted(),
            guardAddr: (raw == nil || raw == zeroAddress) ? nil : raw)
    }

    // MARK: - GET /v1/chains/{id}/owners/{addr}/safes

    /// `{"safes": […]}` — the same envelope the transaction service sends, so
    /// this is the one read that needed no translation at all. It is here so
    /// that a shape change is caught by the harness rather than by a person.
    static func ownerSafes(_ root: Any?) -> [String]? {
        guard let root = root as? [String: Any] else { return nil }
        guard let safes = root["safes"] as? [Any] else { return nil }
        return safes.compactMap { address($0) }
    }

    // MARK: - GET /v1/chains/{id}/safes/{addr}/transactions/queued

    /// The gateway's own id for one queued transaction. `LABEL` and
    /// `CONFLICT_HEADER` rows are the list's furniture and carry no
    /// transaction, so they are dropped here rather than half-read later.
    static func queuedIDs(_ root: Any?) -> [String]? {
        guard let root = root as? [String: Any],
              let results = root["results"] as? [[String: Any]]
        else { return nil }
        return results.compactMap { row in
            guard (row["type"] as? String) == "TRANSACTION",
                  let tx = row["transaction"] as? [String: Any],
                  let id = tx["id"] as? String, !id.isEmpty
            else { return nil }
            return id
        }
    }

    // MARK: - GET /v1/chains/{id}/transactions/{id}

    /// One gateway transaction, in the transaction service's row shape.
    ///
    /// nil when the body carries no `detailedExecutionInfo` — a queued Safe
    /// transaction always has one, so a body without it is a module or
    /// incoming transfer that does not belong in this list, not an empty row.
    static func txRow(_ root: Any?) -> [String: Any]? {
        guard let root = root as? [String: Any],
              let exec = root["detailedExecutionInfo"] as? [String: Any],
              let safe = address(root["safeAddress"])
        else { return nil }
        let data = (root["txData"] as? [String: Any]) ?? [:]

        var row: [String: Any] = [
            "safe": safe,
            "to": address(data["to"]) ?? zeroAddress,
            "value": (data["value"] as? String) ?? String(int(data["value"]) ?? 0),
            "data": (data["hexData"] as? String) ?? "",
            "operation": int(data["operation"]) ?? 0,
            "isExecuted": root["executedAt"] != nil && !(root["executedAt"] is NSNull),
        ]
        if let decoded = data["dataDecoded"] { row["dataDecoded"] = decoded }
        if let hash = exec["safeTxHash"] as? String { row["safeTxHash"] = hash }
        if let nonce = int(exec["nonce"]) { row["nonce"] = nonce }
        if let required = int(exec["confirmationsRequired"]) {
            row["confirmationsRequired"] = required
        }
        // The signing path re-encodes the hash from these and refuses on a
        // mismatch (`SafeSigner.prepare` check 3), so a miss here cannot sign
        // the wrong thing — it can only refuse.
        for key in ["safeTxGas", "baseGas", "gasPrice"] {
            row[key] = (exec[key] as? String) ?? String(int(exec[key]) ?? 0)
        }
        if let token = address(exec["gasToken"]) { row["gasToken"] = token }
        if let receiver = address(exec["refundReceiver"]) { row["refundReceiver"] = receiver }
        if let at = iso8601(millis: exec["submittedAt"]) { row["submissionDate"] = at }
        if let at = iso8601(millis: root["executedAt"]) { row["executionDate"] = at }

        let confirmations = (exec["confirmations"] as? [[String: Any]]) ?? []
        row["confirmations"] = confirmations.compactMap { c -> [String: Any]? in
            guard let owner = address(c["signer"]) else { return nil }
            var out: [String: Any] = ["owner": owner]
            if let sig = c["signature"] as? String { out["signature"] = sig }
            if let at = iso8601(millis: c["submittedAt"]) { out["submissionDate"] = at }
            return out
        }
        return row
    }
}
