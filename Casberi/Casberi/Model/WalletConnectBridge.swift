import Foundation
import Combine
import Security
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

    /// Shipped Reown project id (2026-07-16). NOT a secret — it identifies the
    /// app to the relay and rides in the binary exactly like every web dapp's
    /// rides in its JS bundle. It is not a credential: it authorises nothing,
    /// and the read-only proposal is what keeps the handshake safe, not the
    /// obscurity of this string. What it DOES carry is our relay rate limit, so
    /// treat a rotation as a release, not a config tweak.
    ///
    /// `-wcProjectID` still overrides it in DEBUG (a throwaway id for probing
    /// against a fresh relay quota). Empty here would degrade the screen to
    /// paste-only rather than showing a Connect button that can't work.
    private static let shippedProjectID = "0ee1e915fc17d733fbd5d2d3b6824c66"

    static var projectID: String {
        let override = UserDefaults.standard.string(forKey: "wcProjectID")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return override.isEmpty ? shippedProjectID : override
    }

    /// No project id, no relay, no Connect button. The honesty rule's first
    /// corollary: a control that can't work doesn't appear.
    static var isAvailable: Bool { !projectID.isEmpty }

    // MARK: - Configuration

    /// The app group the SDK stores its pairing keys under — the same group
    /// the SwiftData store shares with the extensions. Named once: the
    /// keychain preflight below must probe EXACTLY the group the SDK will
    /// write, or a pass there says nothing about the write that crashes.
    private static let appGroup = "group.com.casberi.app"

    private static var configured = false

    static func configureIfNeeded() {
        guard !configured, isAvailable else { return }

        // `Redirect` throws only on a malformed universal link or linkMode
        // without one — neither is reachable with a bare native scheme. If it
        // ever does throw, stay unconfigured so Connect reports unavailable
        // rather than half-working.
        guard let redirect = try? AppMetadata.Redirect(native: "casberi://",
                                                       universal: nil) else { return }

        Networking.configure(groupIdentifier: appGroup,
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

    /// The chain-store id for Solana, which is one row in the picker but a
    /// whole namespace here.
    static let solanaNetworkID = "solana-mainnet"

    /// CAIP-2 namespaces, named once. These two strings decide which family an
    /// account belongs to, which chains get proposed, and whether an address is
    /// case-sensitive — spelling them inline in each of those places is how the
    /// three quietly disagree.
    static let solanaNamespace = "solana"
    static let evmNamespace = "eip155"

    /// Solana mainnet, named BOTH ways a wallet might know it (2026-07-16).
    /// This looks like belt-and-braces and isn't — the two ids are the same
    /// chain, and which one a given wallet answers to is not something we get
    /// to choose:
    ///
    /// 1. `5eykt4…` is correct and current. It is the first 32 chars of the
    ///    real mainnet genesis hash — verified against the chain itself
    ///    (`getGenesisHash` → `5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d`),
    ///    and it is the only mainnet id in the CAIP-2 namespace registry.
    /// 2. `4sGjMW…` is legacy, and is in the wild because CAIP-30's own test
    ///    cases shipped it labelled "Solana Mainnet", derived from a genesis
    ///    hash (`4sGjMW1sUnHzSxGspuhpqLDx6wiyjNtAMdL4VZHirAn`) that is NOT the
    ///    mainnet genesis. The spec was wrong; wallets implemented the spec.
    ///
    /// Naming both is free precisely because of the optional-namespace
    /// property this file is built on: nothing is required, so a wallet that
    /// knows only one id approves that one and ignores the other rather than
    /// refusing. A wallet answering to both returns the same address twice and
    /// `accounts(from:)` dedupes it. Naming only the correct one would be
    /// standards-pure and would silently fail to connect real wallets — the
    /// exact "silent compatibility bug" the EVM table above refuses to risk.
    private static let solanaMainnetChains: [Blockchain] = [
        Blockchain("solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp")!,
        Blockchain("solana:4sGjMW1sUnHzSxGspuhpqLDx6wiyjNtZ")!,
    ]

    /// The proposal: the chains we actually read, and nothing else. `methods`
    /// and `events` are empty ON PURPOSE and must stay that way — a single
    /// entry here is a capability the wallet would grant us, and the promise
    /// on the Wallet screen would stop being true.
    ///
    /// One namespace per family, and only for families the person actually has
    /// switched on: proposing `solana` to someone who reads EVM only would ask
    /// their wallet for an account on a chain this app won't look at. Neither
    /// namespace may carry empty chains — `Namespace.validate` rejects only
    /// that (`unsupportedChains`), so an empty list is the one way to make a
    /// read-only proposal throw.
    static func readOnlyNamespaces() -> [String: ProposalNamespace] {
        let active = WalletChainStore.activeNetworkIDs()
        var namespaces: [String: ProposalNamespace] = [:]

        let evmChains = active
            .compactMap { caip2ByNetworkID[$0] }
            .compactMap { Blockchain($0) }
        if !evmChains.isEmpty {
            namespaces[evmNamespace] = ProposalNamespace(chains: evmChains, methods: [], events: [])
        }
        if active.contains(solanaNetworkID) {
            namespaces[solanaNamespace] = ProposalNamespace(chains: solanaMainnetChains,
                                                            methods: [], events: [])
        }
        // Every chain off, or a chain set that maps to nothing: fall back to
        // Ethereum rather than propose a namespace-less session the SDK would
        // reject. An EOA wears the same address on every EVM chain, so the
        // address we came for arrives regardless of which we name.
        if namespaces.isEmpty {
            namespaces[evmNamespace] = ProposalNamespace(chains: [ethereumMainnet],
                                                         methods: [], events: [])
        }
        return namespaces
    }

    // MARK: - Connect

    enum ConnectError: Error {
        case unavailable
        /// The SDK handed back a URI that isn't a URL. Distinct from
        /// `unavailable` — availability was already established by then, and a
        /// caller that hides the Connect button on `.unavailable` must not hide
        /// it for a parse bug.
        case malformedURI(String)
        /// The session outlived the read and two attempts to kill it. Carries
        /// the topic because the person's escape hatch is disconnecting
        /// Casberi from inside their own wallet, and the wallet lists sessions
        /// by topic. Never swallow this — see `tearDown`.
        case tearDownFailed(topic: String, underlying: Error)
        /// This device's keychain refused the app-group write the handshake
        /// crypto depends on (carries the `OSStatus` for the log line and the
        /// screen's honest copy). Pre-flighted HERE because the SDK
        /// force-unwraps that exact write — `try! kms.createSymmetricKey` /
        /// `try! kms.createX25519KeyPair` in reown-swift 2.3.0's
        /// AppPairService/AppProposeService — so its failure is a process
        /// kill, not an error anyone can catch. The simulator never enforces
        /// keychain access groups, which is why only a device can surface
        /// this; `scripts/wc-handshake.sh` can't.
        case keychainUnavailable(OSStatus)
    }

    /// What a completed handshake meant. Deliberately NOT `[String]?` — "no
    /// wallet app" and "you never approved" are different things to say, and a
    /// nil would flatten them into one wrong line.
    enum ConnectOutcome {
        /// The accounts the wallet handed over, AFTER the session carrying them
        /// was torn down. Empty is possible in principle and means the wallet
        /// approved without sharing an account.
        case connected([ConnectedAccount])
        /// No installed app claims the `wc:` scheme. Kept for the probe and
        /// for callers that pass no `offerManualPairing` handler; the Wallet
        /// screen no longer ends here, since not claiming `wc:` doesn't mean
        /// no wallet is installed (2026-07-23 — see `connect`).
        case noWalletApp
        /// Nobody approved before the proposal expired.
        case timedOut
    }

    // Deliberately no `connectURI()` here. It existed, the probe was its only
    // caller, and `connect` replaced it — but the reason not to bring it back
    // is that it was the safe-looking half of an unsafe whole: propose a
    // session and hand the URI out, with the settle listener, the read and the
    // teardown all left as the caller's problem. That's the shape a future
    // "I just need a URI" caller reaches for, and it leaks live sessions.
    // Whatever you need, add it to `connect`.

    /// The whole handshake: propose → open the wallet → wait for approval →
    /// read the address → kill the session. This is the only entry point any
    /// UI should call; the pieces below it are public for the probe.
    ///
    /// `open` is injected rather than reached for directly so the probe can
    /// stub it, and it must return whether an installed app actually claimed
    /// the `wc:` scheme. Getting that answer is harder than it looks and the
    /// screen carries the note: neither `UIApplication.open`'s completion nor
    /// SwiftUI's `openURL` reports it truthfully (both say success for a URI
    /// nothing claims), so the real implementation gates on `canOpenURL`. Do
    /// not "simplify" a caller back to the opened-Bool alone.
    ///
    /// Note what does NOT happen on the `.noWalletApp` path: nothing is torn
    /// down, because nothing settled — an unanswered proposal is a pairing,
    /// not a session. It carries no methods and expires on its own at
    /// `expiryTimestamp` (5 minutes), so there is nothing to revoke.
    /// - Parameter offerManualPairing: called when no installed app claims the
    ///   `wc:` scheme — hands over the pairing URI so the caller can show it
    ///   for pasting into a wallet directly. The handshake keeps listening
    ///   after this fires; it is an alternative route to the same approval,
    ///   not a failure report.
    static func connect(timeout: Duration = .seconds(300),
                        open: @MainActor (URL) async -> Bool,
                        offerManualPairing: @MainActor (URL) -> Void = { _ in }) async throws -> ConnectOutcome {
        guard isAvailable else { throw ConnectError.unavailable }
        // Prove the keychain write the SDK is about to force-try, while its
        // failure can still be an error instead of a crash. See
        // `ConnectError.keychainUnavailable`.
        if let refusal = keychainRefusal() {
            NSLog("WalletConnect: keychain refused the app-group write (OSStatus %d) — connect degraded to paste-only", refusal)
            throw ConnectError.keychainUnavailable(refusal)
        }
        configureIfNeeded()

        let uri = try await Sign.instance.connect(namespaces: readOnlyNamespaces())
        guard let url = URL(string: uri.absoluteString) else {
            throw ConnectError.malformedURI(uri.absoluteString)
        }

        // Subscribe BEFORE the wallet can possibly answer. `connect` returns
        // once the proposal is published, and a wallet that auto-approves a
        // remembered pairing can settle in the window between that return and
        // a subscribe placed after `open` — the settle event would fire with
        // nobody listening, and this would then wait out the full timeout
        // while a LIVE session sat on the relay. `async let` starts the child
        // task at this line, which closes the window.
        async let settled = firstSettledSession(timeout: timeout)

        if await open(url) == false {
            // NOTHING CLAIMED `wc:` — which is not the same as "no wallet"
            // (fixed 2026-07-23, user: "the connect a wallet app doesn't
            // work"). `canOpenURL` is still the only trustworthy read of the
            // scheme (see the Info.plist note), but the scheme itself has
            // stopped being a reliable proxy for "a wallet is installed":
            // wallets increasingly register a UNIVERSAL LINK
            // (metamask.app.link/wc?uri=…) and no longer claim the bare `wc:`.
            // On such a device the old code told a person with a wallet on
            // their home screen that they had none, and stopped.
            //
            // So this no longer dead-ends. The pairing URI is handed to the
            // caller to show, and the listener KEEPS RUNNING while they paste
            // it into their wallet's own scan/paste screen — every
            // WalletConnect wallet has one. Waiting is correct here precisely
            // because there is now a way forward; the 2026-07-16 early return
            // was right only while this branch had nothing to offer.
            await offerManualPairing(url)
        }
        guard let session = await settled else { return .timedOut }

        let found = accounts(from: session)

        // Read first, then kill — and hand the addresses back only once the
        // kill SUCCEEDED. That ordering is the feature: an address reaches the
        // caller exclusively through a path where the session that carried it
        // is already gone, so there is no branch on which we watch a wallet
        // while a live pairing survives.
        if let failure = await tearDownShielded(topic: session.topic) {
            throw ConnectError.tearDownFailed(topic: session.topic, underlying: failure)
        }
        return .connected(found)
    }

    /// The status the keychain answers the SDK's write with, asked FIRST —
    /// nil means writes work and the handshake may proceed. This mirrors the
    /// exact query `KeychainStorage.buildBaseServiceQuery` builds around the
    /// pairing keys (generic password, data-protection keychain,
    /// after-first-unlock-this-device-only, our app group), because the
    /// access group + data-protection pair is what iOS authorises against —
    /// probing anything weaker would pass where the real write dies. The
    /// probe item is deleted on the way out; a duplicate left by an
    /// interrupted earlier run answers the same question, so it counts as a
    /// pass too.
    private static func keychainRefusal() -> OSStatus? {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecUseDataProtectionKeychain: true,
            kSecAttrService: "casberi.wc.preflight",
            kSecAttrAccessGroup: appGroup,
            kSecAttrAccount: "probe"
        ]
        query[kSecValueData] = Data([1])
        let status = SecItemAdd(query as CFDictionary, nil)
        query.removeValue(forKey: kSecValueData)
        SecItemDelete(query as CFDictionary)
        return (status == errSecSuccess || status == errSecDuplicateItem) ? nil : status
    }

    /// One account a wallet shared: the address, and which family it belongs
    /// to. The family is read off the session rather than guessed from the
    /// address's shape — the wallet already told us, and `SNS.isAddress`-style
    /// sniffing would be a guess standing next to an authoritative answer.
    struct ConnectedAccount: Equatable {
        let address: String
        /// CAIP-2 namespace — `eip155` or `solana`.
        let namespace: String
        var isSolana: Bool { namespace == solanaNamespace }
        /// The chain this account needs switched on to be readable at all, or
        /// nil when the default chain set already covers it. The screen asks
        /// this rather than restating the id, so the namespace and the chain
        /// can't drift apart in two files.
        var requiredNetworkID: String? { isSolana ? solanaNetworkID : nil }
    }

    /// Every DISTINCT account the settled session handed over, in the order it
    /// sent them.
    ///
    /// Deduped, because a CAIP-10 account is an address ON A CHAIN: a session
    /// settled over our five EVM chains carries the same EOA five times, once
    /// per chain, and a Solana wallet answering to both mainnet ids sends the
    /// same address twice. Measured 2026-07-16 — before this dedupe the probe
    /// reported "connected 5 address(es)" against a wallet holding exactly one.
    /// Casberi watches an ADDRESS, not an address-on-a-chain
    /// (`WalletChainStore` alone decides which chains get read), so the chain
    /// half is noise; the NAMESPACE is not, since it decides whether Solana has
    /// to be switched on to read the thing at all.
    ///
    /// The comparison key normalises PER FAMILY, and that asymmetry is not
    /// cosmetic: EVM is case-insensitive (EIP-55 case is a checksum, so the
    /// same wallet arrives cased differently from different wallets and must
    /// collapse), while base58 is case-SENSITIVE — lowercasing a Solana address
    /// can fold two genuinely different wallets into one. Note the test is an
    /// ALLOWLIST — lowercase only what is known to be EVM — not "everything
    /// that isn't Solana": the moment a second base58 namespace is proposed
    /// (sui, near, tron are all real WalletConnect namespaces) a denylist would
    /// silently start corrupting it. Never store the normalised form either
    /// way; the rows show what the wallet sent.
    ///
    /// Namespaces are walked in SORTED key order, not Dictionary order. The
    /// order here becomes the order they're watched in, and WalletScreen's
    /// first watched address leads the screen — so iterating a Dictionary would
    /// hand a different wallet the lead on each connect, for the same wallet.
    static func accounts(from session: Session) -> [ConnectedAccount] {
        var seen = Set<String>()
        var distinct: [ConnectedAccount] = []
        for key in session.namespaces.keys.sorted() {
            for account in session.namespaces[key]?.accounts ?? [] {
                let normalised = account.namespace == evmNamespace
                    ? account.address.lowercased()
                    : account.address
                guard seen.insert("\(account.namespace):\(normalised)").inserted else { continue }
                distinct.append(ConnectedAccount(address: account.address,
                                                 namespace: account.namespace))
            }
        }
        return distinct
    }

    /// Kill the session where cancellation cannot reach it, returning the
    /// failure rather than throwing it. Nil means the session is gone.
    ///
    /// Detached ON PURPOSE, and this is the subtlest load-bearing line in the
    /// file. `connect` runs inside a Task the screen cancels when someone taps
    /// cancel, and cancellation propagates into every `await` below it — which
    /// is right for the WAIT and catastrophic for the KILL. A cancel landing in
    /// the window between settle and teardown would make `disconnect` throw,
    /// make the 1s retry gate throw instantly (a cancelled sleep doesn't
    /// sleep), and strand a live, signable session on the relay: precisely the
    /// outcome this whole design exists to prevent, caused by the person trying
    /// to back out of it. A detached task inherits no cancellation, so once a
    /// session exists its teardown always runs to a real answer.
    ///
    /// Takes the topic, not the `Session`, so nothing non-Sendable crosses into
    /// the detached task.
    private static func tearDownShielded(topic: String) async -> Error? {
        await Task.detached {
            do {
                try await tearDown(topic: topic)
                return nil
            } catch {
                // One retry — a transient relay blip shouldn't strand a session
                // the person can't see. This sleep really sleeps: detached, so
                // no cancellation to short-circuit it.
                try? await Task.sleep(for: .seconds(1))
                do {
                    try await tearDown(topic: topic)
                    return nil
                } catch let second {
                    return second
                }
            }
        }.value
    }

    /// Kill the session. **Throws on purpose — do not `try?` this.**
    ///
    /// Teardown is not cleanup here, it's the feature: the session exists only
    /// long enough to read `accounts`, and a session that outlives that read is
    /// a live pairing the wallet will still honour signing requests on. If this
    /// throws, the promise on the Wallet screen is false until it succeeds, so
    /// the caller must retry or say so out loud — swallowing it is the one
    /// failure mode this whole design exists to avoid. Callers inside `connect`
    /// go through `tearDownShielded`, which adds the retry and the cancellation
    /// shield; this is the bare verb.
    static func tearDown(topic: String) async throws {
        try await Sign.instance.disconnect(topic: topic)
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
