import Foundation

/// POSEIDON OVER BN254, THE SHIELDED POOL'S ONE HASH (prd §593e, 2026-09-05).
///
/// Ethrex Privacy's pool is `lambdaclass/minimal-shielded-pool`, and every
/// secret it holds is a Poseidon hash over the BN254 **scalar** field: a note
/// is `Poseidon(TAG_LEAF, Poseidon(ownerPk, rho), value)`, a nullifier is
/// `Poseidon(TAG_NULL, Poseidon(domain, spendKey), commitment)`, and the
/// Merkle tree pairs with `Poseidon(left, right)`. Shield needs the commitment;
/// unshield needs all of it plus the tree. So this is the floor the whole seat
/// stands on, and it is verified against the repo's own circomlibjs vectors by
/// `privacy-poseidon-selftest.sh` before anything trusts a number it produced —
/// a wrong hash here is a deposit nobody can ever spend and a proof that never
/// verifies, both of which render as an app that simply does not work.
///
/// **This is field arithmetic, not a component, so it is written out rather
/// than reused** — the "don't hand-roll" rule is about UI, and there is no
/// existing 254-bit modular field in this tree. The algorithm (x^5 S-box, 8
/// full rounds, 57/56 partial, the circomlibjs mix convention
/// `new[i] = Σ M[i][j]·state[j]`) mirrors `reference/poseidon_bn254.py`
/// exactly, and the constants are GENERATED from the same JSON that file reads
/// (`PrivacyDevnetPoseidonConstants`), never retyped.
enum PrivacyDevnetPoseidon {

    /// The BN254 scalar field element, four little-endian 64-bit limbs held in
    /// **Montgomery form** (`a·R mod p`, `R = 2^256`). Montgomery is the point:
    /// a single commitment is ~195 field multiplies and each one would
    /// otherwise need a 512-bit division; CIOS turns every one into shifts and
    /// 64-bit multiplies. Normal form is only ever seen at the boundary
    /// (`init(limbs:)` in, `words()`/`bytes()` out).
    struct Fp: Equatable {
        var v: (UInt64, UInt64, UInt64, UInt64)

        static func == (a: Fp, b: Fp) -> Bool {
            a.v.0 == b.v.0 && a.v.1 == b.v.1 && a.v.2 == b.v.2 && a.v.3 == b.v.3
        }

        // BN254 scalar modulus p, little-endian limbs.
        static let p: (UInt64, UInt64, UInt64, UInt64) =
            (0x43e1f593f0000001, 0x2833e84879b97091, 0xb85045b68181585d, 0x30644e72e131a029)
        // -p^{-1} mod 2^64.
        static let inv64: UInt64 = 0xc2e1f593efffffff
        // R^2 mod p, for converting NORMAL → Montgomery via one montmul.
        static let r2: (UInt64, UInt64, UInt64, UInt64) =
            (0x1bb8e645ae216da7, 0x53fe3ab1e35c59e3, 0x8c49833d53bb8085, 0x0216d0b17f4e44a5)

        static let zero = Fp(v: (0, 0, 0, 0))

        /// From NORMAL little-endian limbs (already reduced mod p not required —
        /// values below p in practice, and montmul-by-R^2 reduces regardless).
        init(v: (UInt64, UInt64, UInt64, UInt64)) { self.v = v }

        init(limbs: [UInt64]) {
            precondition(limbs.count == 4)
            // NORMAL a → Montgomery: montmul(a, R^2) = a·R^2·R^{-1} = a·R.
            self = Fp.montmul(Fp(v: (limbs[0], limbs[1], limbs[2], limbs[3])),
                              Fp(v: Fp.r2))
        }

        init(_ small: UInt64) { self.init(limbs: [small, 0, 0, 0]) }

        /// From a big-endian 32-byte encoding (how the chain and the wire carry
        /// a field element). Reduced mod p by construction of the montmul.
        init(bytesBE b: [UInt8]) {
            precondition(b.count == 32)
            var limbs = [UInt64](repeating: 0, count: 4)
            for i in 0..<4 {
                var w: UInt64 = 0
                for j in 0..<8 { w = (w << 8) | UInt64(b[i * 8 + j]) }
                limbs[3 - i] = w
            }
            self.init(limbs: limbs)
        }

        /// NORMAL little-endian limbs (Montgomery → normal is montmul by 1).
        func words() -> [UInt64] {
            let n = Fp.montmul(self, Fp(v: (1, 0, 0, 0)))
            return [n.v.0, n.v.1, n.v.2, n.v.3]
        }

        /// Canonical big-endian 32 bytes.
        func bytesBE() -> [UInt8] {
            let w = words()
            var out = [UInt8](repeating: 0, count: 32)
            for i in 0..<4 {
                let limb = w[3 - i]
                for j in 0..<8 { out[i * 8 + j] = UInt8((limb >> (56 - 8 * j)) & 0xff) }
            }
            return out
        }

        // MARK: field ops

        static func add(_ a: Fp, _ b: Fp) -> Fp {
            var r = [UInt64](repeating: 0, count: 4)
            var carry: UInt64 = 0
            let av = [a.v.0, a.v.1, a.v.2, a.v.3], bv = [b.v.0, b.v.1, b.v.2, b.v.3]
            for i in 0..<4 {
                let (s1, c1) = av[i].addingReportingOverflow(bv[i])
                let (s2, c2) = s1.addingReportingOverflow(carry)
                r[i] = s2; carry = (c1 ? 1 : 0) + (c2 ? 1 : 0)
            }
            return reduceOnce(r, extra: carry)
        }

        static func sub(_ a: Fp, _ b: Fp) -> Fp {
            var r = [UInt64](repeating: 0, count: 4)
            var borrow: UInt64 = 0
            let av = [a.v.0, a.v.1, a.v.2, a.v.3], bv = [b.v.0, b.v.1, b.v.2, b.v.3]
            for i in 0..<4 {
                let (d1, br1) = av[i].subtractingReportingOverflow(bv[i])
                let (d2, br2) = d1.subtractingReportingOverflow(borrow)
                r[i] = d2; borrow = (br1 ? 1 : 0) + (br2 ? 1 : 0)
            }
            if borrow != 0 { // add p back
                let p = [Fp.p.0, Fp.p.1, Fp.p.2, Fp.p.3]
                var carry: UInt64 = 0
                for i in 0..<4 {
                    let (s1, c1) = r[i].addingReportingOverflow(p[i])
                    let (s2, c2) = s1.addingReportingOverflow(carry)
                    r[i] = s2; carry = (c1 ? 1 : 0) + (c2 ? 1 : 0)
                }
            }
            return Fp(v: (r[0], r[1], r[2], r[3]))
        }

        /// Subtract p from (extra:r) once if the value is >= p.
        private static func reduceOnce(_ r: [UInt64], extra: UInt64) -> Fp {
            let p = [Fp.p.0, Fp.p.1, Fp.p.2, Fp.p.3]
            // needsSub if extra>0 OR r >= p.
            var ge = extra != 0
            if !ge {
                ge = true
                for i in (0..<4).reversed() {
                    if r[i] < p[i] { ge = false; break }
                    if r[i] > p[i] { break }
                }
            }
            if !ge { return Fp(v: (r[0], r[1], r[2], r[3])) }
            var out = [UInt64](repeating: 0, count: 4)
            var borrow: UInt64 = 0
            for i in 0..<4 {
                let (d1, br1) = r[i].subtractingReportingOverflow(p[i])
                let (d2, br2) = d1.subtractingReportingOverflow(borrow)
                out[i] = d2; borrow = (br1 ? 1 : 0) + (br2 ? 1 : 0)
            }
            return Fp(v: (out[0], out[1], out[2], out[3]))
        }

        /// CIOS Montgomery multiplication: (a·b·R^{-1}) mod p.
        static func montmul(_ a: Fp, _ b: Fp) -> Fp {
            let av = [a.v.0, a.v.1, a.v.2, a.v.3]
            let bv = [b.v.0, b.v.1, b.v.2, b.v.3]
            let p = [Fp.p.0, Fp.p.1, Fp.p.2, Fp.p.3]
            var t = [UInt64](repeating: 0, count: 6) // 4 + 2 guard limbs
            for i in 0..<4 {
                // t += a * b[i]
                var carry: UInt64 = 0
                for j in 0..<4 {
                    let (hi, lo) = av[j].multipliedFullWidth(by: bv[i])
                    let (s1, c1) = t[j].addingReportingOverflow(lo)
                    let (s2, c2) = s1.addingReportingOverflow(carry)
                    t[j] = s2
                    carry = hi &+ (c1 ? 1 : 0) &+ (c2 ? 1 : 0)
                }
                let (s1, c1) = t[4].addingReportingOverflow(carry)
                t[4] = s1; t[5] &+= (c1 ? 1 : 0)
                // m = t[0] * inv64 mod 2^64
                let m = t[0] &* Fp.inv64
                // t += m * p, then shift right one limb
                var carry2: UInt64 = 0
                let (mh0, ml0) = m.multipliedFullWidth(by: p[0])
                let (_, c0) = t[0].addingReportingOverflow(ml0)
                carry2 = mh0 &+ (c0 ? 1 : 0)
                for j in 1..<4 {
                    let (hi, lo) = m.multipliedFullWidth(by: p[j])
                    let (a1, ca) = t[j].addingReportingOverflow(lo)
                    let (a2, cb) = a1.addingReportingOverflow(carry2)
                    t[j - 1] = a2
                    carry2 = hi &+ (ca ? 1 : 0) &+ (cb ? 1 : 0)
                }
                let (a1, ca) = t[4].addingReportingOverflow(carry2)
                t[3] = a1
                t[4] = t[5] &+ (ca ? 1 : 0)
                t[5] = 0
            }
            return reduceOnce([t[0], t[1], t[2], t[3]], extra: t[4])
        }

        static func mul(_ a: Fp, _ b: Fp) -> Fp { montmul(a, b) }

        /// x^5, the Poseidon S-box.
        func pow5() -> Fp {
            let x2 = Fp.mul(self, self)
            let x4 = Fp.mul(x2, x2)
            return Fp.mul(x4, self)
        }
    }

    // MARK: - Poseidon permutation

    private static func params(_ t: Int) -> (Int, Int, [Fp], [[Fp]]) {
        let (rf, rp, cRaw, mRaw): (Int, Int, [[UInt64]], [[[UInt64]]]) = t == 3
            ? (PrivacyDevnetPoseidonConstants.roundsF3, PrivacyDevnetPoseidonConstants.roundsP3,
               PrivacyDevnetPoseidonConstants.c3, PrivacyDevnetPoseidonConstants.m3)
            : (PrivacyDevnetPoseidonConstants.roundsF4, PrivacyDevnetPoseidonConstants.roundsP4,
               PrivacyDevnetPoseidonConstants.c4, PrivacyDevnetPoseidonConstants.m4)
        let c = cRaw.map { Fp(limbs: $0) }
        let m = mRaw.map { $0.map { Fp(limbs: $0) } }
        return (rf, rp, c, m)
    }

    /// circomlib Poseidon over `inputs` (length 2 or 3), returning `state[0]`.
    static func hash(_ inputs: [Fp]) -> Fp {
        let t = inputs.count + 1
        precondition(t == 3 || t == 4, "pool uses only t=3 and t=4")
        let (rf, rp, c, m) = params(t)
        var state = [Fp.zero] + inputs
        for r in 0..<(rf + rp) {
            for i in 0..<t { state[i] = Fp.add(state[i], c[r * t + i]) }
            if r < rf / 2 || r >= rf / 2 + rp {
                for i in 0..<t { state[i] = state[i].pow5() }
            } else {
                state[0] = state[0].pow5()
            }
            var next = [Fp](repeating: Fp.zero, count: t)
            for i in 0..<t {
                var acc = Fp.zero
                for j in 0..<t { acc = Fp.add(acc, Fp.mul(m[i][j], state[j])) }
                next[i] = acc
            }
            state = next
        }
        return state[0]
    }

    // MARK: - The pool's tagged shapes (mirror circuits/spend.circom)

    static let tagPk = Fp(1), tagLeaf = Fp(2), tagNull = Fp(3)

    static func p2(_ a: Fp, _ b: Fp) -> Fp { hash([a, b]) }
    static func p3(_ a: Fp, _ b: Fp, _ c: Fp) -> Fp { hash([a, b, c]) }

    /// The public owner key of a spend key: `Poseidon(TAG_PK, spendKey, 0)`.
    static func ownerPk(spendKey: Fp) -> Fp { hash([tagPk, spendKey, Fp.zero]) }

    /// A note's inner hash: `Poseidon(ownerPk, rho)`.
    static func inner(spendKey: Fp, rho: Fp) -> Fp { p2(ownerPk(spendKey: spendKey), rho) }

    /// A note commitment (the tree leaf): `Poseidon(TAG_LEAF, inner, value)`.
    /// This is exactly what the pool's `shield(bytes32 inner)` recomputes.
    static func commitment(inner: Fp, value: Fp) -> Fp { hash([tagLeaf, inner, value]) }

    /// A nullifier: `Poseidon(TAG_NULL, Poseidon(domain, spendKey), commitment)`.
    static func nullifier(domain: Fp, spendKey: Fp, commitment cm: Fp) -> Fp {
        hash([tagNull, p2(domain, spendKey), cm])
    }
}
