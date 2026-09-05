import Foundation

/// A SHIELDED NOTE, AND THE ARITHMETIC THAT PUTS ONE IN THE POOL (prd §593e).
///
/// A note is the pool's private unit of value: `(spendKey, rho, value)`, whose
/// on-chain shadow is the commitment `Poseidon(TAG_LEAF, inner, value)` with
/// `inner = Poseidon(ownerPk(spendKey), rho)`. **Shield** creates one and adds
/// its commitment as a tree leaf; the shielded **balance** ("View") is the sum
/// of the notes whose nullifier has not yet appeared on-chain.
///
/// This file is deliberately Foundation-only and holds NO secrets and NO
/// keychain — it is the pure math, compiled WHOLE by `privacy-poseidon-selftest.sh`
/// and checked against the same live values that landed a real shield on chain
/// 8141 (`shield(bytes32)`'s selector, the note chain, the depth-20 tree). The
/// secret storage and the signing/broadcast live in `PrivacyDevnetSend`, which
/// is where the app's keychain and RPC already are.
///
/// **Unshield is deliberately NOT here.** Spending a note needs a Groth16 proof
/// generated on-device, which is a native prover integration (rapidsnark-class)
/// held as its own scoped step (prd §593e ruling). Everything up to the proof —
/// the tree, the nullifier, the value conservation — is expressible here when
/// that lands; today this file carries only what Shield and View need.
enum PrivacyDevnetNote {

    typealias Fp = PrivacyDevnetPoseidon.Fp

    /// The pool's Merkle depth (mirrors `circuits/spend.circom` DEPTH=20).
    static let treeDepth = 20

    /// `shield(bytes32)`'s selector, `keccak256("shield(bytes32)")[0..<4]`.
    /// A fixed constant so this file needs no keccak and stays Foundation-only;
    /// it is the first four bytes of every shield transaction's second frame on
    /// this chain (measured, `0x26123548...`).
    static let shieldSelector: [UInt8] = [0x26, 0x12, 0x35, 0x48]

    /// The `inner` a shield transaction carries in its calldata. The pool
    /// recomputes the commitment itself from `inner` and `msg.value`, so the
    /// wire carries `inner`, never the commitment.
    static func inner(spendKey: Fp, rho: Fp) -> Fp {
        PrivacyDevnetPoseidon.inner(spendKey: spendKey, rho: rho)
    }

    /// The tree leaf a shield of `value` under `inner` produces —
    /// `Poseidon(TAG_LEAF, inner, value)`. What the pool emits in `LeafAppended`.
    static func commitment(inner: Fp, value: Fp) -> Fp {
        PrivacyDevnetPoseidon.commitment(inner: inner, value: value)
    }

    /// The calldata for `shield(bytes32 inner)`: selector ‖ 32-byte inner.
    static func shieldCalldata(inner: Fp) -> [UInt8] {
        shieldSelector + inner.bytesBE()
    }

    /// A field element from a hex WEI quantity (`"0x16345785d8a0000"`), which is
    /// how the amount rides the wire and how `msg.value` reaches the pool. A
    /// shield value is a native-ETH amount, always well below the pool's
    /// `MAX_VALUE = 2^128`, so it is a canonical field element by construction.
    static func fp(weiHex: String) -> Fp {
        var t = weiHex.hasPrefix("0x") ? String(weiHex.dropFirst(2)) : weiHex
        if t.isEmpty { t = "0" }
        if t.count % 2 == 1 { t = "0" + t }
        var bytes = [UInt8]()
        var i = t.startIndex
        while i < t.endIndex {
            let j = t.index(i, offsetBy: 2)
            bytes.append(UInt8(t[i..<j], radix: 16) ?? 0)
            i = j
        }
        // Left-pad to 32 big-endian bytes.
        if bytes.count > 32 { bytes = Array(bytes.suffix(32)) }
        let padded = [UInt8](repeating: 0, count: 32 - bytes.count) + bytes
        return Fp(bytesBE: padded)
    }

    /// A field element from raw big-endian bytes (a `LeafAppended` topic, a
    /// stored note's hex).
    static func fp(bytesBE b: [UInt8]) -> Fp {
        if b.count == 32 { return Fp(bytesBE: b) }
        if b.count > 32 { return Fp(bytesBE: Array(b.suffix(32))) }
        return Fp(bytesBE: [UInt8](repeating: 0, count: 32 - b.count) + b)
    }

    /// The incremental Merkle root over `leaves` at the pool's fixed depth,
    /// left-filled with the canonical zero subtree — `Poseidon(left, right)`
    /// pairing, exactly the pool's `_computeRoot`. Used to CHECK that a leaf
    /// this device believes it shielded really sits in the tree the chain
    /// published, never to produce a proof.
    static func merkleRoot(leaves: [Fp]) -> Fp {
        // Precompute zero subtree roots: zeros[0] = 0, zeros[k] = H(z,z).
        var zeros = [Fp.zero]
        for _ in 0..<treeDepth {
            zeros.append(PrivacyDevnetPoseidon.p2(zeros[zeros.count - 1], zeros[zeros.count - 1]))
        }
        if leaves.isEmpty { return zeros[treeDepth] }
        var level = leaves
        for depth in 0..<treeDepth {
            var next = [Fp]()
            var i = 0
            while i < level.count {
                let left = level[i]
                let right = i + 1 < level.count ? level[i + 1] : zeros[depth]
                next.append(PrivacyDevnetPoseidon.p2(left, right))
                i += 2
            }
            level = next
        }
        return level[0]
    }
}
