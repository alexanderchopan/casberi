import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// THE KEY THIS PHONE SIGNS VIBENET WITH (prd §523, 2026-08-29) — a P-256
/// key born inside the Secure Enclave, one per device, that can never leave it.
///
/// ## WHY THIS CHAIN AND NOT SAFE
///
/// `SignerKey` (prd §425) had to keep a RAW secp256k1 scalar in a generic
/// password and its own doc says why: `.privateKeyUsage` governs a Secure
/// Enclave `kSecClassKey`, the Enclave speaks P-256, and a Safe accepts a
/// P-256 signature only through a WebAuthn signer contract that pass did not
/// build. So that key exists as bytes, and bytes can in principle be read.
///
/// Vibenet ships a **P256Authenticator as a first-class contract**
/// (`0x8130c89f…`, measured off the live contract map 2026-08-29). The
/// Enclave's own curve is the curve, so this key is generated in hardware and
/// **the private half never exists in this process, in this app's memory, or
/// anywhere on disk in a form anything can use.** What the Keychain holds is
/// `dataRepresentation` — an Enclave-wrapped blob that is useless to anyone
/// who is not this Secure Enclave. There is no export path because there is
/// nothing to export, which is a stronger promise than `SignerKey` can make
/// and the reason its no-export guard is spelled differently here.
///
/// ## THE COST, STATED WHERE IT IS PAID
///
/// `.biometryCurrentSet` — so **re-enrolling Face ID destroys the key**, the
/// §427 lesson inherited whole. That is kept rather than softened to
/// `.biometryAny` for §427's reason: a changed enrolled set is a changed
/// AUTHORITY, and the chain cannot see it. The consequence is that
/// `presence()` must be able to tell a destroyed key from an absent one
/// WITHOUT raising a prompt, because those two sentences send a person to
/// completely different places.
///
/// There is no seed phrase and no recovery. On a devnet with test money that
/// is a feature, not a gap: if the phone goes, another authenticator on the
/// account revokes this one. That is why revoke ships early (§523's build
/// order) and why nothing in this file pretends otherwise.
///
/// ## WHAT THIS FILE DELIBERATELY DOES NOT DO
///
/// It does not reach the network, it does not encode a transaction, and it
/// does not know what an account is. It makes a key, says whether the key is
/// there, hands out the public half, and signs 32 bytes when a human proves
/// they are present. `scripts/vibenet-selftest.sh` fails the build if this
/// file ever names an RPC method or a URL — the `CursorFetch` rule, in a file
/// one call away from being able to move something.
enum VibenetDeviceKey {

    // MARK: - Where it lives

    /// Its OWN service, never `SignerKey`'s. Two different curves for two
    /// different chains under one service name is how a future migration
    /// deletes the wrong key.
    private static let service = "casberi-vibenet-signer"
    private static let account = "device-p256"

    /// The public half, cached in UserDefaults as lowercase hex of the raw
    /// 64-byte `x || y`.
    ///
    /// **Cached deliberately, and it is not a duplicate of the truth.** Every
    /// screen that draws this key needs the public half — the Permissions row,
    /// the key sheet, the join that decides whether an account can be signed
    /// for — and reading it back out of the Keychain means reconstituting the
    /// Enclave key, which under `.biometryCurrentSet` raises a Face ID prompt.
    /// A room that asks for a biometric in order to DRAW is unusable, so the
    /// public half — which is public, by definition, and worth nothing to
    /// anyone who has it — lives where it can be read for free.
    private static let publicKeyDefaultsKey = "vibenet.signer.publicKey"

    // MARK: - Is there a key, and can there be one

    /// Whether this device has a Secure Enclave at all. **False on every
    /// simulator**, which is why no simulator run can exercise a single path
    /// below and why the harness is the only proof any of this is right.
    static var enclaveAvailable: Bool { SecureEnclave.isAvailable }

    /// Whether a key can be created. Biometry is not optional: the item is
    /// written with `.biometryCurrentSet`, so on a device with nothing
    /// enrolled the key would be created and then be permanently unusable — a
    /// signer that silently cannot sign. Refusing up front is the honest
    /// version (`SignerKey.biometryAvailable`'s ruling, same reasoning).
    static func biometryAvailable() -> Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                             error: &error)
    }

    /// THREE STATES, and collapsing any two of them is a wrong sentence on a
    /// security screen.
    ///
    /// * `.none` — no key was ever made here. Offer to make one.
    /// * `.present` — there is a key. It may still refuse to sign if the
    ///   person cancels, which is a different thing again.
    /// * `.destroyed` — a key was made, and the Keychain no longer holds it.
    ///   On this access control that means the enrolled biometric set
    ///   changed. This is the sentence that sends somebody to arrange an
    ///   on-chain revoke, so it is never guessed at.
    enum Presence: Equatable { case none, present, destroyed }

    /// Reads presence WITHOUT decrypting anything and therefore **without
    /// raising a biometric prompt** — attributes only, no `kSecReturnData`
    /// (`SignerKey.presence`'s rule, and the reason its own no-export guard
    /// counts `kSecReturnData` occurrences rather than `SecItemCopyMatching`
    /// lines).
    static func presence() -> Presence {
        guard publicKeyHex() != nil else { return .none }
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
        // Anything else is the Keychain refusing for a reason that is not
        // absence. **Never report a key as destroyed on a maybe** — that
        // sentence tells somebody their key is gone and sends them to another
        // device to revoke it.
        return .present
    }

    // MARK: - The public half

    /// Lowercase hex of the raw 64-byte `x || y`, or nil when no key was made
    /// here. No `0x`, because this is a key and not an address, and the two
    /// being visually distinguishable is worth the missing prefix.
    static func publicKeyHex() -> String? {
        UserDefaults.standard.string(forKey: publicKeyDefaultsKey)
    }

    /// The raw 64 bytes, which is the form a P-256 authenticator wants.
    static func publicKeyXY() -> Data? {
        guard let hex = publicKeyHex() else { return nil }
        return Self.data(fromHex: hex)
    }

    /// WHAT THE CHAIN WOULD CALL THIS KEY — `keccak256(x || y)`, lowercase hex
    /// with an `0x`, or nil when no key was made here.
    ///
    /// **Measured against the contract itself** (prd §523): the deployed
    /// `P256Authenticator.authenticate` returns exactly this word for a valid
    /// signature, and three real account creations on chain name their signing
    /// key by it. So this is not our convention — it is the chain's, and this
    /// phone can state its own on-chain identity before it has ever been
    /// authorized anywhere, which is what the key row shows and what
    /// `VibenetSigner.Facts.ourActorID` is filled with.
    ///
    /// **It is the CANONICAL id, not the only possible one.** An actorId is
    /// supplied by whoever authorizes a key, so another client could register
    /// this same key under a different word; a lookup that misses still means
    /// cannot-say rather than no. That distinction is the whole reason
    /// `VibenetSigner` has a separate refusal for it.
    static func actorID() -> String? {
        guard let xy = publicKeyXY(), xy.count == 64 else { return nil }
        return "0x" + Self.hex(Keccak256.hash([UInt8](xy)))
    }

    /// A short, stable, human-comparable fingerprint — first four and last
    /// four hex characters of the public key. For the key sheet and the
    /// Permissions row, so two keys can be told apart at a glance without
    /// printing 128 characters.
    ///
    /// **Never used as an identity in code**, only in copy: four characters at
    /// each end collide easily enough that a join on this would be wrong, and
    /// wrong in the direction that authorizes something.
    static func fingerprint() -> String? {
        guard let hex = publicKeyHex(), hex.count >= 8 else { return nil }
        return "\(hex.prefix(4))…\(hex.suffix(4))"
    }

    // MARK: - Making one

    /// Creates the key, stores the Enclave blob, caches the public half, and
    /// returns the public key hex.
    ///
    /// Refuses rather than overwriting when a key already exists: replacing it
    /// silently would leave every account that authorized the old one pointing
    /// at a key this phone can no longer produce, which reads from the room as
    /// "you are not an authenticator" with no way to find out why.
    @discardableResult
    static func create() throws -> String {
        guard enclaveAvailable else { throw Failure.noEnclave }
        guard biometryAvailable() else { throw Failure.noBiometry }
        guard presence() == .none else { throw Failure.alreadyExists }

        // TWO DIFFERENT PROTECTIONS, and conflating them is a bug this file
        // shipped and a signed run caught (2026-08-29).
        //
        // The access control below governs USE OF THE ENCLAVE KEY:
        // `.privateKeyUsage` plus `.biometryCurrentSet`, so every signature
        // costs a Face ID and re-enrolling erases it. That is correct and is
        // what makes the promise real.
        //
        // It must NOT also be attached to the keychain item that stores the
        // key's `dataRepresentation`. That item is a GENERIC PASSWORD holding
        // an Enclave-wrapped blob, and `SignerKey`'s doc already says why
        // `.privateKeyUsage` does not belong on one: the flag governs a
        // `kSecClassKey`. Attaching it made `SecItemAdd` demand user presence
        // to WRITE, which fails `-25293` (errSecAuthFailed) on any headless
        // run — measured on a signed Mac Catalyst build, where a bare
        // command-line binary had already failed differently (`-34018`,
        // missing entitlement) and masked it. The blob needs device-only
        // accessibility and nothing more: it is worthless to anything that is
        // not this Secure Enclave, so the protection that matters is on the
        // key, not on the copy of its wrapper.
        var acError: Unmanaged<CFError>?
        let control = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            [.privateKeyUsage, .biometryCurrentSet],
            &acError
        )
        // Surface the OSStatus rather than a bare nil — the code is the
        // difference between "this device can't" and "we asked for something
        // wrong" (`SignerKey`'s measured lesson).
        let acCode = acError.map { OSStatus(CFErrorGetCode($0.takeRetainedValue() as CFError)) }
        guard let control else { throw Failure.keychainRefused(acCode ?? errSecParam) }

        let key: SecureEnclave.P256.Signing.PrivateKey
        do {
            key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: control)
        } catch {
            throw Failure.enclaveRefused
        }

        // x963 is `0x04 || x || y`; the leading byte is a format tag, not key
        // material, and every consumer here wants the 64 bytes after it.
        let x963 = key.publicKey.x963Representation
        guard x963.count == 65, x963.first == 0x04 else { throw Failure.enclaveRefused }
        let xy = x963.dropFirst()

        var blob = [UInt8](key.dataRepresentation)
        var add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(blob),
            // Device-only accessibility, NOT the Enclave key's access control —
            // see the note above `control`. Named for
            // `scripts/keychain-audit.py`, and true: a signing key that rides
            // an encrypted backup onto whatever device restores it is the exact
            // failure that audit exists to prevent.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            // Named for `scripts/keychain-audit.py`, and true: an item written
            // with an access control is non-synchronizable by construction,
            // but a guarantee the audit cannot see is a guarantee nobody can
            // check (`SignerKey`'s own wording, same reason).
            kSecAttrSynchronizable as String: false,
        ]
        let status = SecItemAdd(add as CFDictionary, nil)
        blob.resetBytes(in: 0..<blob.count)
        add[kSecValueData as String] = nil
        guard status == errSecSuccess else { throw Failure.keychainRefused(status) }

        let hex = Self.hex(xy)
        UserDefaults.standard.set(hex, forKey: publicKeyDefaultsKey)
        return hex
    }

    // MARK: - Signing

    /// Signs 32 bytes and returns the raw 64-byte `r || s`.
    ///
    /// **Raises a biometric prompt every time, by construction.** There is no
    /// cached context and no reuse duration: this app's one signing key costs
    /// a Face ID per signature, which is the cost `.biometryCurrentSet` was
    /// chosen for.
    ///
    /// `r || s` and not DER, because that is what an on-chain verifier reads.
    /// `SignerKey`'s own doc records the sibling trap — `derRepresentation` is
    /// what most libraries hand back and a contract refuses every one.
    ///
    /// **Low-s is NOT normalised here and that is deliberate**: secp256k1
    /// verifiers reject a high-s signature as malleable, and P-256 verifiers
    /// in this family do not. Normalising anyway would produce a signature
    /// that is valid arithmetic and is not what the authenticator expects to
    /// see. When the P256Authenticator's expectation is MEASURED, this comment
    /// is where the answer belongs.
    static func sign(digest: Data) throws -> Data {
        guard digest.count == 32 else { throw Failure.badDigest }
        guard let key = try loadKey() else { throw Failure.noKey }
        let signature: P256.Signing.ECDSASignature
        do {
            signature = try key.signature(for: digest)
        } catch {
            // A cancelled prompt and a destroyed key both land here, and the
            // CALLER separates them by asking `presence()` — which raises no
            // prompt — rather than by reading this error, whose code is the
            // same for both (§427's measured lesson, one chain over).
            throw Failure.signingRefused
        }
        return signature.rawRepresentation
    }

    /// Reconstitutes the Enclave key. **This is the one call that decrypts**,
    /// so it is the one that raises a prompt, and it is private for that
    /// reason: a second caller elsewhere in the tree would be a second
    /// unexplained Face ID.
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

    // MARK: - Removing it

    /// Deletes the key and forgets the public half.
    ///
    /// The caller owns the sentence that must go with it: any account that
    /// authorized this key should revoke it first, or that account is carrying
    /// an authenticator nobody can ever produce a signature for. Deleting here
    /// changes nothing on chain and this file never claims it does.
    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: publicKeyDefaultsKey)
    }

    // MARK: - Failures

    enum Failure: Error, Equatable {
        /// No Secure Enclave. Every simulator, and nothing else.
        case noEnclave
        /// A Secure Enclave with no enrolled biometric — the key would be
        /// created unusable.
        case noBiometry
        /// A key is already here. Never silently replaced.
        case alreadyExists
        /// The Enclave refused to generate or to reconstitute.
        case enclaveRefused
        /// The Keychain refused, with its own status code.
        case keychainRefused(OSStatus)
        /// Asked to sign something that is not a 32-byte digest.
        case badDigest
        /// Nothing to sign with.
        case noKey
        /// The signature did not happen. A cancelled prompt and a destroyed
        /// key both land here — ask `presence()` to tell them apart.
        case signingRefused
    }

    // MARK: - Hex

    /// Lowercase, no `0x`. Local rather than shared because this file is
    /// deliberately reachable by a `swiftc` harness with nothing else in it.
    static func hex(_ data: some Sequence<UInt8>) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    static func data(fromHex hex: String) -> Data? {
        var s = Substring(hex)
        if s.hasPrefix("0x") || s.hasPrefix("0X") { s = s.dropFirst(2) }
        guard s.count % 2 == 0, !s.isEmpty else { return nil }
        var out = Data(capacity: s.count / 2)
        var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2)
            guard let b = UInt8(s[i..<j], radix: 16) else { return nil }
            out.append(b)
            i = j
        }
        return out
    }
}
