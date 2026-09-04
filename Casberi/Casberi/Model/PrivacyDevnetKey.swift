import Foundation
import LocalAuthentication
import P256K
import Security

/// THE KEY THIS PHONE SIGNS ETHREX PRIVACY WITH (prd §593a, 2026-09-04) —
/// secp256k1, stored on this device, for a devnet whose money is worthless.
///
/// The header said FRAMES DEVNET until §593d: this file was started from
/// `FramesKey` and its first line came with it. Harmless to the compiler and
/// not to a reader — the keychain service below is the thing that actually
/// keeps the two apart, and a comment naming the wrong chain is how somebody
/// later concludes they are the same key.
///
/// ## A SEPARATE KEY FROM HEGOTÁ'S, AND THAT IS THE POINT
///
/// `HegotaKey` holds a scalar of exactly this shape and could sign here — the
/// curve is the same and so is the address derivation. It must not. These are
/// two chains with two faucets and two nonce spaces, and one key signing both
/// means a nonce read from one chain can be spent on the other, a "Remove this
/// key" on one screen silently empties the other seat, and a devnet bug in one
/// reaches the other's account. Different chain, different key, its own
/// keychain service. The harness fails the build if this file reaches for
/// either `casberi-hegota-signer`, `casberi-frames-signer` or
/// `casberi-dev-signer`.
///
/// ## WHY THIS IS NOT THE VIBENET KEY, AND WHY IT IS A WEAKER PROMISE
///
/// `VibenetDeviceKey` is a P-256 key born inside the Secure Enclave: the
/// private half never exists in this process and there is no export path
/// because there is nothing to export. **This key cannot be that.** Every
/// signature on this chain is scheme `0x1` (secp256k1) — 5 of 5 — and the
/// Enclave speaks P-256, so an Enclave key cannot sign here at all.
///
/// So this key is a 32-byte scalar in the Keychain, exactly `SignerKey`'s and
/// `HegotaKey`'s shape, which means **the bytes exist and could in principle
/// be read**. That is a real downgrade and it is a deliberate, stated ruling
/// carried from §525 (user, 2026-08-29: *"its devnet so exportable key is
/// fine"*). It is defensible only because of what it can reach: a chain with a
/// faucet, where every token is worthless by construction and the chain's own
/// footer says it may be reset without notice. **Do not reuse this type, this
/// service, or this reasoning for a chain where value is real.**
///
/// ## WHY NOT THE SAFE SIGNER'S KEY
///
/// `SignerKey` already holds a secp256k1 scalar. It is one owner of a Safe
/// holding real funds; sharing would mean a devnet bug reaches the item that
/// guards real money, and a signature intended for a test chain is produced by
/// the key that can move mainnet value.
///
/// ## WHAT IS THE SAME, ON PURPOSE
///
/// Everything below is §531's proven body, transplanted rather than rewritten:
/// the three-state adoption that survives a reinstall, the refusal to delete
/// on an unreadable keychain, the delete that matches every synchronizability,
/// and the self-check that recovers every signature back to this phone before
/// returning it. Those rules were paid for on a real device and none of them
/// is chain-specific.

enum PrivacyDevnetKey {

    /// **Its OWN service, and that is the whole of why this is a separate file.**
    /// Sharing a keychain service with a sibling devnet seat means one seat's
    /// "make an account" silently adopts the other's key and its address — the
    /// room would then show a balance belonging to a different chain's account,
    /// which renders perfectly. Never `SignerKey`'s either.
    private static let service = "casberi-privacydevnet-signer"
    private static let account = "device-secp256k1"
    private static let addressKey = "privacydevnet.signer.address"

    // MARK: - Presence

    /// Three states, and collapsing any two is a wrong sentence on a screen
    /// about a key (`VibenetDeviceKey.Presence`'s ruling, same reasoning).
    enum Presence: Equatable { case none, present, destroyed }

    /// Attribute-only, so it decrypts nothing and raises no prompt.
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
        // Never report destroyed on a maybe — that sentence sends somebody to
        // arrange a replacement they may not need.
        return .present
    }

    /// **Is there an item, regardless of what this phone remembers?**
    ///
    /// `presence()` above answers `.none` the moment the cached address is
    /// missing and never asks the keychain at all, which is right for a screen
    /// (an account with no known address is nothing a person can use) and is
    /// exactly the blind spot that made the §531 duplicate permanent: the item
    /// was there, nothing could see it, and every "Create an account" bounced
    /// off it. Attribute-only, so it decrypts nothing and raises no prompt.
    static func keychainHoldsItem() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess
    }

    /// The address this key signs as, cached so a row can be drawn without
    /// decrypting the scalar.
    static func address() -> String? {
        UserDefaults.standard.string(forKey: addressKey)
    }

    static func biometryAvailable() -> Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                             error: &error)
    }

    // MARK: - Making one

    /// **A KEY CAN OUTLIVE EVERY MEMORY OF IT, AND THAT USED TO BE A DEAD
    /// END** (prd §531, 2026-08-30).
    ///
    /// `presence()` is derived from the CACHED ADDRESS in `UserDefaults`, and
    /// the two halves of this key do not have the same lifetime: deleting the
    /// app wipes the defaults and **leaves the keychain item exactly where it
    /// was**, which is Apple's documented behaviour on iOS and plainly true on
    /// Catalyst. So a reinstall — the ordinary way this app reaches a device —
    /// left the item present and the address gone. `presence()` read `.none`,
    /// the room offered "Create an account", and `SecItemAdd` answered
    /// `errSecDuplicateItem` (`-25299`) forever. The screen said "The keychain
    /// refused (code -25299)", the account could never be made, and because
    /// the faucet button only exists once a key does, **the faucet became
    /// unreachable too** — one root cause wearing two reports.
    ///
    /// The answer is to ADOPT rather than replace. That item IS this phone's
    /// account: it may hold faucet ETH, it is what the chain knows, and
    /// overwriting it would strand both. Only bytes that are not a usable key
    /// at all are thrown away, and then a fresh one is minted in their place
    /// rather than left as a second dead end.
    ///
    /// `.destroyed` — the mirror case, the address cached and the item gone —
    /// used to throw `.alreadyExists` here, so this sheet's own head said
    /// "Making a new one is safe" over a button that answered "There's already
    /// a key on this phone." The stale address is cleared and the mint
    /// proceeds, which is what that sentence was always promising.
    @discardableResult
    static func create() throws -> String {
        switch presence() {
        case .present:
            throw Failure.alreadyExists
        case .destroyed:
            // All that is left of a key the keychain no longer has. Nothing
            // reads it once the item is gone, and holding it is what blocked
            // the replacement.
            UserDefaults.standard.removeObject(forKey: addressKey)
        case .none:
            break
        }

        let minted = try mint()
        switch minted {
        case .stored(let address):
            return address
        case .duplicate:
            switch adoptStoredKey() {
            case .adopted(let address):
                return address
            case .unreadable(let status):
                // **NEVER DELETE ON A MAYBE.** A locked device or a refused
                // access group answers exactly like an item that is not there,
                // and deleting on that reading destroys this phone's real
                // account — `SignerKey.presence()`'s rule (an unreadable
                // keychain is never reported as an absent one), which the
                // first cut of this fix broke in the one place it costs the
                // most.
                throw Failure.locked(status)
            case .unusableBytes:
                // Read, and not a key. It can sign nothing, so nothing is lost
                // by replacing it, and leaving it would reproduce this same
                // duplicate on every future tap.
                delete()
                let replacement = try mint()
                guard case .stored(let address) = replacement else {
                    throw Failure.keychainRefused(errSecDuplicateItem)
                }
                return address
            }
        }
    }

    private enum Minted { case stored(String), duplicate }

    /// Generate a scalar and write it. Hands back `.duplicate` rather than
    /// throwing, because a duplicate is the one keychain answer this file can
    /// do something about.
    private static func mint() throws -> Minted {
        guard let key = try? P256K.Recovery.PrivateKey(format: .uncompressed),
              let addr = ethereumAddress(uncompressedPublicKey: [UInt8](key.publicKey.dataRepresentation))
        else { throw Failure.curve }

        var scalar = [UInt8](key.dataRepresentation)
        var add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(scalar),
            // Device-only and non-synchronizable, named for
            // `scripts/keychain-audit.py`. Worthless money is still not a
            // reason to let a signing key ride a backup onto another device.
            //
            // **`WhenUnlockedThisDeviceOnly`, not `WhenPasscodeSetThisDeviceOnly`
            // — measured, not a downgrade for its own sake.** `SignerKey`
            // (this file's own shape: a software key with no `SecAccessControl`
            // object on its storage, biometry enforced only at SIGN time via
            // `kSecUseAuthenticationContext`) uses `WhenUnlockedThisDeviceOnly`
            // and it is the proven, shipped choice. `WhenPasscodeSet` failed
            // `-25308` (errSecInteractionNotAllowed) on a real signed Catalyst
            // run: that protection class needs an authenticated/interactive
            // session to ESTABLISH, which `VibenetDeviceKey` gets for free
            // because generating its Enclave key with `.biometryCurrentSet`
            // triggers a biometric prompt before the blob is ever written —
            // this key has no such step, so nothing here interacts with the
            // user before the write. Matching `SignerKey`'s constant is
            // matching its whole reasoning, not a smaller number for its own
            // sake.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
        ]
        let status = SecItemAdd(add as CFDictionary, nil)
        scalar.resetBytes(in: 0..<scalar.count)
        add[kSecValueData as String] = nil
        if status == errSecDuplicateItem { return .duplicate }
        guard status == errSecSuccess else { throw Failure.keychainRefused(status) }

        UserDefaults.standard.set(addr, forKey: addressKey)
        return .stored(addr)
    }

    /// **THREE ANSWERS, NEVER TWO.** "The bytes are not a key" and "we could
    /// not read the bytes" look identical from a nil and are opposite
    /// instructions: the first says the item is worthless and may be replaced,
    /// the second says we are blind and must touch nothing. Collapsing them is
    /// how a locked device loses this phone's real account, which is
    /// `SignerKey.presence()`'s own rule (an unreadable keychain is never
    /// reported as an absent one) one file over.
    private enum Adoption {
        case adopted(String)
        /// Read, and not a usable secp256k1 scalar.
        case unusableBytes
        /// Not read at all — locked, refused, or gone between the duplicate
        /// and this query.
        case unreadable(OSStatus)
    }

    /// The address of the key already in the keychain, cached so this phone
    /// remembers it again.
    ///
    /// Reading the scalar raises no prompt: this item carries no
    /// `SecAccessControl`, and biometry is asked for at SIGN time through
    /// `kSecUseAuthenticationContext` instead — the same split `SignerKey`
    /// uses.
    private static func adoptStoredKey() -> Adoption {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return .unreadable(status)
        }
        var scalar = [UInt8](data)
        defer { scalar.resetBytes(in: 0..<scalar.count) }
        guard let key = try? P256K.Recovery.PrivateKey(dataRepresentation: scalar,
                                                       format: .uncompressed),
              let addr = ethereumAddress(uncompressedPublicKey: [UInt8](key.publicKey.dataRepresentation))
        else { return .unusableBytes }
        UserDefaults.standard.set(addr, forKey: addressKey)
        return .adopted(addr)
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            // `SynchronizableAny`, `SignerKey`'s own constant. A delete query
            // that names no synchronizability matches only the
            // non-synchronizable item, so an item written under any other
            // attribute survives "Remove this key" — and then the next
            // "Create an account" hits the duplicate `create()` now adopts.
            // Removing means removing.
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: addressKey)
    }

    // MARK: - Signing

    /// Signs 32 bytes and returns `v || r || s` — **the recovery byte FIRST**,
    /// and `v` as a bare 0/1 rather than 27/28.
    ///
    /// That ordering is not a style choice and not what most chains use: it was
    /// measured off this chain's own wire across all 5 of its signatures (§548), and
    /// `r || s || v` recovers nothing there. It is the single easiest thing
    /// here to get wrong while looking right, which is why the layout is
    /// asserted in the harness rather than left to this comment.
    static func sign(hash: [UInt8], reason: String) throws -> [UInt8] {
        guard hash.count == 32 else { throw Failure.curve }
        guard let expected = address() else { throw Failure.missing }

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
        guard status == errSecSuccess, let data = item as? Data else {
            if status == errSecItemNotFound { throw Failure.missing }
            throw Failure.locked(status)
        }

        var scalar = [UInt8](data)
        defer { scalar.resetBytes(in: 0..<scalar.count) }
        guard let key = try? P256K.Recovery.PrivateKey(dataRepresentation: scalar,
                                                       format: .uncompressed)
        else { throw Failure.curve }

        // Nothing re-hashes here. The `signature(for data:)` overload would
        // SHA-256 the input and sign something else entirely — `SignerKey`'s
        // own recorded trap.
        let digest = HashDigest(hash)
        guard let signature = try? key.signature(for: digest),
              let compact = try? signature.compactRepresentation
        else { throw Failure.curve }

        // THE SELF-CHECK. Recover our own public key back out and require it to
        // be this phone: one curve operation proving the digest signed is the
        // digest asked for, that the recovery id is the right one of four, and
        // that the cached address still belongs to the stored scalar.
        guard let recovered = try? P256K.Recovery.PublicKey(digest, signature: signature,
                                                            format: .uncompressed),
              let recoveredAddress = ethereumAddress(uncompressedPublicKey: [UInt8](recovered.dataRepresentation)),
              recoveredAddress.lowercased() == expected.lowercased()
        else { throw Failure.selfCheck }

        return [UInt8(compact.recoveryId)] + [UInt8](compact.signature)
    }

    /// `keccak256(uncompressed public key without its 0x04 tag)`, last 20 bytes.
    static func ethereumAddress(uncompressedPublicKey key: [UInt8]) -> String? {
        guard key.count == 65, key.first == 0x04 else { return nil }
        let hash = Keccak256.hash(Array(key.dropFirst()))
        return "0x" + hash.suffix(20).map { String(format: "%02x", $0) }.joined()
    }

    enum Failure: Error, Equatable {
        case alreadyExists
        case missing
        case curve
        case selfCheck
        case locked(OSStatus)
        case keychainRefused(OSStatus)
    }
}
