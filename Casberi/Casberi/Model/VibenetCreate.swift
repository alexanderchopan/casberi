import Foundation

/// MAKING AN ACCOUNT THIS PHONE CAN SIGN FOR (prd §523, 2026-08-29).
///
/// Foundation-only BY DESIGN so `scripts/vibenet-signer-selftest.sh` compiles
/// it WHOLE. Nothing here reaches the network, holds a key, or signs: it turns
/// an intent into the exact bytes that need signing, and hands back the address
/// those bytes commit to. The Enclave signature and the broadcast are the
/// caller's, deliberately — this is the part that must be checkable.
///
/// ## THE ORDER IS THE WHOLE THING
///
/// The account's address is derived FROM the initial actors and is then SIGNED
/// OVER as `sender`. So the sequence is: choose the salt, build the actor from
/// this phone's key, derive the address, put that address in `sender`, and only
/// then compute the preimage. Deriving after signing, or signing over a
/// placeholder, produces a signature the node refuses with "create address does
/// not match the sender" — which is the good failure. The bad one is deriving
/// the address slightly wrong, which is a valid signature over an account
/// nobody asked for.
///
/// ## THE PROXY BODY IS NOT OURS TO INVENT
///
/// `code` is a 93-byte proxy whose target is the live `DefaultAccount`, and it
/// comes from `VibenetConfig` rather than a literal here: vibenet redeploys on
/// no schedule, so a pinned body would silently create accounts pointing at a
/// contract that no longer means what we think. `proxyCode(forAccount:)` builds
/// it from the address the config just handed us, and its shape is pinned
/// against a real creation in the harness.
enum VibenetCreate {

    /// Everything a creation needs, and nothing it doesn't.
    struct Plan: Equatable {
        /// Where the account will be. Derived, then signed over as `sender`.
        let address: Data
        /// The 32 bytes that get signed. `VibenetDeviceKey.sign(digest:)` takes
        /// its keccak — this type deliberately does not hash, so the harness
        /// can pin the preimage and a second hasher can check it.
        let preimage: Data
        /// The transaction, ready for `VibenetTransaction.encoded` once a
        /// signature exists.
        let fields: VibenetTransaction.Fields
        /// The actor id the chain will know this phone by on this account.
        let actorID: Data
    }

    /// The EIP-1167-shaped proxy body: a 20-byte target spliced into a fixed
    /// prologue and epilogue, 93 bytes total.
    ///
    /// Read off a real creation rather than written from a standard — this is
    /// NOT the canonical minimal proxy (that one is 45 bytes), and assuming the
    /// canonical form would produce a different init-code hash and therefore a
    /// different address, which is the failure this whole file is arranged to
    /// avoid.
    static func proxyCode(forAccount target: Data) -> Data? {
        guard target.count == 20 else { return nil }
        let prologue = Data([
            0x7f, 0x36, 0x08, 0x94, 0xa1, 0x3b, 0xa1, 0xa3, 0x21, 0x06, 0x67, 0xc8,
            0x28, 0x49, 0x2d, 0xb9, 0x8d, 0xca, 0x3e, 0x20, 0x76, 0xcc, 0x37, 0x35,
            0xa9, 0x20, 0xa3, 0xca, 0x50, 0x5d, 0x38, 0x2b, 0xbc, 0x54, 0x80, 0x15,
            0x61, 0x00, 0x2c, 0x57, 0x61, 0x00, 0x43, 0x56, 0x5b, 0x50, 0x73])
        let epilogue = Data([
            0x5b, 0x36, 0x3d, 0x3d, 0x37, 0x3d, 0x3d, 0x3d, 0x36, 0x3d, 0x85, 0x5a,
            0xf4, 0x3d, 0x82, 0x80, 0x3e, 0x90, 0x3d, 0x91, 0x60, 0x5b, 0x57, 0xfd,
            0x5b, 0xf3])
        return prologue + target + epilogue
    }

    /// Compose a creation whose only key is this phone.
    ///
    /// `userSalt` is the caller's: it is what makes two accounts from one key
    /// distinct, so it must be random and is never derived here — a salt this
    /// function invented would make the address a function of the key alone,
    /// and a second account impossible.
    ///
    /// `scope: 0` and empty `policyData` match every actor observed on this
    /// chain. **Both remain unmeasured for any other value** (§523), so a
    /// caller wanting a restricted first key is asking for something this
    /// codebase has never seen work.
    /// `keystore`, `defaultAccount` and `authenticator` all come from the LIVE
    /// contract map and are parameters rather than literals — vibenet redeploys
    /// on no schedule, and a pinned address starts naming a contract that no
    /// longer means what this file thinks it does. Passing them in also keeps
    /// this file Foundation-only, so the harness can compile it whole.
    static func plan(keystore: Data,
                     defaultAccount: Data,
                     authenticator: Data,
                     publicKeyXY: Data,
                     userSalt: Data,
                     nonceSequence: UInt64 = 0,
                     gasLimit: UInt64,
                     maxFeePerGas: UInt64,
                     maxPriorityFeePerGas: UInt64,
                     calls: [[VibenetTransaction.Call]] = [],
                     payer: Data = Data(),
                     metadata: Data = Data()) -> Plan? {
        // These three are EARLY EXITS rather than the protection, and the
        // harness says so rather than pretending otherwise: removing them
        // changes nothing observable, because `actorID` re-checks the key,
        // `VibenetAddress.derive` the salt and `.leaf` the authenticator. They
        // are kept because failing at the top of the function is easier to read
        // than a nil arriving from three files away.
        guard publicKeyXY.count == 64, userSalt.count == 32, authenticator.count == 20,
              let actorID = VibenetP256Auth.actorID(publicKeyXY: publicKeyXY),
              let code = proxyCode(forAccount: defaultAccount) else { return nil }

        // The authenticator is the P256 contract itself — the same address the
        // 149-byte `sender_auth` is prefixed with, so the two can never
        // disagree about which verifier is being claimed.
        let actor = VibenetTransaction.InitialActor(
            actorID: actorID,
            authenticator: authenticator,
            scope: 0,
            policyData: Data())

        guard let address = VibenetAddress.derive(keystore: keystore,
                                                  userSalt: userSalt,
                                                  code: code,
                                                  initialActors: [actor]) else { return nil }

        let fields = VibenetTransaction.Fields(
            chainID: VibenetSigner.chainID,
            sender: address,
            nonceSequence: nonceSequence,
            maxPriorityFeePerGas: maxPriorityFeePerGas,
            maxFeePerGas: maxFeePerGas,
            gasLimit: gasLimit,
            accountChanges: [.create(.init(userSalt: userSalt,
                                           code: code,
                                           initialActors: [actor]))],
            // WHAT THE TRANSACTION DOES IS THE CALLER'S, never invented here.
            // A first draft assumed a creation carries one empty call to the
            // new account itself; the real creations do not — one targets
            // `0xb8834191…`, an address this file has no business guessing at.
            // `calls` is signed over, so a fabricated entry is a signature over
            // a transaction nobody asked for. Empty is a legal and honest
            // default: it creates the account and does nothing else.
            calls: calls,
            metadata: metadata,
            payer: payer)

        return Plan(address: address,
                    preimage: VibenetTransaction.senderSigningPreimage(fields),
                    fields: fields,
                    actorID: actorID)
    }
}
