import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// THE PASSKEY THAT SIGNS A FRAMES ACCOUNT (prd §728d) — a P-256 key born inside
/// the Secure Enclave, one per device, that can never leave it.
///
/// ## WHY THIS SEAT CAN HAVE ONE NOW
///
/// `FramesKey`'s own doc says an Enclave key "cannot sign here at all", and for
/// an ordinary address that is still true: the default code accepts
/// secp256k1 only. It stopped being true of an ACCOUNT the day the account
/// could have code — `FramesPasskeyAccount` is 64 bytes that accept a P-256
/// signature from this key. So the Frames seat can finally make the promise
/// `VibenetDeviceKey` makes and `FramesKey` cannot: the private half never
/// exists in this process, and there is nothing to export.
///
/// ## ITS OWN SERVICE, AND vibenet's RULES
///
/// Never `VibenetDeviceKey`'s item — two chains, two keys (`FramesKey`'s
/// ruling). Everything else is that file's proven body: `.biometryCurrentSet`
/// (re-enrolling Face ID destroys the key, and `presence()` tells destroyed
/// from absent without a prompt), the public half cached where drawing it
/// costs nothing, a raw digest signed without being hashed again, and `s`
/// folded low (`FramesPasskeyAccount.lowS`, which the harness drives).
///
/// **Nothing here reaches the network or knows what a transaction is.**
enum FramesPasskey {

    private static let service = "casberi-frames-passkey"
    private static let account = "device-p256"
    private static let publicKeyDefaultsKey = "frames.passkey.publicKey"

    /// **False on every simulator.** No simulator run can make this key.
    static var enclaveAvailable: Bool { SecureEnclave.isAvailable }

    static func biometryAvailable() -> Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    enum Presence: Equatable { case none, present, destroyed }

    /// Attributes only — no `kSecReturnData` — so no prompt.
    static func presence() -> Presence {
        guard publicKey() != nil else { return .none }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess { return .present }
        if status == errSecItemNotFound { return .destroyed }
        return .present
    }

    /// The public half, `qx ‖ qy`.
    static func publicKey() -> Data? {
        guard let hex = UserDefaults.standard.string(forKey: publicKeyDefaultsKey),
              let data = RLP.data(fromHex: hex), data.count == 64 else { return nil }
        return data
    }

    /// The account this key signs for, as an address — derived, never stored.
    static func accountAddress() -> String? {
        guard let xy = publicKey(), let owner = FramesPasskeyAccount.owner(publicKey: xy) else { return nil }
        return "0x" + RLP.hex(FramesPasskeyAccount.address(owner: owner))
    }

    /// Make the key, and return the account address it signs for.
    ///
    /// **An item left by a previous install is ADOPTED, not duplicated** —
    /// `FramesKey`'s §531 lesson: the cached public half is gone after a
    /// reinstall while the Keychain item is not, and `SecItemAdd` would answer
    /// "duplicate" forever.
    static func create() throws -> String {
        guard enclaveAvailable else { throw Failure.noEnclave }
        guard biometryAvailable() else { throw Failure.noBiometry }
        guard presence() == .none else { throw Failure.alreadyExists }

        if let adopted = try adoptStoredKey() { return adopted }

        var acError: Unmanaged<CFError>?
        guard let control = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            [.privateKeyUsage, .biometryCurrentSet], &acError) else {
            throw Failure.keychainRefused(acError.map {
                OSStatus(CFErrorGetCode($0.takeRetainedValue() as CFError)) } ?? errSecParam)
        }
        let key: SecureEnclave.P256.Signing.PrivateKey
        do {
            key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: control)
        } catch {
            throw Failure.enclaveRefused
        }
        let x963 = key.publicKey.x963Representation
        guard x963.count == 65, x963.first == 0x04 else { throw Failure.enclaveRefused }

        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: key.dataRepresentation,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
        ]
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.keychainRefused(status) }
        return try cache(publicKey: x963.dropFirst())
    }

    private static func adoptStoredKey() throws -> String? {
        guard let key = try loadKey() else { return nil }
        let x963 = key.publicKey.x963Representation
        guard x963.count == 65 else { return nil }
        return try cache(publicKey: x963.dropFirst())
    }

    private static func cache(publicKey xy: Data) throws -> String {
        let bytes = Data(xy)
        guard bytes.count == 64, let owner = FramesPasskeyAccount.owner(publicKey: bytes) else {
            throw Failure.enclaveRefused
        }
        UserDefaults.standard.set(RLP.hex(bytes), forKey: publicKeyDefaultsKey)
        return "0x" + RLP.hex(FramesPasskeyAccount.address(owner: owner))
    }

    /// Sign 32 bytes. Returns `r ‖ s` with `s` folded low. **A Face ID every
    /// time.**
    static func sign(digest: Data, reason: String) throws -> Data {
        guard digest.count == 32 else { throw Failure.badDigest }
        guard let key = try loadKey() else { throw Failure.noKey }
        let signature: P256.Signing.ECDSASignature
        do {
            // The pre-hashed overload. `signature(for: Data)` would SHA-256
            // the digest again and sign something else — the trap
            // `VibenetDeviceKey` shipped once.
            signature = try key.signature(for: FramesPasskeyDigest(digest))
        } catch {
            throw Failure.signingRefused
        }
        let raw = signature.rawRepresentation
        guard raw.count == 64 else { throw Failure.badDigest }
        _ = reason
        return FramesPasskeyAccount.lowS(raw)
    }

    /// The one call that reconstitutes the Enclave key.
    private static func loadKey() throws -> SecureEnclave.P256.Signing.PrivateKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let blob = item as? Data else {
            if status == errSecItemNotFound { return nil }
            throw Failure.keychainRefused(status)
        }
        return try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: blob)
    }

    /// Deletes the key and forgets the public half. **The account keeps its
    /// address and its coin, and nothing can ever sign for it again** — the
    /// caller owns that sentence.
    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: publicKeyDefaultsKey)
    }

    enum Failure: Error, Equatable {
        case noEnclave
        case noBiometry
        case alreadyExists
        case enclaveRefused
        case keychainRefused(OSStatus)
        case badDigest
        case noKey
        case signingRefused
    }
}

/// 32 already-hashed bytes as a CryptoKit `Digest`, so nothing hashes them again.
private struct FramesPasskeyDigest: Digest {
    private let bytes: Data
    init(_ bytes: Data) { self.bytes = bytes }
    static var byteCount: Int { 32 }
    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try bytes.withUnsafeBytes(body)
    }
}

extension FramesPasskeyDigest: Sequence {
    func makeIterator() -> Array<UInt8>.Iterator { [UInt8](bytes).makeIterator() }
}
