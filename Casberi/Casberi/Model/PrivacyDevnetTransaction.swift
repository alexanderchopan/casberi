import Foundation

/// THE ETHREX PRIVACY TYPE-`0x6` ENVELOPE, AND THE HASH THAT GETS SIGNED
/// (prd §593a amendment, 2026-09-04). Foundation-only BY DESIGN so a `swiftc`
/// harness compiles it WHOLE.
///
/// **Proven against the chain, not read off a spec.** This envelope re-encodes
/// **14 of 14** real type-`0x6` transactions byte-identically, their keccak
/// matching the RPC's own hash 14/14. Two are pinned as fixtures.
///
/// ## HOW IT WAS FOUND, because the method is worth more than the answer
///
/// §593a recorded that this envelope could not be reproduced and that sending
/// was therefore blocked. That was true of the SEARCH and false of the chain. A
/// Swift harness over the shipped RLP enumerated the three places the wire
/// looked ambiguous — eight combinations — reproduced Hegotá byte-exactly as a
/// control, and matched nothing here. The conclusion drawn was "the layout
/// differs and cannot be read", because `debug_getRawTransaction` and both
/// raw-by-hash methods are refused on the public endpoint.
///
/// **The node itself was the oracle the whole time.** `eth_sendRawTransaction`
/// on this chain answers a malformed envelope by NAMING the field it was
/// decoding and its Rust type — `Error decoding field 'nonce_keys' of type
/// alloc::vec::Vec<primitive_types::U256>` — so feeding it progressively longer
/// RLP lists walks the envelope in order, with no guessing. Eight submissions
/// gave eight field names. **Build the cheap instrument, and when it fails, ask
/// whether the SYSTEM can be made to answer rather than searching harder.**
///
/// ## THE EIGHT FIELDS, AND WHY THEY ARE NEITHER SIBLING'S
///
///     chain_id, nonce_keys, nonce, sender, frames, signatures,
///     fees(nested), blob_versioned_hashes, recent_root_references
///
/// Hegotá is **eleven, flat**. Frames is **seven**, with the three fees NESTED
/// and no keyed nonces. This is Frames' nested-fee shape PLUS Hegotá's keyed
/// nonces PLUS recent roots — a third arrangement, which is why neither
/// sibling's encoder can produce it and why this is a separate file rather
/// than a parameter.
///
/// ## FOUR THINGS THAT SILENTLY PRODUCE A WRONG SIGNATURE
///
/// 1. **The fee triple is NESTED.** Flattening it encodes cleanly, hashes to
///    something, and is refused — Frames' own recorded lesson, and the node
///    here confirms it by naming `fees` as one field.
/// 2. **`recentRootReferences` comes LAST, after the blob hashes.** Putting it
///    before them is a decode error, which is at least loud; putting it in a
///    plausible-looking earlier slot would not be.
/// 3. **`signer` is written LITERAL**, measured 9 of 9 on signed transactions
///    here — the opposite of Hegotá, which writes it EMPTY (measured 0/5). The
///    empty form is not merely different: it changes the hash.
/// 4. **A `sourceID` is 32 BYTES.** `HegotaTransaction.RootReference` types it
///    as `UInt64`, which cannot hold one — a width that no chain it was written
///    for could ever disprove, since `0x…8272` has no code on Hegotá.
enum PrivacyDevnetTransaction {

    /// Measured off this chain's own type census: `0x2` and `0x6`, nothing else.
    static let txType: UInt8 = 0x06

    /// A frame: `[mode, flags, target, [gasLimit, stateLimit], value, data]`.
    ///
    /// **The two budgets are a nested pair here, and they are spelled
    /// `gasLimit`/`stateLimit` on the wire** — Hegotá says
    /// `executionGasLimit`/`stateGasLimit` and Frames says
    /// `gasLimit`/`stateGasLimit`. Three chains, three spellings; a READER
    /// written for one draws nil budgets on another, which renders as frames
    /// that had no budget at all.
    struct Frame: Equatable, Sendable {
        var mode: UInt64
        var flags: UInt64
        /// Empty means the sender.
        var target: Data
        var gasLimit: UInt64
        var stateLimit: UInt64
        /// Big-endian, and canonically MINIMAL when encoded — see `item`.
        var value: Data
        var data: Data

        var item: RLP.Item {
            .list([.bytes(RLP.quantity(mode)),
                   .bytes(RLP.quantity(flags)),
                   .bytes(target),
                   .list([.bytes(RLP.quantity(gasLimit)),
                          .bytes(RLP.quantity(stateLimit))]),
                   // **A QUANTITY**, so a value of zero is EMPTY and not one
                   // zero byte. `0x0` and `0x00` are different encodings and
                   // only the first is canonical — the encoder failed both
                   // fixtures on exactly this before it was caught by diffing
                   // against a known-good encoding rather than by reading.
                   .bytes(RLP.minimal(value)),
                   .bytes(data)])
        }
    }

    /// A signature entry: `[scheme, signer, msg, signature]`.
    struct Signature: Equatable, Sendable {
        var scheme: UInt64
        /// **LITERAL on this chain**, unlike Hegotá — see trap 3.
        var signer: Data
        /// EMPTY selects "sign the transaction's own hash"; 32 bytes selects
        /// "sign this digest directly".
        var msg: Data
        var signature: Data

        var isElided: Bool { msg.isEmpty }

        func item(elided: Bool) -> RLP.Item {
            .list([.bytes(RLP.quantity(scheme)),
                   .bytes(signer),
                   .bytes(msg),
                   .bytes(elided && isElided ? Data() : signature)])
        }
    }

    /// A recent-root reference: `[source_id, slot, root]`.
    ///
    /// `sourceID` and `root` are 32 bytes; only `slot` is a quantity.
    struct RootReference: Equatable, Sendable {
        var sourceID: Data
        var slot: UInt64
        var root: Data
        var item: RLP.Item {
            .list([.bytes(sourceID),
                   .bytes(RLP.quantity(slot)),
                   .bytes(root)])
        }
    }

    /// The eight envelope fields, in the order the node's own decoder reads
    /// them.
    struct Fields: Equatable, Sendable {
        var chainID: UInt64
        /// Keyed nonces (EIP-8250). On THIS chain they double as nullifiers:
        /// the pool emits every spent key as a log topic byte-identical to the
        /// value here.
        var nonceKeys: [Data]
        /// A scalar sequence within the key set. Named `nonce` by the node.
        var nonce: UInt64
        var sender: Data
        var frames: [Frame]
        var signatures: [Signature]
        var maxPriorityFeePerGas: UInt64
        var maxFeePerGas: UInt64
        var maxFeePerBlobGas: UInt64
        var blobVersionedHashes: [Data]
        var recentRootReferences: [RootReference]
    }

    /// The eight fields as RLP. `elided` chooses between the bytes that get
    /// SIGNED and the bytes that get SENT.
    ///
    /// One function for both, deliberately: two encoders differing by one flag
    /// is how a transaction gets signed in one shape and broadcast in another.
    static func body(_ f: Fields, elided: Bool) -> [RLP.Item] {
        [.bytes(RLP.quantity(f.chainID)),
         // **QUANTITIES, not fixed-width bytes.** The node types these
         // `Vec<U256>`, so RLP's minimal-integer rule applies and a leading
         // zero is STRIPPED — a real key beginning `0x0c…` rides the wire as 31
         // bytes. Writing the padded 32 changes the hash, which is how the
         // first cut of this encoder failed both fixtures while a Python
         // prototype that happened to strip them passed.
         .list(f.nonceKeys.map { .bytes(RLP.minimal($0)) }),
         .bytes(RLP.quantity(f.nonce)),
         .bytes(f.sender),
         .list(f.frames.map(\.item)),
         .list(f.signatures.map { $0.item(elided: elided) }),
         // NESTED — see trap 1.
         .list([.bytes(RLP.quantity(f.maxPriorityFeePerGas)),
                .bytes(RLP.quantity(f.maxFeePerGas)),
                .bytes(RLP.quantity(f.maxFeePerBlobGas))]),
         .list(f.blobVersionedHashes.map { .bytes($0) }),
         // LAST — see trap 2.
         .list(f.recentRootReferences.map(\.item))]
    }

    /// The bytes hashed to produce what a signature entry with an empty `msg`
    /// signs.
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
