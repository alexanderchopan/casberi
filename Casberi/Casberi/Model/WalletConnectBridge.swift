import Foundation
import Combine
import WalletConnectSign
import WalletConnectPairing
import WalletConnectNetworking
import WalletConnectSigner

/// Connect a wallet instead of typing its address (prd 84, 2026-07-16).
///
/// The whole design is one sentence: **we ask for nothing and keep only the
/// address.** A normal WalletConnect session is a live pairing that can be
/// asked to sign; that would quietly falsify the Wallet screen's promise that
/// watching an address can never trade or move funds. So this proposes a
/// session with ZERO methods and ZERO events, reads the account out of the
/// settled session, and tears the session down on the spot. Nothing survives
/// the handshake that could sign anything — the promise holds structurally,
/// not by our restraint.
///
/// Three facts from reown-swift 2.3.0 that this leans on (all read out of the
/// SDK source, not the docs — the docs describe the JS client, which DOES
/// silently populate optional methods; Swift's `ProposalNamespace.methods` has
/// no default, so nothing fills it in behind us):
///
/// 1. `Namespace.validate(_: [String: ProposalNamespace])` only rejects empty
///    CHAINS. It has no empty-methods check, so `methods: []` proposes fine.
/// 2. `Sign.connect(namespaces:)` hardcodes required namespaces to `[:]` and
///    routes everything we pass to `optionalNamespaces` — Reown's own CAIP-25
///    guidance, baked in. Nothing is demanded, so nothing can be refused for
///    non-support.
/// 3. A settled `SessionNamespace` MUST carry accounts (`validate` throws
///    `.unsupportedAccounts` on an empty list). So an approved session always
///    hands back the address, which is the only thing we came for.
///
/// The paste field on the Wallet screen stays regardless (ruling 2026-07-16):
/// this is the fast path, never the only one. With no project id configured
/// `isAvailable` is false and the screen degrades to paste-only, the same shape
/// as the GitHub setup screen with an empty shipped client id.
enum WalletConnectBridge {

    // MARK: - Availability

    /// Shipped project id. Empty until a build carries one — the Reown project
    /// id is NOT a secret (it rides in the binary, exactly like every web
    /// dapp's), but it isn't committed yet, so DEBUG reads `-wcProjectID` and
    /// release degrades to paste-only rather than pretending Connect works.
    private static let shippedProjectID = ""

    static var projectID: String {
        let override = UserDefaults.standard.string(forKey: "wcProjectID")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return override.isEmpty ? shippedProjectID : override
    }

    /// No project id, no relay, no Connect button. The honesty rule's first
    /// corollary: a control that can't work doesn't appear.
    static var isAvailable: Bool { !projectID.isEmpty }

    // MARK: - Configuration

    private static var configured = false

    static func configureIfNeeded() {
        guard !configured, isAvailable else { return }

        // `Redirect` throws only on a malformed universal link or linkMode
        // without one — neither is reachable with a bare native scheme. If it
        // ever does throw, stay unconfigured so Connect reports unavailable
        // rather than half-working.
        guard let redirect = try? AppMetadata.Redirect(native: "casberi://",
                                                       universal: nil) else { return }

        Networking.configure(groupIdentifier: "group.com.casberi.app",
                             projectId: projectID,
                             socketFactory: WalletConnectSocketFactory())

        Pair.configure(metadata: AppMetadata(
            name: "Casberi",
            description: "Watch a wallet's activity — read-only.",
            url: "https://casberi.app",
            icons: [],
            redirect: redirect
        ))

        Sign.configure(crypto: UnusedCryptoProvider())

        // Last, not first: an early return above must leave this false, or
        // every later call short-circuits on the guard while `Sign.instance`
        // fatalErrors on a config that was never set.
        configured = true
    }

    // MARK: - The read-only proposal

    /// Alchemy network id → CAIP-2, for the chains the wallet screen reads.
    /// Robinhood Chain is deliberately absent: its CAIP-2 id isn't verified
    /// here, and a wrong chain id in a proposal is a silent compatibility bug.
    /// It costs nothing to omit — an EOA wears the same address on every EVM
    /// chain, so the address we came for arrives regardless of which we name.
    private static let caip2ByNetworkID: [String: String] = [
        "eth-mainnet":   "eip155:1",
        "base-mainnet":  "eip155:8453",
        "arb-mainnet":   "eip155:42161",
        "opt-mainnet":   "eip155:10",
        "matic-mainnet": "eip155:137",
    ]

    /// Ethereum mainnet — the floor a proposal falls back to if the chain
    /// picker somehow yields nothing mappable. Force-unwrapped deliberately: a
    /// nil here means the literal is malformed, which is a programmer error we
    /// want at launch, not a mysterious connect failure five screens later.
    private static let ethereumMainnet = Blockchain("eip155:1")!

    /// The proposal: the chains we actually read, and nothing else. `methods`
    /// and `events` are empty ON PURPOSE and must stay that way — a single
    /// entry here is a capability the wallet would grant us, and the promise
    /// on the Wallet screen would stop being true.
    static func readOnlyNamespaces() -> [String: ProposalNamespace] {
        let chains = WalletChainStore.activeNetworkIDs()
            .compactMap { caip2ByNetworkID[$0] }
            .compactMap { Blockchain($0) }
        return ["eip155": ProposalNamespace(chains: chains.isEmpty ? [ethereumMainnet] : chains,
                                            methods: [],
                                            events: [])]
    }

    // MARK: - Connect

    enum ConnectError: Error {
        case unavailable
    }

    /// Propose, and hand back the `wc:` URI to deep-link into a wallet.
    static func connectURI() async throws -> WalletConnectURI {
        guard isAvailable else { throw ConnectError.unavailable }
        configureIfNeeded()
        return try await Sign.instance.connect(namespaces: readOnlyNamespaces())
    }

    /// Every address the settled session handed over.
    static func addresses(from session: Session) -> [String] {
        session.namespaces.values
            .flatMap(\.accounts)
            .map(\.address)
    }

    /// Kill the session. **Throws on purpose — do not `try?` this.**
    ///
    /// Teardown is not cleanup here, it's the feature: the session exists only
    /// long enough to read `accounts`, and a session that outlives that read is
    /// a live pairing the wallet will still honour signing requests on. If this
    /// throws, the promise on the Wallet screen is false until it succeeds, so
    /// the caller must retry or say so out loud (`ShellChrome.flash()`) —
    /// swallowing it is the one failure mode this whole design exists to avoid.
    static func tearDown(_ session: Session) async throws {
        try await Sign.instance.disconnect(topic: session.topic)
    }

    /// The first session the wallet settles, or nil if `timeout` elapses, the
    /// publisher finishes, or the task is cancelled.
    ///
    /// The timeout is not politeness — without it, a person who taps Connect
    /// and never approves leaves this suspended for the process lifetime. It
    /// defaults to the 5 minutes WalletConnect stamps into the proposal's
    /// `expiryTimestamp`: past that the wallet couldn't settle anyway.
    static func firstSettledSession(timeout: Duration = .seconds(300)) async -> Session? {
        await withTaskGroup(of: Session?.self) { group in
            // `.values` keeps its own subscription alive for the lifetime of
            // the for-await, so there's no cancellable to store — and nothing
            // for ARC to release out from under us mid-wait.
            group.addTask {
                for await settled in Sign.instance.sessionSettlePublisher.values {
                    return settled.session
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

/// Required by `Sign.configure(crypto:)` and never called on this path.
///
/// The SDK reaches a `CryptoProvider` only through signature/identity code —
/// `EIP191Verifier` (recover a signer), `EIP1271Verifier` (contract wallets),
/// `EIP55` (checksum an address), `ENSResolver` (namehash). All four belong to
/// SIWE / `authentication:` flows, and a read-only proposal uses none of them:
/// the address arrives verbatim in the settled session's `accounts`.
///
/// So rather than pull in a secp256k1 + keccak dependency to satisfy an
/// initializer, both members fail loudly — `preconditionFailure`, not
/// `assertionFailure`, because the latter compiles out under `-O` and would let
/// a release build hash to empty `Data()` and watch a WRONG ADDRESS in silence.
/// Trapping is the honest outcome: if a future change adds `authentication:` to
/// the proposal, it needs a real CryptoProvider, and it should find that out
/// immediately rather than corrupt an address.
private struct UnusedCryptoProvider: CryptoProvider {
    enum Unreachable: Error { case readOnlySessionsNeverRecoverKeys }

    func recoverPubKey(signature: EthereumSignature, message: Data) throws -> Data {
        throw Unreachable.readOnlySessionsNeverRecoverKeys
    }

    func keccak256(_ data: Data) -> Data {
        preconditionFailure("keccak256 is unreachable on the read-only wallet path — "
                            + "if this fires, the proposal grew an authentication flow "
                            + "and needs a real CryptoProvider.")
    }
}
