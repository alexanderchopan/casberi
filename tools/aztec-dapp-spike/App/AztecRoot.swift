import Foundation
import Security

/// The Aztec account's ONE secret: 32 random bytes in iCloud Keychain, the way
/// Casberi keeps private money's root (prd §1562): a synchronizable generic
/// password, AfterFirstUnlock (a synchronizable item can be neither
/// ThisDeviceOnly nor biometric). A phone signed in to the same Apple account
/// gets it back, and the engine derives the same account from it. Never logged.
enum AztecRoot {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.casberi.spike.aztec.root",
        kSecAttrAccount as String: "root",
        kSecAttrSynchronizable as String: true,
    ]

    /// The root as hex, made the first time it is asked for. `made` says which.
    static func ensure() -> (hex: String, made: Bool)? {
        var read = query
        read[kSecReturnData as String] = true
        var out: CFTypeRef?
        if SecItemCopyMatching(read as CFDictionary, &out) == errSecSuccess, let data = out as? Data, data.count == 32 {
            return (hex(data), false)
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        var add = query
        add[kSecValueData as String] = Data(bytes)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            log("{\"event\":\"rootFailed\",\"detail\":\(status)}")
            return nil
        }
        return (hex(Data(bytes)), true)
    }

    private static func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
}
