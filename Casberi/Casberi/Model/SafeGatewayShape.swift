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
        /// The fallback handler and the singleton the Safe runs (prd §1249),
        /// lowercased; nil for none, the zero address, or a body that does
        /// not carry the field. The gateway sends both as `{value, …}`.
        var fallbackHandler: String? = nil
        var implementation: String? = nil
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
            guardAddr: (raw == nil || raw == zeroAddress) ? nil : raw,
            fallbackHandler: nonZero(root["fallbackHandler"]),
            implementation: nonZero(root["implementation"]) ?? nonZero(root["masterCopy"]))
    }

    /// An address field, lowercased, with the zero address read as none —
    /// trap 2's rule, for every field that can be absent.
    private static func nonZero(_ any: Any?) -> String? {
        guard let raw = address(any)?.lowercased(), raw != zeroAddress else { return nil }
        return raw
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

    // MARK: - GET /v1/chains/{id}/safes/{addr}/transactions/history

    /// The EXECUTED multisig transactions on the history's first page,
    /// newest first, at most `cap`, each in the transaction service's row
    /// shape that `SafeBridge.describe` and `landOutcome` already read (prd
    /// §1249): `safeTxHash` (lowercased), `safe`, `nonce`, `isExecuted`,
    /// `executionDate`, and whatever of `to`/`value`/`dataDecoded`/
    /// `actionCount` the list's `txInfo` carries.
    ///
    /// UNMEASURED: authored from safe-client-gateway's own transaction-list
    /// shapes (`TransactionItem`, `DateLabel`, `MultisigExecutionInfo`,
    /// `TransferTransactionInfo`, `CustomTransactionInfo`,
    /// `SettingsChangeTransaction`), not from a captured response. So:
    ///
    ///   * only `TRANSACTION` rows whose id is `multisig_<safe>_<hash>` count
    ///     — a module transaction, an incoming transfer, the creation row and
    ///     the `DATE_LABEL` furniture are not a Safe transaction this app can
    ///     close a loop on;
    ///   * only `txStatus == "SUCCESS"` — a FAILED or CANCELLED execution did
    ///     not "go through", and the closing row's sentence says it did;
    ///   * **a row with no readable `timestamp` is DROPPED** (§790's rule):
    ///     its only other date would be this pass's clock, and an executed
    ///     transaction dated "now" is a fabricated recency;
    ///   * nil only when the body is not a list at all — an empty history is
    ///     `[]`, and a refused read is nil.
    static func history(_ root: Any?, cap: Int = 20) -> [[String: Any]]? {
        guard let root = root as? [String: Any],
              let results = root["results"] as? [[String: Any]]
        else { return nil }
        var out: [[String: Any]] = []
        for item in results {
            guard out.count < cap else { break }
            guard (item["type"] as? String) == "TRANSACTION",
                  let tx = item["transaction"] as? [String: Any],
                  let id = tx["id"] as? String
            else { continue }
            let parts = id.split(separator: "_").map(String.init)
            guard parts.count == 3, parts[0] == "multisig",
                  isHash(parts[2]),
                  (tx["txStatus"] as? String) == "SUCCESS",
                  let executed = iso8601(millis: tx["timestamp"])
            else { continue }
            let exec = (tx["executionInfo"] as? [String: Any]) ?? [:]
            if let type = exec["type"] as? String, type != "MULTISIG" { continue }
            let safe = parts[1]
            var row: [String: Any] = [
                "safe": safe,
                "safeTxHash": parts[2].lowercased(),
                "isExecuted": true,
                "executionDate": executed,
                "value": "0",
                "data": "",
            ]
            if let nonce = int(exec["nonce"]) { row["nonce"] = nonce }
            let info = (tx["txInfo"] as? [String: Any]) ?? [:]
            switch (info["type"] as? String) ?? "" {
            case "Transfer":
                // A Safe's own multisig transfer is OUTGOING; the amount rides
                // `transferInfo` and the token's address names its contract.
                guard (info["direction"] as? String) == "OUTGOING",
                      let recipient = address(info["recipient"]),
                      let transfer = info["transferInfo"] as? [String: Any]
                else { continue }  // a row this cannot read is dropped, never landed bare
                let amount = (transfer["value"] as? String) ?? int(transfer["value"]).map({ String($0) })
                switch (transfer["type"] as? String) ?? "" {
                case "NATIVE_COIN":
                    row["to"] = recipient
                    if let amount { row["value"] = amount }
                case "ERC20":
                    guard let token = address(transfer["tokenAddress"]), let amount else { continue }
                    row["to"] = token
                    row["dataDecoded"] = [
                        "method": "transfer",
                        "parameters": [["name": "to", "value": recipient] as [String: Any],
                                       ["name": "value", "value": amount] as [String: Any]],
                    ] as [String: Any]
                default:
                    row["to"] = recipient
                }
            case "Custom":
                if (info["isCancellation"] as? Bool) == true {
                    // Safe's reject shape: zero, no data, to the Safe itself.
                    row["to"] = safe
                    break
                }
                if let to = address(info["to"]) { row["to"] = to }
                if let value = (info["value"] as? String) ?? int(info["value"]).map({ String($0) }) {
                    row["value"] = value
                }
                if let count = int(info["actionCount"]) { row["actionCount"] = count }
                if let method = info["methodName"] as? String, !method.isEmpty,
                   int(info["actionCount"]) == nil {
                    row["dataDecoded"] = ["method": method, "parameters": [[String: Any]]()] as [String: Any]
                }
            case "SettingsChange":
                row["to"] = safe
                if let decoded = info["dataDecoded"] as? [String: Any] { row["dataDecoded"] = decoded }
            default:
                break
            }
            out.append(row)
        }
        return out
    }

    /// `0x` and 64 hex digits — a `safeTxHash`, and nothing shorter.
    static func isHash(_ text: String) -> Bool {
        let body = text.lowercased().hasPrefix("0x") ? text.dropFirst(2) : Substring(text)
        return body.count == 64 && body.allSatisfy(\.isHexDigit)
    }

    // MARK: - POST /v1/chains/{id}/transactions/{safeTxHash}/confirmations

    /// The body of the gateway's `addConfirmation` (prd §1249) — the
    /// confirmation write's first door, `SafeSigner.post`. One field,
    /// `signedSafeTxHash`, the 65-byte signature hex; held here so
    /// `safe-gateway-selftest.sh` pins the shape the signer sends.
    /// UNMEASURED against the live gateway.
    static func confirmationBody(signature: String) -> [String: Any] {
        ["signedSafeTxHash": signature]
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
