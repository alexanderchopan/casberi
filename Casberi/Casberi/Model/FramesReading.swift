import Foundation

/// READING A FRAME TRANSACTION BACK — the Frames devnet's pure model
/// (prd §548). Foundation-only BY DESIGN so
/// `scripts/frames-tx-selftest.sh` compiles it WHOLE.
///
/// **Split out of `FramesBridge.swift` because the rule below could not be
/// tested where it lived.** That file holds `@Observable` state, a
/// `BridgeStore` registration and the address book, so no `swiftc` harness can
/// reach it — and the one reading in this seat where being wrong costs real
/// trust was sitting inside it, guarded by nothing. A move, not a copy.
///
/// ## THE RULE THIS FILE EXISTS FOR
///
/// **A frame's STATUS is about execution; only its EFFECT says what it did.**
/// Measured on this chain by sending four transactions: a frame inside an
/// atomic batch reports `status: 0x1` after being rolled back. The same frame
/// carried ONE log when its transfer persisted and ZERO when it was reverted,
/// and its status read `0x1` both times.
///
/// And the converse, which is stranger: a transaction reporting
/// `status: 0x0` can still have MOVED MONEY, because frames are not atomic
/// unless `flags` bit 2 says so — verified by reading the EIP-7708 log back
/// off a failed transaction whose recipient kept the ETH.
///
/// So a row drawn from `status` alone can tell somebody their money moved when
/// it did not, and a row drawn from the transaction's own status can tell them
/// nothing moved when it did. `valueLanded` is the honest reading, and it is
/// only possible because this chain publishes every ETH movement as a log —
/// the third of §500's three reasons a devnet like this earns a seat.

// MARK: - Reading a frame transaction back

/// THE READ SIDE, and the trap that makes it a separate type from Hegotá's.
///
/// **A frame's execution budget is reported as `gasLimit` here and
/// `executionGasLimit` on Hegotá.** A reader written for one gets `nil` on the
/// other, and a frame drawn with a nil budget is a frame that looks like it
/// had none — the two-bar figure's whole subject, wrong, silently. Both
/// spellings are read here with this chain's own first, so a reader pointed at
/// the wrong chain degrades to correct rather than to empty.
enum FramesRead {

    /// One frame as the RPC reports it.
    struct Frame: Equatable, Codable {
        var mode: UInt64
        var flags: UInt64
        var target: String?
        var executionGas: UInt64?
        var stateGas: UInt64?
        var value: String?
        var data: String?

        /// `0` DEFAULT, `1` VERIFY, `2` SENDER. Named rather than numbered
        /// wherever a person sees it: "mode 2" says nothing and "Sender" says
        /// what ran.
        var modeName: String {
            switch mode {
            case 0: String(localized: "Default")
            case 1: String(localized: "Verify")
            case 2: String(localized: "Sender")
            default: String(localized: "Mode \(String(mode))")
            }
        }

        /// Bits 0 and 1 are the `APPROVE` scope — execution and payment. A
        /// VERIFY frame without them leaves the transaction with no payer.
        var approvesExecution: Bool { flags & 0x1 != 0 }
        var approvesPayment: Bool { flags & 0x2 != 0 }
        /// Bit 2 marks an atomic batch, terminated by a following non-batch
        /// frame.
        var startsBatch: Bool { flags & 0x4 != 0 }
    }

    /// One frame's outcome.
    struct FrameOutcome: Equatable, Codable {
        var succeeded: Bool
        var gasUsed: UInt64?
        /// **OPTIONAL, AND NEVER DEFAULTED TO ZERO.** Measured 2026-09-01:
        /// absent from all 5 transactions on this chain (10 frames), while
        /// Hegotá's receipts carry it. All five are plain transfers that grow
        /// no state, so this is not proof the field does not exist — the
        /// faucet's own error guide tells implementers to "check
        /// `stateGasUsed` on the receipt", which means it is meant to be
        /// there.
        ///
        /// Nil means **the chain did not say**, which is a different fact from
        /// zero and is the whole point: `0x0` is the discriminator that tells
        /// a missing STATE budget apart from a too-small EXECUTION budget, and
        /// reading an absent field as zero would assert that diagnosis every
        /// time. A figure draws the state bar only when this is non-nil.
        var stateGasUsed: UInt64?
        var logCount: Int
    }

    static func hexInt(_ any: Any?) -> UInt64? {
        guard let s = any as? String else { return nil }
        let body = s.hasPrefix("0x") ? String(s.dropFirst(2)) : s
        guard !body.isEmpty else { return nil }
        return UInt64(body, radix: 16)
    }

    /// Frames off an `eth_getTransactionByHash` result.
    static func frames(inTransaction tx: [String: Any]) -> [Frame] {
        guard let raw = tx["frames"] as? [[String: Any]] else { return [] }
        return raw.map { f in
            Frame(mode: hexInt(f["mode"]) ?? 0,
                  flags: hexInt(f["flags"]) ?? 0,
                  target: f["to"] as? String,
                  // This chain's spelling FIRST; Hegotá's accepted so a reader
                  // pointed at the wrong chain is wrong-but-drawn rather than
                  // silently empty.
                  executionGas: hexInt(f["gasLimit"]) ?? hexInt(f["executionGasLimit"]),
                  stateGas: hexInt(f["stateGasLimit"]),
                  value: f["value"] as? String,
                  data: f["data"] as? String)
        }
    }

    /// Outcomes off an `eth_getTransactionReceipt` result.
    static func outcomes(inReceipt receipt: [String: Any]) -> [FrameOutcome] {
        guard let raw = receipt["frameReceipts"] as? [[String: Any]] else { return [] }
        return raw.map { r in
            FrameOutcome(succeeded: (r["status"] as? String) == "0x1",
                         gasUsed: hexInt(r["gasUsed"]),
                         stateGasUsed: hexInt(r["stateGasUsed"]),
                         logCount: (r["logs"] as? [[String: Any]])?.count ?? 0)
        }
    }

    /// **WHY A FRAME FAILED, when the chain can tell us.**
    ///
    /// The faucet's own error guide: *"A frame reverts having used exactly its
    /// `execution` budget, with `stateGasUsed: 0x0` — missing state budget,
    /// not execution. Raising `--frame-gas-limit` will not help."* Two
    /// failures that render identically, and the chain publishes the
    /// discriminator.
    ///
    /// Returns nil when the frame succeeded, or when the reading cannot be
    /// made — an absent `stateGasUsed` is **not** evidence of a state
    /// starvation, and saying so would send somebody to raise a budget that
    /// was never the problem (§83, on the one line a developer would act on).
    enum Starvation: Equatable { case state, execution }

    static func starvation(frame: Frame, outcome: FrameOutcome) -> Starvation? {
        guard !outcome.succeeded else { return nil }
        guard let used = outcome.gasUsed, let budget = frame.executionGas,
              used == budget else { return nil }
        // Only a REPORTED zero is evidence. Nil is "the chain did not say".
        guard let state = outcome.stateGasUsed else { return nil }
        return state == 0 ? .state : .execution
    }
}

// MARK: - What a frame transaction looks like once it has been read

/// One frame paired with what it DID. Two arrays on the wire — `frames` on the
/// transaction, `frameReceipts` on the receipt — and they are zipped exactly
/// once, here, so no view can pair them differently.
struct FramesFrameRow: Equatable, Codable {
    var frame: FramesRead.Frame
    var outcome: FramesRead.FrameOutcome?

    /// **DID THIS FRAME'S VALUE ACTUALLY LAND — read from its EFFECT, never
    /// from its status** (prd §548, second follow-up).
    ///
    /// Measured on this chain: a frame inside an atomic batch reports
    /// `status: 0x1` after being rolled back. The same frame carried ONE log
    /// when its transfer persisted and ZERO when it was reverted, and its
    /// status said `0x1` both times. Every ETH movement here is an EIP-7708
    /// log, so the log IS the effect and its absence IS the rollback — which
    /// is only true because this chain publishes those logs, and is the third
    /// reading §500 said the seat is for.
    ///
    /// **Nil means the question does not apply**, not that it failed: a VERIFY
    /// frame moves no value and has nothing to land, and a frame with no
    /// receipt has not been read. Three answers where a Bool has two, because
    /// collapsing "moved nothing by design" into "did not move" is a false
    /// alarm on the one frame every transaction here carries.
    var valueLanded: Bool? {
        guard let outcome else { return nil }
        // `value` is the WIRE's hex string, not bytes — and "0x", "0x0" and
        // "0x00" are all the same nothing, so the test is for a non-zero
        // digit rather than for a non-empty field.
        guard let raw = frame.value else { return nil }
        let body = raw.hasPrefix("0x") || raw.hasPrefix("0X") ? String(raw.dropFirst(2)) : raw
        guard body.contains(where: { $0 != "0" }) else { return nil }
        return outcome.logCount > 0
    }
}

/// A frame transaction, read back.
struct FramesMove: Identifiable, Equatable, Codable {
    var hash: String
    var blockNumber: UInt64
    var sender: String
    var payer: String
    var succeeded: Bool
    /// **THE TRANSACTION'S OWN, NEVER THE SUM OF ITS FRAMES.** Measured
    /// 2026-09-01 on a transaction this app sent: the two frames report 100
    /// and 3,000 gas, and the receipt reports **210,790**. Adding the frames
    /// up and presenting the total as what the transaction cost is wrong by
    /// two orders of magnitude, and wrong in the direction that looks
    /// plausible.
    var gasUsed: UInt64?
    var rows: [FramesFrameRow]

    var id: String { hash }

    /// Somebody else paid. The one reading this chain publishes that ordinary
    /// chains hide — and it is a comparison of two fields on the SAME receipt,
    /// never an inference.
    var sponsored: Bool { payer.lowercased() != sender.lowercased() }

    /// Did every frame RUN without reverting?
    ///
    /// **NEVER USE THIS TO DESCRIBE MONEY** (prd §548, second follow-up). It
    /// reads `status`, and `status` is about EXECUTION, not effect: a frame
    /// inside an atomic batch reports `status: 0x1` after being rolled back —
    /// measured on this chain, where the same frame carried one log when its
    /// effect persisted and zero when it was reverted, with an identical
    /// `0x1` both times. A tick drawn from this would tell somebody their
    /// money moved when it did not. Use `valueLanded` / `movedValue` below.
    var everyFrameRan: Bool {
        rows.allSatisfy { $0.outcome?.succeeded ?? true }
    }

    /// **Did any value actually land?** The honest question, and the one a
    /// room may draw beside a figure.
    ///
    /// Nil when it cannot be answered — no receipt, so no logs to read. Nil is
    /// not false: an unread receipt is not evidence that nothing moved, which
    /// is §515a's rule on the one reading where being wrong is expensive.
    var movedValue: Bool? {
        let answerable = rows.contains { $0.outcome != nil }
        guard answerable else { return nil }
        return rows.contains { $0.valueLanded == true }
    }

    /// Frames that declared a value and whose effect did NOT persist. Empty is
    /// the healthy answer; anything in it is money the sender meant to move
    /// and which was rolled back.
    var rolledBack: [FramesFrameRow] { rows.filter { $0.valueLanded == false } }

    /// **WHAT THIS TRANSACTION DID TO THE BALANCE OF THE ACCOUNT THAT READ
    /// IT** — signed wei, or nil when it could not be worked out.
    ///
    /// **This is EXACT, and only because of two things this chain publishes.**
    /// Every ETH movement is an EIP-7708 log, so the transfers are known
    /// rather than inferred — and gas is NOT among them (measured 2026-09-01:
    /// a send moving 0.001 ETH and paying 0.000210790 in fees emits exactly
    /// ONE log, the transfer). A reconstruction from logs alone would drift by
    /// the cumulative fee, which on a young account is most of the movement.
    ///
    /// The receipt closes it: it carries `gasUsed`, `effectiveGasPrice` and —
    /// the part no ordinary chain gives — the `payer`. So the fee is
    /// subtracted only from whoever actually paid it, which is the difference
    /// between a curve and a guess on a chain where somebody else can pay.
    var deltaWei: Decimal?
}

/// One address, as the chain currently reports it.
struct FramesAccount: Identifiable, Equatable, Codable {
    var address: String
    /// **RAW HEX, not a number.** A genesis account on this chain holds
    /// 99,999.999762 ETH, which overflows `UInt64` when expressed in wei —
    /// see `FramesMoney`. Stored as the chain said it so nothing downstream
    /// can narrow it.
    var balanceWeiHex: String?
    var nonce: UInt64?
    var moves: [FramesMove]

    var id: String { address.lowercased() }

    /// **Did the chain answer for this address?** Derived rather than stored,
    /// because the two reads that populate it are the evidence: a balance or a
    /// nonce came back, so a host answered. An account with neither was asked
    /// and not answered, which the room must say rather than draw as a zero
    /// (§515a — an unreached read is not evidence of an empty account).
    var reached: Bool { balanceWeiHex != nil || nonce != nil }

    /// Frames across every move whose value did NOT land — money the sender
    /// meant to move and which was rolled back. See `FramesFrameRow
    /// .valueLanded`: this cannot be read from status.
    var rolledBack: [FramesFrameRow] { moves.flatMap(\.rolledBack) }
}
