import Foundation

/// A FRAMES ACCOUNT A PASSKEY SIGNS FOR (prd §728d) — the account contract, its
/// address, the frame that installs it, and the transaction it signs.
/// Foundation-only BY DESIGN so `scripts/frames-tx-selftest.sh` compiles it
/// whole, runs its bytecode, and pins its address.
///
/// ## WHY AN ACCOUNT CONTRACT, WHEN THE CHAIN VERIFIES P-256 ITSELF
///
/// EIP-8141 validates a `P256` signature at the protocol level — the node
/// checks `r ‖ s ‖ qx ‖ qy` against the canonical hash before any frame runs,
/// and refused a corrupted one here as "Invalid frame transaction signature"
/// (2026-09-13). What it does NOT do is let a P-256 key authorise an ordinary
/// address: the default code an address with no code runs accepts
/// **secp256k1 only**. So a Secure Enclave key needs an account whose own
/// code says "a P-256 signature from THIS key approves me". That is the whole
/// contract below — 64 bytes, no storage, no owner-change path.
///
/// ## WHAT THE CODE DOES
///
/// Called by anybody but the entry point (`0xaa`), it stops — so the account
/// can RECEIVE coin like any address. Called by the entry point, which is who
/// calls a VERIFY frame, it asks the transaction's own signature list, via
/// `SIGPARAM`, whether entry 0 is a P-256 signature over the transaction
/// (`msg` empty) whose signer is this account's owner; if so it `APPROVE`s
/// whatever scope the frame's flags allow (`FRAMEPARAM`), otherwise it
/// reverts. The protocol has already verified the signature itself; the code
/// only says whose it must be.
///
/// ## HOW IT GETS THERE
///
/// Its address is fixed before it exists — CREATE2 through the deterministic
/// deployment proxy at `0x4e59…956c`, measured present on chain 81410 (69
/// bytes of code) — so the address can be shown, watched and funded first, and
/// the code is installed by the account's own first transaction, as EIP-8141's
/// "deploy new account" prefix: a DEFAULT frame to the proxy, then the VERIFY
/// frame that now has code to run.
enum FramesPasskeyAccount {

    /// Arachnid's deterministic deployment proxy.
    static let deployer = Data([0x4e, 0x59, 0xb4, 0x48, 0x47, 0xb3, 0x79, 0x57, 0x85, 0x88,
                                0x92, 0x0c, 0xa7, 0x8f, 0xbf, 0x26, 0xc0, 0xb4, 0x95, 0x6c])

    /// One account per key, so one salt.
    static let salt = Data(count: 32)

    /// The deploy frame's budgets. **State carries the account's creation and
    /// its code** — 120 bytes for the account and 64 for the code at 1,530 gas
    /// a byte is ~282,000; 450,000 stays under the 500,000 the mempool allows
    /// the whole validation prefix.
    static let deployExecutionGas: UInt64 = 150_000
    static let deployStateGas: UInt64 = 450_000

    /// The address EIP-8141 names a P-256 signer by: `keccak256(qx ‖ qy)[12:]`.
    static func owner(publicKey xy: Data) -> Data? {
        guard xy.count == 64 else { return nil }
        return Data(Keccak256.hash([UInt8](xy)).suffix(20))
    }

    /// **THE ACCOUNT'S CODE — 64 bytes, and every jump target is counted in
    /// the comment beside it.** Pinned byte for byte in the harness, which also
    /// RUNS it against the four cases that matter.
    static func runtime(owner: Data) -> Data {
        var code: [UInt8] = []
        code += [0x33, 0x60, 0xaa, 0x14]             //  0 CALLER == ENTRY_POINT
        code += [0x60, 0x08, 0x57]                   //  4 PUSH1 8, JUMPI
        code += [0x00]                               //  7 STOP — a plain receive
        code += [0x5b]                               //  8 JUMPDEST
        code += [0x60, 0x01, 0x5f, 0xb4]             //  9 SIGPARAM(scheme, signature 0)
        code += [0x60, 0x02, 0x14]                   // 13 == P256
        code += [0x60, 0x02, 0x5f, 0xb4, 0x15, 0x16] // 16 SIGPARAM(msg, 0) == 0, AND
        code += [0x5f, 0x5f, 0xb4]                   // 22 SIGPARAM(signer, 0)
        code += [0x73] + [UInt8](owner.prefix(20))   // 25 PUSH20 owner
        code += [0x14, 0x16]                         // 46 EQ, AND
        code += [0x60, 0x36, 0x57]                   // 48 PUSH1 54, JUMPI
        code += [0x5f, 0x5f, 0xfd]                   // 51 REVERT
        code += [0x5b]                               // 54 JUMPDEST
        code += [0x60, 0x06, 0x60, 0x0a, 0xb0, 0xb3] // 55 FRAMEPARAM(allowed scope, TXPARAM(this frame))
        code += [0x5f, 0x5f, 0xaa]                   // 61 APPROVE(scope, 0, 0)
        return Data(code)
    }

    /// A constructor that returns the runtime: `CODECOPY` it, `RETURN` it.
    static func initcode(owner: Data) -> Data {
        let body = runtime(owner: owner)
        let length = UInt8(body.count)
        return Data([0x60, length, 0x60, 0x0a, 0x5f, 0x39, 0x60, length, 0x5f, 0xf3]) + body
    }

    /// `keccak256(0xff ‖ deployer ‖ salt ‖ keccak256(initcode))[12:]`.
    static func address(owner: Data) -> Data {
        let codeHash = Keccak256.hash([UInt8](initcode(owner: owner)))
        let preimage = [UInt8]([0xff]) + [UInt8](deployer) + [UInt8](salt) + codeHash
        return Data(Keccak256.hash(preimage).suffix(20))
    }

    /// The DEFAULT frame that installs the code: the proxy's calldata is
    /// `salt ‖ initcode`.
    static func deployFrame(owner: Data) -> FramesTransaction.Frame {
        FramesTransaction.Frame(mode: 0, flags: 0x00, target: deployer,
                                executionGas: deployExecutionGas, stateGas: deployStateGas,
                                value: Data(), data: salt + initcode(owner: owner))
    }

    /// **A SEND FROM THE PASSKEY ACCOUNT.** The deadline first, the deploy
    /// frame only while the account has no code, the VERIFY frame the code
    /// answers, then the legs — joined by the stitched send's own rule.
    static func transaction(owner: Data,
                            deploy: Bool,
                            legs: [FramesTransaction.Leg],
                            atomic: Bool,
                            nonce: UInt64,
                            maxPriorityFeePerGas: UInt64,
                            maxFeePerGas: UInt64,
                            executionGas: UInt64 = 100_000,
                            stateGas: UInt64 = 250_000,
                            deadline: UInt64?) -> FramesTransaction.Fields {
        let account = address(owner: owner)
        let last = legs.count - 1
        return FramesTransaction.Fields(
            chainID: FramesTransaction.chainID, nonce: nonce, sender: account,
            frames: FramesTransaction.expiryPrefix(deadline)
                + (deploy ? [deployFrame(owner: owner)] : [])
                + [FramesTransaction.Frame(mode: 1, flags: 0x03, target: account,
                                           executionGas: executionGas, stateGas: 0,
                                           value: Data(), data: Data())]
                + legs.enumerated().map { index, leg in
                    FramesTransaction.Frame(mode: 2,
                                            flags: atomic && index < last ? FramesTransaction.atomicFlag : 0x00,
                                            target: leg.recipient,
                                            executionGas: executionGas, stateGas: stateGas,
                                            value: leg.value, data: leg.data)
                },
            signatures: [FramesTransaction.Signature(scheme: 2, signer: owner, msg: Data(), signature: Data())],
            maxPriorityFeePerGas: maxPriorityFeePerGas,
            maxFeePerGas: maxFeePerGas,
            maxFeePerBlobGas: 0,
            blobVersionedHashes: [])
    }

    /// The `P256` signature entry's bytes: `r ‖ s ‖ qx ‖ qy`, with `s` folded
    /// into the lower half — EIP-8141 requires low-s, and the Enclave signs
    /// either half at random.
    static func signatureBytes(rs: Data, publicKey xy: Data) -> Data? {
        guard rs.count == 64, xy.count == 64 else { return nil }
        return lowS(rs) + xy
    }

    // MARK: - Low-s

    /// The P-256 group order, big-endian (the NIST constant).
    static let curveOrder: [UInt8] = [
        0xff, 0xff, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xbc, 0xe6, 0xfa, 0xad, 0xa7, 0x17, 0x9e, 0x84, 0xf3, 0xb9, 0xca, 0xc2, 0xfc, 0x63, 0x25, 0x51,
    ]

    /// Half the order, floored.
    static let curveHalfOrder: [UInt8] = [
        0x7f, 0xff, 0xff, 0xff, 0x80, 0x00, 0x00, 0x00, 0x7f, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xde, 0x73, 0x7d, 0x56, 0xd3, 0x8b, 0xcf, 0x42, 0x79, 0xdc, 0xe5, 0x61, 0x7e, 0x31, 0x92, 0xa8,
    ]

    /// `r ‖ s` with `s` replaced by `n - s` when it sits above `n / 2`.
    static func lowS(_ rs: Data) -> Data {
        guard rs.count == 64 else { return rs }
        let bytes = [UInt8](rs)
        let s = Array(bytes[32..<64])
        var high = false
        for i in 0..<32 where s[i] != curveHalfOrder[i] {
            high = s[i] > curveHalfOrder[i]
            break
        }
        guard high else { return rs }
        var folded = [UInt8](repeating: 0, count: 32)
        var borrow = 0
        for i in stride(from: 31, through: 0, by: -1) {
            let diff = Int(curveOrder[i]) - Int(s[i]) - borrow
            folded[i] = UInt8((diff + 256) % 256)
            borrow = diff < 0 ? 1 : 0
        }
        return Data(bytes[0..<32]) + Data(folded)
    }
}
