import Foundation
import SwiftData

/// A Safe STATEMENT's refusals, rail and hand-off (prd §913) — the co-signer
/// signing what a Safe says rather than what it spends. `SafeStatement.swift`
/// does the arithmetic and the reading; this file decides whether a
/// signature may happen, and it is one file for `SafeSigner`'s reason: the
/// refusals are the argument, and a second decision site is a second place
/// to forget one.
///
/// **The one refusal that is new here.** §425's fourth refusal — no free-form
/// typed data — is kept by READING the words: a statement is signed only when
/// `SafeStatement` names it (a sign-in whose address is the Safe, a Snapshot
/// vote cast from the Safe). Everything else declines with the hash on
/// screen. A CoW order and a Permit ride this envelope; this is where they
/// stop.
///
/// **Where the words come from.** A request over WalletConnect carries only
/// the inner hash, so the message is fetched from Safe's own service by the
/// hash this file computes for it — the proposer's app posted it there with
/// the first signature — or comes in by paste (tier 0). The hash of what was
/// found must equal the hash asked about, or the words on screen are not the
/// words being signed.
///
/// **The rail.** `getMessageHash(bytes)` is asked of the Safe itself and must
/// agree with the local figure; a read failure refuses. Then the threshold
/// and the owner set, from the chain.
///
/// **This file makes a write** — one signature to Safe's service, on one of
/// two paths (a signature added to a known message, or a message created
/// with its first signature). Both are `POST`s to Safe's own transaction
/// service and nothing else, which `scripts/safe-signer-selftest.sh` holds
/// this file to.
@MainActor
enum SafeStatementSigner {

    enum Refusal: Error, Equatable {
        case noKey
        case chainUnsupported(String)
        case chainUnreadable
        case thresholdTooLow(Int)
        case notAnOwner
        case hashMismatch(local: String, chain: String)
        case requesterHashMismatch(local: String, requester: String)
        /// The words behind the hash could not be found: Safe's service has
        /// no record of this message and nothing was pasted.
        case messageUnknown
        /// Words were found, and they do not hash to what the request names.
        case messageMismatch
        /// Words were found and this app cannot name them. The signer
        /// declines; `why` is the sentence.
        case unreadable(why: String)
        case serviceThrottled(until: Date?)
        case nothingToDo
        case signerNotDeployed(String)
        case signatureNotAccepted
    }

    struct Ready: Equatable {
        let seg: String
        let chainId: Int
        let safeAddress: String
        /// The 32-byte inner hash (EIP-191 or EIP-712), hex.
        let innerHash: String
        /// What this phone signs: the Safe's own hash of the inner one.
        let safeMessageHash: String
        let statement: SafeStatement
        /// The message as Safe's service takes it back: the text verbatim
        /// when `messageIsText`, else the typed data's JSON.
        let messageIsText: Bool
        let messageJSON: String
        let have: Int
        let required: Int
        let signer: SafeSigner.Identity
        /// Whether Safe's service already holds this message — decides which
        /// of the two writes carries the signature.
        let knownToService: Bool
        let standing: SafeSigner.Standing

        /// The message as `SafeStatement.read` and the service take it.
        var message: Any {
            if messageIsText { return messageJSON }
            if let data = messageJSON.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) { return object }
            return messageJSON
        }
    }

    /// The landed-row door: `wallet:safemsg:<seg>:<safeMessageHash>` names
    /// the OUTER hash, so the words are fetched by it first and the inner
    /// hash read off them; then the same refusals as any other statement.
    static func prepare(landedRef ref: String, safe: String) async -> Result<Ready, Refusal>? {
        let bits = ref.split(separator: ":", maxSplits: 3).map(String.init)
        guard bits.count == 4, bits[0] == "wallet", bits[1] == "safemsg" else { return nil }
        guard let chainId = SafeSigner.chainId(seg: bits[2]) else { return .failure(.chainUnsupported(bits[2])) }
        let read = await SafeServiceGate.get("\(gatewayURL(chainId: chainId))/messages/\(bits[3])")
        if case .throttled(let until) = read { return .failure(.serviceThrottled(until: until)) }
        guard let known = serviceMessage(read.json),
              let reading = SafeStatement.read(message: known.message, safe: safe)
        else { return .failure(.messageUnknown) }
        return await prepare(chainId: chainId, safe: safe, innerHash: reading.hash,
                             requesterHash: nil, pasted: known.message)
    }

    // MARK: - Reading the message

    private static func gatewayURL(chainId: Int) -> String {
        "https://safe-client.safe.global/v1/chains/\(chainId)"
    }

    private static func serviceURL(seg: String) -> String {
        "https://api.safe.global/tx-service/\(seg)/api/v1"
    }

    /// One message as the Client Gateway serves it. **UNMEASURED against the
    /// gateway** (2026-09-24, prd §913): built to the gateway's documented
    /// message shape with no network egress from the authoring host. Every
    /// miss reads as "the service does not know this message", which
    /// refuses (`messageUnknown`) — it can never sign something else.
    struct ServiceMessage {
        let message: Any
        let confirmedBy: [String]
        let required: Int?
        let status: String?
    }

    static func serviceMessage(_ root: Any?) -> ServiceMessage? {
        guard let root = root as? [String: Any], let message = root["message"] else { return nil }
        let confirmations = (root["confirmations"] as? [[String: Any]]) ?? []
        let owners = confirmations.compactMap { c -> String? in
            if let owner = c["owner"] as? [String: Any] { return SafeGatewayShape.address(owner["value"]) }
            return SafeGatewayShape.address(c["owner"])
        }
        return ServiceMessage(message: message, confirmedBy: owners.map { $0.lowercased() },
                              required: SafeGatewayShape.int(root["confirmationsRequired"]),
                              status: root["status"] as? String)
    }

    // MARK: - The refusals

    /// Everything that must be true before a Face ID prompt is worth raising.
    /// `requesterHash` is a paired app's own digest of the `SafeMessage`
    /// typed data (nil for a paste); `pasted` is the inner message a person
    /// handed in (nil when the service is to be asked).
    static func prepare(chainId: Int, safe: String, innerHash: [UInt8],
                        requesterHash: [UInt8]?, pasted: Any?) async -> Result<Ready, Refusal> {
        guard SafeSigner.hasAnyKey else { return .failure(.noKey) }
        guard SafeSigner.canSign(chainId: chainId), let seg = SafeSigner.seg(chainId: chainId) else {
            return .failure(.chainUnsupported(String(chainId)))
        }
        guard innerHash.count == 32,
              let localBytes = SafeMessageEncoder.safeMessageHash(chainId: chainId, safe: safe, message: innerHash)
        else { return .failure(.messageMismatch) }
        let local = SafeABI.hex(localBytes)
        if let requesterHash {
            let requester = SafeABI.hex(requesterHash)
            guard local.lowercased() == requester.lowercased() else {
                return .failure(.requesterHashMismatch(local: local, requester: requester))
            }
        }

        // The words. A paste wins; else Safe's service, by the hash we hold.
        var known: ServiceMessage?
        let read = await SafeServiceGate.get("\(gatewayURL(chainId: chainId))/messages/\(local)")
        if case .throttled(let until) = read, pasted == nil {
            return .failure(.serviceThrottled(until: until))
        }
        known = serviceMessage(read.json)
        guard let message = pasted ?? known?.message else { return .failure(.messageUnknown) }
        guard let reading = SafeStatement.read(message: message, safe: safe) else {
            return .failure(.messageMismatch)
        }
        guard reading.hash == innerHash else { return .failure(.messageMismatch) }
        if case .unreadable(let why) = reading.statement { return .failure(.unreadable(why: why)) }

        let identities = await SafeSigner.identities(chainId: chainId)
        let mine = Set(identities.map { $0.address.lowercased() })
        if let known, known.confirmedBy.contains(where: { mine.contains($0) }) {
            return .failure(.nothingToDo)
        }

        // The chain: the threshold, the owner set, and the Safe's own hash.
        guard let railCalldata = SafeMessageEncoder.getMessageHashCalldata(message: innerHash)
        else { return .failure(.messageMismatch) }
        async let thresholdRead = SafeSigner.ethCall(chainId: chainId, to: safe, data: SafeCall.getThresholdSelector)
        async let ownersRead = SafeSigner.ethCall(chainId: chainId, to: safe, data: SafeCall.getOwnersSelector)
        async let railRead = SafeSigner.ethCall(chainId: chainId, to: safe, data: railCalldata)

        guard let thresholdHex = await thresholdRead, let threshold = SafeCall.decodeUInt(thresholdHex)
        else { return .failure(.chainUnreadable) }
        guard threshold >= 2 else { return .failure(.thresholdTooLow(threshold)) }
        guard let ownersHex = await ownersRead, let owners = SafeCall.decodeAddressArray(ownersHex)
        else { return .failure(.chainUnreadable) }
        guard let signer = identities.first(where: { owners.contains($0.address.lowercased()) })
        else { return .failure(.notAnOwner) }
        guard let chainHex = await railRead,
              let chainBytes = SafeABI.hexBytes(chainHex), chainBytes.count == 32
        else { return .failure(.chainUnreadable) }
        let chain = SafeABI.hex(chainBytes)
        guard chain.lowercased() == local.lowercased() else {
            return .failure(.hashMismatch(local: local, chain: chain))
        }
        if signer.kind == .enclave {
            guard let deployed = await SafeEnclaveSigner.proxyDeployed(chainId: chainId, address: signer.address)
            else { return .failure(.chainUnreadable) }
            guard deployed else { return .failure(.signerNotDeployed(signer.address)) }
        }

        let isText = message is String
        let json: String
        if let text = message as? String {
            json = text
        } else if let data = try? JSONSerialization.data(withJSONObject: message, options: [.sortedKeys]) {
            json = String(decoding: data, as: UTF8.self)
        } else {
            return .failure(.messageMismatch)
        }
        return .success(Ready(
            seg: seg, chainId: chainId, safeAddress: safe,
            innerHash: SafeABI.hex(innerHash), safeMessageHash: local,
            statement: reading.statement, messageIsText: isText, messageJSON: json,
            have: known?.confirmedBy.count ?? 0, required: known?.required ?? threshold,
            signer: signer, knownToService: known != nil,
            standing: SafeSigner.Standing(safeAddress: safe, seg: seg,
                                          ownerCount: owners.count, threshold: threshold)))
    }

    // MARK: - The signature

    enum Outcome: Equatable {
        case posted
        /// Signed, handed back unposted: the paired app delivers, or the
        /// service would not take it and the bytes go to the clipboard.
        case signedNotPosted(signature: String, status: Int)
        case refused(Refusal)
        case keyRefused(SignerKey.Failure)
        case enclaveRefused(SafeEnclaveKey.Failure)
    }

    /// Re-checks every refusal, signs, and — when asked — posts.
    static func sign(chainId: Int, safe: String, innerHash: [UInt8], requesterHash: [UInt8]?,
                     pasted: Any?, post: Bool) async -> (Outcome, Ready?) {
        let ready: Ready
        switch await prepare(chainId: chainId, safe: safe, innerHash: innerHash,
                             requesterHash: requesterHash, pasted: pasted) {
        case .success(let value): ready = value
        case .failure(let refusal): return (.refused(refusal), nil)
        }
        guard let hash = SafeABI.hexBytes(ready.safeMessageHash), hash.count == 32 else {
            return (.refused(.messageMismatch), ready)
        }
        let reason = String(localized: "Sign this statement for your Safe")
        let signature: [UInt8]
        switch ready.signer.kind {
        case .k1:
            do {
                signature = try await Task.detached(priority: .userInitiated) {
                    try SignerKey.sign(hash: hash, reason: reason)
                }.value
            } catch let failure as SignerKey.Failure {
                return (.keyRefused(failure), ready)
            } catch {
                return (.keyRefused(.curve), ready)
            }
        case .enclave:
            switch await SafeEnclaveSigner.assert(challenge: hash, chainId: chainId, reason: reason) {
            case .success(let bytes):
                guard let wrapped = SafeWebAuthn.contractSignature(signer: ready.signer.address, data: bytes)
                else { return (.refused(.signatureNotAccepted), ready) }
                signature = wrapped
            case .failure(.noKey): return (.enclaveRefused(.noKey), ready)
            case .failure(.keyRefused(let failure)): return (.enclaveRefused(failure), ready)
            case .failure(.chainUnreadable): return (.refused(.chainUnreadable), ready)
            case .failure(.notAccepted), .failure(.encoding): return (.refused(.signatureNotAccepted), ready)
            }
        }
        let hexSignature = SafeABI.hex(signature)
        guard post else { return (.signedNotPosted(signature: hexSignature, status: 0), ready) }
        let status = await self.post(ready, signature: hexSignature)
        if status == 201 || status == 200 { return (.posted, ready) }
        return (.signedNotPosted(signature: hexSignature, status: status), ready)
    }

    /// The writes. A message the service knows takes a signature on its own
    /// path; one it does not is created with this signature as its first.
    /// Both bodies are read from the service's own serializers
    /// (`SafeMessageSignatureSerializer`: `signature`; `SafeMessageSerializer`:
    /// `message` as a string or an EIP-712 object, plus `signature`).
    private static func post(_ ready: Ready, signature: String) async -> Int {
        if ready.knownToService {
            let (_, status) = await IngestSupport.postJSONStatus(
                "\(serviceURL(seg: ready.seg))/messages/\(ready.safeMessageHash)/signatures/",
                auth: SafeServiceGate.authorization,
                body: ["signature": signature],
                service: "Safe")
            return status
        }
        var message: Any = ready.messageJSON
        if !ready.messageIsText,
           let data = ready.messageJSON.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) {
            message = object
        }
        let (_, status) = await IngestSupport.postJSONStatus(
            "\(serviceURL(seg: ready.seg))/safes/\(EIP55.checksum(ready.safeAddress))/messages/",
            auth: SafeServiceGate.authorization,
            body: ["message": message, "signature": signature],
            service: "Safe")
        return status
    }

    // MARK: - Afterwards

    /// One sentence for what was signed — the statement in its own words.
    static func title(for statement: SafeStatement, signed: Bool) -> String {
        switch statement {
        case .signIn(let siwe):
            return signed
                ? String(localized: "You signed in to \(siwe.domain) as your Safe, from this phone")
                : String(localized: "A sign-in to \(siwe.domain) is waiting for your signature")
        case .snapshotVote(let vote):
            return signed
                ? String(localized: "You voted in \(vote.space) as your Safe, from this phone")
                : String(localized: "A Snapshot vote in \(vote.space) is waiting for your signature")
        case .unreadable:
            return signed
                ? String(localized: "You signed a statement for your Safe from this phone")
                : String(localized: "A statement Casberi can't read is waiting for your signature")
        }
    }

    static func land(context: ModelContext, ready: Ready, posted: Bool) {
        let ref = "wallet:safemsgsigned:\(ready.seg):\(ready.safeMessageHash)"
        var descriptor = FetchDescriptor<Thing>(predicate: #Predicate { $0.sourceRef == ref })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor), !existing.isEmpty { return }
        var title = title(for: ready.statement, signed: true)
        if !posted { title += " — " + String(localized: "Safe's service didn't take it") }
        let thing = Thing(kind: .note, title: title, source: SafeBridge.sourceName, sourceRef: ref)
        thing.walletAddress = ready.safeAddress
        context.insert(thing)
        SpotlightIndex.index([thing])
    }

    // MARK: - The queue

    /// Messages waiting on this phone, for every Safe it signs for — landed
    /// as rows tagged "Your turn" so the digest and the feed say so
    /// (`wallet:safemsg:`), and re-faced once signed. Runs inside the Safe
    /// sync; a phone with no key reads nothing.
    ///
    /// **UNMEASURED against the gateway's list shape** (prd §913): a body
    /// this reader does not understand lands nothing, never a wrong row.
    static func sweep(context: ModelContext, existing: Set<String>) async -> Int {
        guard SafeSigner.hasAnyKey else { return 0 }
        let standing = await SafeSigner.standing()
        guard standing.reachable, !standing.safes.isEmpty else { return 0 }
        var added = 0
        var faces: [(ref: String, title: String, tags: [String])] = []
        for safe in standing.safes {
            guard let chainId = SafeSigner.chainId(seg: safe.seg) else { continue }
            let identities = await SafeSigner.identities(chainId: chainId)
            let mine = Set(identities.map { $0.address.lowercased() })
            let read = await SafeServiceGate.get(
                "\(gatewayURL(chainId: chainId))/safes/\(EIP55.checksum(safe.safeAddress))/messages")
            guard let root = read.json as? [String: Any],
                  let results = root["results"] as? [[String: Any]] else { continue }
            for row in results {
                guard let hash = row["messageHash"] as? String, hash.hasPrefix("0x"),
                      let item = serviceMessage(row) else { continue }
                let ref = "wallet:safemsg:\(safe.seg):\(hash.lowercased())"
                let yourTurn = item.status == "NEEDS_CONFIRMATION"
                    && !item.confirmedBy.contains(where: { mine.contains($0) })
                let statement = SafeStatement.read(message: item.message, safe: safe.safeAddress)?.statement
                    ?? .unreadable(why: "")
                let signedByMe = item.confirmedBy.contains(where: { mine.contains($0) })
                let title = title(for: statement, signed: signedByMe)
                let tags = yourTurn ? ["Your turn"] : []
                if existing.contains(ref) {
                    faces.append((ref, title, tags))
                    continue
                }
                guard yourTurn else { continue }
                let thing = Thing(kind: .note, title: title,
                                  content: "https://app.safe.global/transactions/messages?safe=\(safe.seg):\(EIP55.checksum(safe.safeAddress))",
                                  source: SafeBridge.sourceName, sourceRef: ref)
                thing.walletAddress = safe.safeAddress
                thing.tags = tags
                context.insert(thing)
                SpotlightIndex.index([thing])
                added += 1
            }
        }
        if !faces.isEmpty {
            let landed = IngestSupport.thingsByRef(context, source: SafeBridge.sourceName)
            for face in faces {
                guard let thing = landed[face.ref], thing.isLive else { continue }
                if thing.title != face.title { thing.title = face.title }
                if thing.tags != face.tags { thing.tags = face.tags }
            }
        }
        return added
    }
}
