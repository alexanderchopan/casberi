import Foundation
import CryptoKit
import CommonCrypto
import P256K

/// Nostr Wallet Connect (NIP-47) — a Lightning wallet read through the
/// connection string it hands out (prd §1098).
///
/// §226 ruled Lightning unreadable, and for a Lightning ADDRESS it is: an
/// LNURL-pay endpoint publishes nothing about the payments it takes. NWC is
/// a different door that ruling never weighed. Alby Hub, Coinos, Primal and
/// most custodial and self-hosted Lightning wallets hand out a connection —
/// `nostr+walletconnect://<wallet key>?relay=<wss>&secret=<hex>` — that
/// answers requests sent through a Nostr relay, scoped to what the person
/// allowed when they made it.
///
/// **Read-only is checked, not promised** (the Splits rule, prd §820): before
/// a connection is kept, it is asked what it may do (`get_info`, else the
/// wallet's published info event), and a connection that can pay
/// (`pay_invoice`, `pay_keysend`, either `multi_` form) is refused. Only
/// `get_balance` and `list_transactions` are ever sent.
///
/// Encryption is NIP-04 (AES-256-CBC over the ECDH x-coordinate), the
/// encryption every NWC wallet answers; a wallet that answers only NIP-44
/// says so as an error, and the page shows that sentence.
enum NostrWalletConnect {

    struct Connection: Equatable, Codable {
        /// The wallet service's x-only key, hex.
        let walletPubkey: String
        let relays: [String]
        /// The client secret, hex — the credential. Lives in the Keychain only.
        let secret: String
        /// The wallet's Lightning address, when the string carries one.
        let lud16: String?

        var relayHosts: [String] { relays.compactMap { URL(string: $0)?.host } }
    }

    /// The methods that can move money. A connection allowed any of them is
    /// refused on save.
    static let spendingMethods: Set<String> = ["pay_invoice", "multi_pay_invoice",
                                               "pay_keysend", "multi_pay_keysend"]

    // MARK: - The connection string

    static func parse(_ raw: String) -> Connection? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let schemes = ["nostr+walletconnect://", "nostrwalletconnect://", "nostr+walletconnect:"]
        guard let scheme = schemes.first(where: { s.lowercased().hasPrefix($0) }) else { return nil }
        let rest = String(s.dropFirst(scheme.count))
        let parts = rest.split(separator: "?", maxSplits: 1).map(String.init)
        guard parts.count == 2, isHex(parts[0], bytes: 32),
              let items = URLComponents(string: "x://x?" + parts[1])?.queryItems else { return nil }
        let relays = items.filter { $0.name == "relay" }.compactMap(\.value)
            .filter { ["wss", "ws"].contains(URL(string: $0)?.scheme ?? "") }
        guard let secret = items.first(where: { $0.name == "secret" })?.value,
              isHex(secret, bytes: 32), !relays.isEmpty,
              (try? P256K.Schnorr.PrivateKey(dataRepresentation: hexBytes(secret))) != nil
        else { return nil }
        return Connection(walletPubkey: parts[0].lowercased(), relays: relays,
                          secret: secret.lowercased(),
                          lud16: items.first(where: { $0.name == "lud16" })?.value)
    }

    /// True for anything that starts like a connection string — the field
    /// uses it to say "that string is incomplete" instead of nothing.
    static func looksLikeConnection(_ raw: String) -> Bool {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("nostr+walletconnect")
    }

    // MARK: - What one request answers

    enum Failure: Error, Equatable {
        /// No relay answered at all.
        case unreachable
        /// The wallet answered with an error — its own code and words.
        case wallet(code: String, message: String)
        /// An answer that could not be decrypted or read.
        case unreadable
    }

    struct Transaction: Equatable {
        let incoming: Bool
        let amountMsats: Int
        let feesMsats: Int
        let description: String?
        let paymentHash: String
        let createdAt: Date
        let settledAt: Date?
        /// "settled", "pending", "failed", "expired" — or nil from a wallet
        /// older than the field, whose list holds settled payments only.
        let state: String?
    }

    /// The methods this connection may call, by `get_info`, else by the
    /// wallet's published info event. nil when neither could be read.
    static func methods(_ c: Connection) async -> Result<Set<String>, Failure> {
        switch await request(c, method: "get_info", params: [:]) {
        case .success(let result):
            if let methods = result["methods"] as? [String] { return .success(Set(methods)) }
        case .failure(.unreachable):
            return .failure(.unreachable)
        case .failure:
            break   // RESTRICTED or unsupported: ask the info event instead
        }
        let answer = await NostrRelay.requestAny(c.relays, filter: [
            "kinds": [13194], "authors": [c.walletPubkey], "limit": 1])
        guard answer.reached else { return .failure(.unreachable) }
        guard let content = answer.events.first?["content"] as? String else {
            return .failure(.unreadable)
        }
        return .success(Set(content.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)))
    }

    static func balanceMsats(_ c: Connection) async -> Result<Int, Failure> {
        switch await request(c, method: "get_balance", params: [:]) {
        case .success(let result):
            guard let msats = result["balance"] as? Int else { return .failure(.unreadable) }
            return .success(msats)
        case .failure(let f):
            return .failure(f)
        }
    }

    /// The newest `limit` payments, newest first.
    static func transactions(_ c: Connection, limit: Int = 50) async -> Result<[Transaction], Failure> {
        switch await request(c, method: "list_transactions", params: ["limit": limit]) {
        case .success(let result):
            guard let list = result["transactions"] as? [[String: Any]] else { return .failure(.unreadable) }
            return .success(list.compactMap(transaction))
        case .failure(let f):
            return .failure(f)
        }
    }

    static func transaction(_ t: [String: Any]) -> Transaction? {
        guard let type = t["type"] as? String,
              let amount = t["amount"] as? Int,
              let hash = t["payment_hash"] as? String, !hash.isEmpty,
              let created = t["created_at"] as? Double ?? (t["created_at"] as? Int).map(Double.init)
        else { return nil }
        let settled = t["settled_at"] as? Double ?? (t["settled_at"] as? Int).map(Double.init)
        let description = (t["description"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return Transaction(incoming: type == "incoming", amountMsats: amount,
                           feesMsats: t["fees_paid"] as? Int ?? 0,
                           description: description, paymentHash: hash,
                           createdAt: Date(timeIntervalSince1970: created),
                           settledAt: settled.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil },
                           state: t["state"] as? String)
    }

    // MARK: - One request, one answer

    /// Sends one NIP-47 request and waits for its answer, on the first relay
    /// that completes the round trip.
    static func request(_ c: Connection, method: String,
                        params: [String: Any], timeout: TimeInterval = 12) async -> Result<[String: Any], Failure> {
        guard let secret = try? P256K.Schnorr.PrivateKey(dataRepresentation: hexBytes(c.secret)),
              let shared = sharedSecret(secret: hexBytes(c.secret), peer: c.walletPubkey),
              let body = try? JSONSerialization.data(withJSONObject: ["method": method, "params": params]),
              let plain = String(data: body, encoding: .utf8),
              let content = nip04Encrypt(plain, key: shared)
        else { return .failure(.unreadable) }
        // NIP-47 addresses the request to the wallet by its key, in a `p` tag.
        let recipient = [["p", c.walletPubkey]]
        guard let event = signedEvent(kind: 23194, content: content, tags: recipient, key: secret)
        else { return .failure(.unreadable) }
        let clientPubkey = hex(secret.xonly.bytes)
        guard let eventID = event["id"] as? String else { return .failure(.unreadable) }

        for relay in c.relays {
            guard let reply = await NostrRelay.publishAndAwait(
                relay, event: event,
                filter: ["kinds": [23195], "authors": [c.walletPubkey],
                         "#p": [clientPubkey], "#e": [eventID]],
                timeout: timeout) else { continue }
            guard let text = reply["content"] as? String,
                  let decrypted = nip04Decrypt(text, key: shared),
                  let data = decrypted.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return .failure(.unreadable) }
            if let error = root["error"] as? [String: Any] {
                return .failure(.wallet(code: error["code"] as? String ?? "OTHER",
                                        message: error["message"] as? String ?? ""))
            }
            return .success(root["result"] as? [String: Any] ?? [:])
        }
        return .failure(.unreachable)
    }

    // MARK: - Events (NIP-01)

    /// A signed event: id = SHA-256 of `[0, pubkey, created_at, kind, tags,
    /// content]` serialised with no whitespace and unescaped slashes (the
    /// base64 content carries `/`, and an escaped one changes the id).
    static func signedEvent(kind: Int, content: String, tags: [[String]],
                            key: P256K.Schnorr.PrivateKey, at: Date = .now) -> [String: Any]? {
        let pubkey = hex(key.xonly.bytes)
        let created = Int(at.timeIntervalSince1970)
        guard let id = eventID(pubkey: pubkey, created: created, kind: kind, tags: tags, content: content)
        else { return nil }
        var aux = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, aux.count, &aux) == errSecSuccess,
              let signature = try? key.signature(for: HashDigest(id), auxiliaryRand: aux)
        else { return nil }
        return ["id": hex(id), "pubkey": pubkey, "created_at": created, "kind": kind,
                "tags": tags, "content": content, "sig": hex([UInt8](signature.dataRepresentation))]
    }

    static func eventID(pubkey: String, created: Int, kind: Int,
                        tags: [[String]], content: String) -> [UInt8]? {
        let array: [Any] = [0, pubkey, created, kind, tags, content]
        guard let data = try? JSONSerialization.data(withJSONObject: array,
                                                     options: [.withoutEscapingSlashes])
        else { return nil }
        return Array(SHA256.hash(data: data))
    }

    // MARK: - NIP-04

    /// The ECDH x-coordinate — unhashed, as NIP-04 specifies (libsecp256k1's
    /// own ECDH hashes it, which is why the point is multiplied here instead).
    static func sharedSecret(secret: [UInt8], peer xonlyHex: String) -> [UInt8]? {
        guard isHex(xonlyHex, bytes: 32),
              let point = try? P256K.Signing.PublicKey(dataRepresentation: [0x02] + hexBytes(xonlyHex),
                                                       format: .compressed),
              let product = try? point.multiply(secret, format: .compressed)
        else { return nil }
        return Array(product.dataRepresentation.dropFirst())
    }

    static func nip04Encrypt(_ plain: String, key: [UInt8], iv fixedIV: [UInt8]? = nil) -> String? {
        var iv = fixedIV ?? [UInt8](repeating: 0, count: 16)
        if fixedIV == nil, SecRandomCopyBytes(kSecRandomDefault, 16, &iv) != errSecSuccess { return nil }
        guard let cipher = aes(Array(plain.utf8), key: key, iv: iv, operation: CCOperation(kCCEncrypt))
        else { return nil }
        return Data(cipher).base64EncodedString() + "?iv=" + Data(iv).base64EncodedString()
    }

    static func nip04Decrypt(_ content: String, key: [UInt8]) -> String? {
        let parts = content.components(separatedBy: "?iv=")
        guard parts.count == 2,
              let cipher = Data(base64Encoded: parts[0]),
              let iv = Data(base64Encoded: parts[1]), iv.count == 16,
              let plain = aes(Array(cipher), key: key, iv: Array(iv), operation: CCOperation(kCCDecrypt))
        else { return nil }
        return String(bytes: plain, encoding: .utf8)
    }

    private static func aes(_ input: [UInt8], key: [UInt8], iv: [UInt8], operation: CCOperation) -> [UInt8]? {
        guard key.count == 32 else { return nil }
        var out = [UInt8](repeating: 0, count: input.count + kCCBlockSizeAES128)
        var moved = 0
        let status = CCCrypt(operation, CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                             key, key.count, iv, input, input.count, &out, out.count, &moved)
        guard status == kCCSuccess else { return nil }
        return Array(out.prefix(moved))
    }

    // MARK: - Hex

    static func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

    static func hexBytes(_ s: String) -> [UInt8] {
        var out: [UInt8] = []
        var chars = Array(s)
        if chars.count % 2 == 1 { chars.insert("0", at: 0) }
        for i in stride(from: 0, to: chars.count, by: 2) {
            guard let byte = UInt8(String(chars[i...i + 1]), radix: 16) else { return [] }
            out.append(byte)
        }
        return out
    }

    private static func isHex(_ s: String, bytes: Int) -> Bool {
        s.count == bytes * 2 && s.allSatisfy(\.isHexDigit)
    }
}
