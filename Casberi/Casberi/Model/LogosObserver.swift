import Foundation
import Security
import UIKit

/// Your node, read through its Logos Observer (2026-10-03). The Observer runs
/// beside the node and answers a paired device's reads over pinned TLS 1.3,
/// each request signed with a per-device HMAC key, so the node's own API
/// (writes included) never has to face the network. The wire is
/// `LogosObserverWire`; this file is the connections, the keys and the pairings.
///
/// **Several Observers, routed by scope (prd §1155a).** A person can run one
/// beside the node (a NUC) and another beside Basecamp (their Mac), so Casberi
/// keeps every pairing and each tile reads through the newest Observer granted
/// its scope: Node through `node.status.read`, Chat through `chat.read`
/// (`LogosObserverWire.pick`). Pairing an Observer at an address already paired
/// replaces that pairing. When the node pairing exists, the node's base is that
/// Observer's address, and `LogosIngest.readNode` reads through here.
///
/// **What drops a pairing.** Only that Observer saying `revoked`, or the
/// person forgetting it. A skewed clock, a bad signature or a lost replay race
/// keeps the key and takes no reading, so it never lands a "your node
/// stopped" row for a node that is fine.
@MainActor @Observable
final class LogosObserver {
    static let shared = LogosObserver()

    struct Paired: Codable, Equatable, Identifiable {
        var base: String
        var pin: String
        var name: String
        var deviceID: String
        var granted: [String]
        var pairedAt: Date
        var id: String { deviceID }
        var grantsNode: Bool { granted.contains(LogosObserverWire.nodeScope) }
        var grantsChat: Bool { granted.contains(LogosObserverWire.chatScope) }
    }

    /// The one pairing §1095 kept, read once and moved into the list.
    private static let legacyKey = "logos.observer.v1"
    private static let pairingsKey = "logos.observers.v2"
    private static let service = "casberi-logos-observer"

    private(set) var pairings: [Paired] = [] {
        didSet {
            if let data = try? JSONEncoder().encode(pairings) {
                DefaultsWrite.set(data, forKey: Self.pairingsKey)
            }
        }
    }

    /// The last thing an Observer refused, in words, for the page to show.
    private(set) var notice: String?

    private init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.pairingsKey),
           let list = try? JSONDecoder().decode([Paired].self, from: data) {
            pairings = list
        } else if let data = defaults.data(forKey: Self.legacyKey),
                  let one = try? JSONDecoder().decode(Paired.self, from: data) {
            // §1095 kept one key under the account "hmac": move it under the
            // device id, so every pairing has its own.
            if let key = Self.readKey(account: "hmac"), Self.storeKey(key, account: one.deviceID) {
                Self.deleteKey(account: "hmac")
                pairings = [one]
            }
            DefaultsWrite.remove(Self.legacyKey)
        }
    }

    /// The Observer Node reads through, and the one Chat reads through.
    var nodePairing: Paired? { LogosObserverWire.pick(pairings, granted: \.granted, scope: LogosObserverWire.nodeScope) }
    var chatPairing: Paired? { LogosObserverWire.pick(pairings, granted: \.granted, scope: LogosObserverWire.chatScope) }

    /// Whether this node base is read through a paired Observer.
    func serves(_ base: String?) -> Bool { base != nil && nodePairing?.base == base }

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
                  Self.storeKey(pairing.key, account: pairing.deviceID)
            else { return .refused(String(localized: "The Observer's answer didn't make sense. Try again.")) }
            // The same Observer paired again replaces its old pairing.
            for old in pairings where old.base == offer.baseURL && old.deviceID != pairing.deviceID {
                Self.deleteKey(account: old.deviceID)
            }
            pairings.removeAll { $0.base == offer.baseURL }
            let fresh = Paired(base: offer.baseURL, pin: offer.pin, name: offer.name,
                               deviceID: pairing.deviceID, granted: pairing.granted, pairedAt: Date())
            pairings.append(fresh)
            notice = nil
            if fresh.grantsNode { LogosStore.shared.useNode(offer.baseURL) }
            if fresh.grantsChat { chat = .loading }
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

    /// One reading of the node through its Observer. nil when the Observer
    /// answered but refused (skew, signature, replay): no reading, no rows.
    /// An Observer that does not answer at all reads as an unreachable node,
    /// as the node's own silence did before.
    func reading() async -> LogosWire.NodeSnapshot? {
        guard let paired = nodePairing, let key = Self.readKey(account: paired.deviceID) else { return nil }
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
                    drop(paired)
                    if LogosStore.shared.node == paired.base { LogosStore.shared.useNode(nil) }
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

    // MARK: - Chat (chat.read)

    /// What the Chat tile can show. Held in memory only and dropped with the
    /// pairing: decrypted messages never reach the library or iCloud.
    enum ChatState: Equatable {
        case notPaired
        /// Paired, but no Observer granted `chat.read`: pairing again is the
        /// only way to grant it.
        case notGranted
        /// Basecamp's Chat app has not started `chat_module` on that machine.
        case notStarted
        case unreachable
        case loading
        case ready([LogosObserverWire.Conversation])
    }

    private(set) var chat: ChatState = .notPaired

    /// Reads the conversation list through the Observer granted `chat.read`.
    func readChat() async {
        // The demo shows what a paired Chat looks like (prd §1155): sample
        // conversations, nothing read and nothing sent.
        if DemoMode.isActive {
            chat = .ready(DemoChat.conversations().map { $0.enriched(with: DemoChat.messages(in: $0.id)) })
            return
        }
        guard let paired = chatPairing else { chat = pairings.isEmpty ? .notPaired : .notGranted; return }
        guard let key = Self.readKey(account: paired.deviceID) else { chat = .notPaired; return }
        if case .ready = chat {} else { chat = .loading }
        switch await signed("GET", "/v2/chat/conversations", paired: paired, key: key) {
        case .answered(200, let json):
            switch LogosObserverWire.chatAvailability(json) {
            case .available?:
                guard let convos = LogosObserverWire.conversations(json) else { chat = .notStarted; return }
                chat = .ready(enrichedKeepingKnown(convos))
                await enrich(convos, paired: paired, key: key)
            // The Observer answered, so it is reachable: a `null` body is its
            // bridge to Basecamp failing (Basecamp closed, the bridge not
            // started), which the person fixes the same way as an unstarted
            // Chat — on their computer, never by checking the network.
            default: chat = .notStarted
            }
        case .answered(let code, let json):
            if LogosObserverWire.refusal(status: code, json: json)?.dropsCredential == true {
                drop(paired)
                if LogosStore.shared.node == paired.base { LogosStore.shared.useNode(nil) }
                chat = chatPairing == nil ? (pairings.isEmpty ? .notPaired : .notGranted) : .loading
                return
            }
            chat = code == 403 ? .notGranted : .unreachable
        case .failed, .pinMismatch:
            chat = .unreachable
        }
    }

    /// **Who wrote, read once per conversation (prd §1213).** The list names
    /// no person, so the newest conversations' messages are read for their
    /// sender and their newest line — at most `enrichCap`, newest first, and
    /// kept in memory with everything else here.
    private static let enrichCap = 12
    private var enrichedByID: [String: LogosObserverWire.Conversation] = [:]

    /// The list as read, with what an earlier read learned about each
    /// conversation still on it while this read fetches again.
    private func enrichedKeepingKnown(_ convos: [LogosObserverWire.Conversation]) -> [LogosObserverWire.Conversation] {
        convos.map { convo in
            guard let known = enrichedByID[convo.id] else { return convo }
            var out = convo
            out.peer = convo.peer ?? known.peer
            out.senders = known.senders
            // A newer list line beats an older message.
            if let last = known.last, (convo.lastActivity ?? .distantPast) <= last.date.addingTimeInterval(1) {
                out.last = last
            }
            return out
        }
    }

    private func enrich(_ convos: [LogosObserverWire.Conversation], paired: Paired, key: Data) async {
        for convo in convos.prefix(Self.enrichCap) {
            guard case .answered(200, let json) = await signed(
                "GET", LogosObserverWire.messagesTarget(convo: convo.id), paired: paired, key: key),
                  let messages = LogosObserverWire.messages(json) else { continue }
            enrichedByID[convo.id] = convo.enriched(with: messages)
            // The pairing may have gone, or a newer read replaced the list.
            guard case .ready(let current) = chat else { return }
            chat = .ready(current.map { $0.id == convo.id ? convo.enriched(with: messages) : $0 })
        }
    }

    /// One conversation's messages, oldest first; nil when they could not be read.
    func messages(in convo: String) async -> [LogosObserverWire.ChatMessage]? {
        if DemoMode.isActive { return DemoChat.messages(in: convo) }
        guard let paired = chatPairing, let key = Self.readKey(account: paired.deviceID) else { return nil }
        guard case .answered(200, let json) = await signed(
            "GET", LogosObserverWire.messagesTarget(convo: convo), paired: paired, key: key)
        else { return nil }
        return LogosObserverWire.messages(json)
    }

    // MARK: - Forgetting

    /// Revoke this device on one Observer, then forget it here whatever the
    /// Observer said: an unreachable Observer cannot keep the phone paired.
    func forget(_ paired: Paired) async {
        if let key = Self.readKey(account: paired.deviceID) {
            _ = await signed("DELETE", "/v2/device", paired: paired, key: key)
        }
        drop(paired)
    }

    /// Every pairing, revoked and forgotten (the Logos page's teardown).
    func forgetAll() async {
        for paired in pairings { await forget(paired) }
    }

    private func drop(_ paired: Paired) {
        pairings.removeAll { $0.deviceID == paired.deviceID }
        Self.deleteKey(account: paired.deviceID)
        if chatPairing == nil { enrichedByID = [:] }
        if chatPairing == nil { chat = pairings.isEmpty ? .notPaired : .notGranted }
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

    // MARK: - The keys (device-only Keychain, one per pairing)

    private static func storeKey(_ key: Data, account: String) -> Bool {
        deleteKey(account: account)
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
        ]
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    private static func readKey(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, data.count == 32 else { return nil }
        return data
    }

    private static func deleteKey(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
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

/// The demo's Logos chats (prd §1155): the demo person's own week — the
/// Quillmark launch, a node on the testnet — dated from now so they stay fresh.
/// Only while the demo is on; never stored.
enum DemoChat {
    private static func ago(_ minutes: Double) -> Int64 {
        Int64((Date().timeIntervalSince1970 - minutes * 60) * 1000)
    }

    /// The names the demo person gave (`LogosChatNames`), so the demo shows
    /// a named person beside one still known only by address.
    static let names: [String: String] = ["0x7c41e2b0d93a5f18": "Ana Kovač",
                                          "0x19ad04c7e6b2f350": "Mira"]

    static func conversations() -> [LogosObserverWire.Conversation] {
        // Named as Basecamp names them ("Direct message"), so the demo shows
        // the person, not the kind (prd §1213).
        [.init(id: "demo-ana", direct: true, name: "Direct message", nickname: nil,
               preview: "Node's synced. Pairing the phone now",
               lastActivity: Date(timeIntervalSince1970: TimeInterval(ago(4)) / 1000),
               messageCount: 5, historyOnly: false),
         .init(id: "demo-tom", direct: true, name: "Direct message", nickname: nil,
               preview: "Did the reset take your accounts too?",
               lastActivity: Date(timeIntervalSince1970: TimeInterval(ago(38)) / 1000),
               messageCount: 1, historyOnly: false),
         .init(id: "demo-ops", direct: false, name: "Node operators", nickname: nil,
               preview: "Reset lands with 0.4, back up your keys",
               lastActivity: Date(timeIntervalSince1970: TimeInterval(ago(95)) / 1000),
               messageCount: 4, historyOnly: false),
         .init(id: "demo-quill", direct: false, name: "Quillmark beta", nickname: nil,
               preview: "1.4 is in review",
               lastActivity: Date(timeIntervalSince1970: TimeInterval(ago(60 * 26)) / 1000),
               messageCount: 2, historyOnly: true)]
    }

    static func messages(in convo: String) -> [LogosObserverWire.ChatMessage] {
        switch convo {
        case "demo-ana":
            return [.init(fromSelf: false, sender: "0x7c41e2b0d93a5f18", content: "Did your node finish syncing?", timestampMs: ago(31)),
                    .init(fromSelf: true, sender: nil, content: "Just about. 461 peers, mining since this morning", timestampMs: ago(27)),
                    .init(fromSelf: false, sender: "0x7c41e2b0d93a5f18", content: "Nice. Three tickets ready on mine", timestampMs: ago(12)),
                    .init(fromSelf: false, sender: "0x7c41e2b0d93a5f18", content: "Want to try a send once the testnet's back?", timestampMs: ago(11)),
                    .init(fromSelf: true, sender: nil, content: "Node's synced. Pairing the phone now", timestampMs: ago(4))]
        case "demo-tom":
            return [.init(fromSelf: false, sender: "0xa3d9f07b2c615e84", content: "Did the reset take your accounts too?", timestampMs: ago(38))]
        case "demo-ops":
            return [.init(fromSelf: false, sender: "0x19ad04c7e6b2f350", content: "Heads up: testnet resets with 0.4", timestampMs: ago(140)),
                    .init(fromSelf: false, sender: "0xe08b33f1a4c79d26", content: "Same genesis accounts?", timestampMs: ago(120)),
                    .init(fromSelf: true, sender: nil, content: "Mine started empty last time", timestampMs: ago(118)),
                    .init(fromSelf: false, sender: "0x19ad04c7e6b2f350", content: "Reset lands with 0.4, back up your keys", timestampMs: ago(95))]
        case "demo-quill":
            return [.init(fromSelf: true, sender: nil, content: "Build's up for testers", timestampMs: ago(60 * 28)),
                    .init(fromSelf: false, sender: "0x5f2e81c0b7a4d963", content: "1.4 is in review", timestampMs: ago(60 * 26))]
        default:
            return []
        }
    }
}


/// **The names you give the people you chat with on Logos (prd §1213).**
/// chat_module names nobody, so a person is their chat address until you
/// name them. Kept on this phone only — a name, never a message — and
/// keyed by the address, which chat_module 0.3.0 renews at every Basecamp
/// launch, so a name holds until they restart Basecamp. A name in Addresses
/// for the same address also counts.
@MainActor @Observable
final class LogosChatNames {
    static let shared = LogosChatNames()
    private static let key = "logos.chatNames.v1"
    private(set) var names: [String: String]

    private init() {
        names = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }

    func name(_ address: String) -> String? {
        if DemoMode.isActive, let demo = DemoChat.names[address] { return demo }
        return names[address] ?? AddressBook.shared.name(for: address)
    }

    /// An empty name forgets the one given.
    func set(_ name: String, for address: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        names[address] = trimmed.isEmpty ? nil : trimmed
        if let data = try? JSONEncoder().encode(names) { DefaultsWrite.set(data, forKey: Self.key) }
    }
}
