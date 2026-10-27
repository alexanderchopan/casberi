import Foundation
import LocalAuthentication
import Security

/// THE KEY YOUR PRIVATE BALANCE SPENDS WITH (prd §1540, 2026-10-26).
///
/// Privacy Pools v2 has one kind of spending key, a software one
/// (`authType 0`): every proof takes the private nullifying and revocable
/// keys as circuit inputs, so they must be in memory, and the Secure Enclave
/// can do neither BN254 nor Poseidon. So this is a random 32-byte seed made
/// on this phone, from which the engine derives all three protocol keys
/// through 0xBow's own HKDF tree (`CryptoService.deriveAppSecret` →
/// `deriveKeys`, entered where a wallet's signature would enter it — a Safe
/// cannot make that signature).
///
/// Kept in the Keychain on this device only, behind Face ID: readable only
/// when the phone has a passcode, never in a backup or iCloud Keychain, and
/// gone if Face ID is re-enrolled (`.biometryCurrentSet`), as
/// `AztecSignerKey` and `SignerKey` are. Every read asks for Face ID.
///
/// **The device-only account (prd §1562).** Since the private root, no
/// product flow makes this seed: the private account's seed is derived from
/// the root in iCloud Keychain (`PrivateRoot`, `PrivateAccount`). A phone
/// that made this one before keeps reading its notes, and Move › Security's
/// Back up withdraws what it holds into the root's account
/// (`PrivateMigration`). Losing this seed loses what it still holds.
enum PrivacyPoolsKey {

    private static let service = "com.casberi.app.privacypools.seed"
    private static let account = "privacy-pools-v2-seed-v1"
    static let seedBytes = 32

    enum Failure: Error, Equatable {
        case alreadyExists, noKey, noRandom, keychainRefused(OSStatus), badSeed
    }

    /// Whether a seed is stored. Attributes only, so no Face ID prompt.
    static func exists() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    /// Makes a fresh seed and stores it. Refuses to replace one.
    static func create() throws {
        guard !exists() else { throw Failure.alreadyExists }
        var seed = Data(count: seedBytes)
        let made = seed.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, seedBytes, $0.baseAddress!) }
        guard made == errSecSuccess else { throw Failure.noRandom }
        defer { seed.resetBytes(in: 0..<seed.count) }
        var add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: seed,
            kSecAttrSynchronizable as String: false,
        ]
        #if DEBUG && targetEnvironment(simulator)
        // A simulator has no passcode and no enrolled Face ID, and either
        // makes the item below unwritable: DEBUG simulator builds keep the
        // seed device-only without the prompt, so the engine's probe can run
        // headless. Compiled out of every shipped binary.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        #else
        var acError: Unmanaged<CFError>?
        guard let control = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, [.biometryCurrentSet], &acError) else {
            throw Failure.keychainRefused(acError.map {
                OSStatus(CFErrorGetCode($0.takeRetainedValue() as CFError)) } ?? errSecParam)
        }
        add[kSecAttrAccessControl as String] = control
        #endif
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.keychainRefused(status) }
    }

    /// The seed, after Face ID (`reason` is the line the prompt shows). The
    /// caller hands it to the engine and lets it go.
    static func seed(reason: String) throws -> Data {
        let context = LAContext()
        context.localizedReason = reason
        context.localizedFallbackTitle = ""
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let seed = item as? Data else {
            throw status == errSecItemNotFound ? Failure.noKey : Failure.keychainRefused(status)
        }
        guard seed.count == seedBytes else { throw Failure.badSeed }
        return seed
    }

    /// Removes the seed. Whatever it holds privately can never move again.
    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
