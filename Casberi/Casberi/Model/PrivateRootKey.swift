import Foundation
import LocalAuthentication
import Security

/// **THE ROOT OF YOUR PRIVATE MONEY, IN iCLOUD KEYCHAIN (prd §1562).**
///
/// One random 32-byte root (`PrivateRoot` derives the private account's
/// seed, its owner and the fresh addresses from it), stored as the recovery
/// key is (prd §1421): a synchronizable generic password, end-to-end
/// encrypted by iCloud Keychain, `AfterFirstUnlock` (a synchronizable item
/// cannot be `ThisDeviceOnly` or carry a biometric access control), in the
/// app id's shared group so the Mac reads what the iPhone wrote. A phone
/// signed in to the same Apple ID holds it, so a lost phone loses nothing
/// private.
///
/// **Never overwritten.** Each root is its own item, named by its public id
/// (`PrivateRoot.id`), so a root made on a new phone before iCloud Keychain
/// has brought the old one cannot replace it: both are read, each account's
/// notes are found, and the OLDEST root is the one new money goes to.
///
/// **What asks for you.** Reading the root asks nothing: the app reads it
/// to find your notes and to move what a fresh address was paid INTO your
/// private balance, which only you can spend, in the background too. What
/// spends asks for the device owner first (`unlock`): Face ID, Touch ID or
/// the passcode.
enum PrivateRootKey {
    private static let service = "com.casberi.app.private-money.root"

    struct Stored: Codable {
        let root: Data
        let made: Date
    }

    private static func query(_ account: String?) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: true,
        ]
        if let account { q[kSecAttrAccount as String] = account }
        return q
    }

    /// Every root this device holds, oldest first: the first is the one new
    /// money goes to.
    static func roots() -> [(id: String, made: Date)] {
        all().map { ($0.id, $0.made) }
    }

    private static func all() -> [(id: String, made: Date, root: [UInt8])] {
        var q = query(nil)
        q[kSecReturnAttributes as String] = true
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitAll
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let rows = out as? [[String: Any]] else { return [] }
        return rows.compactMap { row -> (id: String, made: Date, root: [UInt8])? in
            guard let data = row[kSecValueData as String] as? Data,
                  let stored = try? JSONDecoder().decode(Stored.self, from: data),
                  stored.root.count == 32, let id = PrivateRoot.id([UInt8](stored.root)),
                  row[kSecAttrAccount as String] as? String == "root-" + id else { return nil }
            return (id, stored.made, [UInt8](stored.root))
        }
        .sorted { $0.made < $1.made }
    }

    /// The root new money goes to: the oldest.
    static var currentID: String? { roots().first?.id }

    /// Root `id`'s bytes. The caller derives what it needs and lets them go.
    static func root(_ id: String) -> [UInt8]? {
        all().first { $0.id == id }?.root
    }

    /// The current root, made the first time something private is.
    @discardableResult
    static func ensure() throws -> String {
        if let id = currentID { return id }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess,
              let id = PrivateRoot.id(bytes) else { throw Failure.noRandom }
        defer { for i in bytes.indices { bytes[i] = 0 } }
        var add = query("root-" + id)
        add[kSecValueData as String] = try JSONEncoder().encode(Stored(root: Data(bytes), made: Date()))
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        add[kSecAttrAccessGroup as String] = TokenVault.sharedAccessGroup
        add[kSecAttrLabel as String] = "Casberi private money"
        let status = TokenVault.addNamingGroup(add)
        guard status == errSecSuccess else { throw Failure.keychainRefused(status) }
        // Made here: there are no notes of its to find, and no addresses to walk.
        markFound(id)
        UserDefaults.standard.set(true, forKey: madeHereKey + id)
        NSLog("privateRoot| made | %@", id)
        return id
    }

    // MARK: - Which roots' notes this phone has found (prd §1562)

    private static let foundKey = "privateRoot.found.v1"

    /// Whether this phone has read root `id`'s notes from the pool. A phone
    /// that got the root from iCloud Keychain has not, until the watch does.
    static func found(_ id: String) -> Bool {
        foundIDs().contains(id)
    }

    private static let madeHereKey = "privateRoot.madeHere."

    /// Whether root `id` was made on this phone (its fresh addresses are all
    /// in this phone's book, so there is nothing to walk back).
    static func madeHere(_ id: String) -> Bool { UserDefaults.standard.bool(forKey: madeHereKey + id) }

    static func markFound(_ id: String) {
        let ids = foundIDs().union([id]).sorted()
        UserDefaults.standard.set(ids, forKey: foundKey)
    }

    private static func foundIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: foundKey) ?? [])
    }

    #if DEBUG
    /// `-privateForgetLocal YES`: this phone forgets it found any root's notes.
    static func forgetFound() {
        UserDefaults.standard.removeObject(forKey: foundKey)
        for (id, _) in roots() { UserDefaults.standard.removeObject(forKey: madeHereKey + id) }
    }
    #endif

    enum Failure: Error, Equatable { case noRandom, keychainRefused(OSStatus), refused }

    /// The device owner says yes before anything spends from a root's account.
    static func unlock(reason: String) async throws {
        #if DEBUG && targetEnvironment(simulator)
        // A simulator has no passcode and no Face ID (as `PrivacyPoolsKey`).
        return
        #else
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil),
              (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) == true else {
            throw Failure.refused
        }
        #endif
    }

    /// Whether an iCloud account is signed in to carry the root (iCloud
    /// Keychain itself has no public switch to read; signed out, it is
    /// certainly on this phone only).
    static var iCloudSignedIn: Bool { FileManager.default.ubiquityIdentityToken != nil }
}
