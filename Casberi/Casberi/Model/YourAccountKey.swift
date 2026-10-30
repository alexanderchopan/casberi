import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// **YOUR ACCOUNT'S KEYS (prd §1421, §1424): P-256 keys born in this phone's
/// Secure Enclave.** Key 0 created the account, so the address comes from it
/// forever (`YourAccount.address`). Every send moves the account to a new key
/// (the wallet spec, section 3b), so there are as many keys as sends — and
/// each NETWORK keeps its own: a send on Base moves Base's, Ethereum's stays.
/// Which key a network answers to is read from the chain at each send
/// (`YourAccountChain.configuredX`), never remembered here; a retired key is
/// refused by the chain, so keeping its wrapped blob costs nothing.
///
/// The shape of `SafeEnclaveKey` (§913) under its own service, never that
/// file's item: each Enclave-wrapped `dataRepresentation` a device-only
/// generic password (`key-<n>`), `.privateKeyUsage` with `.biometryCurrentSet`
/// where Face ID is enrolled, so re-enrolling Face ID destroys them (§427) and
/// recovery is the way back. The public halves and the address are cached in
/// UserDefaults, where drawing and matching them needs no prompt.
enum YourAccountKey {
    private static let service = "com.casberi.app.account.enclave"
    private static let addressKey = "yourAccount.address"
    /// Step 1's single key's public half (prd §1422), read as key 0.
    private static let key0Key = "yourAccount.key0.public"
    private static let publicKeysKey = "yourAccount.publicKeys"
    /// A key made for a send that has not landed yet, reused by the next one.
    private static let pendingKey = "yourAccount.pendingNext"

    /// The account's address, once created on — or recovered to — this device.
    static var address: String? { UserDefaults.standard.string(forKey: addressKey) }

    /// Key 0's `x ‖ y`, hex: the key the address comes from, wherever it is
    /// now. On the phone that made the account it is this phone's key 0; on
    /// a phone the account was recovered to (`adopt`) it is the first
    /// phone's, read from the recovery key's item, and no key here matches it.
    private static let originKey = "yourAccount.origin"
    static var originHex: String? {
        UserDefaults.standard.string(forKey: originKey) ?? UserDefaults.standard.string(forKey: key0Key)
    }
    static var origin: (x: [UInt8], y: [UInt8])? {
        guard let hex = originHex, let xy = SafeABI.hexBytes(hex), xy.count == 64 else { return nil }
        return (Array(xy[0..<32]), Array(xy[32..<64]))
    }

    /// Whether this phone holds the key the account was made with — false
    /// on a phone it was recovered to, which can therefore never be the one
    /// to create it on a network where it does not exist yet.
    static var holdsOrigin: Bool {
        guard let o = origin else { return false }
        return publicKey(0).map { $0.x == o.x && $0.y == o.y } ?? false
    }

    enum Failure: Error, Equatable {
        case noEnclave
        case enclaveRefused
        case keychainRefused(OSStatus)
        case noAddress
        case noKey
    }

    // MARK: - The public halves

    /// Every key's `x ‖ y`, hex, by index.
    private static var publicKeys: [String] {
        get {
            if let all = UserDefaults.standard.stringArray(forKey: publicKeysKey) { return all }
            return UserDefaults.standard.string(forKey: key0Key).map { [$0] } ?? []
        }
        set { UserDefaults.standard.set(newValue, forKey: publicKeysKey) }
    }

    static var keyCount: Int { publicKeys.count }

    static func publicKey(_ index: Int) -> (x: [UInt8], y: [UInt8])? {
        guard publicKeys.indices.contains(index),
              let xy = SafeABI.hexBytes(publicKeys[index]), xy.count == 64 else { return nil }
        return (Array(xy[0..<32]), Array(xy[32..<64]))
    }

    /// The key whose x the chain holds.
    static func index(matchingX x: [UInt8]) -> Int? {
        publicKeys.indices.first { publicKey($0)?.x == x }
    }

    // MARK: - Making keys

    /// Whether key 0 was made behind Face ID (or Touch ID). Every later key
    /// takes the same policy, never a weaker one: a key made while Face ID
    /// was locked out must not quietly become the account's next key with no
    /// prompt on it.
    private static let biometricKey = "yourAccount.biometric"

    /// Biometrics set up on this phone, locked out or not.
    private static var biometryEnrolled: Bool {
        var error: NSError?
        if LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) { return true }
        return error.map { LAError.Code(rawValue: $0.code) == .biometryLockout } ?? false
    }

    /// Key 0's policy, as recorded; for an account made before it was
    /// recorded, what this phone can do now.
    private static var biometric: Bool {
        (UserDefaults.standard.object(forKey: biometricKey) as? Bool) ?? biometryEnrolled
    }

    private static func item(_ index: Int) -> [String: Any] { item(named: "key-\(index)") }

    private static func item(named name: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: name]
    }

    /// The public half of the key already stored as `key-<index>`, if any —
    /// read without a prompt (only signing needs one).
    private static func stored(_ index: Int) -> [UInt8]? { stored(item(index)) }

    private static func stored(_ item: [String: Any]) -> [UInt8]? {
        var query = item
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let blob = out as? Data,
              let key = try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: blob) else { return nil }
        let xy = [UInt8](key.publicKey.rawRepresentation)
        return xy.count == 64 ? xy : nil
    }

    /// A new Enclave key stored as `key-<index>`; or, when that item already
    /// exists (the app was killed between storing a key and recording it, or
    /// reinstalled, which keeps the Keychain), that key — never a duplicate
    /// error that would stop every send, and never a deletion of a key the
    /// account might answer to.
    private static func make(index: Int, biometric: Bool) throws -> [UInt8] {
        try make(item(index), domain: domainKey(index), biometric: biometric)
    }

    private static func make(_ item: [String: Any], domain: String, biometric: Bool) throws -> [UInt8] {
        if let existing = stored(item) { return existing }
        guard SecureEnclave.isAvailable else { throw Failure.noEnclave }
        var flags: SecAccessControlCreateFlags = [.privateKeyUsage]
        if biometric { flags.insert(.biometryCurrentSet) }
        guard let control = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, flags, nil) else {
            throw Failure.keychainRefused(errSecParam)
        }
        let key: SecureEnclave.P256.Signing.PrivateKey
        do { key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: control) }
        catch { throw Failure.enclaveRefused }
        var add = item
        add[kSecValueData as String] = key.dataRepresentation
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
        add[kSecAttrSynchronizable as String] = false
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.keychainRefused(status) }
        let context = LAContext()
        if biometric, context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil),
           let state = context.domainState.biometry.stateHash {
            UserDefaults.standard.set(state, forKey: domain)
        }
        let xy = [UInt8](key.publicKey.rawRepresentation)
        guard xy.count == 64 else { throw Failure.noKey }
        return xy
    }

    // MARK: - The record a reinstall reads

    /// Which account this phone's keys belong to, and the key its address
    /// comes from: a device-only item beside the keys, because a reinstall
    /// (or a restore) loses UserDefaults and keeps the Keychain. Without it a
    /// reinstalled phone could only guess — and a phone the account was
    /// recovered to would guess a wrong, empty address from its own key 0.
    private struct Record: Codable { let address: String; let origin: String }

    private static var recordItem: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "record"]
    }

    private static func readRecord() -> Record? {
        var q = recordItem
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    private static func writeRecord(_ record: Record) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        SecItemDelete(recordItem as CFDictionary)
        var add = recordItem
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
        add[kSecAttrSynchronizable as String] = false
        SecItemAdd(add as CFDictionary, nil)
    }

    /// Every key stored here, in order, until the first gap.
    private static func storedKeys() -> [String] {
        var keys: [String] = []
        while let xy = stored(keys.count) { keys.append(Keccak256.hexString(xy)) }
        return keys
    }

    /// Restore this phone's account from its record and its keys.
    private static func restore(_ record: Record) -> String {
        publicKeys = storedKeys()
        UserDefaults.standard.set(publicKeys.first, forKey: key0Key)
        UserDefaults.standard.set(record.origin, forKey: originKey)
        UserDefaults.standard.set(record.address, forKey: addressKey)
        return record.address
    }

    /// Make key 0 and the account's address — or take this phone's own
    /// account back after a reinstall: from its record when it has one; from
    /// a key 0 left with no record (an account made before the record) only
    /// by that key's own address, never for a phone it was recovered to,
    /// which always has a record. Nothing reaches the network: the account
    /// can receive at once and exists on chain at its first send.
    @discardableResult
    static func create() throws -> String {
        if let address { return address }
        if let record = readRecord() { return restore(record) }
        let restoring = stored(0) != nil
        let bio = restoring ? biometric : biometryEnrolled
        let xy = try make(index: 0, biometric: bio)
        guard let account = YourAccount.address(x: Array(xy[0..<32]), y: Array(xy[32..<64])) else {
            throw Failure.noAddress
        }
        publicKeys = restoring ? storedKeys() : [Keccak256.hexString(xy)]
        if !restoring { UserDefaults.standard.set(bio, forKey: biometricKey) }
        UserDefaults.standard.set(Keccak256.hexString(xy), forKey: key0Key)
        UserDefaults.standard.set(account, forKey: addressKey)
        writeRecord(Record(address: account, origin: Keccak256.hexString(xy)))
        // The first send's key, made with the account, as `used` makes each
        // later one: Move's preview never makes a key.
        _ = try? nextKey(after: 0)
        return account
    }

    /// Take an account back onto this phone (prd §1427). When this phone's
    /// own record names it (the app was reinstalled), the keys here already
    /// sign and nothing needs recovering: nil. Otherwise a NEW key, after
    /// every key already stored here (never over one), that the recovery key
    /// then moves the account to, network by network
    /// (`YourAccountChain.recover`); returns its index.
    static func adopt(address account: String, origin: String) throws -> Int? {
        let account = EIP55.checksum(account)
        if let record = readRecord(), record.address.caseInsensitiveCompare(account) == .orderedSame {
            _ = restore(record)
            return nil
        }
        let existing = storedKeys()
        let bio = biometryEnrolled
        let xy = try make(index: existing.count, biometric: bio)
        publicKeys = existing + [Keccak256.hexString(xy)]
        UserDefaults.standard.set(bio, forKey: biometricKey)
        if let first = publicKeys.first { UserDefaults.standard.set(first, forKey: key0Key) }
        UserDefaults.standard.set(origin, forKey: originKey)
        UserDefaults.standard.set(account, forKey: addressKey)
        writeRecord(Record(address: account, origin: origin))
        return existing.count
    }

    /// A key made now, after every other, for the recovery key to move a
    /// network to — never one that might be dead or already in use.
    static func freshKey() throws -> Int {
        let index = publicKeys.count
        let xy = try make(index: index, biometric: biometric)
        publicKeys = publicKeys + [Keccak256.hexString(xy)]
        return index
    }

    // MARK: - The outside-key nudge (prd §1432)

    private static let outsideHeldKey = "yourAccount.outsideKeyHeld"

    /// Whether the Wallet's Needs you asks for a key held outside Casberi:
    /// an account exists here and not every network it is on has one. Read
    /// in a body, so a stored flag (`MoveSecurity` writes it from the chain).
    static var needsOutsideKey: Bool {
        address != nil && !UserDefaults.standard.bool(forKey: outsideHeldKey)
    }

    static func noteOutsideKey(held: Bool) {
        UserDefaults.standard.set(held, forKey: outsideHeldKey)
    }

    /// An account made before the record existed gets one, once.
    static func ensureRecord() {
        guard readRecord() == nil, let address, let origin = originHex else { return }
        writeRecord(Record(address: address, origin: origin))
    }

    /// Whether this phone can still sign with key `index`: its blob is here,
    /// and — for a key behind Face ID — Face ID has not been re-enrolled
    /// since it was made (`.biometryCurrentSet` destroys it, §427). A key the
    /// chain answers to that this phone can no longer use is recovery's job.
    static func holds(_ index: Int) -> Bool {
        guard stored(index) != nil else { return false }
        guard let made = UserDefaults.standard.data(forKey: domainKey(index)) else { return true }
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil),
              let now = context.domainState.biometry.stateHash else { return true }
        return now == made
    }

    private static func domainKey(_ index: Int) -> String { "yourAccount.domainState.\(index)" }

    #if DEBUG
    /// `-yourAccountForgetDevice YES`: this phone loses its keys and its
    /// record of the account, as a lost phone does; the recovery key in
    /// iCloud Keychain stays. The simulator's stand-in for a second iPhone.
    static func forgetDevice() {
        for i in 0..<max(publicKeys.count, 1) + 8 { SecItemDelete(item(i) as CFDictionary) }
        SecItemDelete(recordItem as CFDictionary)
        SecItemDelete(item(named: sessionName) as CFDictionary)
        for k in [addressKey, key0Key, publicKeysKey, pendingKey, biometricKey, originKey] {
            UserDefaults.standard.removeObject(forKey: k)
        }
    }
    #endif

    /// The key a send moves the account to: the one an unlanded send made,
    /// or a new one. Never the key that signs it, nor key 0.
    static func nextKey(after signer: Int) throws -> Int {
        let pending = UserDefaults.standard.object(forKey: pendingKey) as? Int
        if let pending, pending != signer, pending != 0, publicKey(pending) != nil { return pending }
        let index = publicKeys.count
        let xy = try make(index: index, biometric: biometric)
        publicKeys = publicKeys + [Keccak256.hexString(xy)]
        UserDefaults.standard.set(index, forKey: pendingKey)
        return index
    }

    /// A send landed and the chain holds `index`: the next send's key is
    /// made now, straight after its Face ID, so Move's preview finds it
    /// waiting and never makes one (user: picking Swap or Sweep scanned a
    /// face "sometimes"; the first preview after each send made this key,
    /// the likeliest cause — the simulator cannot make such a key to show it).
    static func used(_ index: Int) {
        if (UserDefaults.standard.object(forKey: pendingKey) as? Int) == index {
            UserDefaults.standard.removeObject(forKey: pendingKey)
            _ = try? nextKey(after: index)
        }
    }

    // MARK: - Signing

    /// Sign 32 pre-hashed bytes with key `index`, behind Face ID with
    /// `reason`: `r ‖ s`, `s` low.
    static func sign(_ digest: [UInt8], with index: Int, reason: String) async throws -> (r: [UInt8], s: [UInt8]) {
        try await sign(digest, item: item(index), reason: reason)
    }

    // MARK: - The spend limit's key

    /// The spend limit's own key (prd §1447 item 14): one Enclave key under
    /// the account's policy, that Smart Sessions alone answers to and only
    /// within the limit. Never an owner of the Safe, never rotated: a
    /// session names it, and a new key is a new session.
    private static let sessionName = "session-key"

    /// Its public half, made on first ask.
    static func sessionKey() throws -> (x: [UInt8], y: [UInt8]) {
        let xy = try make(item(named: sessionName), domain: "yourAccount.domainState.session", biometric: biometric)
        return (Array(xy[0..<32]), Array(xy[32..<64]))
    }

    static func signSession(_ digest: [UInt8], reason: String) async throws -> (r: [UInt8], s: [UInt8]) {
        try await sign(digest, item: item(named: sessionName), reason: reason)
    }

    private static func sign(_ digest: [UInt8], item: [String: Any], reason: String) async throws -> (r: [UInt8], s: [UInt8]) {
        var query = item
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let blob = out as? Data else { throw Failure.keychainRefused(status) }
        let context = LAContext()
        context.localizedReason = reason
        let key = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: blob, authenticationContext: context)
        let raw = [UInt8](try key.signature(for: AccountDigest(Data(digest))).rawRepresentation)
        return (Array(raw[0..<32]), SafeWebAuthn.lowS(Array(raw[32..<64])))
    }
}

/// 32 already-hashed bytes, so CryptoKit signs them as they are — the
/// pre-hashed overload; `signature(for: Data)` would hash them again.
private struct AccountDigest: Digest {
    let bytes: Data
    init(_ bytes: Data) { self.bytes = bytes }
    static var byteCount: Int { 32 }
    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R { try bytes.withUnsafeBytes(body) }
    func makeIterator() -> Array<UInt8>.Iterator { [UInt8](bytes).makeIterator() }
    var description: String { "AccountDigest" }
    static func == (a: AccountDigest, b: AccountDigest) -> Bool { a.bytes == b.bytes }
    func hash(into hasher: inout Hasher) { hasher.combine(bytes) }
}
