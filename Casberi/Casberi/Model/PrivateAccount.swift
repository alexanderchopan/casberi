#if DEBUG
import Foundation
import P256K

/// **WHICH PRIVATE ACCOUNT (prd §1562) — DEBUG builds only, Sepolia only.**
///
/// A phone reads every private account it can open: the device-only one made
/// before the root (`PrivateRoot.legacy`: `PrivacyPoolsKey`'s seed, owned by
/// the device-only sender), while its seed is here, then each root in iCloud
/// Keychain (`PrivateRootKey`), its seed and owner derived (`PrivateRoot`).
/// New money goes to the oldest root's account.
///
/// The owner is the DEBUG stand-in for your account (§1554 item 4): its
/// keystore entry names the account's keys on chain, and spending needs only
/// those keys (0xBow's relayer posts and pays), so a phone that derives the
/// seed and knows the owner's address spends what the account holds.
enum PrivateAccount {

    /// Every account this phone can read, the device-only one first.
    static func all() -> [String] {
        (legacyExists ? [PrivateRoot.legacy] : []) + PrivateRootKey.roots().map(\.id)
    }

    /// The device-only account: its seed and its owner's key are both here.
    static var legacyExists: Bool { PrivacyPoolsKey.exists() && PrivacyTestnetSender.legacyAddress != nil }

    enum Failure: Error { case noRoot, curve }

    static func ownerKey(_ id: String) throws -> P256K.Recovery.PrivateKey {
        guard var root = PrivateRootKey.root(id) else { throw Failure.noRoot }
        defer { for i in root.indices { root[i] = 0 } }
        guard let k = PrivateRoot.ownerKey(root) else { throw Failure.curve }
        return try P256K.Recovery.PrivateKey(dataRepresentation: Data(k), format: .uncompressed)
    }

    static func ownerAddress(_ id: String) throws -> String {
        let key = try ownerKey(id)
        guard let address = SignerKey.ethereumAddress(uncompressedPublicKey: [UInt8](key.publicKey.dataRepresentation)) else {
            throw Failure.curve
        }
        return address
    }

    /// Opens account `id` in the engine; returns its owner. `reason` asks for
    /// the device owner first (what spends); nil reads (finding notes, moving
    /// money in). The device-only seed always asks: its item is behind Face ID.
    @MainActor
    @discardableResult
    static func open(_ id: String, reason: String?) async throws -> String {
        let engine = PrivacyEngine.shared
        if id == PrivateRoot.legacy {
            guard let owner = PrivacyTestnetSender.legacyAddress else { throw PrivacyPoolsKey.Failure.noKey }
            var seed = try PrivacyPoolsKey.seed(reason: reason ?? String(localized: "Open your private balance"))
            defer { seed.resetBytes(in: 0..<seed.count) }
            _ = try await engine.open(seed: seed, owner: owner, network: .sepolia)
            return owner
        }
        if let reason { try await PrivateRootKey.unlock(reason: reason) }
        guard var root = PrivateRootKey.root(id) else { throw Failure.noRoot }
        defer { for i in root.indices { root[i] = 0 } }
        guard let derived = PrivateRoot.derive(root, .poolSeed) else { throw Failure.curve }
        var seed = Data(derived)
        defer { seed.resetBytes(in: 0..<seed.count) }
        let owner = try ownerAddress(id)
        _ = try await engine.open(seed: seed, owner: owner, network: .sepolia)
        return owner
    }

    /// The open root account's keystore, registered the first time (two
    /// transactions from its owner, so its notes can be spent). When the
    /// owner is not the sender (a phone that kept its device-only sender),
    /// the sender first pays the owner what the two will cost at twice
    /// today's fee.
    @MainActor
    static func registerIfNeeded(_ id: String, stage: ((Int) -> Void)? = nil) async throws {
        let engine = PrivacyEngine.shared
        guard try await !engine.isRegistered().registered else { return }
        let registration = try await engine.prepareRegister()
        guard !registration.txs.isEmpty else { return }
        let owner = try ownerAddress(id)
        let key = try ownerKey(id)
        let sender = try PrivacyTestnetSender.ensure()
        if sender.lowercased() != owner.lowercased() {
            var gas = 0
            for tx in registration.txs {
                let call: [String: Any] = ["from": owner, "to": tx.to, "data": tx.data, "value": tx.value]
                gas += (Int(PrivacyTestnetSender.hexToDecimal(try await PrivacyTestnetSender.rpc("eth_estimateGas", [call]) as? String ?? "0x0")) ?? 0) * 5 / 4
            }
            let price = UInt64(try await PrivacyTestnetSender.gasPrice()) ?? 0
            let need = Decimal(gas) * Decimal(TestnetTx.fees(gasPrice: price, tip: price).maxFee) * 2
            let has = Decimal(string: try await PrivacyTestnetSender.balance(of: owner)) ?? 0
            if has < need, let value = PrivateMoney.hex(PrivateMoney.plain(need - has)) {
                let hash = try await PrivacyTestnetSender.send(.init(to: owner, data: "0x", value: value))
                NSLog("privateRoot| owner funded | %@ | %@ wei | %@", YourAccount.short(owner), PrivateMoney.plain(need - has), hash)
            }
        }
        for (i, tx) in registration.txs.enumerated() {
            stage?(i + 1)
            let hash = try await PrivacyTestnetSender.send(tx, key: key, from: owner)
            NSLog("privateRoot| register %d | %@", i + 1, hash)
        }
    }
}
#endif
