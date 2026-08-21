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
    /// `gno` (Gnosis Chain) is deliberately ABSENT, and absent rather than
    /// guessed: `WalletApprovals` carries no Gnosis host, so the rail could
    /// not run there — and a chain where the cross-check cannot run is a
    /// chain where this app must not sign. `SafeBridge` still READS Gnosis
    /// Safes exactly as before; only signing declines, and it says so.
    private struct Rail {
        let seg: String
        let chainId: Int
        /// The `WalletApprovals` network id — its measured keyless hosts.
        let network: String
    }
    private static let rails: [Rail] = [
        Rail(seg: "eth",  chainId: 1,     network: "eth-mainnet"),
        Rail(seg: "base", chainId: 8453,  network: "base-mainnet"),
        Rail(seg: "arb1", chainId: 42161, network: "arb-mainnet"),
        Rail(seg: "oeth", chainId: 10,    network: "opt-mainnet"),
        Rail(seg: "pol",  chainId: 137,   network: "matic-mainnet"),
    ]

    static func canSign(onSegment seg: String) -> Bool {
        rails.contains { $0.seg == seg }
    }

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
        guard let me = SignerKey.address() else { return StandingReport() }
        let lookup = await SafeBridge.signerSafes(for: [me], budget: budget,
                                                  requireExecuted: false)
        var report = StandingReport(reachable: lookup.reachable, truncated: lookup.truncated)
        for found in lookup.safes {
            guard let rail = rails.first(where: { $0.seg == found.chain }) else { continue }
            async let ownersRead = call(rail, to: found.address, data: SafeCall.getOwnersSelector)
            async let thresholdRead = call(rail, to: found.address, data: SafeCall.getThresholdSelector)
            guard let ownersHex = await ownersRead,
                  let owners = SafeCall.decodeAddressArray(ownersHex),
                  let thresholdHex = await thresholdRead,
                  let threshold = SafeCall.decodeUInt(thresholdHex),
                  owners.contains(me.lowercased())
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

    private static func baseURL(_ seg: String) -> String {
        "https://api.safe.global/tx-service/\(seg)/api/v1"
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

    /// Everything that must be true before a Face ID prompt is worth raising.
    ///
    /// Ordered cheapest-first only where that is free: the threshold and the
    /// owner set are read from the CHAIN and not from a cached
    /// `SafeBridge` config, because both are exactly the facts an attacker
    /// with the desktop key would change, and a cache is what they would beat.
    static func prepare(seg: String, safeTxHash: String) async -> Result<Ready, Refusal> {
        guard let me = SignerKey.address() else { return .failure(.noKey) }
        guard let rail = rails.first(where: { $0.seg == seg }) else {
            return .failure(.chainUnsupported(seg))
        }
        guard let row = await IngestSupport.getJSON(
                "\(baseURL(seg))/multisig-transactions/\(safeTxHash)/") as? [String: Any],
              let safeAddress = row["safe"] as? String,
              let tx = transaction(from: row)
        else { return .failure(.proposalUnreadable) }

        if (row["isExecuted"] as? Bool) == true { return .failure(.nothingToDo) }
        let confirmations = (row["confirmations"] as? [[String: Any]]) ?? []
        if confirmations.contains(where: {
            ($0["owner"] as? String)?.lowercased() == me.lowercased()
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

        let required = (row["confirmationsRequired"] as? Int) ?? threshold
        return .success(Ready(
            seg: seg, chainId: rail.chainId, safeAddress: safeAddress,
            safeTxHash: local, tx: tx,
            reading: SafeCalldata.read(data: tx.data, to: tx.to, value: tx.value, safe: safeAddress),
            have: confirmations.count, required: required,
            standing: Standing(safeAddress: safeAddress, seg: seg,
                               ownerCount: owners.count, threshold: threshold)))
    }

    private static func call(_ rail: Rail, to: String, data: String) async -> String? {
        await WalletApprovals.rpcRead(
            network: rail.network, method: "eth_call",
            params: [["to": to, "data": data], "latest"]) as? String
    }

    // MARK: - The signature, and the only place it leaves

    enum Outcome: Equatable {
        case posted
        /// Signed, but the service would not take it. The 65 bytes are handed
        /// back so tier 0 (paste / share) still works — a signature this
        /// phone already made must never be thrown away because a third
        /// party was down.
        case signedNotPosted(signature: String, status: Int)
        case refused(Refusal)
        case keyRefused(SignerKey.Failure)
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
        guard let hash = SafeABI.hexBytes(ready.safeTxHash), hash.count == 32 else {
            return .refused(.proposalUnreadable)
        }
        let signature: [UInt8]
        let reason = String(localized: "Sign this Safe transaction")
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
        let hexSignature = SafeABI.hex(signature)
        let status = await post(seg: ready.seg, safeTxHash: ready.safeTxHash,
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
    /// own transaction service — keyless, because the signature is its own
    /// authorization and the service verifies it against the Safe's owner set
    /// before storing it.
    ///
    /// The body shape and the path are read from the service's OWN source
    /// (`SafeMultisigConfirmationSerializer`: a single `signature` field, hex,
    /// at least 65 bytes; `multisig-transactions/<hash>/confirmations/`),
    /// not from docs prose — the spec flagged this as the one thing to
    /// re-measure before writing it.
    private static func post(seg: String, safeTxHash: String, signature: String) async -> Int {
        let (_, status) = await IngestSupport.postJSONStatus(
            "\(baseURL(seg))/multisig-transactions/\(safeTxHash)/confirmations/",
            body: ["signature": signature],
            service: "Safe")
        return status
    }
}
