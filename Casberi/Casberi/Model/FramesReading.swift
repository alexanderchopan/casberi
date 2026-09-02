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
    /// **IS THIS FRAME JOINED TO THE NEXT ONE?** (prd §548 sixth follow-up
    /// amendment.)
    ///
    /// `flags` bit 2 does not mean "roll me back if a later frame fails" — the
    /// node refuses a transaction that sets it on the LAST frame, in its own
    /// words: `atomic batch flag on last frame`. It means this frame is joined
    /// to the one after it, so a run of joined frames plus the first unjoined
    /// frame after them is one atomic group.
    ///
    /// Named separately from `frame.startsBatch` because the drawing asks a
    /// different question than the wire answers: the wire says "a batch begins
    /// here", the strip needs "is there a join between this cell and the next".
    /// They are the same bit and different sentences.
    var joinedToNext: Bool { frame.startsBatch }

    /// What this frame moved, as raw wei hex — nil for a frame that moves
    /// nothing by design, which is every VERIFY frame.
    var valueWeiHex: String? {
        guard let raw = frame.value else { return nil }
        let body = raw.hasPrefix("0x") || raw.hasPrefix("0X") ? String(raw.dropFirst(2)) : raw
        guard body.contains(where: { $0 != "0" }) else { return nil }
        return raw
    }

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
    /// **OPTIONAL, and that is a decode requirement, not a style choice.**
    /// `FramesMove` is `Codable` and cached in UserDefaults, and Swift's
    /// synthesized decoder applies no default for a missing key — a
    /// non-Optional field added here fails the decode of every move already on
    /// disk, silently emptying the room (the `RSSStore.Feed` trap, §312).
    var effectiveGasPriceWei: UInt64? = nil
    /// **WHEN THE BLOCK CARRYING THIS WAS MINED**, and nil where it was not
    /// read.
    ///
    /// Until this landed a Frames row carried `blockNumber` and nothing else,
    /// which made these the one set of undated rows in the app — a block
    /// number is the only clock a log carries and it is not a time to anybody.
    /// The header read that fills it is BOUNDED (`FramesLiveState
    /// .headerDepth`), so a move outside the window legitimately has no time.
    ///
    /// **No `estimatedAt` here, deliberately, and that is a divergence from
    /// Hegotá.** That room interpolates a block's time between two headers it
    /// really read, anchored on a genesis header it fetches every pass for its
    /// restart check. This seat fetches no genesis header, so an estimate here
    /// would be extrapolated from an assumed block rate rather than bracketed
    /// between two facts — a guess wearing the same shape as a reading, which
    /// is the §83 failure in the field most likely to be believed. A move with
    /// no time says its block and stops.
    ///
    /// **`= nil` is a DECODE requirement**, exactly as `effectiveGasPriceWei`
    /// above states: `FramesMove` is `Codable` and cached, and Swift's
    /// synthesized decoder applies no default for a missing key, so a
    /// non-Optional field added here fails the decode of every move already on
    /// disk and silently empties the room.
    var timestamp: Date? = nil
    var rows: [FramesFrameRow]

    var id: String { hash }

    /// **WHO THE MONEY WENT TO.** A row said what ran, what it cost and
    /// whether it landed, and never once who received it — which on a send is
    /// the first thing anybody wants back.
    ///
    /// Payload frames only, deduped, in the order they ran: a VERIFY frame
    /// targets the sender itself and naming it would report you as your own
    /// recipient on every transaction here. Case-folded for the dedupe and
    /// returned in the ORIGINAL spelling, since an address's case is a
    /// checksum and not ours to normalise away.
    var recipients: [String] {
        var seen: Set<String> = []
        var out: [String] = []
        for row in rows where row.frame.mode != 1 {
            guard let to = row.frame.target, !to.isEmpty else { continue }
            guard to.lowercased() != sender.lowercased() else { continue }
            if seen.insert(to.lowercased()).inserted { out.append(to) }
        }
        return out
    }

    /// **WHAT IT COST, IN MONEY.** `gasUsed` is a unit nobody holds; the fee
    /// is what actually left the balance, and this room already computes it
    /// for the balance curve. Both terms are the receipt's own — never a frame
    /// sum, for the reason `gasUsed` states above.
    ///
    /// Nil when either term is missing, never zero: an unread fee and a free
    /// transaction must not look alike, and on this chain nothing is free.
    var feeWei: Decimal? {
        guard let gasUsed, let price = effectiveGasPriceWei else { return nil }
        return Decimal(gasUsed) * Decimal(price)
    }

    /// **THE FEE IS THE SENDER'S, and a sponsored transaction's is not
    /// theirs.** Drawing "you paid 0.0002" under a row whose own second line
    /// says somebody else paid is the two halves of one card disagreeing.
    var feeWeiIfSelfPaid: Decimal? { sponsored ? nil : feeWei }

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

    /// **WHAT TO CALL THIS TRANSACTION — from EFFECTS, never from status.**
    ///
    /// It lived in `FramesMoveRow.verdict`, where nothing but that row could
    /// reach it — so the sheet the row opens would have had to derive the same
    /// reading a second time, and two readings of a rule this sharp drift.
    /// Here that drift is a row and the sheet it opens disagreeing about
    /// whether somebody's money moved, which is the one thing in this seat
    /// that costs real trust.
    ///
    /// The order is load-bearing and is the shipped row's own: a transaction
    /// that failed AND moved money is that first, before anything else it may
    /// also be.
    enum Verdict: String, Equatable, Sendable {
        /// Every frame ran and nothing was rolled back.
        case ran
        /// It reverted and nothing landed.
        case failed
        /// **It reverted and money moved anyway.** Frames are not atomic by
        /// default (§548, measured on this chain), so an earlier frame's
        /// transfer persists under a `status: 0x0`. Drawing this as "Failed"
        /// is a lie about the money and "Ran" is a lie about the outcome.
        case failedButMoved
        /// A frame declared a value, reported `status: 0x1`, and emitted no
        /// log — its effect was reverted and its own receipt says it
        /// succeeded. The trap `valueLanded` exists for.
        case rolledBack

        /// Anything but `ran` earns the destructive tone. Stated here rather
        /// than re-derived per surface, for this property's own reason.
        var isTrouble: Bool { self != .ran }

        /// **THE WORD, in the model** — `FramesRead.Frame.modeName`'s
        /// precedent and `FramesSection.label`'s. A row and its sheet saying
        /// the same state in two different words is the drift this type was
        /// hoisted to prevent, and the words are the whole of what it says.
        var word: String {
            switch self {
            case .ran:            return String(localized: "Ran")
            case .failed:         return String(localized: "Failed")
            case .failedButMoved: return String(localized: "Failed, but value moved")
            case .rolledBack:     return String(localized: "Rolled back")
            }
        }
    }

    var verdict: Verdict {
        if movedValue == true && !succeeded { return .failedButMoved }
        if !rolledBack.isEmpty { return .rolledBack }
        return succeeded ? .ran : .failed
    }

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

// MARK: - Who an address is, from this room's point of view

/// **WHO, rather than a hex string.**
///
/// A sheet that says `0x80cf…2e32 → 0x333e…3a0d` has told you nothing you
/// could not read off the row it opened from; one that says "you → an address
/// you watch" has.
///
/// **Three cases and deliberately no fourth.** Hegotá's `HegotaParty` carries
/// a vault and a nonce manager because that chain HAS them; this one has
/// neither, so a fourth case here would be a permanently unreachable branch.
/// And there is no `burn` case, which is the one that looks missing: this
/// chain's `0x…dead` / `0x…deadbe02` addresses are genesis FIXTURES, funded on
/// purpose and holding real test ETH, so calling one a burn address would tell
/// somebody their money is gone when it is sitting in a dev account (§83, on
/// the one line a receipt is read for).
///
/// Takes `mine` and `watched` rather than reading them, so this file stays
/// Foundation-only and `scripts/frames-tx-selftest.sh` compiles it whole.
enum FramesParty: Equatable, Sendable {
    /// This phone's own account. **Wins over `watched`**, because watching
    /// your own address does not make it somebody else's — and on this chain
    /// the account you made is usually also the one you watch.
    case you(String)
    /// An address on the watch list, returned in the **WATCH LIST's** spelling
    /// rather than the transaction's: an address's case is a checksum, the two
    /// can legitimately differ, and a name given to `0xAbC…` must be found for
    /// a receipt that spelled it `0xabc…`.
    case watched(String)
    case stranger(String)

    var address: String {
        switch self {
        case .you(let a), .watched(let a), .stranger(let a): return a
        }
    }

    /// Whether a door should be offered to watch this address. **A stranger
    /// only** — one of yours is already here, and a button there would do
    /// nothing, which is §83's dead control on the one screen offering it.
    var isStranger: Bool { if case .stranger = self { return true }; return false }

    static func of(_ address: String, mine: String?, watched: [String]) -> FramesParty {
        let key = address.lowercased()
        if let mine, mine.lowercased() == key { return .you(mine) }
        if let match = watched.first(where: { $0.lowercased() == key }) { return .watched(match) }
        return .stranger(address)
    }
}

// MARK: - Who paid for somebody else

/// One address that paid another address's gas.
struct FramesPayer: Identifiable, Equatable, Sendable {
    let address: String
    let count: Int
    /// What they spent, in wei. **Nil when ANY of their transactions' fees
    /// could not be read** — `FramesRoom.curve`'s all-or-nothing rule, for its
    /// reason: a total missing one term is wrong by that term and says so
    /// nowhere, and a sponsor's generosity understated is a specific untruth
    /// about a specific person.
    let gasWei: Decimal?

    var id: String { address.lowercased() }
}

enum FramesPayers {
    /// The sponsors, most generous first.
    ///
    /// **Self-paid transactions are dropped here, not just by the caller.**
    /// The Sponsors scope already filters, but a roster that trusted its
    /// caller would put YOU at the top of the list of people who paid for you
    /// the first time somebody passed it an unfiltered array — which is the
    /// one reading this scope exists to make impossible.
    ///
    /// **A TOTAL ORDER** (gas, then count, then address). `Dictionary`
    /// iteration order is not stable across runs, and a roster that reshuffles
    /// between two reads of identical data reads as broken — the ordering rule
    /// every ranked figure in this app already carries.
    static func roster(_ moves: [FramesMove]) -> [FramesPayer] {
        var order: [String] = []
        var spelling: [String: String] = [:]
        var counts: [String: Int] = [:]
        var totals: [String: Decimal] = [:]
        var complete: [String: Bool] = [:]

        for move in moves where move.sponsored {
            let key = move.payer.lowercased()
            if counts[key] == nil {
                order.append(key)
                spelling[key] = move.payer
                counts[key] = 0
                totals[key] = 0
                complete[key] = true
            }
            counts[key]! += 1
            if let fee = move.feeWei { totals[key]! += fee } else { complete[key] = false }
        }

        return order.map { key in
            FramesPayer(address: spelling[key] ?? key,
                        count: counts[key] ?? 0,
                        gasWei: (complete[key] ?? false) ? totals[key] : nil)
        }
        .sorted { a, b in
            // An unreadable total sorts LAST rather than as zero — it is not a
            // claim that they paid nothing. A real gas total is always above
            // zero, so a negative stand-in can never collide with one.
            let x = a.gasWei ?? Decimal(-1)
            let y = b.gasWei ?? Decimal(-1)
            if x != y { return x > y }
            if a.count != b.count { return a.count > b.count }
            return a.id < b.id
        }
    }

    /// Every transaction this payer paid for, in the order the room lists them.
    static func moves(of payer: String, in moves: [FramesMove]) -> [FramesMove] {
        moves.filter { $0.sponsored && $0.payer.lowercased() == payer.lowercased() }
    }
}

// MARK: - Saying when

/// The dateline grammar, mirroring `HegotaFormat`'s so the two devnet rooms
/// read alike. Foundation-only, like everything else in this file.
enum FramesFormat {
    /// How long ago, in the app's own coarse grain.
    ///
    /// **Nil is a real answer and every caller draws nothing for it.** The
    /// header read is bounded, so a move past the window has no time — a
    /// different thing from a move at the epoch, and substituting "now" for a
    /// miss is the fake status §83 bans.
    static func time(_ date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let seconds = max(0, now.timeIntervalSince(date))
        let minutes = Int(seconds / 60)
        if minutes < 1 { return String(localized: "just now") }
        if minutes < 60 { return String(localized: "\(String(minutes))m ago") }
        let hours = minutes / 60
        if hours < 24 { return String(localized: "\(String(hours))h ago") }
        let days = hours / 24
        if days < 7 { return String(localized: "\(String(days))d ago") }
        let weeks = days / 7
        if weeks < 52 { return String(localized: "\(String(weeks))w ago") }
        return String(localized: "\(String(weeks / 52))y ago")
    }

    /// A sheet's dateline.
    ///
    /// **The block is always said and the time only when it was read** — which
    /// is the inverse of how it looks it should go, and is right for this
    /// chain. The block number is the chain's own identity for the moment,
    /// exact, and the thing you would paste into an explorer or quote to
    /// somebody else; the date is the only form of it a person can read. So
    /// both where both exist, and the exact one alone where they do not.
    static func stamp(_ date: Date?, block: UInt64) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        // Grouped: block 60,258 rather than 60258 — this is a COUNT of blocks
        // and reads as one. (An identifier would not be grouped; this is not
        // an identifier, it is a height.)
        let number = f.string(from: NSNumber(value: block)) ?? String(block)
        guard let date else { return String(localized: "Block \(number)") }
        let d = DateFormatter()
        d.dateStyle = .medium
        d.timeStyle = .short
        return String(localized: "\(d.string(from: date)) · block \(number)")
    }
}
