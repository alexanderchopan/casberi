import Foundation
import os
import Security
import WalletConnectNetworking
import WalletConnectSign

/// **THE SIGNER'S SIGNATURE, FROM THE PERSON'S OWN WALLET (prd §1447 item 17).**
///
/// When an operation needs both keys, the Signer (MetaMask, Rabby, any
/// WalletConnect wallet) signs the SafeOp as typed data; before it becomes a
/// key at all, it signs `YourAccountSignerProof`'s typed data once (prd
/// §1516). This is the ONE place Casberi asks a wallet to sign anything, and
/// it is shaped so nothing outlives the one signature:
/// - its own proposal, never `WalletConnectBridge.readOnlyNamespaces()`
///   (that one asks for nothing and stays that way): ONE chain and ONE
///   method, `eth_signTypedData_v4`, no events;
/// - the settled session must name the Signer's address on that chain, or
///   nothing is asked;
/// - **the session is KEPT for the next send (prd §1601, user: "it took me
///   ten minutes to send b/c i had to go back and forth")**: one chain, one
///   method, the Signer's own address, so a later send asks it again with no
///   scan and the wallet still asks the person each time. A session that is
///   gone or never answers is torn down and the next send pairs afresh.
///
/// The caller still checks the signature with the Safe before anything goes
/// (`YourAccountChain.operate`), so a wallet that signs something else is
/// refused there, not trusted here.
enum YourAccountSignerLink {
    enum Failure: Error, Equatable {
        case unavailable
        case malformedURI
        case timedOut
        /// The wallet that connected is not the Signer.
        case notTheSigner(String)
        case refused(String)
        case malformedSignature
        /// The wallet's answer to the proof is not a signature by the
        /// Signer's key (prd §1516): another key's, or a contract's.
        case notProven
        /// The wallet turned the connection down (prd §1601).
        case declined
        /// A kept session the wallet no longer has (prd §1601).
        case gone
        /// The person chose another wallet (prd §1644).
        case switched
    }

    /// How long the Signer is waited for, connecting and then signing (prd
    /// §1601; was five minutes each, the screen frozen for all of it).
    static let wait: Duration = .seconds(120)

    static let method = "eth_signTypedData_v4"

    /// Ask the Signer for `typedData`'s signature on `chainId`. `show` gets
    /// the pairing link at once (a QR for a wallet on another device, a link
    /// for one on this phone); the answer is `r ‖ s ‖ v`, `v` 27 or 28.
    /// A session kept from an earlier send is asked first, with no scan:
    /// `kept` gets the wallet's own door, if it named one (prd §1601).
    ///
    /// **ANOTHER WALLET (prd §1644).** `switching` fires when the person
    /// chooses another wallet: the session asked is let go and the same
    /// signature is asked over a fresh pairing, the ask never ending. How
    /// each other ending treats the session is `SignerSwitch.closes`: a
    /// wallet that never answered, cancelled or not, is not kept.
    static func sign(typedData: String, signer: String, chainId: Int, timeout: Duration = wait,
                     kept: @escaping @MainActor (URL?) -> Void = { _ in },
                     resend: SignerSignal? = nil, switching: SignerSignal? = nil,
                     show: @MainActor (URL) -> Void) async throws -> [UInt8] {
        var asked = keptSession(signer: signer, chainId: chainId)
        var wasKept = asked != nil
        if wasKept { trace("asking the kept session") }
        while true {
            if asked == nil {
                let pairing = try await connect(signer: signer, chainIds: [chainId], timeout: timeout, show: show)
                // Connected: the code has done its work, so the sheet says to
                // approve in the wallet, as for a kept session, with its door
                // and Ask again (prd §1609). Its door is THIS session's: a wallet
                // just let go may still be listed for the same address.
                asked = (pairing, door(of: pairing.topic))
            }
            guard let (pairing, door) = asked else { throw Failure.unavailable }
            let sent = OSAllocatedUnfairLock(initialState: false)
            do {
                // The request goes first, then the wallet is opened onto it
                // (prd §1605): it is waiting there when the wallet comes up.
                return try await request(pairing, typedData: typedData, chainId: chainId, timeout: timeout,
                                         resend: resend, switching: switching,
                                         sent: { sent.withLock { $0 = true }; kept(door) })
            } catch {
                guard let end = ending(error, sent: sent.withLock { $0 }) else { throw error }
                if SignerSwitch.closes(end) { close(pairing) }
                guard SignerSwitch.pairsAfresh(end, kept: wasKept) else { throw error }
                trace(end == .switched ? "another wallet: pairing afresh" : "the kept session is gone: pairing afresh")
                asked = nil
                wasKept = false
            }
        }
    }

    /// **An app's sign-in, by your co-signer (prd §1700l).** For a page in
    /// Apps on Aztec's browser that takes only a plain key's signature: one
    /// `personal_sign` or `eth_signTypedData_v4` on Ethereum, over a pairing
    /// of its own that asks for that one method and is let go once answered,
    /// so the Signer's kept session (Safe approvals only) is never widened.
    /// The answer must recover to `signer` over `digest`, or nothing goes
    /// back to the page. Once the wallet has connected, the request goes and
    /// `sent` gets the wallet's own door, so the wallet is opened onto it, and
    /// each `resend` asks the same question again (as a send does, prd §1605,
    /// §1609): a wallet left in the background misses a request.
    static func signForApp(method appMethod: String, params: [String], digest: [UInt8], signer: String,
                           timeout: Duration = wait, resend: SignerSignal? = nil,
                           sent: @MainActor (URL?) -> Void = { _ in },
                           show: @MainActor (URL) -> Void) async throws -> [UInt8] {
        guard ["personal_sign", "eth_signTypedData_v4"].contains(appMethod), digest.count == 32 else { throw Failure.unavailable }
        let chainId = YourAccountOp.ethereum.chainId
        let pairing = try await connect(signer: signer, chainIds: [chainId], method: appMethod, timeout: timeout, show: show)
        defer { close(pairing) }
        guard let chain = Blockchain("eip155:\(chainId)") else { throw Failure.unavailable }
        func make() throws -> Request {
            try Request(topic: pairing.topic, method: appMethod, params: AnyCodable(params), chainId: chain)
        }
        let request = try make()
        let ids = Asked(request.id)
        let resends = resend?.stream()
        async let answer = answer(to: ids, topic: pairing.topic, timeout: timeout)
        let again = Task {
            guard let resends else { return }
            for await _ in resends {
                guard let next = try? make() else { continue }
                ids.add(next.id)
                try? await Sign.instance.request(params: next)
                trace("asked \(appMethod) again for an app")
            }
        }
        defer { again.cancel() }
        do { try await Sign.instance.request(params: request) } catch { throw Failure.gone }
        trace("asked \(appMethod) for an app")
        await sent(door(of: pairing.topic))
        switch await answer {
        case .answered(.response(let value)):
            guard let hex = try? value.get(String.self) else { throw Failure.malformedSignature }
            let signature = try normalized(hex)
            guard EcRecover.address(digest: digest, signature: signature)?.caseInsensitiveCompare(signer) == .orderedSame else {
                throw Failure.notProven
            }
            return signature
        case .answered(.error(let error)): throw Failure.refused(error.message)
        case .gone: throw Failure.gone
        case .switched: throw Failure.switched
        case .none: throw Failure.timedOut
        }
    }

    /// What a failed ask means for its session (prd §1644), or nil for an
    /// answer (a refusal, a malformed signature) that leaves it as it is.
    /// A cancelled ask is the person's, whatever the request threw.
    private static func ending(_ error: Error, sent: Bool) -> SignerSwitch.End? {
        if Task.isCancelled { return .cancelled(sent: sent) }
        switch error as? Failure {
        case .switched?: return .switched
        case .gone?: return .gone
        case .timedOut?: return .timedOut
        default: return nil
        }
    }

    /// A live session with `signer` on `chainId` that asks for this
    /// signature and nothing else, and the wallet's own door (prd §1601).
    /// A watch-only session asks for nothing, and Receive's asks for a send,
    /// so neither is ever taken for this.
    static func keptSession(signer: String, chainId: Int) -> (Pairing, URL?)? {
        guard WalletConnectBridge.isAvailable else { return nil }
        WalletConnectBridge.configureIfNeeded()
        for session in Sign.instance.getSessions() where session.expiryDate > Date().addingTimeInterval(120) {
            guard let ns = session.namespaces[WalletConnectBridge.evmNamespace], ns.methods == [method] else { continue }
            let agreed = Set(ns.accounts.filter { $0.address.caseInsensitiveCompare(signer) == .orderedSame }
                                        .compactMap { Int($0.blockchain.reference) })
            guard agreed.contains(chainId) else { continue }
            let door = session.peer.redirect?.native.flatMap(URL.init(string:))
            return (Pairing(topic: session.topic, signer: signer, chainIds: agreed), door)
        }
        return nil
    }

    /// The wallet's own door for the session on `topic`.
    static func door(of topic: String) -> URL? {
        Sign.instance.getSessions().first { $0.topic == topic }?.peer.redirect?.native.flatMap(URL.init(string:))
    }

    /// A settled session with the Signer's wallet: its topic and the
    /// networks it agreed to sign on.
    struct Pairing: Sendable {
        let topic: String
        let signer: String
        let chainIds: Set<Int>
    }

    /// **ONE SCAN FOR EVERY NETWORK (prd §1456).** One proposal naming every
    /// network the batch will ask on, one method; the settled session must
    /// name the Signer. Several requests then ride it, one per network.
    /// With no Signer yet (choosing one at Create, prd §1457), the wallet's
    /// first address is the Signer — a key only once `prove` says so.
    /// `method` is the one thing the session may ask: a signature here, a
    /// send for Receive › From another wallet (prd §1506).
    static func connect(signer: String?, chainIds: [Int], method: String = method,
                        timeout: Duration = .seconds(300),
                        show: @MainActor (URL) -> Void) async throws -> Pairing {
        let chains = chainIds.compactMap { Blockchain("eip155:\($0)") }
        guard WalletConnectBridge.isAvailable, !chains.isEmpty else { throw Failure.unavailable }
        WalletConnectBridge.configureIfNeeded()
        let namespaces = [WalletConnectBridge.evmNamespace: ProposalNamespace(chains: chains, methods: [method], events: [])]
        // The proposal waits on the relay socket; a socket the SDK left
        // closed (measured: a proposal stalled for minutes) is opened here,
        // and a stalled proposal is asked once more on a fresh socket.
        var uri: WalletConnectURI?
        for attempt in 1...2 {
            trace("proposing on \(chains.map(\.absoluteString).joined(separator: ",")), attempt \(attempt)")
            if !(await socketUp(within: .seconds(10))) {
                trace("socket down: connecting")
                try? Networking.instance.connect()
                _ = await socketUp(within: .seconds(10))
            }
            uri = await within(.seconds(25)) { try? await Sign.instance.connect(namespaces: namespaces) } ?? nil
            if uri != nil { break }
            trace("the proposal stalled: a fresh socket")
            try? Networking.instance.disconnect(closeCode: .normalClosure)
            try? Networking.instance.connect()
        }
        guard let uri else { throw Failure.unavailable }
        trace("proposed")
        guard let url = URL(string: uri.absoluteString) else { throw Failure.malformedURI }
        async let settled = settlement(of: uri.topic, timeout: timeout)
        await show(url)
        let session: Session
        switch await settled {
        case .settled(let s): session = s
        case .declined: throw Failure.declined
        case .none: throw Failure.timedOut
        }
        trace("settled")
        let accounts = session.namespaces[WalletConnectBridge.evmNamespace]?.accounts ?? []
        guard let signer = signer ?? accounts.first.map({ EIP55.checksum($0.address) }) else {
            Task.detached { try? await WalletConnectBridge.tearDown(topic: session.topic) }
            throw Failure.notTheSigner("")
        }
        let agreed = Set(accounts.filter { $0.address.caseInsensitiveCompare(signer) == .orderedSame }
                                 .compactMap { Int($0.blockchain.reference) })
        guard !agreed.isEmpty else {
            Task.detached { try? await WalletConnectBridge.tearDown(topic: session.topic) }
            throw Failure.notTheSigner(accounts.first?.address ?? "")
        }
        return Pairing(topic: session.topic, signer: signer, chainIds: agreed)
    }

    /// One signature over a settled pairing, on one of its networks.
    static func request(_ pairing: Pairing, typedData: String, chainId: Int, timeout: Duration = wait,
                        resend: SignerSignal? = nil, switching: SignerSignal? = nil,
                        sent: @MainActor () -> Void = {}) async throws -> [UInt8] {
        guard pairing.chainIds.contains(chainId), let chain = Blockchain("eip155:\(chainId)") else { throw Failure.unavailable }
        func make() throws -> Request {
            try Request(topic: pairing.topic, method: method, params: AnyCodable([pairing.signer, typedData]), chainId: chain)
        }
        let request = try make()
        let ids = Asked(request.id)
        // Listened to before the request goes, so a tap is never missed.
        let resends = resend?.stream(), switches = switching?.stream()
        async let answer = answer(to: ids, topic: pairing.topic, timeout: timeout, switching: switches)
        // **ASK AGAIN (prd §1609, user: "sometimes it doesn't fire w/
        // rainbow").** A wallet in the background can miss a request; the
        // same question is asked again on the same session, and whichever
        // asking it answers is the answer.
        let again = Task {
            guard let resends else { return }
            for await _ in resends {
                guard let next = try? make() else { continue }
                ids.add(next.id)
                try? await Sign.instance.request(params: next)
                trace("asked again on \(chainId)")
            }
        }
        defer { again.cancel() }
        do {
            try await Sign.instance.request(params: request)
        } catch {
            // A session the SDK no longer holds: asked of a fresh pairing.
            trace("the request was not sent: \(error)")
            throw Failure.gone
        }
        trace("asked on \(chainId)")
        await sent()
        let result: RPCResult
        switch await answer {
        case .answered(let r): result = r
        case .gone: throw Failure.gone
        case .switched: throw Failure.switched
        case .none: throw Failure.timedOut
        }
        switch result {
        case .error(let error):
            throw Failure.refused(error.message)
        case .response(let value):
            guard let hex = try? value.get(String.self) else { throw Failure.malformedSignature }
            return try normalized(hex)
        }
    }

    /// **The wallet holds the Signer's key (prd §1516).** One typed-data
    /// signature over the account, the key and a fresh challenge, which must
    /// recover to `pairing.signer`; asked on Base when the wallet agreed to
    /// it. Throws `.notProven` for any other answer.
    static func prove(_ pairing: Pairing, account: String, timeout: Duration = wait) async throws {
        var challenge = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, 32, &challenge) == errSecSuccess,
              let chainId = YourAccountSignerProof.chain(of: pairing.chainIds, preferring: YourAccountOp.base.chainId),
              let typed = YourAccountSignerProof.typedData(account: account, signer: pairing.signer,
                                                           chainId: chainId, challenge: challenge),
              let digest = YourAccountSignerProof.digest(typed) else { throw Failure.unavailable }
        let signature: [UInt8]
        do {
            signature = try await request(pairing, typedData: typed, chainId: chainId, timeout: timeout)
        } catch Failure.malformedSignature {
            // A smart wallet's ERC-1271/6492 answer is longer than 65 bytes.
            throw Failure.notProven
        }
        let verdict = YourAccountSignerProof.verdict(signer: pairing.signer,
                                                     recovered: EcRecover.address(digest: digest, signature: signature))
        trace("proof: \(verdict)")
        guard verdict == .holds else { throw Failure.notProven }
    }

    /// The session torn down, answered or not, once more after a second if
    /// the relay refused: a wallet let go that stays listed is the one the
    /// next send asks again (prd §1644).
    static func close(_ pairing: Pairing) {
        Task.detached {
            if (try? await WalletConnectBridge.tearDown(topic: pairing.topic)) != nil { return }
            try? await Task.sleep(for: .seconds(1))
            try? await WalletConnectBridge.tearDown(topic: pairing.topic)
        }
    }

    private static func trace(_ line: String) {
        #if DEBUG
        NSLog("signerLink| %@", line)
        #endif
    }

    /// `r ‖ s ‖ v` with `v` 27 or 28 — some wallets answer 0 or 1.
    static func normalized(_ hex: String) throws -> [UInt8] {
        guard var sig = SafeABI.hexBytes(hex), sig.count == 65 else { throw Failure.malformedSignature }
        if sig[64] < 27 { sig[64] += 27 }
        guard sig[64] == 27 || sig[64] == 28 else { throw Failure.malformedSignature }
        return sig
    }

    /// Whether the relay socket is connected, waiting up to `limit`.
    private static func socketUp(within limit: Duration) async -> Bool {
        await within(limit) {
            for await status in Networking.instance.socketConnectionStatusPublisher.values where status == .connected {
                return true
            }
            return false
        } ?? false
    }

    /// `work`'s answer, or nil once `limit` passes.
    private static func within<T: Sendable>(_ limit: Duration, _ work: @escaping @Sendable () async -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await work() }
            group.addTask {
                try? await Task.sleep(for: limit)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    static func response(to id: RPCID, timeout: Duration) async -> RPCResult? {
        if case .answered(let r) = await answer(to: Asked(id), topic: nil, timeout: timeout) { return r }
        return nil
    }

    /// Every id one question was asked under (prd §1609): an Ask again is a
    /// new request with a new id, and the answer to any of them is the answer.
    final class Asked: @unchecked Sendable {
        private let lock = NSLock()
        private var ids: [RPCID]
        init(_ id: RPCID) { ids = [id] }
        func add(_ id: RPCID) { lock.lock(); ids.append(id); lock.unlock() }
        func contains(_ id: RPCID) -> Bool { lock.lock(); defer { lock.unlock() }; return ids.contains(id) }
    }

    enum Answer { case answered(RPCResult), gone, switched, none }

    /// The wallet's answer to `id`; `.gone` the moment the wallet deletes
    /// the session `topic` (prd §1601), `.none` once `timeout` passes or the
    /// task is cancelled; `.switched` when the person chooses another wallet
    /// (prd §1644).
    static func answer(to ids: Asked, topic: String?, timeout: Duration,
                       switching: AsyncStream<Void>? = nil) async -> Answer {
        await withTaskGroup(of: Answer.self) { group in
            group.addTask {
                for await response in Sign.instance.sessionResponsePublisher.values where ids.contains(response.id) {
                    return .answered(response.result)
                }
                return .none
            }
            if let topic {
                group.addTask {
                    for await (deleted, _) in Sign.instance.sessionDeletePublisher.values where deleted == topic {
                        return .gone
                    }
                    return .none
                }
            }
            if let switching {
                group.addTask {
                    for await _ in switching { return .switched }
                    // The sheet done: the other tasks end the wait.
                    try? await Task.sleep(for: timeout)
                    return .none
                }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return .none
            }
            let first = await group.next() ?? .none
            group.cancelAll()
            return first
        }
    }

    enum Settlement { case settled(Session), declined, none }

    /// The session the wallet settles, or `.declined` the moment it turns
    /// the proposal on `pairingTopic` down (prd §1601: a refusal used to be
    /// waited out for the whole five minutes).
    static func settlement(of pairingTopic: String, timeout: Duration) async -> Settlement {
        await withTaskGroup(of: Settlement.self) { group in
            group.addTask {
                for await settled in Sign.instance.sessionSettlePublisher.values {
                    return .settled(settled.session)
                }
                return .none
            }
            group.addTask {
                for await (proposal, _) in Sign.instance.sessionRejectionPublisher.values where proposal.pairingTopic == pairingTopic {
                    return .declined
                }
                return .none
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return .none
            }
            let first = await group.next() ?? .none
            group.cancelAll()
            return first
        }
    }
}
