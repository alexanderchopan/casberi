import Foundation
import SwiftData

/// A recovery GUARDIAN's refusals, rail and hand-off (prd §913). This phone
/// as one of the guardians a Safe's owner named on Candide's
/// `SocialRecoveryModule`: its signature approves ONE owner set for ONE
/// wallet at ONE nonce, the module needs a threshold of guardians and then
/// waits out its delay, and nothing about the key can spend.
///
/// **Everything is read off the module the request names, never a table.**
/// The request carries the module's address in its typed-data domain; before
/// signing, this file asks that contract who it is (`NAME()` and
/// `VERSION()` must be the module's own), asks the wallet whether the module
/// is enabled on it, asks the module whether this phone is a guardian, what
/// the guardian threshold is, and what the wallet's recovery nonce is — and
/// asks the module for `getRecoveryHash` over the same fields, which must
/// equal the local figure. A fake module can only ever be signed for if the
/// wallet's own owners enabled it, which is their act, not this key's.
///
/// **Two refusals carry the promise.** A guardian threshold of 1 makes this
/// key a master key with a delay on it — refused, §425's threshold rule in
/// its second home. And a request at a stale nonce is a request the module
/// will reject, so the phone declines rather than raise a Face ID for
/// nothing.
///
/// **No write.** The signature goes back to the app that asked (over
/// WalletConnect) or to the clipboard (a paste); whoever collects the
/// guardians submits `multiConfirmRecovery`. This file names no host.
@MainActor
enum SafeRecoverySigner {

    enum Refusal: Error, Equatable {
        case noKey
        case chainUnsupported(String)
        case chainUnreadable
        /// The contract at the request's address does not call itself the
        /// module.
        case notARecoveryModule
        /// The module's own version is not the one the request's domain
        /// names — the hash would be wrong, and the rail would refuse; this
        /// says why first.
        case versionMismatch(module: String)
        /// The wallet does not list this module as enabled.
        case moduleNotEnabled
        /// The module does not list this phone as a guardian of the wallet.
        case notAGuardian
        /// A lone guardian is a master key on a delay.
        case guardianThresholdTooLow(Int)
        /// The request's nonce is not the wallet's current recovery nonce.
        case staleNonce(module: Int)
        case hashMismatch(local: String, chain: String)
        case requesterHashMismatch(local: String, requester: String)
        /// The fields could not be encoded (an empty owner set, a threshold
        /// above the owner count).
        case unreadable
    }

    struct Ready: Equatable {
        let request: SafeRecovery.Request
        let seg: String
        /// The recovery hash, hex — what this phone signs.
        let hash: String
        let currentOwners: [String]
        let currentThreshold: Int
        let guardianThreshold: Int
        let guardianCount: Int
        let signer: SafeSigner.Identity
        /// A recovery already scheduled for this wallet, if any.
        let pending: SafeRecovery.PendingRecovery?
    }

    // MARK: - The refusals

    static func prepare(_ request: SafeRecovery.Request, requesterHash: [UInt8]?) async -> Result<Ready, Refusal> {
        guard SafeSigner.hasAnyKey else { return .failure(.noKey) }
        let chainId = request.chainId
        guard SafeSigner.canSign(chainId: chainId), let seg = SafeSigner.seg(chainId: chainId) else {
            return .failure(.chainUnsupported(String(chainId)))
        }
        guard let localBytes = SafeRecovery.recoveryHash(request) else { return .failure(.unreadable) }
        let local = SafeABI.hex(localBytes)
        if let requesterHash {
            let requester = SafeABI.hex(requesterHash)
            guard local.lowercased() == requester.lowercased() else {
                return .failure(.requesterHashMismatch(local: local, requester: requester))
            }
        }
        let module = request.module
        let wallet = request.wallet

        // Who the contract says it is, before anything else is believed.
        async let nameRead = SafeSigner.ethCall(chainId: chainId, to: module, data: SafeRecovery.nameSelector)
        async let versionRead = SafeSigner.ethCall(chainId: chainId, to: module, data: SafeRecovery.versionSelector)
        guard let nameHex = await nameRead else { return .failure(.chainUnreadable) }
        guard SafeRecovery.decodeString(nameHex) == SafeRecovery.moduleName else {
            return .failure(.notARecoveryModule)
        }
        guard let versionHex = await versionRead, let version = SafeRecovery.decodeString(versionHex)
        else { return .failure(.chainUnreadable) }
        guard version == request.version else { return .failure(.versionMismatch(module: version)) }

        guard let enabledCalldata = SafeRecovery.isModuleEnabledCalldata(module: module),
              let thresholdCalldata = SafeRecovery.thresholdCalldata(wallet: wallet),
              let countCalldata = SafeRecovery.guardiansCountCalldata(wallet: wallet),
              let nonceCalldata = SafeRecovery.nonceCalldata(wallet: wallet),
              let railCalldata = SafeRecovery.getRecoveryHashCalldata(request),
              let pendingCalldata = SafeRecovery.getRecoveryRequestCalldata(wallet: wallet)
        else { return .failure(.unreadable) }

        async let enabledRead = SafeSigner.ethCall(chainId: chainId, to: wallet, data: enabledCalldata)
        async let ownersRead = SafeSigner.ethCall(chainId: chainId, to: wallet, data: SafeCall.getOwnersSelector)
        async let walletThresholdRead = SafeSigner.ethCall(chainId: chainId, to: wallet, data: SafeCall.getThresholdSelector)
        async let thresholdRead = SafeSigner.ethCall(chainId: chainId, to: module, data: thresholdCalldata)
        async let countRead = SafeSigner.ethCall(chainId: chainId, to: module, data: countCalldata)
        async let nonceRead = SafeSigner.ethCall(chainId: chainId, to: module, data: nonceCalldata)
        async let railRead = SafeSigner.ethCall(chainId: chainId, to: module, data: railCalldata)
        async let pendingRead = SafeSigner.ethCall(chainId: chainId, to: module, data: pendingCalldata)

        guard let enabledHex = await enabledRead, let enabled = SafeRecovery.decodeBool(enabledHex)
        else { return .failure(.chainUnreadable) }
        guard enabled else { return .failure(.moduleNotEnabled) }

        // Which of this phone's keys the module lists as a guardian.
        let identities = await SafeSigner.identities(chainId: chainId)
        var signer: SafeSigner.Identity?
        var answered = false
        for identity in identities {
            guard let calldata = SafeRecovery.isGuardianCalldata(wallet: wallet, guardian: identity.address),
                  let hex = await SafeSigner.ethCall(chainId: chainId, to: module, data: calldata),
                  let isGuardian = SafeRecovery.decodeBool(hex)
            else { continue }
            answered = true
            if isGuardian { signer = identity; break }
        }
        guard answered else { return .failure(.chainUnreadable) }
        guard let signer else { return .failure(.notAGuardian) }

        guard let thresholdHex = await thresholdRead, let guardianThreshold = SafeCall.decodeUInt(thresholdHex),
              let countHex = await countRead, let guardianCount = SafeCall.decodeUInt(countHex)
        else { return .failure(.chainUnreadable) }
        guard guardianThreshold >= 2 else { return .failure(.guardianThresholdTooLow(guardianThreshold)) }

        guard let nonceHex = await nonceRead, let nonce = SafeCall.decodeUInt(nonceHex)
        else { return .failure(.chainUnreadable) }
        guard nonce == request.nonce else { return .failure(.staleNonce(module: nonce)) }

        guard let chainHex = await railRead,
              let chainBytes = SafeABI.hexBytes(chainHex), chainBytes.count == 32
        else { return .failure(.chainUnreadable) }
        let chain = SafeABI.hex(chainBytes)
        guard chain.lowercased() == local.lowercased() else {
            return .failure(.hashMismatch(local: local, chain: chain))
        }

        let owners = (await ownersRead).flatMap(SafeCall.decodeAddressArray) ?? []
        let currentThreshold = (await walletThresholdRead).flatMap(SafeCall.decodeUInt) ?? 0
        let pending = (await pendingRead).flatMap(SafeRecovery.decodeRecoveryRequest)
        return .success(Ready(request: request, seg: seg, hash: local,
                              currentOwners: owners, currentThreshold: currentThreshold,
                              guardianThreshold: guardianThreshold, guardianCount: guardianCount,
                              signer: signer,
                              pending: (pending?.executableAt ?? 0) > 0 ? pending : nil))
    }

    // MARK: - The signature

    enum Outcome: Equatable {
        /// The bytes, and the guardian address they belong to — the two
        /// things whoever submits `multiConfirmRecovery` needs.
        case signed(signature: String, guardian: String)
        case refused(Refusal)
        case keyRefused(SignerKey.Failure)
        case enclaveRefused(SafeEnclaveKey.Failure)
    }

    static func sign(_ request: SafeRecovery.Request, requesterHash: [UInt8]?) async -> (Outcome, Ready?) {
        let ready: Ready
        switch await prepare(request, requesterHash: requesterHash) {
        case .success(let value): ready = value
        case .failure(let refusal): return (.refused(refusal), nil)
        }
        guard let hash = SafeABI.hexBytes(ready.hash), hash.count == 32 else {
            return (.refused(.unreadable), ready)
        }
        let reason = String(localized: "Approve this recovery")
        switch ready.signer.kind {
        case .k1:
            do {
                let signature = try await Task.detached(priority: .userInitiated) {
                    try SignerKey.sign(hash: hash, reason: reason)
                }.value
                return (.signed(signature: SafeABI.hex(signature), guardian: ready.signer.address), ready)
            } catch let failure as SignerKey.Failure {
                return (.keyRefused(failure), ready)
            } catch {
                return (.keyRefused(.curve), ready)
            }
        case .enclave:
            // The module checks a contract guardian through
            // `SignatureChecker.isValidSignatureNow`, which hands the bytes
            // to the proxy's `isValidSignature` RAW — no Safe envelope here.
            switch await SafeEnclaveSigner.assert(challenge: hash, chainId: request.chainId, reason: reason) {
            case .success(let bytes):
                return (.signed(signature: SafeABI.hex(bytes), guardian: ready.signer.address), ready)
            case .failure(.noKey): return (.enclaveRefused(.noKey), ready)
            case .failure(.keyRefused(let failure)): return (.enclaveRefused(failure), ready)
            case .failure(.chainUnreadable): return (.refused(.chainUnreadable), ready)
            case .failure(.notAccepted), .failure(.encoding): return (.refused(.unreadable), ready)
            }
        }
    }

    // MARK: - Afterwards

    static func land(context: ModelContext, ready: Ready) {
        let ref = "wallet:saferecovery:\(ready.seg):\(ready.hash)"
        var descriptor = FetchDescriptor<Thing>(predicate: #Predicate { $0.sourceRef == ref })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor), !existing.isEmpty { return }
        let title = String(localized: "You approved a recovery of \(WalletStore.shortAddress(ready.request.wallet)) from this phone")
        let thing = Thing(kind: .note, title: title,
                          content: "https://app.safe.global/home?safe=\(ready.seg):\(EIP55.checksum(ready.request.wallet))",
                          source: SafeBridge.sourceName, sourceRef: ref)
        thing.walletAddress = ready.request.wallet
        context.insert(thing)
        SpotlightIndex.index([thing])
        GuardianLedger.remember(chainId: ready.request.chainId, module: ready.request.module,
                                wallet: ready.request.wallet)
    }

    // MARK: - What this phone guards

    /// One wallet this phone guards, read live off the module.
    struct GuardStanding: Equatable {
        let chainId: Int
        let module: String
        let wallet: String
        let isGuardian: Bool
        let threshold: Int
        let count: Int
        /// A lone guardian — the same warning §427's N-of-N gets, for the
        /// opposite reason: not a Safe that can lock, a phone that could take.
        var isLoneGuardian: Bool { isGuardian && threshold <= 1 }
    }

    static func standing(chainId: Int, module: String, wallet: String) async -> GuardStanding? {
        let identities = await SafeSigner.identities(chainId: chainId)
        var isGuardian = false
        var answered = false
        for identity in identities {
            guard let calldata = SafeRecovery.isGuardianCalldata(wallet: wallet, guardian: identity.address),
                  let hex = await SafeSigner.ethCall(chainId: chainId, to: module, data: calldata),
                  let value = SafeRecovery.decodeBool(hex)
            else { continue }
            answered = true
            if value { isGuardian = true; break }
        }
        guard answered,
              let thresholdCalldata = SafeRecovery.thresholdCalldata(wallet: wallet),
              let countCalldata = SafeRecovery.guardiansCountCalldata(wallet: wallet),
              let thresholdHex = await SafeSigner.ethCall(chainId: chainId, to: module, data: thresholdCalldata),
              let threshold = SafeCall.decodeUInt(thresholdHex),
              let countHex = await SafeSigner.ethCall(chainId: chainId, to: module, data: countCalldata),
              let count = SafeCall.decodeUInt(countHex)
        else { return nil }
        return GuardStanding(chainId: chainId, module: module, wallet: wallet,
                             isGuardian: isGuardian, threshold: threshold, count: count)
    }
}

/// The wallets this phone has been asked to guard — learned from requests,
/// never discovered (a module keeps no index a phone could read cheaply).
/// A reading about this device, in UserDefaults, bounded.
enum GuardianLedger {
    struct Entry: Codable, Equatable, Identifiable {
        let chainId: Int
        let module: String
        let wallet: String
        var id: String { "\(chainId):\(module.lowercased()):\(wallet.lowercased())" }
    }

    private static let key = "signer.guardian.ledger"
    static let cap = 24

    static func all() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return entries
    }

    static func remember(chainId: Int, module: String, wallet: String) {
        let entry = Entry(chainId: chainId, module: module, wallet: wallet)
        var entries = all().filter { $0.id != entry.id }
        entries.insert(entry, at: 0)
        if entries.count > cap { entries = Array(entries.prefix(cap)) }
        if let data = try? JSONEncoder().encode(entries) { DefaultsWrite.set(data, forKey: key) }
    }

    static func forget(_ entry: Entry) {
        let entries = all().filter { $0.id != entry.id }
        if let data = try? JSONEncoder().encode(entries) { DefaultsWrite.set(data, forKey: key) }
    }
}
