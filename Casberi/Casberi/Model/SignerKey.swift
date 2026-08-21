import Foundation
import Security
import LocalAuthentication
import P256K

/// The key that can sign and can never spend (prd §425, `docs/signer-spec.md`
/// §4/§6) — a secp256k1 key born on this phone, gated behind Face ID, never
/// exported, and useful only because a Safe whose threshold is 2 or more will
/// not execute on one signature.
///
/// **What it is not.** It is not a wallet. It holds no funds, needs no gas
/// (another owner executes), and has no seed phrase — and that last one is the
/// security model rather than a missing feature. A recovery phrase is a second
/// copy of the key in a drawer, which defeats "this phone's yes" exactly.
/// Recovery lives one level up: the Safe's other owners `swapOwner` a lost
/// phone out, which is also why the setup copy steers a 2-of-2 toward 2-of-3.
///
/// **The curve is `libsecp256k1`, via `21-DOT-DEV/swift-secp256k1`, pinned to
/// an exact revision.** Never a pure-Swift implementation: no constant-time
/// guarantee and no audit history, on the one code path in this app where a
/// timing leak is a stolen key.
///
/// Version note, measured 2026-08-21 and worth keeping: the pin is **0.21.1**
/// rather than the newest 0.23.2, and the reason is a BUILD property, not a
/// crypto one. From 0.22.0 the package assembles `P256K` with a SwiftPM
/// **build-tool plugin**, and Xcode refuses to run an unvalidated plugin from
/// the command line — every `xcodebuild` in `scripts/` would need
/// `-skipPackagePluginValidation`, i.e. plugin fingerprint validation turned
/// off on every build of the app that holds this key, kept correct by
/// remembering a flag in eight places. 0.21.1 predates the plugin, resolves to
/// a clean graph (SwiftPM prunes its ungated dev dependencies), and its
/// signing API is strictly better here: `signature(for:)` THROWS where the
/// newer one calls `fatalError`, so a library fault becomes a decline instead
/// of a crash on the signing screen. Both were built for Mac Catalyst before
/// choosing — the spec listed that as unmeasured; it is measured now, and both
/// compile.
///
/// **No export path, asserted rather than promised.** The private bytes are
/// read in exactly one place — `sign(hash:reason:)` below — and
/// `scripts/safetx-selftest.sh` fails the build if a second reader appears.
enum SignerKey {

    // MARK: - Storage

    /// A service of its OWN, deliberately not `TokenVault`'s.
    ///
    /// `TokenVault.deleteAll()` wipes its whole service in one call — that is
    /// what makes "Delete access" complete for API keys, and it is exactly
    /// what must not happen by accident here. An API key deleted by mistake
    /// is re-pasted; this key deleted by mistake is an ON-CHAIN transaction
    /// by somebody else's wallet (`swapOwner`) before the Safe can be used
    /// again. So it gets its own verb, in the Data tray, with that sentence
    /// attached (§9).
    private static let service = "com.casberi.app.signer"
    private static let account = "safe-cosigner-v1"

    /// The public address, cached so every screen that shows it costs nothing.
    /// A public address is not a secret; reading it must never raise a Face ID
    /// prompt, or the setup screen asks for a fingerprint to show you a string
    /// you are about to paste into a browser.
    private static let addressKey = "signer.address"

    /// The accessibility this item is created under. Spelled once, and named
    /// here so `scripts/keychain-audit.py` can see it: `…ThisDeviceOnly` keeps
    /// the key out of encrypted device backups, and `WhenUnlocked` (rather
    /// than `AfterFirstUnlock`, which every other secret here uses) because
    /// nothing background ever signs — a signature is always a tap.
    private static let accessible = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

    // MARK: - Identity

    /// The EIP-55 address of this phone's signer, or nil if there isn't one.
    /// Reads the cache, never the key.
    static func address() -> String? {
        UserDefaults.standard.string(forKey: addressKey)
    }

    static var exists: Bool { address() != nil }

    /// Whether the KEY is still there, as opposed to whether we remember its
    /// address (prd §426 amendment).
    ///
    /// These come apart, and until this existed the app could not tell you so.
    /// `.biometryCurrentSet` means the Keychain item is **destroyed** — not
    /// locked, destroyed — the moment the enrolled biometric set changes: an
    /// added alternate appearance, a Face ID reset, a TrueDepth repair. The
    /// cached address in UserDefaults survives all of that, so the app went on
    /// showing a signer and a Sign button, and the tap failed with the same
    /// sentence a CANCELLED prompt gives. A control that looks live and is
    /// permanently dead is the §83 failure, on the screen where it costs most.
    ///
    /// It asks for ATTRIBUTES ONLY — no `kSecReturnData` — so the item's value
    /// is never decrypted and no biometric prompt is raised. That is what
    /// makes it safe to call on every appearance of a screen.
    ///
    /// **UNVERIFIED on a device.** The no-prompt property of an attribute-only
    /// query against an access-control item is the documented behaviour and
    /// not something this project has watched happen; check it before
    /// trusting the quiet.
    enum Presence: Equatable {
        /// No key was ever made here.
        case none
        /// The item is in the Keychain. Says nothing about whether Face ID
        /// will succeed right now.
        case present
        /// We remember an address and the item is gone — the enrollment
        /// changed. Unrecoverable; the answer is a new key and an owner swap.
        case destroyed
    }

    static func presence() -> Presence {
        guard address() != nil else { return .none }
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
        // Anything else — the keychain refused for a reason that is not
        // absence. Never report a key as destroyed on a maybe: that sentence
        // tells somebody to go get an on-chain transaction done.
        return .present
    }

    /// Whether a key can be created at all. Biometry is not optional here: the
    /// item is written with `.biometryCurrentSet`, so on a device with no
    /// enrolled biometric the key would be created and then be permanently
    /// unreadable — a signer that silently cannot sign. Refusing up front is
    /// the honest version.
    static func biometryAvailable() -> Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                             error: &error)
    }

    enum Failure: Error, Equatable {
        case noBiometry
        case keychainRefused(OSStatus)
        case alreadyExists
        case curve
        /// The key is there and the system would not unlock it — a cancelled
        /// prompt, a failed match, or an item invalidated because the
        /// biometric enrollment changed. Distinct from "no key", because the
        /// answer for the person is different.
        case locked(OSStatus)
        case missing
        /// The signature did not recover to this phone's own address. Should
        /// be impossible; refuses rather than hands the bytes over, because
        /// the one thing worse than no signature is a signature attributed to
        /// somebody else.
        case selfCheck
    }

    // MARK: - Birth

    /// Generates the key and returns its EIP-55 address.
    ///
    /// The 32 bytes come from `SecRandomCopyBytes`; a value outside the
    /// curve's order is REJECTED and re-drawn rather than clamped, because a
    /// clamped key is a biased key. `libsecp256k1`'s own
    /// `secp256k1_ec_seckey_verify` is what does the rejecting (it is what
    /// `PrivateKey(dataRepresentation:)` throws on), so the range check is the
    /// library's and not ours to get subtly wrong. The retry bound exists only
    /// so a broken RNG fails loudly instead of spinning: the real probability
    /// of one rejection is about 2^-128.
    @discardableResult
    static func create() throws -> String {
        guard !exists else { throw Failure.alreadyExists }
        guard biometryAvailable() else { throw Failure.noBiometry }

        var key: P256K.Recovery.PrivateKey?
        for _ in 0..<8 {
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
                throw Failure.curve
            }
            // `.uncompressed` so `publicKey.dataRepresentation` is the 65-byte
            // `0x04 ‖ X ‖ Y` form Ethereum's address derivation needs. The
            // compressed default would silently hash 33 different bytes and
            // produce a real-looking address for a key that cannot sign for it.
            if let made = try? P256K.Recovery.PrivateKey(dataRepresentation: bytes,
                                                         format: .uncompressed) {
                key = made
            }
            bytes.resetBytes(in: 0..<bytes.count)
            if key != nil { break }
        }
        guard let key else { throw Failure.curve }
        guard let addr = ethereumAddress(uncompressedPublicKey: [UInt8](key.publicKey.dataRepresentation))
        else { throw Failure.curve }

        var control: SecAccessControl?
        var acError: Unmanaged<CFError>?
        // `.biometryCurrentSet`, not `.biometryAny` — enrolling a new face or
        // finger INVALIDATES this item rather than silently widening who can
        // sign, which is the whole guarantee. The cost is real and the setup
        // copy states it: re-enrolling Face ID destroys the key, and the Safe's
        // other owners then `swapOwner` a fresh one in.
        //
        // The spec also listed `.privateKeyUsage`. That flag applies to a
        // Secure Enclave `kSecClassKey`, and this is raw scalar bytes in a
        // generic password — the Enclave speaks P-256 and a Safe cannot accept
        // one without a deployed WebAuthn signer contract, which prd §425
        // explicitly does not build. Including it here would be a flag with
        // nothing to govern.
        control = SecAccessControlCreateWithFlags(nil, accessible, [.biometryCurrentSet], &acError)
        // Released rather than leaked, and read rather than discarded: the
        // only way this fails is a flag combination the OS refuses, and the
        // code it gives is the difference between "this device can't" and
        // "we asked for something wrong".
        let acCode = acError.map { OSStatus(CFErrorGetCode($0.takeRetainedValue() as CFError)) }
        guard let control else { throw Failure.keychainRefused(acCode ?? errSecParam) }

        var raw = [UInt8](key.dataRepresentation)
        var add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(raw),
            kSecAttrAccessControl as String: control,
            // Named for `scripts/keychain-audit.py`, and true: an item written
            // with an access control is non-synchronizable by construction,
            // but a guarantee the audit cannot see is a guarantee nobody can
            // check.
            kSecAttrSynchronizable as String: false,
        ]
        let status = SecItemAdd(add as CFDictionary, nil)
        raw.resetBytes(in: 0..<raw.count)
        add[kSecValueData as String] = nil
        guard status == errSecSuccess else { throw Failure.keychainRefused(status) }

        UserDefaults.standard.set(addr, forKey: addressKey)
        return addr
    }

    /// Deletes the key and forgets the address. The caller owns the sentence
    /// that must accompany it (§9): the other owners should `swapOwner` this
    /// address out first, or the Safe is one signature short forever.
    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: addressKey)
    }

    // MARK: - The address

    /// `EIP55(last 20 bytes of keccak256(X ‖ Y))` — the `0x04` prefix is
    /// dropped, and dropping it is not cosmetic: hashing all 65 bytes yields a
    /// perfectly well-formed address that no signature will ever recover to.
    static func ethereumAddress(uncompressedPublicKey key: [UInt8]) -> String? {
        guard key.count == 65, key[0] == 0x04 else { return nil }
        let digest = Keccak256.hash(Array(key.dropFirst()))
        return EIP55.checksum("0x" + Keccak256.hexString(Array(digest.suffix(20))))
    }

    // MARK: - The one read

    /// Signs a 32-byte hash and returns Safe's 65-byte `r ‖ s ‖ v`.
    ///
    /// **This is the only place the private bytes are read, ever.** It signs
    /// the digest DIRECTLY — no `personal_sign`, no `"\x19Ethereum Signed
    /// Message:\n32"` wrapper — which is what makes `v = 27/28` the correct
    /// discriminator (see `SafeSignature`).
    ///
    /// It takes a HASH and not a transaction on purpose: deciding what may be
    /// signed is `SafeSigner`'s job and involves reading the chain, and a
    /// function here that took a transaction would be a second place those
    /// refusals could be forgotten.
    ///
    /// The self-check at the end is cheap and catches the two failures that
    /// would otherwise be invisible: an address cache that has drifted from
    /// the stored key, and a signature whose recovery id names a different
    /// candidate key than ours.
    static func sign(hash: [UInt8], reason: String) throws -> [UInt8] {
        guard hash.count == 32 else { throw Failure.curve }
        guard let expected = address() else { throw Failure.missing }

        let context = LAContext()
        context.localizedReason = reason
        // No "enter password" escape hatch: this key's guarantee is a
        // biometric on this device, and a passcode fallback would let anyone
        // holding an unlocked phone sign.
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
        guard status == errSecSuccess, let data = item as? Data else {
            if status == errSecItemNotFound { throw Failure.missing }
            throw Failure.locked(status)
        }

        var scalar = [UInt8](data)
        defer { scalar.resetBytes(in: 0..<scalar.count) }
        guard let key = try? P256K.Recovery.PrivateKey(dataRepresentation: scalar,
                                                       format: .uncompressed)
        else { throw Failure.curve }

        // `HashDigest` wraps 32 raw bytes as a `Digest`, which is how the
        // library takes a pre-computed hash. Nothing re-hashes here — the
        // `signature(for data:)` overload would SHA-256 the input and sign
        // something else entirely.
        let digest = HashDigest(hash)
        guard let signature = try? key.signature(for: digest),
              let compact = try? signature.compactRepresentation
        else { throw Failure.curve }

        guard let serialized = SafeSignature.serialize(compact: [UInt8](compact.signature),
                                                       recoveryId: Int(compact.recoveryId))
        else { throw Failure.curve }

        // Recover the public key back out of our own signature and require it
        // to be this phone. Proves three things at once for one curve
        // operation: the digest signed is the digest asked for, the recovery
        // id is the right one of the four candidates, and the cached address
        // still belongs to the stored key.
        guard let recovered = try? P256K.Recovery.PublicKey(digest, signature: signature,
                                                            format: .uncompressed),
              let recoveredAddress = ethereumAddress(uncompressedPublicKey: [UInt8](recovered.dataRepresentation)),
              recoveredAddress.lowercased() == expected.lowercased()
        else { throw Failure.selfCheck }

        return serialized
    }
}

private extension Array where Element == UInt8 {
    /// Overwrite in place. Swift gives no guarantee this survives the
    /// optimizer, which is exactly why the 32 bytes are held for as few lines
    /// as possible above rather than relying on this.
    mutating func resetBytes(in range: Range<Int>) {
        for i in range where indices.contains(i) { self[i] = 0 }
    }
}
