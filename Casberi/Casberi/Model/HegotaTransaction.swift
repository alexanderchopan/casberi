import Foundation

/// THE EIP-8141 FRAME TRANSACTION, AND THE HASH THAT GETS SIGNED
/// (prd §525, 2026-08-29). Foundation-only BY DESIGN so a `swiftc` harness
/// compiles it WHOLE.
///
/// **Proven against the chain, not read off a spec.** The envelope below
/// re-encodes 356 of 356 real frame transactions byte-identically, their
/// keccak matches the RPC's own hash 356/356, and 324 of 324 signatures
/// recover to their declared signer. Two of those are pinned as fixtures.
///
/// ## FOUR THINGS THAT SILENTLY PRODUCE A WRONG SIGNATURE
///
/// 1. **`v ‖ r ‖ s` — the recovery byte comes FIRST**, and `v` is a bare 0/1,
///    never 27/28. `r ‖ s ‖ v` recovers nothing here. This is the reverse of
///    the usual Ethereum layout and is the easiest thing on this chain to get
///    wrong while looking right.
/// 2. **The elision rule is PER ENTRY, not per transaction.** A signature
///    entry with an EMPTY `msg` signs the transaction's own `sigHash`, and its
///    own bytes are blanked out of that hash — the entry stays, its signature
///    field goes empty. An entry carrying a 32-byte `msg` signs that digest
///    DIRECTLY and its bytes REMAIN committed. One real transaction carries
///    both kinds and both recover; blank both and neither does.
/// 3. **`limits` forks shape mid-chain.** A bare scalar in blocks
///    127–244,624, a two-element `[execution, state]` list from 291,781 on,
///    with no overlap. Not accepted polymorphism — a fork. **Write the
///    2-element form**; the wrong shape changes the RLP and therefore the
///    hash, so the signature simply fails.
/// 4. **An empty `signer` or `target` means "the sender".** 3 of 324 signature
///    entries and 22 of 957 frames are empty there. It must stay EMPTY in the
///    bytes and be substituted only when verifying — writing the address in
///    changes the hash.
///
/// ## AND ONE TRAP IN READING IT BACK
///
/// `debug_getRawTransaction` returns the transaction wrapped in ONE MORE RLP
/// byte-string header (`0xb8cc…`). The bytes that hash to the transaction hash
/// are the payload inside it, starting `0x06`. Comparing our output against
/// the RPC's response without stripping that header fails for a reason that
/// looks like an encoder bug and is not.
enum HegotaTransaction {

    /// Measured off this chain's own type census: 431 `0x2` and 356 `0x6`, no
    /// other type anywhere.
    static let txType: UInt8 = 0x06

    /// A frame: `[mode, flags, target, limits, value, data]`.
    struct Frame: Equatable {
        var mode: UInt64
        var flags: UInt64
        /// Empty means the sender — see trap 4.
        var target: Data
        var executionGas: UInt64
        var stateGas: UInt64
        var value: Data
        var data: Data

        /// The modern two-element `[execution, state]` form. See trap 3 for why
        /// the scalar form is not written even though the chain contains it.
        var item: RLP.Item {
            .list([.bytes(RLP.quantity(mode)),
                   .bytes(RLP.quantity(flags)),
                   .bytes(target),
                   .list([.bytes(RLP.quantity(executionGas)),
                          .bytes(RLP.quantity(stateGas))]),
                   .bytes(value),
                   .bytes(data)])
        }
    }

    /// A signature entry: `[scheme, signer, msg, signature]`.
    struct Signature: Equatable {
        var scheme: UInt64
        /// Empty means the sender — see trap 4.
        var signer: Data
        /// EMPTY selects "sign the transaction's own sigHash"; 32 bytes selects
        /// "sign this digest directly". An all-zero 32-byte msg is a different,
        /// reserved thing — absence and zero are not the same here.
        var msg: Data
        var signature: Data

        /// Whether this entry's bytes are blanked when computing the sigHash.
        /// The whole of the per-entry elision rule, in one place.
        var isElided: Bool { msg.isEmpty }

        func item(elided: Bool) -> RLP.Item {
            .list([.bytes(RLP.quantity(scheme)),
                   .bytes(signer),
                   .bytes(msg),
                   .bytes(elided && isElided ? Data() : signature)])
        }
    }

    /// A recent-root reference: `[source_id, slot, root]`.
    struct RootReference: Equatable {
        var sourceID: UInt64
        var slot: UInt64
        var root: Data
        var item: RLP.Item {
            .list([.bytes(RLP.quantity(sourceID)),
                   .bytes(RLP.quantity(slot)),
                   .bytes(root)])
        }
    }

    /// The eleven envelope fields, in the order the chain hashes them.
    struct Fields: Equatable {
        var chainID: UInt64
        /// Keyed nonces (EIP-8250). The top-level `nonce` an RPC reports is a
        /// LOSSY projection of these — two transactions from one sender with
        /// the same `nonce` on disjoint key sets are both valid, in either
        /// order.
        var nonceKeys: [UInt64]
        var nonceSequence: UInt64
        var sender: Data
        var frames: [Frame]
        var signatures: [Signature]
        var maxPriorityFeePerGas: UInt64
        var maxFeePerGas: UInt64
        var maxFeePerBlobGas: UInt64
        var blobVersionedHashes: [Data]
        var recentRootReferences: [RootReference]
    }

    /// The eleven fields as RLP. `elided` chooses between the bytes that get
    /// SIGNED and the bytes that get SENT — the only difference is whether
    /// empty-`msg` signature entries carry their signature.
    ///
    /// One function for both, deliberately: two encoders differing by one flag
    /// is how a transaction gets signed in one shape and broadcast in another.
    static func body(_ f: Fields, elided: Bool) -> [RLP.Item] {
        [.bytes(RLP.quantity(f.chainID)),
         .list(f.nonceKeys.map { .bytes(RLP.quantity($0)) }),
         .bytes(RLP.quantity(f.nonceSequence)),
         .bytes(f.sender),
         .list(f.frames.map(\.item)),
         .list(f.signatures.map { $0.item(elided: elided) }),
         .bytes(RLP.quantity(f.maxPriorityFeePerGas)),
         .bytes(RLP.quantity(f.maxFeePerGas)),
         .bytes(RLP.quantity(f.maxFeePerBlobGas)),
         .list(f.blobVersionedHashes.map { .bytes($0) }),
         .list(f.recentRootReferences.map(\.item))]
    }

    /// The bytes that get hashed to produce what a signature entry with an
    /// empty `msg` signs.
    static func signingPreimage(_ f: Fields) -> Data {
        Data([txType]) + RLP.encode(.list(body(f, elided: true)))
    }

    /// The bytes that get broadcast — and whose keccak IS the transaction
    /// hash, which is the cheapest possible end-to-end check that an encoder is
    /// right.
    static func encoded(_ f: Fields) -> Data {
        Data([txType]) + RLP.encode(.list(body(f, elided: false)))
    }
}
