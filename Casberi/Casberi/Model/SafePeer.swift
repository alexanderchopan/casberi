import Combine
import Foundation
import SwiftData
import WalletConnectSign
import WalletConnectPairing

/// THIS PHONE AS A WALLETCONNECT PEER — the Safe web app, or any app that
/// speaks to owner wallets, pairs to it the way it pairs to a hardware
/// wallet (prd §913; `docs/signer-spec.md` §7's tier 2). The peer takes a
/// request, reads it through `SafePeerRequest`, runs it through the same
/// signer the service path uses, and hands the signature back over the
/// session. Nothing here decides whether a signature may happen.
///
/// **One method offered, and the offer is the whole door.** A session
/// settles with `SafePeerRequest.allowedMethods` and no other; an app that
/// REQUIRES more is refused at the proposal (`AutoNamespaces` throws, and
/// the refusal is landed as a row naming the app). A request for any other
/// method is answered with an error and landed as a row, so a paired app
/// that tried to send a transaction is on the record where the person looks.
///
/// **The same `Sign` client the read-only connect uses** — a WalletConnect
/// client is a peer in both directions, and `WalletConnectBridge` already
/// configured it. No `ReownWalletKit` (it would bring Push, Verify and Pay
/// along and is unmeasured on Mac Catalyst); `Pair.instance.pair(uri:)`,
/// `Sign.instance.approve/rejectSession/respond/disconnect` are the whole
/// surface used.
///
/// **Accounts.** The session lists this phone's K1 address on every rail
/// chain, and the Enclave owner's proxy address on each chain the factory
/// has answered for. The app asks the ADDRESS it means to; the request's
/// address must be one of ours or it is refused before it is read.
///
/// **UNMEASURED against Safe{Wallet}** (2026-09-24): whether its owner-wallet
/// connector proposes `eth_sendTransaction` as REQUIRED (which this peer
/// refuses by construction) or optional is not known from here. A refused
/// proposal is landed with the methods it required, so the first real
/// pairing says which.
@MainActor
enum SafePeer {

    // MARK: - State the screens read

    @MainActor @Observable
    final class State {
        var sessions: [PeerSession] = []
        /// Requests waiting on the person, oldest first. The shell mounts a
        /// sheet on the first.
        var asks: [PendingAsk] = []
        var pairing = false
        var lastRefusal: String?
    }

    struct PeerSession: Identifiable, Equatable {
        let topic: String
        let name: String
        let url: String
        let expires: Date
        var id: String { topic }
    }

    struct PendingAsk: Identifiable, Equatable {
        let topic: String
        let requestId: RPCID
        let app: String
        let address: String
        let ask: SafePeerRequest.Ask
        var id: String { "\(topic):\(requestId.string)" }
    }

    static let state = State()
    private static var cancellables = Set<AnyCancellable>()
    private static var started = false
    /// The last pairing's names, so a refused proposal can be landed by app.
    private static var contextProvider: (() -> ModelContext?)?

    // MARK: - Lifecycle

    /// Subscribes once. Called from the shell at launch when this phone
    /// holds a key, and from the Safe page — a paired app can ring while
    /// the app is anywhere.
    static func startIfNeeded(context: @escaping () -> ModelContext?) {
        contextProvider = context
        guard !started, SafeSigner.hasAnyKey, WalletConnectBridge.isAvailable else { return }
        WalletConnectBridge.configureIfNeeded()
        started = true

        Sign.instance.sessionProposalPublisher
            .receive(on: DispatchQueue.main)
            .sink { proposal, _ in
                Task { @MainActor in await handle(proposal: proposal) }
            }
            .store(in: &cancellables)
        Sign.instance.sessionRequestPublisher
            .receive(on: DispatchQueue.main)
            .sink { request, _ in
                Task { @MainActor in await handle(request: request) }
            }
            .store(in: &cancellables)
        Sign.instance.sessionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { sessions in
                Task { @MainActor in refresh(sessions) }
            }
            .store(in: &cancellables)
        Sign.instance.sessionDeletePublisher
            .receive(on: DispatchQueue.main)
            .sink { _, _ in
                Task { @MainActor in refresh(Sign.instance.getSessions()) }
            }
            .store(in: &cancellables)
        refresh(Sign.instance.getSessions())
    }

    private static func refresh(_ sessions: [Session]) {
        // Only sessions THIS peer settled: a read-only connect (§84) tears
        // its session down on the spot, so anything left standing is ours —
        // but the test is structural, not temporal: ours carry an account.
        state.sessions = sessions
            .filter { !$0.accounts.isEmpty && $0.expiryDate > .now }
            .map { PeerSession(topic: $0.topic, name: $0.peer.name, url: $0.peer.url, expires: $0.expiryDate) }
            .sorted { $0.expires > $1.expires }
    }

    // MARK: - Pairing

    enum PairError: Error, Equatable {
        case unavailable
        case noKey
        case notAPairingLink
        case relayRefused(String)
    }

    /// Pairs with a `wc:` link the person pasted (or scanned, or opened).
    /// The proposal that follows arrives through `handle(proposal:)`.
    static func pair(uri text: String, context: @escaping () -> ModelContext?) async -> Result<Void, PairError> {
        guard WalletConnectBridge.isAvailable else { return .failure(.unavailable) }
        guard SafeSigner.hasAnyKey else { return .failure(.noKey) }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let uri = WalletConnectURI(string: trimmed) else { return .failure(.notAPairingLink) }
        startIfNeeded(context: context)
        state.pairing = true
        defer { state.pairing = false }
        do {
            try await Pair.instance.pair(uri: uri)
            return .success(())
        } catch {
            return .failure(.relayRefused(String(describing: error)))
        }
    }

    static func disconnect(topic: String) async {
        try? await Sign.instance.disconnect(topic: topic)
        refresh(Sign.instance.getSessions())
    }

    // MARK: - The proposal

    private static func handle(proposal: Session.Proposal) async {
        var chains: [Blockchain] = []
        var accounts: [Account] = []
        for chainId in SafeSigner.chainIDs {
            guard let chain = Blockchain("eip155:\(chainId)") else { continue }
            let identities = await SafeSigner.identities(chainId: chainId)
            guard !identities.isEmpty else { continue }
            chains.append(chain)
            for identity in identities {
                if let account = Account(blockchain: chain, address: identity.address) {
                    accounts.append(account)
                }
            }
        }
        guard !accounts.isEmpty else {
            try? await Sign.instance.rejectSession(proposalId: proposal.id, reason: .unsupportedAccounts)
            return
        }
        do {
            let namespaces = try AutoNamespaces.build(
                sessionProposal: proposal,
                chains: chains,
                methods: Array(SafePeerRequest.allowedMethods),
                events: ["chainChanged", "accountsChanged"],
                accounts: accounts)
            _ = try await Sign.instance.approve(proposalId: proposal.id, namespaces: namespaces)
            WalletConnectApps.record(appNamed: proposal.proposer.name)
            refresh(Sign.instance.getSessions())
        } catch let error as AutoNamespacesError {
            try? await Sign.instance.rejectSession(proposalId: proposal.id, reason: RejectionReason(from: error))
            let required = proposal.requiredNamespaces.values.flatMap { $0.methods }.sorted()
            landRefusal(app: proposal.proposer.name, url: proposal.proposer.url, id: proposal.pairingTopic,
                        what: String(localized: "asked for more than a signature (\(required.joined(separator: ", ")))"))
        } catch {
            try? await Sign.instance.rejectSession(proposalId: proposal.id, reason: .userRejected)
        }
    }

    // MARK: - The request

    private static func handle(request: Request) async {
        let session = state.sessions.first { $0.topic == request.topic }
            ?? Sign.instance.getSessions().first { $0.topic == request.topic }
                .map { PeerSession(topic: $0.topic, name: $0.peer.name, url: $0.peer.url, expires: $0.expiryDate) }
        let app = session?.name ?? String(localized: "A paired app")
        let appURL = session?.url ?? ""
        let chainId = Int(request.chainId.reference)
        switch SafePeerRequest.parse(method: request.method, params: request.params.value, chainId: chainId) {
        case .success(let parsed):
            let identities = await SafeSigner.identities(chainId: parsed.ask.chainId)
            guard identities.contains(where: { $0.address.lowercased() == parsed.address.lowercased() }) else {
                await respondError(request, code: 5000, message: "Not this phone's address")
                landRefusal(app: app, url: appURL, id: request.id.string,
                            what: String(localized: "asked for a signature from \(WalletStore.shortAddress(parsed.address)), which isn't this phone"))
                return
            }
            state.asks.append(PendingAsk(topic: request.topic, requestId: request.id, app: app,
                                         address: parsed.address, ask: parsed.ask))
        case .failure(let refusal):
            await respondError(request, code: 5101, message: "Unsupported method")
            landRefusal(app: app, url: appURL, id: request.id.string, what: sentence(for: refusal, method: request.method))
        }
    }

    static func sentence(for refusal: SafePeerRequest.Refusal, method: String) -> String {
        switch refusal {
        case .methodNotOffered(let name):
            return String(localized: "asked this phone to \(name) — it signs a Safe transaction, statement or recovery and nothing else")
        case .paramsUnreadable, .typedDataUnreadable:
            return String(localized: "sent a \(method) request Casberi couldn't read")
        case .notASafeShape(let primaryType):
            return String(localized: "asked for a signature over \(primaryType), which isn't a Safe shape")
        case .chainMismatch(let request, let domain):
            return String(localized: "named chain \(request.map(String.init) ?? "?") for data on chain \(domain)")
        case .foreignDomain:
            return String(localized: "sent Safe-shaped data from a domain that isn't a Safe's")
        }
    }

    private static func respondError(_ request: Request, code: Int, message: String) async {
        try? await Sign.instance.respond(topic: request.topic, requestId: request.id,
                                         response: .error(JSONRPCError(code: code, message: message)))
    }

    // MARK: - The answer

    /// The sheet signed (through the signer that owns the shape, which
    /// re-checked every refusal on the way) and hands the bytes here to be
    /// delivered. This file transports; it never signs.
    static func deliver(_ ask: PendingAsk, signature: String) async -> Bool {
        state.asks.removeAll { $0.id == ask.id }
        do {
            try await Sign.instance.respond(topic: ask.topic, requestId: ask.requestId,
                                            response: .response(AnyCodable(signature)))
            return true
        } catch {
            return false
        }
    }

    static func decline(_ ask: PendingAsk) async {
        state.asks.removeAll { $0.id == ask.id }
        await respondUserRejected(ask)
    }

    private static func respondUserRejected(_ ask: PendingAsk) async {
        try? await Sign.instance.respond(topic: ask.topic, requestId: ask.requestId,
                                         response: .error(JSONRPCError(code: 5000, message: "User rejected")))
    }

    // MARK: - The record

    /// A refused ask is a row where the person looks (prd §913): the app
    /// that tried to send a transaction through this phone is not a toast.
    /// Its door is that app, by the URL it gave when it paired (§912).
    private static func landRefusal(app: String, url: String, id: String, what: String) {
        guard let context = contextProvider?() else { return }
        let ref = "wallet:saferefused:\(id)"
        var descriptor = FetchDescriptor<Thing>(predicate: #Predicate { $0.sourceRef == ref })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor), !existing.isEmpty { return }
        let thing = Thing(kind: .note,
                          title: String(localized: "\(app) \(what) — Casberi refused"),
                          content: url, source: SafeBridge.sourceName, sourceRef: ref)
        context.insert(thing)
        SpotlightIndex.index([thing])
        state.lastRefusal = thing.title
    }
}
