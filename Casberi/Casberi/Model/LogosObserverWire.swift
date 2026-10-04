import Foundation
import CryptoKit

/// Logos Observer v2, pure (2026-10-03). The Observer is a read-only sidecar
/// beside a person's Logos node (github.com/0xterricola/logos-observer): the
/// node's raw API stays on `127.0.0.1:8080`, and a phone reads the node through
/// the Observer over pinned TLS 1.3 with a per-device HMAC key.
///
/// Foundation + CryptoKit only BY DESIGN, so `scripts/logos-observer-selftest.sh`
/// compiles this file whole and runs the Observer's own interoperability
/// vectors through it: the HMAC signature, the SPKI pin and the pairing QR.
/// A wrong byte in any of them looks identical from the phone — every request
/// answered `401 bad_signature`, or a pairing that never finds its Observer.
///
/// The contract is frozen in `design/mockups/logos-observer-spec.html`.
enum LogosObserverWire {

    static let protocolTag = "LOGOS-OBSERVER-V2"
    static let defaultPort = 8081

    // MARK: - Scopes

    /// The read scopes v2 defines. `blend.status.read` is reserved until Logos
    /// names its node data, so Casberi never asks for it.
    static let readScopes = ["node.status.read", "network.status.read",
                             "mining.status.read", "rewards.status.read"]

    /// What a scope lets the device read, in the words the consent tray shows.
    static func scopeLabel(_ scope: String) -> String {
        switch scope {
        case "node.status.read": return String(localized: "Sync and block height")
        case "network.status.read": return String(localized: "Peer count")
        case "mining.status.read": return String(localized: "Whether it's mining")
        case "rewards.status.read": return String(localized: "Rewards waiting")
        case "blend.status.read": return String(localized: "Blend network status")
        default: return scope
        }
    }

    /// Only `*.read` scopes are ever accepted. A QR offering a control scope
    /// (`mining.control`, `rewards.claim`, `node.control`) is refused outright:
    /// Casberi never holds a key that can act on a node.
    static func isReadScope(_ scope: String) -> Bool {
        scope.hasSuffix(".read") && !scope.contains(" ")
    }

    // MARK: - The pairing QR

    struct Offer: Equatable {
        var expires: Date
        /// `host:port`, IPv6 in brackets.
        var host: String
        var port: Int
        var bonjour: String?
        /// `sha256/<base64url>`, the SPKI pin.
        var pin: String
        /// The 32-byte bootstrap secret, as the QR spelled it (base64url).
        var secret: String
        var name: String
        var scopes: [String]

        func isExpired(at now: Date) -> Bool { now >= expires }
        var baseURL: String {
            let h = host.contains(":") ? "[\(host)]" : host
            return "https://\(h):\(port)"
        }
    }

    /// Reads `logos-observer://pair?v=2&exp=…&h=…&b=…&pin=…&s=…&n=…&sc=…`.
    /// nil for anything that is not a well-formed v2 offer: a wrong version, a
    /// pin that is not 32 bytes, a secret that is not 32 bytes, no scopes, or
    /// any scope that is not a read.
    static func offer(_ text: String) -> Offer? {
        guard let comps = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              comps.scheme?.lowercased() == "logos-observer",
              comps.host?.lowercased() == "pair"
        else { return nil }
        var q: [String: String] = [:]
        for item in comps.queryItems ?? [] {
            guard q[item.name] == nil else { return nil }   // a repeated key is not a guess we make
            q[item.name] = item.value ?? ""
        }
        guard q["v"] == "2",
              let expText = q["exp"], let exp = TimeInterval(expText),
              let hostPort = q["h"], let (host, port) = splitHostPort(hostPort),
              let pin = q["pin"], pinDigest(pin) != nil,
              let secret = q["s"], base64urlDecode(secret)?.count == 32,
              let scopeText = q["sc"]
        else { return nil }
        let scopes = scopeText.split(separator: ",").map(String.init)
        guard !scopes.isEmpty, scopes.allSatisfy(isReadScope),
              Set(scopes).count == scopes.count
        else { return nil }
        let name = (q["n"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let bonjour = q["b"].flatMap { $0.isEmpty ? nil : $0 }
        return Offer(expires: Date(timeIntervalSince1970: exp), host: host, port: port,
                     bonjour: bonjour, pin: pin, secret: secret,
                     name: name.isEmpty ? String(localized: "Logos Observer") : name,
                     scopes: scopes)
    }

    /// `192.168.1.20:8081`, `observer.local:8081`, `[fe80::1]:8081`, or a bare
    /// host (the v2 default port).
    static func splitHostPort(_ text: String) -> (String, Int)? {
        var host = text, port = defaultPort
        if text.hasPrefix("[") {
            guard let close = text.firstIndex(of: "]") else { return nil }
            host = String(text[text.index(after: text.startIndex)..<close])
            let rest = text[text.index(after: close)...]
            if !rest.isEmpty {
                guard rest.hasPrefix(":"), let p = Int(rest.dropFirst()) else { return nil }
                port = p
            }
        } else if let colon = text.lastIndex(of: ":") {
            guard !text[..<colon].contains(":"), let p = Int(text[text.index(after: colon)...]) else { return nil }
            host = String(text[..<colon])
            port = p
        }
        guard !host.isEmpty, !host.contains("/"), !host.contains(" "),
              (1...65535).contains(port) else { return nil }
        return (host, port)
    }

    // MARK: - The SPKI pin

    /// The DER prefix of an ECDSA P-256 SubjectPublicKeyInfo: SEQUENCE {
    /// AlgorithmIdentifier { id-ecPublicKey, prime256v1 }, BIT STRING (0 unused
    /// bits) }. What follows is the 65-byte uncompressed point — exactly what
    /// `SecKeyCopyExternalRepresentation` returns for a P-256 key.
    static let p256SPKIPrefix: [UInt8] = [
        0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01,
        0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00,
    ]

    /// `sha256/<base64url>` of a DER SubjectPublicKeyInfo.
    static func pin(spki: Data) -> String {
        "sha256/" + base64urlEncode(Data(SHA256.hash(data: spki)))
    }

    /// The pin of a P-256 key given as its uncompressed point (`04‖x‖y`, 65
    /// bytes). nil for anything else — an RSA or Ed25519 key can never match a
    /// v2 Observer, so it is never pinned.
    static func pin(p256Point point: Data) -> String? {
        guard point.count == 65, point.first == 0x04 else { return nil }
        return pin(spki: Data(p256SPKIPrefix) + point)
    }

    /// The 32 digest bytes a pin names, or nil when it is not `sha256/` plus
    /// 43 base64url characters.
    static func pinDigest(_ pin: String) -> Data? {
        guard pin.hasPrefix("sha256/") else { return nil }
        let body = String(pin.dropFirst("sha256/".count))
        guard body.count == 43, let d = base64urlDecode(body), d.count == 32 else { return nil }
        return d
    }

    /// Constant-time: whether a server's key matches the pin the QR carried.
    static func matches(pin expected: String, p256Point point: Data) -> Bool {
        guard let want = pinDigest(expected), let got = pin(p256Point: point).flatMap(pinDigest),
              want.count == got.count else { return false }
        return zip(want, got).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    // MARK: - Signing a request

    /// The string the HMAC covers. `target` is the request-target EXACTLY as
    /// sent on the request line — path, then `?query` only if there is one, no
    /// normalisation — and `nonce` is its base64url spelling, as sent.
    static func canonical(method: String, target: String, timestamp: Int,
                          nonce: String, deviceID: String, body: Data) -> String {
        let bodyHash = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
        return [protocolTag, method.uppercased(), target, String(timestamp),
                nonce, deviceID, bodyHash].joined(separator: "\n")
    }

    static func signature(key: Data, canonical: String) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(canonical.utf8), using: SymmetricKey(data: key))
        return base64urlEncode(Data(mac))
    }

    /// The four `X-Observer-*` headers for one request. `nonce` is 16 fresh
    /// random bytes, `now` the phone's clock (the Observer allows ±120s).
    static func headers(key: Data, deviceID: String, method: String, target: String,
                        body: Data = Data(), now: Date, nonce: Data) -> [String: String] {
        let ts = Int(now.timeIntervalSince1970)
        let n = base64urlEncode(nonce)
        let c = canonical(method: method, target: target, timestamp: ts, nonce: n,
                          deviceID: deviceID, body: body)
        return ["X-Observer-Device": deviceID,
                "X-Observer-Timestamp": String(ts),
                "X-Observer-Nonce": n,
                "X-Observer-Signature": signature(key: key, canonical: c)]
    }

    // MARK: - Pairing

    static func pairBody(secret: String, deviceName: String, scopes: [String]) -> Data {
        (try? JSONSerialization.data(withJSONObject: [
            "secret": secret, "device_name": deviceName, "scopes": scopes,
        ], options: [.sortedKeys])) ?? Data()
    }

    struct Pairing: Equatable {
        var deviceID: String
        var key: Data
        var granted: [String]
    }

    /// `{device_id, hmac_key, granted_scopes}`. nil unless the key is 32 bytes
    /// and every granted scope is one we asked for and a read.
    static func pairing(_ json: Any?, requested: [String]) -> Pairing? {
        guard let obj = json as? [String: Any],
              let id = obj["device_id"] as? String, !id.isEmpty,
              let keyText = obj["hmac_key"] as? String, let key = base64urlDecode(keyText), key.count == 32,
              let granted = obj["granted_scopes"] as? [String], !granted.isEmpty,
              granted.allSatisfy({ requested.contains($0) && isReadScope($0) })
        else { return nil }
        return Pairing(deviceID: id, key: key, granted: granted)
    }

    // MARK: - Refusals

    enum Refusal: String, Equatable {
        case revoked, clockSkew = "clock_skew", badSignature = "bad_signature",
             replay, scope, invalidBootstrap = "invalid_bootstrap", other

        /// Only a revoked or unknown device drops the stored key. Every other
        /// refusal keeps it: a skewed clock or a lost race is not an unpairing.
        var dropsCredential: Bool { self == .revoked }
    }

    /// `{"error": "<code>"}` on a 401 or 403; nil for any other status.
    static func refusal(status: Int, json: Any?) -> Refusal? {
        guard status == 401 || status == 403 else { return nil }
        let code = (json as? [String: Any])?["error"] as? String ?? ""
        return Refusal(rawValue: code) ?? .other
    }

    // MARK: - The status snapshot

    /// One section of `/v2/status`: left out when not granted, `null` when its
    /// read failed. The two must never collapse, or "unknown" draws as "no".
    enum Read<T: Equatable>: Equatable {
        case notGranted, failed, value(T)
        var value: T? { if case .value(let v) = self { return v }; return nil }
    }

    struct Node: Equatable { var reachable: Bool; var phase: String?; var height: Int?; var tip: String? }
    struct Mining: Equatable { var isMining: Bool; var rewardsEnabled: Bool?; var autoClaim: Bool? }
    struct Rewards: Equatable {
        var tickets: Int?; var slotsUntilExpiry: Int?; var vouchers: Int?; var claimable: Decimal?
    }

    struct Status: Equatable {
        var observedAt: Date?
        var node: Read<Node>
        var peers: Read<Int>
        var mining: Read<Mining>
        var rewards: Read<Rewards>
    }

    static func status(_ json: Any?) -> Status? {
        guard let obj = json as? [String: Any], (obj["v"] as? NSNumber)?.intValue == 2 else { return nil }
        func read<T>(_ key: String, _ parse: ([String: Any]) -> T?) -> Read<T> {
            guard let raw = obj[key] else { return .notGranted }
            guard let dict = raw as? [String: Any], let v = parse(dict) else { return .failed }
            return .value(v)
        }
        let node: Read<Node> = read("node") { d in
            guard let r = d["reachable"] as? Bool else { return nil }
            return Node(reachable: r, phase: d["phase"] as? String,
                        height: (d["height"] as? NSNumber)?.intValue, tip: d["tip"] as? String)
        }
        let peers: Read<Int> = read("network") { ($0["peers"] as? NSNumber)?.intValue }
        let mining: Read<Mining> = read("mining") { d in
            guard let m = d["is_mining"] as? Bool else { return nil }
            return Mining(isMining: m, rewardsEnabled: d["rewards_enabled"] as? Bool,
                          autoClaim: d["auto_claim"] as? Bool)
        }
        let rewards: Read<Rewards> = read("rewards") { d in
            Rewards(tickets: (d["claimable_tickets"] as? NSNumber)?.intValue,
                    slotsUntilExpiry: (d["slots_until_expiry"] as? NSNumber)?.intValue,
                    vouchers: (d["vouchers"] as? NSNumber)?.intValue,
                    claimable: (d["total_claimable"] as? String).flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) })
        }
        let observed = (obj["observed_at"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
        return Status(observedAt: observed, node: node, peers: peers, mining: mining, rewards: rewards)
    }

    /// The same reading the direct node read produces, so the room, its rows
    /// and its notifications need nothing new. A node section that is missing
    /// or failed is an unreachable node: without it there is no height to show.
    static func snapshot(_ s: Status) -> LogosWire.NodeSnapshot {
        guard let node = s.node.value, node.reachable else { return .unreachable }
        var snap = LogosWire.NodeSnapshot(reachable: true, phase: node.phase,
                                          height: node.height, tip: node.tip)
        snap.peers = s.peers.value
        if let m = s.mining.value { snap.mining = m.isMining; snap.miningPays = m.rewardsEnabled }
        if let r = s.rewards.value {
            snap.tickets = r.tickets
            snap.vouchers = r.vouchers
            snap.claimable = r.claimable
        }
        return snap
    }

    // MARK: - base64url (RFC 4648, no padding)

    static func base64urlEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func base64urlDecode(_ text: String) -> Data? {
        guard !text.isEmpty, text.allSatisfy({ $0.isLetter && $0.isASCII || $0.isNumber && $0.isASCII || $0 == "-" || $0 == "_" })
        else { return nil }
        var s = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        return Data(base64Encoded: s)
    }
}
