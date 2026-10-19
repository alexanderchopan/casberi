import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// **YOUR ACCOUNT'S KEY (prd §1421): a P-256 key born in this phone's Secure
/// Enclave.** Key 0 created the account, so the address comes from it
/// forever (`YourAccount.address`); the key the account answers to later
/// changes with every send (the wallet spec, section 3b), which is the send's own work.
///
/// The shape of `SafeEnclaveKey` (§913) under its own service, never that
/// file's item: the Enclave-wrapped `dataRepresentation` in a device-only
/// generic password, `.privateKeyUsage` with `.biometryCurrentSet`, so
/// re-enrolling Face ID destroys it (§427) and recovery is the way back. The
/// public half and the address are cached in UserDefaults, where drawing
/// them costs nothing and needs no prompt.
enum YourAccountKey {
    private static let service = "com.casberi.app.account.enclave"
    private static let addressKey = "yourAccount.address"
    private static let publicKeyKey = "yourAccount.key0.public"

    /// The account's address, once created on this device.
    static var address: String? { UserDefaults.standard.string(forKey: addressKey) }

    enum Failure: Error, Equatable {
        case noEnclave
        case enclaveRefused
        case keychainRefused(OSStatus)
        case noAddress
    }

    /// Make key 0 and the account's address. Nothing reaches the network:
    /// the account can receive at once and exists on chain at its first send.
    @discardableResult
    static func create() throws -> String {
        if let address { return address }
        guard SecureEnclave.isAvailable else { throw Failure.noEnclave }
        var flags: SecAccessControlCreateFlags = [.privateKeyUsage]
        if LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) {
            flags.insert(.biometryCurrentSet)
        }
        guard let control = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, flags, nil) else {
            throw Failure.keychainRefused(errSecParam)
        }
        let key: SecureEnclave.P256.Signing.PrivateKey
        do { key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: control) }
        catch { throw Failure.enclaveRefused }
        let xy = [UInt8](key.publicKey.rawRepresentation)
        guard xy.count == 64,
              let account = YourAccount.address(x: Array(xy[0..<32]), y: Array(xy[32..<64])) else {
            throw Failure.noAddress
        }
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "key-0",
            kSecValueData as String: key.dataRepresentation,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
        ]
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.keychainRefused(status) }
        UserDefaults.standard.set(Keccak256.hexString(xy), forKey: publicKeyKey)
        UserDefaults.standard.set(account, forKey: addressKey)
        return account
    }
}
