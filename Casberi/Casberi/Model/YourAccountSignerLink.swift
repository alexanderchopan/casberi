import Foundation
import WalletConnectNetworking
import WalletConnectSign

/// **THE SIGNER'S SIGNATURE, FROM THE PERSON'S OWN WALLET (prd §1447 item 17).**
///
/// When an operation needs both keys, the Signer (MetaMask, Rabby, any
/// WalletConnect wallet) signs the SafeOp as typed data. This is the ONE
/// place Casberi asks a wallet to sign anything, and it is shaped so nothing
/// outlives the one signature:
/// - its own proposal, never `WalletConnectBridge.readOnlyNamespaces()`
///   (that one asks for nothing and stays that way): ONE chain and ONE
///   method, `eth_signTypedData_v4`, no events;
/// - the settled session must name the Signer's address on that chain, or
///   nothing is asked;
/// - one request, the answer read, the session torn down — answered,
///   refused or timed out — before the signature reaches the caller.
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
    }

    static let method = "eth_signTypedData_v4"

    /// Ask the Signer for `typedData`'s signature on `chainId`. `show` gets
    /// the pairing link at once (a QR for a wallet on another device, a link
    /// for one on this phone); the answer is `r ‖ s ‖ v`, `v` 27 or 28.
    static func sign(typedData: String, signer: String, chainId: Int, timeout: Duration = .seconds(300),
                     show: @MainActor (URL) -> Void) async throws -> [UInt8] {
        let pairing = try await connect(signer: signer, chainIds: [chainId], timeout: timeout, show: show)
        defer { close(pairing) }
        return try await request(pairing, typedData: typedData, chainId: chainId, timeout: timeout)
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
    /// first address is the Signer, and nothing is asked over the session.
    static func connect(signer: String?, chainIds: [Int], timeout: Duration = .seconds(300),
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
        async let settled = WalletConnectBridge.firstSettledSession(timeout: timeout)
        await show(url)
        guard let session = await settled else { throw Failure.timedOut }
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
    static func request(_ pairing: Pairing, typedData: String, chainId: Int, timeout: Duration = .seconds(300)) async throws -> [UInt8] {
        guard pairing.chainIds.contains(chainId), let chain = Blockchain("eip155:\(chainId)") else { throw Failure.unavailable }
        let request = try Request(topic: pairing.topic, method: method,
                                  params: AnyCodable([pairing.signer, typedData]), chainId: chain)
        async let answer = response(to: request.id, timeout: timeout)
        try await Sign.instance.request(params: request)
        trace("asked on \(chainId)")
        guard let result = await answer else { throw Failure.timedOut }
        switch result {
        case .error(let error):
            throw Failure.refused(error.message)
        case .response(let value):
            guard let hex = try? value.get(String.self) else { throw Failure.malformedSignature }
            return try normalized(hex)
        }
    }

    /// The session torn down, answered or not.
    static func close(_ pairing: Pairing) {
        Task.detached { try? await WalletConnectBridge.tearDown(topic: pairing.topic) }
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

    private static func response(to id: RPCID, timeout: Duration) async -> RPCResult? {
        await withTaskGroup(of: RPCResult?.self) { group in
            group.addTask {
                for await response in Sign.instance.sessionResponsePublisher.values where response.id == id {
                    return response.result
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
