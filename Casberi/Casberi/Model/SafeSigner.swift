import Foundation
import SwiftData

/// The refusals, the rail, and the hand-off (prd §425, `docs/signer-spec.md`
/// §5/§7/§8) — everything between "a transaction is waiting" and "65 bytes
/// left this phone".
///
/// `SafeTransaction.swift` does the arithmetic and `SignerKey.swift` holds the
/// key; this file is the only place that decides whether a signature may
/// happen at all. It is deliberately one file, because the six refusals below
/// are the entire security argument and a second decision site is a second
/// place to forget one.
///
/// **The rail, and why the encoder is not trusted alone.** Before signing,
/// this asks the Safe contract itself for `getTransactionHash(...)` over the
/// same ten fields and requires the answer to equal the locally computed
/// `safeTxHash`. It refuses on mismatch AND on failure to read. That single
/// `eth_call` turns every possible encoding mistake — a wrong domain
/// separator, a wrong type hash, a mispadded word, an inlined `data` field —
/// into a DECLINE instead of a valid signature over the wrong transaction.
/// It also handles Safe version drift for free: a pre-1.3.0 Safe uses a
/// different EIP-712 domain, disagrees, and is refused, with no version table
/// here to maintain.
///
/// **This file makes Casberi's first outbound write in its history** (§7 tier
/// 1: one `POST` of one signature to Safe's own transaction service, keyless
/// because the signature is its own authorization). That is why it takes the
/// conduct-guard treatment the read-only bridges already have —
/// `scripts/safetx-selftest.sh` fails the build on any other write verb or
/// host appearing here.
@MainActor
enum SafeSigner {

    // MARK: - Where a signature is even possible

    /// A Safe transaction-service segment paired with the chain id its
    /// domain separator carries and the RPC network the rail reads on.
    ///
    /// **A chain is here ONLY if the cross-check can run on it.** That is the
    /// whole rule and it has not changed: a chain where `getTransactionHash`
    /// cannot be read is a chain this app must not sign on, because the local
    /// encoder would be the only witness to what is being authorized.
    ///
    /// `gno` (Gnosis Chain) was absent under that rule until 2026-09-07, when
    /// it turned out the rule was being applied to a fact about ONE FILE —
    /// "`WalletApprovals` carries no Gnosis host" — rather than about the app.
    /// `GnosisPayBridge` has read Gnosis Chain on every wallet pass since
    /// 2026-07-26 through hosts it measured and `NetworkReach` discloses, so
    /// the cross-check has somewhere to run and the refusal no longer follows.
    /// See the rail's own comment for what remains unmeasured.
    private struct Rail: Sendable {
        let seg: String
        let chainId: Int
        /// The `WalletApprovals` network id — its measured keyless hosts. Nil
        /// for a chain read through another bridge's own hosts; see
        /// `reader`.
        let network: String?
        /// Where the cross-check's `eth_call` goes. The rail exists ONLY so
        /// that question has an answer — a chain with no reader is a chain
        /// this app refuses to sign on.
        let reader: Reader

        init(seg: String, chainId: Int, network: String? = nil, reader: Reader = .walletApprovals) {
            self.seg = seg
            self.chainId = chainId
            self.network = network
            self.reader = reader
        }
    }

    /// Whose measured, disclosed hosts answer this chain's `eth_call`.
    ///
    /// Two cases rather than a host list, because this file may not name a
    /// host that is not Safe's own — that is what makes the one-POST conduct
    /// guard checkable (`scripts/safetx-selftest.sh`). Each case delegates to
    /// the bridge that already owns its hosts and already discloses them on
    /// the privacy screen.
    private enum Reader {
        /// `WalletApprovals`' keyless per-chain hosts — five EVM chains.
        case walletApprovals
        /// `GnosisPayBridge`'s two measured Gnosis Chain hosts.
        case gnosisChain
    }

    /// A constant table, so `nonisolated`: the Enclave signer (not main-actor)
    /// reads `chainIDs` off it (prd §913).
    nonisolated private static let rails: [Rail] = [
        Rail(seg: "eth",  chainId: 1,     network: "eth-mainnet"),
        Rail(seg: "base", chainId: 8453,  network: "base-mainnet"),
        Rail(seg: "arb1", chainId: 42161, network: "arb-mainnet"),
        Rail(seg: "oeth", chainId: 10,    network: "opt-mainnet"),
        Rail(seg: "pol",  chainId: 137,   network: "matic-mainnet"),
        // GNOSIS CHAIN, ADDED 2026-09-07 — and the reason it was absent is
        // exactly the reason it may now be here.
        //
        // The original refusal said: "`WalletApprovals` carries no Gnosis
        // host, so the rail could not run there — and a chain where the
        // cross-check cannot run is a chain where this app must not sign."
        // The RULE is untouched and is the whole safety argument. What changed
        // is that its premise was about one file: `GnosisPayBridge` has swept
        // Gnosis Chain on every wallet pass since 2026-07-26 through two hosts
        // it MEASURED (`rpc.gnosischain.com`, `rpc.gnosis.gateway.fm`, both
        // disclosed in `NetworkReach`), so the cross-check does have somewhere
        // to run.
        //
        // This matters more than a sixth chain usually would: a Gnosis Pay
        // account IS a Safe on Gnosis Chain (prd §222), so every card account
        // this app already reads sat on the one chain it refused to sign for.
        //
        // UNMEASURED: those hosts are proven for `eth_getLogs` and
        // `eth_getBlockByNumber`, not for `eth_call`. If they refuse it the
        // read fails, `prepare` returns `.chainUnreadable`, and the app
        // DECLINES — the same answer it gave before, reached the same way. So
        // the worst case of being wrong here is today's behaviour.
        Rail(seg: "gno",  chainId: 100,   reader: .gnosisChain),
    ]

    static func canSign(onSegment seg: String) -> Bool {
        rails.contains { $0.seg == seg }
    }

    static func canSign(chainId: Int) -> Bool {
        rails.contains { $0.chainId == chainId }
    }

    /// Every chain the rail runs on, by id.
    nonisolated static var chainIDs: [Int] { rails.map(\.chainId) }

    static func seg(chainId: Int) -> String? { rails.first { $0.chainId == chainId }?.seg }
    static func chainId(seg: String) -> Int? { rails.first { $0.seg == seg }?.chainId }

    /// One `eth_call` on a rail chain, through the reader that owns and
    /// discloses its hosts — lent to the statement, recovery and Enclave
    /// signers (prd §913) so every signature in this app crosses the same
    /// six rails and no other file names a host.
    static func ethCall(chainId: Int, to: String, data: String) async -> String? {
        guard let rail = rails.first(where: { $0.chainId == chainId }) else { return nil }
        return await call(rail, to: to, data: data)
    }

    /// `eth_getCode`, same rails. Nil when the chain did not answer.
    static func ethGetCode(chainId: Int, address: String) async -> String? {
        guard let rail = rails.first(where: { $0.chainId == chainId }) else { return nil }
        let params: [Any] = [address, "latest"]
        switch rail.reader {
        case .walletApprovals:
            guard let network = rail.network else { return nil }
            return await WalletApprovals.rpcRead(
                network: network, method: "eth_getCode", params: params) as? String
        case .gnosisChain:
            return await GnosisPayBridge.read(method: "eth_getCode", params: params) as? String
        }
    }

    // MARK: - Which key is speaking

    /// One of this phone's two keys, and the address the Safe knows it by
    /// (prd §913). The §425 key is an EOA and its address is its own; the
    /// Secure Enclave key is a CONTRACT owner whose address is read from
    /// Safe's passkey factory, per chain, so it is nil on a chain the
    /// factory never reached.
    struct Identity: Equatable {
        enum Kind: Equatable { case k1, enclave }
        let kind: Kind
        let address: String
    }

    /// Both keys, where each can speak on this chain. The K1 key first: it
    /// is the one §425 built and the one most Safes name.
    static func identities(chainId: Int) async -> [Identity] {
        var out: [Identity] = []
        if let k1 = SignerKey.address() { out.append(Identity(kind: .k1, address: k1)) }
        if SafeEnclaveKey.exists, let proxy = await SafeEnclaveSigner.signerAddress(chainId: chainId) {
            out.append(Identity(kind: .enclave, address: proxy))
        }
        return out
    }

    /// Whether either key exists — the screen's "is this phone a signer".
    static var hasAnyKey: Bool { SignerKey.exists || SafeEnclaveKey.exists }

    // MARK: - Where this phone stands, and the one way a Safe can die

    /// One Safe this phone is an owner of, read from the CHAIN.
    ///
    /// **`hasNoSpareOwner` is the most consequential fact this app can state
    /// about a Safe** (prd §426 amendment, user: "we can't create a risk for a
    /// situation where a multisig would be locked"). In an N-of-N — two owners
    /// and a threshold of two, three and three — every owner is load-bearing:
    /// lose ANY one key and the Safe can never meet its threshold again. And
    /// owner management is not an escape hatch, because `swapOwner`,
    /// `removeOwner` and `changeThreshold` are ordinary Safe transactions
    /// executed BY the Safe on itself and need the threshold met like anything
    /// else. There is no admin path. The funds are finished.
    ///
    /// This app cannot avoid creating that exposure by choosing a Keychain
    /// flag: a device-only key with no seed phrase can die with the phone
    /// whatever gates it, and prd §425 accepts that explicitly. What it can do
    /// is refuse to let somebody walk into an N-of-N without being told.
    ///
    /// **A module is the one real escape and is deliberately not counted.**
    /// An enabled Safe module executes without signatures, so a Safe with a
    /// recovery module installed can dig itself out — but nothing here can
    /// tell a recovery module from any other kind, and a warning softened by a
    /// module we have not read is a warning that lies in the safe direction
    /// on the screen where that costs most.
    struct Standing: Equatable {
        let safeAddress: String
        let seg: String
        let ownerCount: Int
        let threshold: Int

        /// Every owner load-bearing — losing one ends the Safe.
        var hasNoSpareOwner: Bool { ownerCount > 0 && ownerCount == threshold }
        /// How many owners could be lost before the Safe is stuck.
        var spareOwners: Int { max(0, ownerCount - threshold) }
    }

    struct StandingReport: Equatable {
        var safes: [Standing] = []
        /// False when nothing answered. An empty list from a REACHABLE read
        /// means "you are not an owner of anything yet", which is the ordinary
        /// state right after making a key; an empty list from an unreachable
        /// one means nothing at all, and the two must not read alike.
        var reachable = true
        var truncated = false

        var needingASpareOwner: [Standing] { safes.filter(\.hasNoSpareOwner) }
    }

    /// Every Safe this phone signs for, with the shape of its owner set.
    ///
    /// Discovery rides Safe's own reverse index (there is no cheap on-chain
    /// way to ask "what am I an owner of"); the FACTS that decide the warning
    /// are then read from the chain, because a cached config is exactly what
    /// an attacker holding the desktop key would change.
    static func standing(budget: Duration = .seconds(8)) async -> StandingReport {
        // Both keys' addresses (prd §913). The Enclave owner's is the same on
        // every chain the factory reached, so one cached read names it.
        var mine: [String] = []
        if let k1 = SignerKey.address() { mine.append(k1) }
        if SafeEnclaveKey.exists, let proxy = SafeEnclaveSigner.anyCachedAddress() { mine.append(proxy) }
        guard !mine.isEmpty else { return StandingReport() }
        let lookup = await SafeBridge.signerSafes(for: mine, budget: budget,
                                                  requireExecuted: false)
        var report = StandingReport(reachable: lookup.reachable, truncated: lookup.truncated)
        let lowered = Set(mine.map { $0.lowercased() })
        for found in lookup.safes {
            guard let rail = rails.first(where: { $0.seg == found.chain }) else { continue }
            async let ownersRead = call(rail, to: found.address, data: SafeCall.getOwnersSelector)
            async let thresholdRead = call(rail, to: found.address, data: SafeCall.getThresholdSelector)
            guard let ownersHex = await ownersRead,
                  let owners = SafeCall.decodeAddressArray(ownersHex),
                  let thresholdHex = await thresholdRead,
                  let threshold = SafeCall.decodeUInt(thresholdHex),
                  owners.contains(where: { lowered.contains($0) })
            else { continue }
            report.safes.append(Standing(safeAddress: found.address, seg: found.chain,
                                         ownerCount: owners.count, threshold: threshold))
        }
        return report
    }

    // MARK: - The verdict

    /// Why this app will not sign. Every case is a REFUSAL with a sentence,
    /// never a silent nil — a co-signer that declines without saying why is
    /// indistinguishable from one that is broken, and the person's next move
    /// differs for each of these.
    enum Refusal: Error, Equatable {
        /// No key on this phone yet.
        case noKey
        /// The transaction service did not answer, or answered a shape this
        /// build cannot read.
        case proposalUnreadable
        /// Safe's shared keyless quota refused the read (prd §789). Not
        /// `proposalUnreadable`: nothing is wrong with the proposal, and the
        /// sentence for that one sends somebody looking for a fault that
        /// isn't there. `until` is Safe's own reset, when it sent one.
        case serviceThrottled(until: Date?)
        /// The chain did not answer. NOT the same as a mismatch: not knowing
        /// is not knowing it is fine.
        case chainUnreadable
        /// Signing is not offered on this chain at all (see `rails`).
        case chainUnsupported(String)
        /// A 1-of-N Safe naming this phone is a custodial wallet wearing a
        /// multisig's clothes — the entire promise is void, so this refuses
        /// even though the signature would be accepted.
        case thresholdTooLow(Int)
        /// The chain does not currently list this phone as an owner.
        case notAnOwner
        /// The local encoder and the Safe contract disagree. The one refusal
        /// that means something is WRONG rather than merely not ready.
        case hashMismatch(local: String, chain: String)
        /// The transaction service's own `safeTxHash` is not the hash of the
        /// fields it sent alongside it. Caught separately from the chain
        /// mismatch because it accuses a different party.
        case serviceHashMismatch(local: String, service: String)
        /// Already executed, or already signed by this phone.
        case nothingToDo
        /// A paired app's own digest of the typed data it sent is not the
        /// hash of the fields it sent — the service-mismatch refusal, for a
        /// requester that is not Safe's service (prd §913).
        case requesterHashMismatch(local: String, requester: String)
        /// The Safe names this phone's Enclave owner, but the owner's proxy
        /// has no code yet: the desktop has to run the factory's
        /// `createSigner` before any signature from it can verify.
        case signerNotDeployed(String)
        /// The factory verified the Enclave assertion and did not accept it.
        /// The bytes are discarded.
        case signatureNotAccepted
    }

    /// A transaction that has passed every refusal and is ready for a tap.
    /// Holding the hash and the ten fields means the screen and the signature
    /// cannot drift apart between the check and the tap.
    struct Ready: Equatable {
        let seg: String
        let chainId: Int
        let safeAddress: String
        let safeTxHash: String
        let tx: SafeTransaction
        let reading: SafeCalldata
        let have: Int
        let required: Int
        /// The owner set this transaction was checked against — already read
        /// for the refusals, so carrying it costs nothing and saves the sign
        /// screen a second round trip to say whether this Safe has a spare
        /// owner.
        let standing: Standing
        /// Which of this phone's keys the Safe lists (prd §913).
        let signer: Identity

        /// This very transaction is the repair for `hasNoSpareOwner`: it adds
        /// an owner without raising the threshold to match. Worth naming,
        /// because it is the one transaction somebody in that state should be
        /// hurried through rather than warned about.
        var addsASpareOwner: Bool {
            guard case .addOwner(_, let threshold) = reading else { return false }
            return (Int(threshold) ?? .max) <= standing.threshold
        }
    }

    // MARK: - Reading the proposal

    /// The WRITE's host. One `POST`, to Safe's transaction service, because
    /// that is where a confirmation has to land — the Client Gateway the
    /// reads moved to (prd §789b) is a read path.
    private static func baseURL(_ seg: String) -> String {
        "https://api.safe.global/tx-service/\(seg)/api/v1"
    }

    /// The READ's host — Safe's own Client Gateway, which takes a bare
    /// `safeTxHash` as a transaction id (measured §789b). The proposal read
    /// moved here with the rest for §789's reason: the transaction service
    /// meters keyless callers against one exhausted pool, so leaving this
    /// read there would have left SIGNING broken for the same reason the
    /// room was.
    ///
    /// Safe-owned either way, which is the rule `safetx-selftest.sh` holds
    /// this file to — it reaches Safe and nothing else.
    private static func gatewayURL(_ rail: Rail) -> String {
        "https://safe-client.safe.global/v1/chains/\(rail.chainId)"
    }

    /// A uint256 field that arrives as a String in v2 and an Int in v1 of the
    /// service's own serializer, and must be one string here. Nil rather than
    /// a zero default — a `baseGas` we failed to read is a different
    /// transaction, and the rail would catch it, but only after asking
    /// somebody to look at a screen built from a guess.
    static func amountField(_ value: Any?) -> String? {
        if let s = value as? String { return s.isEmpty ? "0" : s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    /// An address field the service may send as `null` (`gasToken` and
    /// `refundReceiver` routinely are). Null legitimately MEANS the zero
    /// address here, which is the one place a default is correct — and the
    /// rail proves it, since a Safe that meant something else disagrees.
    static func addressField(_ value: Any?) -> String {
        (value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? SafeTransaction.zeroAddress
    }

    /// The ten fields, out of one transaction-service object.
    static func transaction(from row: [String: Any]) -> SafeTransaction? {
        guard let to = row["to"] as? String,
              let value = amountField(row["value"]),
              let safeTxGas = amountField(row["safeTxGas"]),
              let baseGas = amountField(row["baseGas"]),
              let gasPrice = amountField(row["gasPrice"])
        else { return nil }
        // `operation` and `nonce` are small enough to be Ints on every
        // serializer version, but v2 sends `nonce` as a string.
        let operation = (row["operation"] as? Int)
            ?? (row["operation"] as? NSNumber)?.intValue
            ?? Int(row["operation"] as? String ?? "")
        let nonce = (row["nonce"] as? Int)
            ?? (row["nonce"] as? NSNumber)?.intValue
            ?? Int(row["nonce"] as? String ?? "")
        guard let operation, let nonce, operation >= 0, nonce >= 0 else { return nil }
        return SafeTransaction(
            to: to,
            value: value,
            data: (row["data"] as? String) ?? "",
            operation: operation,
            safeTxGas: safeTxGas,
            baseGas: baseGas,
            gasPrice: gasPrice,
            gasToken: addressField(row["gasToken"]),
            refundReceiver: addressField(row["refundReceiver"]),
            nonce: nonce)
    }

    // MARK: - The six refusals

    /// Everything that must be true before a Face ID prompt is worth raising,
    /// for a proposal read from Safe's own service.
    ///
    /// Ordered cheapest-first only where that is free: the threshold and the
    /// owner set are read from the CHAIN and not from a cached
    /// `SafeBridge` config, because both are exactly the facts an attacker
    /// with the desktop key would change, and a cache is what they would beat.
    static func prepare(seg: String, safeTxHash: String) async -> Result<Ready, Refusal> {
        await ClearSign.warm()
        guard hasAnyKey else { return .failure(.noKey) }
        guard let rail = rails.first(where: { $0.seg == seg }) else {
            return .failure(.chainUnsupported(seg))
        }
        let read = await SafeServiceGate.get("\(gatewayURL(rail))/transactions/\(safeTxHash)")
        if case .throttled(let until) = read { return .failure(.serviceThrottled(until: until)) }
        guard let row = SafeGatewayShape.txRow(read.json),
              let safeAddress = row["safe"] as? String,
              let tx = transaction(from: row)
        else { return .failure(.proposalUnreadable) }

        if (row["isExecuted"] as? Bool) == true { return .failure(.nothingToDo) }
        let confirmations = (row["confirmations"] as? [[String: Any]]) ?? []
        let identities = await identities(chainId: rail.chainId)
        let mine = Set(identities.map { $0.address.lowercased() })
        if confirmations.contains(where: {
            mine.contains(($0["owner"] as? String)?.lowercased() ?? "")
        }) { return .failure(.nothingToDo) }

        // (3) The local encoder against the service's own claim. The service
        // is not the chain, so this is a consistency check on what we were
        // SENT — the fields and the hash must describe each other — and the
        // chain check below is the one that decides.
        guard let localBytes = SafeTxEncoder.safeTxHash(chainId: rail.chainId,
                                                        safe: safeAddress, tx: tx)
        else { return .failure(.proposalUnreadable) }
        let local = SafeABI.hex(localBytes)
        guard local.lowercased() == safeTxHash.lowercased() else {
            return .failure(.serviceHashMismatch(local: local, service: safeTxHash))
        }
        return await verify(rail: rail, safeAddress: safeAddress, tx: tx, local: local,
                            identities: identities, row: row)
    }

    /// The same refusals for a transaction that arrived IN HAND — from a
    /// paired app over WalletConnect, or pasted (prd §913). There is no
    /// service row to compare against; the requester's own digest of the
    /// typed data stands in for the service's hash, and the chain decides.
    /// The service is still asked, once, for what it knows — whether this
    /// hash executed already or this phone already signed it — and a service
    /// that does not know the hash yet is the ordinary case for the FIRST
    /// signature, not a refusal.
    static func prepare(chainId: Int, safe: String, tx: SafeTransaction,
                        requesterHash: [UInt8]) async -> Result<Ready, Refusal> {
        await ClearSign.warm()
        guard hasAnyKey else { return .failure(.noKey) }
        guard let rail = rails.first(where: { $0.chainId == chainId }) else {
            return .failure(.chainUnsupported(String(chainId)))
        }
        guard let localBytes = SafeTxEncoder.safeTxHash(chainId: chainId, safe: safe, tx: tx)
        else { return .failure(.proposalUnreadable) }
        let local = SafeABI.hex(localBytes)
        let requester = SafeABI.hex(requesterHash)
        guard local.lowercased() == requester.lowercased() else {
            return .failure(.requesterHashMismatch(local: local, requester: requester))
        }
        let identities = await identities(chainId: chainId)
        let mine = Set(identities.map { $0.address.lowercased() })
        // What the service knows, if it knows this hash at all. `.missing`
        // is the first signature's ordinary state and leaves the row empty.
        var row: [String: Any] = [:]
        let read = await SafeServiceGate.get("\(gatewayURL(rail))/transactions/\(local)")
        if let known = SafeGatewayShape.txRow(read.json) {
            if (known["isExecuted"] as? Bool) == true { return .failure(.nothingToDo) }
            let confirmations = (known["confirmations"] as? [[String: Any]]) ?? []
            if confirmations.contains(where: {
                mine.contains(($0["owner"] as? String)?.lowercased() ?? "")
            }) { return .failure(.nothingToDo) }
            row = known
        }
        return await verify(rail: rail, safeAddress: safe, tx: tx, local: local,
                            identities: identities, row: row)
    }

    /// Refusals (1), (2) and (4), from the chain — ONE decision site for both
    /// doors above, because the six refusals are the entire security
    /// argument and a second copy is a second place to forget one.
    private static func verify(rail: Rail, safeAddress: String, tx: SafeTransaction, local: String,
                               identities: [Identity], row: [String: Any]) async -> Result<Ready, Refusal> {
        // (1) and (2) — from the chain, never from a local flag.
        guard let railCalldata = SafeCall.getTransactionHash(tx) else {
            return .failure(.proposalUnreadable)
        }
        async let thresholdRead = call(rail, to: safeAddress, data: SafeCall.getThresholdSelector)
        async let ownersRead = call(rail, to: safeAddress, data: SafeCall.getOwnersSelector)
        async let railRead = call(rail, to: safeAddress, data: railCalldata)

        guard let thresholdHex = await thresholdRead,
              let threshold = SafeCall.decodeUInt(thresholdHex)
        else { return .failure(.chainUnreadable) }
        guard threshold >= 2 else { return .failure(.thresholdTooLow(threshold)) }

        guard let ownersHex = await ownersRead,
              let owners = SafeCall.decodeAddressArray(ownersHex)
        else { return .failure(.chainUnreadable) }
        // Whichever of this phone's keys the Safe lists speaks (prd §913);
        // the guard below is the refusal, and it is one line so the harness
        // can hold it.
        guard let signer = identities.first(where: { owners.contains($0.address.lowercased()) })
                ?? identities.first
        else { return .failure(.noKey) }
        let me = signer.address
        guard owners.contains(me.lowercased()) else { return .failure(.notAnOwner) }

        // (4) THE RAIL. A read failure is a refusal, not a pass — the whole
        // point is that we never sign a hash we computed alone.
        guard let chainHex = await railRead,
              let chainBytes = SafeABI.hexBytes(chainHex), chainBytes.count == 32
        else { return .failure(.chainUnreadable) }
        let chain = SafeABI.hex(chainBytes)
        guard chain.lowercased() == local.lowercased() else {
            return .failure(.hashMismatch(local: local, chain: chain))
        }

        // An Enclave owner is a contract, and a contract with no code cannot
        // answer `isValidSignature` — the desktop's `createSigner` is the
        // missing step, and saying so beats a signature Safe's service
        // rejects with a 422 nobody can read.
        if signer.kind == .enclave {
            guard let deployed = await SafeEnclaveSigner.proxyDeployed(chainId: rail.chainId, address: me)
            else { return .failure(.chainUnreadable) }
            guard deployed else { return .failure(.signerNotDeployed(me)) }
        }

        let confirmations = (row["confirmations"] as? [[String: Any]]) ?? []
        let required = (row["confirmationsRequired"] as? Int) ?? threshold
        return .success(Ready(
            seg: rail.seg, chainId: rail.chainId, safeAddress: safeAddress,
            safeTxHash: local, tx: tx,
            // The chain opens the clear-signing registry for a call the
            // reader cannot name (prd §834). No token read here: this file
            // reaches Safe and nothing else, and the sign block states an
            // amount in base units unless the descriptor itself names the
            // token — the same rule it keeps for a plain `transfer`.
            reading: SafeCalldata.read(data: tx.data, to: tx.to, value: tx.value, safe: safeAddress,
                                       chainId: rail.chainId, style: .casberi()),
            have: confirmations.count, required: required,
            standing: Standing(safeAddress: safeAddress, seg: rail.seg,
                               ownerCount: owners.count, threshold: threshold),
            signer: signer))
    }

    private static func call(_ rail: Rail, to: String, data: String) async -> String? {
        let params: [Any] = [["to": to, "data": data], "latest"]
        switch rail.reader {
        case .walletApprovals:
            guard let network = rail.network else { return nil }
            return await WalletApprovals.rpcRead(
                network: network, method: "eth_call", params: params) as? String
        case .gnosisChain:
            return await GnosisPayBridge.read(method: "eth_call", params: params) as? String
        }
    }

    // MARK: - The signature, and the only place it leaves

    enum Outcome: Equatable {
        case posted
        /// Signed, but the service would not take it. The 65 bytes are handed
        /// back so tier 0 (paste / share) still works — a signature this
        /// phone already made must never be thrown away because a third
        /// party was down. The paired-app door (prd §913) returns this on
        /// purpose with `status: 0`: the app that asked delivers.
        case signedNotPosted(signature: String, status: Int)
        case refused(Refusal)
        case keyRefused(SignerKey.Failure)
        /// The Enclave key would not sign — a cancelled prompt, a destroyed
        /// item (prd §913). Its own case, because its sentences differ.
        case enclaveRefused(SafeEnclaveKey.Failure)
    }

    /// Re-checks EVERY refusal, signs, and posts. The re-check is not
    /// belt-and-braces: `prepare` ran when the screen was drawn, and an owner
    /// can be removed or a threshold dropped to 1 between then and the tap.
    static func sign(seg: String, safeTxHash: String) async -> Outcome {
        let ready: Ready
        switch await prepare(seg: seg, safeTxHash: safeTxHash) {
        case .success(let value): ready = value
        case .failure(let refusal): return .refused(refusal)
        }
        return await signVerified(ready, post: true)
    }

    /// The paired-app door (prd §913): the same re-check over the fields in
    /// hand, then the signature handed BACK rather than posted — the app
    /// that asked is the one delivering it to Safe's service, and a second
    /// post of the same signature is a 422 nobody reads.
    static func sign(chainId: Int, safe: String, tx: SafeTransaction,
                     requesterHash: [UInt8]) async -> Outcome {
        let ready: Ready
        switch await prepare(chainId: chainId, safe: safe, tx: tx, requesterHash: requesterHash) {
        case .success(let value): ready = value
        case .failure(let refusal): return .refused(refusal)
        }
        return await signVerified(ready, post: false)
    }

    /// The signature itself, by whichever key the Safe lists. Every refusal
    /// has already passed on THIS `Ready`; nothing here decides anything.
    private static func signVerified(_ ready: Ready, post: Bool) async -> Outcome {
        guard let hash = SafeABI.hexBytes(ready.safeTxHash), hash.count == 32 else {
            return .refused(.proposalUnreadable)
        }
        let reason = String(localized: "Sign this Safe transaction")
        let signature: [UInt8]
        switch ready.signer.kind {
        case .k1:
            do {
                // OFF THE MAIN ACTOR, and not as a nicety. `SecItemCopyMatching`
                // against a biometry-gated item BLOCKS until the person answers
                // the Face ID prompt — on the main thread that is the whole UI
                // frozen behind a system sheet, for as long as they take to look
                // at it. This enum is `@MainActor` (it touches the model context
                // and the screen state), so the one blocking call in the flow is
                // the one thing that has to leave it.
                signature = try await Task.detached(priority: .userInitiated) {
                    try SignerKey.sign(hash: hash, reason: reason)
                }.value
            } catch let failure as SignerKey.Failure {
                return .keyRefused(failure)
            } catch {
                return .keyRefused(.curve)
            }
        case .enclave:
            // The Enclave assertion, verified by Safe's factory before it
            // leaves (prd §913), wrapped as the contract signature the Safe's
            // own `checkNSignatures` reads (`v = 0`).
            switch await SafeEnclaveSigner.assert(challenge: hash, chainId: ready.chainId, reason: reason) {
            case .success(let bytes):
                guard let wrapped = SafeWebAuthn.contractSignature(signer: ready.signer.address, data: bytes)
                else { return .refused(.proposalUnreadable) }
                signature = wrapped
            case .failure(.noKey):
                return .enclaveRefused(.noKey)
            case .failure(.keyRefused(let failure)):
                return .enclaveRefused(failure)
            case .failure(.chainUnreadable):
                return .refused(.chainUnreadable)
            case .failure(.notAccepted), .failure(.encoding):
                return .refused(.signatureNotAccepted)
            }
        }
        let hexSignature = SafeABI.hex(signature)
        guard post else { return .signedNotPosted(signature: hexSignature, status: 0) }
        let status = await self.post(seg: ready.seg, safeTxHash: ready.safeTxHash,
                                     signature: hexSignature)
        // 201 Created is the documented success; 200 is accepted too rather
        // than treated as a failure, since a signature that really did land
        // must not be reported as lost.
        if status == 201 || status == 200 { return .posted }
        return .signedNotPosted(signature: hexSignature, status: status)
    }

    // MARK: - Afterwards

    /// The signature lands as a thing, so the corpus ends up holding the whole
    /// arc — proposed (`wallet:safe:`), signed (here), executed or replaced
    /// (`wallet:safeoutcome:`). Same `wallet:safe…` ref family as its
    /// siblings, so `SafeBridge.retagToOwnSource` and
    /// `scripts/ref-shape-audit.py` both keep seeing one shape.
    ///
    /// `posted` is on the ROW, not implied: a signature Safe's service refused
    /// still exists and still counts, and the row is the only place that fact
    /// survives once the toast is gone.
    static func land(context: ModelContext, ready: Ready, posted: Bool) {
        let ref = "wallet:safesigned:\(ready.seg):\(ready.safeTxHash)"
        var descriptor = FetchDescriptor<Thing>(predicate: #Predicate { $0.sourceRef == ref })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor), !existing.isEmpty { return }
        let title = posted
            ? String(localized: "You signed a Safe transaction from this phone")
            : String(localized: "You signed a Safe transaction from this phone — Safe's service didn't take it")
        let thing = Thing(kind: .transaction, title: title,
                          source: SafeBridge.sourceName, sourceRef: ref)
        thing.walletAddress = ready.safeAddress
        context.insert(thing)
        SpotlightIndex.index([thing])
    }

    /// **The only write this app makes.** One `POST`, one signature, to Safe's
    /// own transaction service. The signature is its own authorization — the
    /// service verifies it against the Safe's owner set before storing it —
    /// and `SafeServiceGate.authorization` rides along only so this write
    /// draws on the same quota the reads do (nil while no key ships, which is
    /// today: prd §789).
    ///
    /// The body shape and the path are read from the service's OWN source
    /// (`SafeMultisigConfirmationSerializer`: a single `signature` field, hex,
    /// at least 65 bytes; `multisig-transactions/<hash>/confirmations/`),
    /// not from docs prose — the spec flagged this as the one thing to
    /// re-measure before writing it.
    private static func post(seg: String, safeTxHash: String, signature: String) async -> Int {
        let (_, status) = await IngestSupport.postJSONStatus(
            "\(baseURL(seg))/multisig-transactions/\(safeTxHash)/confirmations/",
            auth: SafeServiceGate.authorization,
            body: ["signature": signature],
            service: "Safe")
        return status
    }
}
