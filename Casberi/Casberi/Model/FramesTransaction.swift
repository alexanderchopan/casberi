import Foundation

/// THE EIP-8141 FRAME TRANSACTION ON THE FRAMES DEVNET, AND THE HASH THAT
/// GETS SIGNED (prd §548, 2026-09-01). Foundation-only BY DESIGN so
/// `scripts/frames-tx-selftest.sh` compiles it WHOLE.
///
/// ## THIS IS NOT `HegotaTransaction`, AND THE DIFFERENCE IS SILENT
///
/// Both chains run ethrex, both serve type `0x06`, both call it EIP-8141 —
/// and their envelopes are different lists. Hegotá hashes **eleven** flat
/// fields; this chain hashes **seven**, with the three fee fields folded into
/// a nested list of their own:
///
/// ```
/// FRAMES    0x06 || rlp([chain_id, nonce, sender, frames, signatures,
///                        [max_priority_fee, max_fee, max_fee_per_blob_gas],
///                        blob_hashes])
///
/// HEGOTÁ    0x06 || rlp([chain_id, nonce_keys, nonce_seq, sender, frames,
///                        signatures, max_priority_fee, max_fee,
///                        max_fee_per_blob_gas, blob_hashes,
///                        recent_root_references])
/// ```
///
/// Three shapes differ: `nonce` is a SCALAR here where Hegotá carries keyed
/// nonces (EIP-8250, which this chain does not implement — no transaction on
/// it has ever carried `nonceKeys`), `fees` is a NESTED list where Hegotá's
/// are flat, and there is no `recent_root_references` field at all.
///
/// **Signing with the wrong one does not fail loudly.** It produces a
/// well-formed signature over a different digest, which recovers to a real
/// address — just not to a transaction anybody meant. That is why this file
/// exists rather than a `chain:` parameter on Hegotá's, and why its fixtures
/// are real mined transactions rather than hand-written vectors.
///
/// ## PROVEN AGAINST THE CHAIN, NOT READ OFF A SPEC
///
/// Measured 2026-09-01 against every type-`0x06` transaction on chain 81410:
/// the envelope below re-encodes **5 of 5** byte-identically and their keccak
/// matches the RPC's own `hash` 5/5; **5 of 5** signatures recover to their
/// declared signer against the elided preimage. Two are pinned as fixtures.
/// Five is the whole population — the chain opened on 2026-08-28 — so this is
/// a complete census rather than a sample, and it is also a small one: re-run
/// the harness against a wider population once the chain has one.
///
/// ## WHAT CARRIES OVER FROM HEGOTÁ UNCHANGED, AND IS STILL LOAD-BEARING
///
/// 1. **`v ‖ r ‖ s` — the recovery byte comes FIRST**, and `v` is a bare 0/1,
///    never 27/28. The faucet's own error guide calls this "the single most
///    common reason a hand-built frame transaction is refused". Confirmed here
///    by recovery, 5/5.
/// 2. **The elision rule is PER ENTRY, not per transaction.** A signature
///    entry with an EMPTY `msg` signs the transaction's own sigHash and its
///    own signature bytes are blanked out of that hash — the entry stays, the
///    signature field goes empty. A 32-byte `msg` signs that digest directly
///    and its bytes REMAIN committed. All five fixtures are the empty-`msg`
///    kind; the 32-byte kind is unexercised on this chain and is written to
///    Hegotá's proven rule.
/// 3. **The gas slot is a two-element `[execution, state]` list**, never a
///    scalar. The faucet lists the scalar form as its first common error.
///
/// ## THE ONE RULE THAT IS UNPROVEN HERE
///
/// On Hegotá an EMPTY `signer` or `target` means "the sender" and must stay
/// empty in the bytes (22 of 957 frames, 3 of 324 signatures). **No
/// transaction on this chain has ever used it** — all 5 write both literally,
/// which the harness pins — so the convention is carried over from the shared
/// spec rather than measured. It fails safe: this file only ever WRITES what
/// it is given, so an empty stays empty and a literal stays literal.
enum FramesTransaction {

    /// Measured off this chain's own type census, blocks 0–56,503:
    /// 14 `0x2`, 5 `0x6`, 1 `0x0`, no other type anywhere.
    static let txType: UInt8 = 0x06

    /// The chain this file encodes for. A `chainID` field that disagreed with
    /// the chain the bytes are sent to produces a signature the node refuses
    /// with no useful reason, so it is named here beside the envelope rather
    /// than passed in from a screen.
    static let chainID: UInt64 = 81410

    // MARK: - The pieces

    /// A frame: `[mode, flags, target, [execution, state], value, data]`.
    ///
    /// **Two gas budgets, and they are not interchangeable.** `execution` pays
    /// for running code, `state` pays for state growth. Execution gas cannot
    /// cover state growth, so a frame that writes new state with `state: 0`
    /// halts on that write and burns its whole execution budget — which reads
    /// exactly like an execution limit set too low. That is the failure the
    /// room's two-bar figure exists to tell apart.
    struct Frame: Equatable {
        /// `0` DEFAULT (called by the entry point), `1` VERIFY (static; where
        /// authorisation happens), `2` SENDER (executes with `tx.sender` as
        /// the caller).
        var mode: UInt64
        /// Bits 0 and 1 are the `APPROVE` scope; bit 2 marks an atomic batch,
        /// which must be terminated by a following non-batch frame.
        var flags: UInt64
        /// Empty means the sender — see the type doc; unproven on this chain.
        var target: Data
        var executionGas: UInt64
        var stateGas: UInt64
        var value: Data
        var data: Data

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
        /// `1` is secp256k1 and the only scheme this chain has ever seen.
        var scheme: UInt64
        /// Empty means the sender — see the type doc.
        var signer: Data
        /// EMPTY selects "sign the transaction's own sigHash"; 32 bytes
        /// selects "sign this digest directly". An all-zero 32-byte `msg` is a
        /// different, reserved thing — absence and zero are not the same here.
        var msg: Data
        var signature: Data

        /// Only an empty-`msg` entry is elided. See rule 2 in the type doc.
        var isElided: Bool { msg.isEmpty }

        func item(elided: Bool) -> RLP.Item {
            .list([.bytes(RLP.quantity(scheme)),
                   .bytes(signer),
                   .bytes(msg),
                   .bytes(elided && isElided ? Data() : signature)])
        }
    }

    // MARK: - The envelope

    /// The seven envelope fields, in the order the chain hashes them.
    struct Fields: Equatable {
        var chainID: UInt64
        /// A plain scalar. This chain implements no keyed nonces, so unlike
        /// Hegotá there is no lossy-projection caveat: the `nonce` an RPC
        /// reports IS the nonce that gets hashed.
        var nonce: UInt64
        var sender: Data
        var frames: [Frame]
        var signatures: [Signature]
        var maxPriorityFeePerGas: UInt64
        var maxFeePerGas: UInt64
        var maxFeePerBlobGas: UInt64
        var blobVersionedHashes: [Data]
    }

    /// The seven fields as RLP. `elided` chooses between the bytes that get
    /// SIGNED and the bytes that get SENT — the only difference is whether
    /// empty-`msg` signature entries carry their signature.
    ///
    /// One function for both, deliberately: two encoders differing by one flag
    /// is how a transaction gets signed in one shape and broadcast in another.
    ///
    /// **The fee list is nested and that is the whole of this function's
    /// divergence from Hegotá.** Flattening it produces a six-field list that
    /// encodes cleanly, hashes to something, and is refused.
    static func body(_ f: Fields, elided: Bool) -> [RLP.Item] {
        [.bytes(RLP.quantity(f.chainID)),
         .bytes(RLP.quantity(f.nonce)),
         .bytes(f.sender),
         .list(f.frames.map(\.item)),
         .list(f.signatures.map { $0.item(elided: elided) }),
         .list([.bytes(RLP.quantity(f.maxPriorityFeePerGas)),
                .bytes(RLP.quantity(f.maxFeePerGas)),
                .bytes(RLP.quantity(f.maxFeePerBlobGas))]),
         .list(f.blobVersionedHashes.map { .bytes($0) })]
    }

    /// The bytes that get hashed to produce what a signature entry with an
    /// empty `msg` signs.
    static func signingPreimage(_ f: Fields) -> Data {
        Data([txType]) + RLP.encode(.list(body(f, elided: true)))
    }

    /// The bytes that get broadcast — and whose keccak IS the transaction
    /// hash, which is the cheapest possible end-to-end check that an encoder
    /// is right.
    static func encoded(_ f: Fields) -> Data {
        Data([txType]) + RLP.encode(.list(body(f, elided: false)))
    }

    // MARK: - The smallest useful transaction

    /// **A VERIFY frame then a SENDER frame**, which is the minimum this chain
    /// accepts: without an `APPROVE` the transaction has no payer and is
    /// invalid. The VERIFY frame targets the sender with `flags = 0x03` — the
    /// two `APPROVE` scope bits, execution and payment — which runs the
    /// default code path, checks the outer signature and approves both.
    ///
    /// Every one of the five real transactions on this chain has exactly this
    /// shape, and the harness pins that.
    ///
    /// `stateGas` defaults to 250,000 because that is what the faucet's own
    /// guidance says covers a transfer to an address that does not exist yet —
    /// and a transfer to a fresh address is the common case on a devnet whose
    /// accounts are minutes old. Sending with `state: 0` would halt on that
    /// write and report an execution failure.
    static func transfer(sender: Data,
                         to recipient: Data,
                         value: Data,
                         nonce: UInt64,
                         maxPriorityFeePerGas: UInt64,
                         maxFeePerGas: UInt64,
                         executionGas: UInt64 = 100_000,
                         stateGas: UInt64 = 250_000) -> Fields {
        Fields(chainID: chainID,
               nonce: nonce,
               sender: sender,
               frames: [
                   Frame(mode: 1, flags: 0x03, target: sender,
                         executionGas: executionGas, stateGas: stateGas,
                         value: Data(), data: Data()),
                   Frame(mode: 2, flags: 0x00, target: recipient,
                         executionGas: executionGas, stateGas: stateGas,
                         value: value, data: Data()),
               ],
               signatures: [],
               maxPriorityFeePerGas: maxPriorityFeePerGas,
               maxFeePerGas: maxFeePerGas,
               maxFeePerBlobGas: 0,
               blobVersionedHashes: [])
    }

    /// ONE LEG OF A STITCHED TRANSACTION.
    struct Leg: Equatable {
        var recipient: Data
        var value: Data
    }

    /// **THE FLAG THAT MAKES A BATCH ALL-OR-NOTHING**, and the whole reason a
    /// stitched send needs a control rather than a promise.
    ///
    /// MEASURED ON THIS CHAIN, 2026-09-01, by sending two transactions with the
    /// same shape and the same failure in their last frame and then reading the
    /// RECIPIENTS' BALANCES back — not the `status` field, which is the one
    /// thing on this chain that cannot be trusted for this:
    ///
    /// - `0x9bb9cfef…`, payload flags `0x0`: transaction status `0x0`, and
    ///   frame 1's recipient **holds 0.001 ETH to this day**. The money moved
    ///   and stayed moved inside a transaction that reports failure.
    /// - `0x2642331b…`, payload flags `0x4`: transaction status `0x0`, and
    ///   frame 1's recipient holds **zero**. Undone.
    ///
    /// So atomicity is REAL and OPT-IN. A stitched send that does not set this
    /// is a send where leg 3 failing leaves legs 1 and 2 gone — which is true
    /// of no other send anywhere in this app, and is why the control has to
    /// say what OFF means rather than only what ON means.
    static let atomicFlag: UInt64 = 0x04

    /// SEVERAL PAYLOAD FRAMES UNDER ONE SIGNATURE.
    ///
    /// `transfer` is this with exactly one leg, and is kept rather than folded
    /// into it: it is what the byte-exact fixtures in
    /// `scripts/frames-tx-selftest.sh` pin, and a builder proven against the
    /// chain should not be re-derived to add a feature it does not use.
    ///
    /// **The VERIFY frame is built, never chosen.** It is `mode 1, flags 0x03`
    /// targeting the sender, and it heads all 34 frame transactions this chain
    /// has ever carried. It is not a leg, it takes no value, and no picker
    /// offers it — exposing it would expose plumbing rather than a choice.
    ///
    /// **The atomic flag goes on EVERY payload frame, not just the first.**
    /// Only the first-frame case is measured (above), and the frame-by-frame
    /// reading of it — each frame carrying "undo me if a later one fails" — is
    /// the one that generalises; setting it on the last frame is harmless
    /// since nothing follows. The alternative reading, that one flagged frame
    /// governs the whole batch, would leave legs 2..n unprotected while the
    /// control claimed otherwise, which is the more expensive way to be wrong.
    static func stitched(sender: Data,
                         legs: [Leg],
                         atomic: Bool,
                         nonce: UInt64,
                         maxPriorityFeePerGas: UInt64,
                         maxFeePerGas: UInt64,
                         executionGas: UInt64 = 100_000,
                         stateGas: UInt64 = 250_000) -> Fields {
        let payloadFlags: UInt64 = atomic ? atomicFlag : 0x00
        return Fields(chainID: chainID,
                      nonce: nonce,
                      sender: sender,
                      frames: [Frame(mode: 1, flags: 0x03, target: sender,
                                     executionGas: executionGas, stateGas: stateGas,
                                     value: Data(), data: Data())]
                          + legs.map {
                              Frame(mode: 2, flags: payloadFlags, target: $0.recipient,
                                    executionGas: executionGas, stateGas: stateGas,
                                    value: $0.value, data: Data())
                          },
                      signatures: [],
                      maxPriorityFeePerGas: maxPriorityFeePerGas,
                      maxFeePerGas: maxFeePerGas,
                      maxFeePerBlobGas: 0,
                      blobVersionedHashes: [])
    }

    /// The validation prefix is bounded at 500,000 gas on this chain — frames
    /// plus signature cost. Stated here so a builder can refuse before the
    /// node does, since the node's refusal for this is one sentence about
    /// `MAX_VERIFY_GAS` that names no remedy.
    static let maxVerifyGas: UInt64 = 500_000

    /// Does this transaction's validation prefix fit? Only mode-1 frames sit
    /// in the prefix.
    static func prefixWithinBudget(_ f: Fields) -> Bool {
        let prefix = f.frames.filter { $0.mode == 1 }
            .reduce(UInt64(0)) { $0 &+ $1.executionGas }
        return prefix <= maxVerifyGas
    }
}
