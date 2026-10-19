import CryptoKit
import Foundation
import LocalAuthentication

/// The account's keys, each a P-256 key born in this iPhone's Secure Enclave.
/// Key 0 created the account (its address comes from it forever); the
/// current key is the one the account answers to now. A rotation makes the
/// next key here, and the chain switches to it in the same transaction it
/// signs. The blobs are Enclave-wrapped: useless off this device.
///
/// Testnet harness only. Casberi's shipped key is `SafeEnclaveKey` (§913).
enum EnclaveKeys {
    private static let blobsKey = "safe-spike.keys"
    private static let currentKey = "safe-spike.current"

    static var count: Int { blobs.count }
    static var currentIndex: Int {
        get { UserDefaults.standard.integer(forKey: currentKey) }
        set { UserDefaults.standard.set(newValue, forKey: currentKey) }
    }
    private static var blobs: [Data] {
        get { UserDefaults.standard.array(forKey: blobsKey) as? [Data] ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: blobsKey) }
    }

    /// Face ID on every signature where the device has it; presence only in
    /// the simulator, which has the Enclave but no enrolled face.
    private static func accessControl() -> SecAccessControl {
        var flags: SecAccessControlCreateFlags = [.privateKeyUsage]
        if LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) { flags.insert(.biometryCurrentSet) }
        return SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, flags, nil)!
    }

    @discardableResult
    static func make() throws -> Int {
        let key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: accessControl())
        blobs.append(key.dataRepresentation)
        return blobs.count - 1
    }

    static func key(_ index: Int) throws -> SafeAccount.Key {
        let blob = blobs[index]
        let pub = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: blob).publicKey.rawRepresentation
        let xy = [UInt8](pub)
        return SafeAccount.Key(x: Array(xy[0..<32]), y: Array(xy[32..<64])) { digest in
            let context = LAContext()
            context.localizedReason = "Sign with key \(index)"
            let signer = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: blob, authenticationContext: context)
            let raw = [UInt8](try signer.signature(for: PreHashed(Data(digest))).rawRepresentation)
            return (Array(raw[0..<32]), SafeWebAuthn.lowS(Array(raw[32..<64])))
        }
    }

    static func forgetAll() {
        UserDefaults.standard.removeObject(forKey: blobsKey)
        UserDefaults.standard.removeObject(forKey: currentKey)
    }
}

/// 32 already-hashed bytes, so CryptoKit signs them as they are — the
/// pre-hashed overload; `signature(for: Data)` would hash them again.
private struct PreHashed: Digest {
    let bytes: Data
    init(_ bytes: Data) { self.bytes = bytes }
    static var byteCount: Int { 32 }
    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R { try bytes.withUnsafeBytes(body) }
    func makeIterator() -> Array<UInt8>.Iterator { [UInt8](bytes).makeIterator() }
    var description: String { "PreHashed" }
    static func == (a: PreHashed, b: PreHashed) -> Bool { a.bytes == b.bytes }
    func hash(into hasher: inout Hasher) { hasher.combine(bytes) }
}
