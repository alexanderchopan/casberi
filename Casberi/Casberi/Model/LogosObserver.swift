import Foundation
import Security
import UIKit

/// Your node, read through its Logos Observer (2026-10-03). The Observer runs
/// beside the node and answers a paired device's reads over pinned TLS 1.3,
/// each request signed with a per-device HMAC key, so the node's own API
/// (writes included) never has to face the network. The wire is
/// `LogosObserverWire`; this file is the connection, the key and the pairing.
///
/// **One pairing at a time**, as there is one node at a time
/// (`LogosStore.node`). When paired, the node's base is the Observer's own
/// address and port, over TLS, and `LogosIngest.readNode` reads through here.
///
/// **What drops the pairing.** Only the Observer saying `revoked`, or the
/// person forgetting the node. A skewed clock, a bad signature or a lost
/// replay race keeps the key and takes no reading, so it never lands a "your
/// node stopped" row for a node that is fine.
@MainActor @Observable
final class LogosObserver {
    static let shared = LogosObserver()

    struct Paired: Codable, Equatable {
        var base: String
        var pin: String
        var name: String
        var deviceID: String
        var granted: [String]
        var pairedAt: Date
    }

    private static let pairedKey = "logos.observer.v1"
    private static let service = "casberi-logos-observer"

    private(set) var paired: Paired? {
        didSet {
            if let paired, let data = try? JSONEncoder().encode(paired) {
                DefaultsWrite.set(data, forKey: Self.pairedKey)
            } else {
                DefaultsWrite.remove(Self.pairedKey)
            }
        }
    }

    /// An offer that arrived by link (`logos-observer://pair?…`, the system
    /// camera's hand-off), waiting for the Logos page to show its consent tray.
    var pendingOffer: LogosObserverWire.Offer?

    /// The last thing the Observer refused, in words, for the page to show.
    private(set) var notice: String?

    private init() {
        paired = UserDefaults.standard.data(forKey: Self.pairedKey)
            .flatMap { try? JSONDecoder().decode(Paired.self, from: $0) }
    }

    /// Whether this node base is the paired Observer.
    func serves(_ base: String?) -> Bool { base != nil && paired?.base == base }

    // MARK: - Pairing

    enum PairOutcome: Equatable {
        case paired
        case expired
        /// The Observer's key did not match the QR's pin: not the Observer
        /// the QR came from. The secret was never sent.
        case wrongObserver
        case unreachable
        case refused(String)
    }

    func pair(_ offer: LogosObserverWire.Offer, scopes: [String]) async -> PairOutcome {
        guard !offer.isExpired(at: Date()) else { return .expired }
        guard let url = URL(string: offer.baseURL + "/v2/pair") else { return .unreachable }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = LogosObserverWire.pairBody(secret: offer.secret,
                                                      deviceName: Self.deviceName,
                                                      scopes: scopes)
        let session = PinnedSession(pin: offer.pin)
        let result = await session.send(request)
        switch result {
        case .pinMismatch: return .wrongObserver
        case .failed: return .unreachable
        case .answered(let status, let json):
            guard status == 200 else {
                let code = (json as? [String: Any])?["error"] as? String ?? ""
                return .refused(Self.pairRefusal(code))
            }
            guard let pairing = LogosObserverWire.pairing(json, requested: scopes),
                  Self.storeKey(pairing.key)
            else { return .refused(String(localized: "The Observer's answer didn't make sense. Try again.")) }
            paired = Paired(base: offer.baseURL, pin: offer.pin, name: offer.name,
                            deviceID: pairing.deviceID, granted: pairing.granted, pairedAt: Date())
            notice = nil
            LogosStore.shared.useNode(offer.baseURL)
            return .paired
        }
    }

    private static func pairRefusal(_ code: String) -> String {
        switch code {
        case "pairing_expired":
            return String(localized: "That pairing code expired. Make a new one on the Observer.")
        case "invalid_bootstrap", "pairing_not_pending":
            return String(localized: "That pairing code was already used. Make a new one on the Observer.")
        default:
            return String(localized: "The Observer refused to pair (\(code)).")
        }
    }

    /// What the Observer's device list shows for this phone. Without the
    /// device-name entitlement iOS answers the model ("iPhone"), which is
    /// honest and enough.
    private static var deviceName: String {
        String(UIDevice.current.name.prefix(80))
    }

    // MARK: - Recognising one

    /// Whether the address someone typed is a Logos Observer rather than a
    /// node: its unauthenticated `/health` names the service. An Observer
    /// answers only a paired device, so watching its address as a node would
    /// read "Not answering" forever (a Logos tester did exactly that,
    /// 2026-10-04). The probe sends nothing but the path, so it trusts any
    /// certificate; pairing is still pinned.
    static func answersAsObserver(_ base: String) async -> Bool {
        guard let comps = URLComponents(string: base), let host = comps.host else { return false }
        var https = URLComponents()
        https.scheme = "https"
        https.host = host
        https.port = comps.port ?? LogosObserverWire.defaultPort
        https.path = "/health"
        guard let url = https.url else { return false }
        let result = await PinnedSession(pin: nil).send(URLRequest(url: url))
        guard case .answered(200, let json) = result else { return false }
        return (json as? [String: Any])?["service"] as? String == "logos-observer"
    }

    // MARK: - Reading

    /// One reading of the node through the Observer. nil when the Observer
    /// answered but refused (skew, signature, replay): no reading, no rows.
    /// An Observer that does not answer at all reads as an unreachable node,
    /// as the node's own silence did before.
    func reading() async -> LogosWire.NodeSnapshot? {
        guard let paired, let key = Self.readKey() else { return nil }
        for attempt in 0..<2 {
            switch await signed("GET", "/v2/status", paired: paired, key: key) {
            case .pinMismatch:
                notice = String(localized: "Your Observer's identity changed. Pair it again.")
                return nil
            case .failed:
                return .unreachable
            case .answered(200, let json):
                guard let status = LogosObserverWire.status(json) else { return nil }
                notice = nil
                return LogosObserverWire.snapshot(status)
            case .answered(let code, let json):
                let refusal = LogosObserverWire.refusal(status: code, json: json) ?? .other
                if refusal == .replay, attempt == 0 { continue }   // a fresh nonce, once
                if refusal.dropsCredential {
                    forgetLocally()
                    LogosStore.shared.useNode(nil)
                    notice = String(localized: "Your Observer removed this device. Pair it again to keep reading your node.")
                } else if refusal == .clockSkew {
                    notice = String(localized: "This phone's clock and your Observer's disagree, so it refused the read.")
                } else {
                    notice = String(localized: "Your Observer refused the read (\(refusal.rawValue)).")
                }
                return nil
            }
        }
        return nil
    }

    // MARK: - Forgetting

    /// Revoke this device on the Observer, then forget it here whatever the
    /// Observer said: an unreachable Observer cannot keep the phone paired.
    func forget() async {
        if let paired, let key = Self.readKey() {
            _ = await signed("DELETE", "/v2/device", paired: paired, key: key)
        }
        forgetLocally()
    }

    func forgetLocally() {
        paired = nil
        Self.deleteKey()
    }

    // MARK: - The signed request

    private func signed(_ method: String, _ target: String, paired: Paired, key: Data) async -> PinnedSession.Result {
        guard let url = URL(string: paired.base + target) else { return .failed }
        var request = URLRequest(url: url)
        request.httpMethod = method
        var nonce = Data(count: 16)
        let ok = nonce.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) == errSecSuccess }
        guard ok else { return .failed }
        for (name, value) in LogosObserverWire.headers(key: key, deviceID: paired.deviceID, method: method,
                                                        target: target, now: Date(), nonce: nonce) {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return await PinnedSession(pin: paired.pin).send(request)
    }

    // MARK: - The key (device-only Keychain)

    private static func storeKey(_ key: Data) -> Bool {
        deleteKey()
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "hmac",
            kSecValueData as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
        ]
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    private static func readKey() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "hmac",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, data.count == 32 else { return nil }
        return data
    }

    private static func deleteKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// One TLS 1.3 connection that trusts exactly one key: the Observer's, named
/// by the SPKI pin its QR carried. No CA is consulted, and a certificate
/// whose key differs is refused before a byte of the request is sent — so the
/// bootstrap secret only ever reaches the Observer the QR came from. A nil pin
/// is the `/health` probe alone, which carries no secret and no credential.
final class PinnedSession: NSObject, URLSessionDelegate, @unchecked Sendable {
    enum Result { case answered(Int, Any?), pinMismatch, failed }

    private let pin: String?
    private var mismatched = false

    init(pin: String?) { self.pin = pin }

    func send(_ request: URLRequest) async -> Result {
        NetworkLedger.shared.record(request, as: "Logos")
        let config = URLSessionConfiguration.ephemeral
        config.tlsMinimumSupportedProtocolVersion = .TLSv13
        config.timeoutIntervalForRequest = 10
        config.urlCache = nil
        config.httpShouldSetCookies = false
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failed }
            let json = data.isEmpty ? nil : try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            return .answered(http.statusCode, json)
        } catch {
            return mismatched ? .pinMismatch : .failed
        }
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge)
        async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust
        else { return (.performDefaultHandling, nil) }
        guard let pin else { return (.useCredential, URLCredential(trust: trust)) }
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first,
              let key = SecCertificateCopyKey(leaf),
              let point = SecKeyCopyExternalRepresentation(key, nil) as Data?,
              LogosObserverWire.matches(pin: pin, p256Point: point)
        else {
            mismatched = true
            return (.cancelAuthenticationChallenge, nil)
        }
        return (.useCredential, URLCredential(trust: trust))
    }
}
