import Foundation

/// The value types a Hegotá sweep produces — a move, a frame, a nonce lane, an
/// account.
///
/// **Foundation-only, and split out of `HegotaBridge` for exactly that
/// reason.** `HegotaRoom` decides what the room leads with over these types, so
/// leaving them beside the networking meant the room's rules could not be
/// compiled by a `swiftc` harness at all — which is how a head that leads with
/// the wrong reading, or a total that quietly includes an account we never
/// reached, ships with every check green. Caught by the harness on its first
/// run against `HegotaRoom`, before any of it reached a device.

// MARK: - What a sweep learns

struct HegotaMove: Equatable, Sendable, Identifiable, Codable {
    let hash: String
    let counterparty: String
    let wei: Decimal
    let incoming: Bool
    let block: UInt64
    /// The frames this transaction ran, when they have been read. Nil means not
    /// read yet — never "it had none", which is why the row draws no strip
    /// rather than an empty one.
    var frames: [HegotaFrame]?
    /// Who paid the gas. Equal to the sender on every transaction measured on
    /// this chain so far; a different address is a sponsorship.
    var payer: String?
    var sender: String?
    /// The non-zero nonce keys this transaction was sent on.
    var nonceKeys: [String] = []
    var nonceSeq: String?
    /// A legacy type-`0x2` transaction has no frames and never will — the
    /// visible difference between this chain's two eras.
    var isFrameTransaction: Bool = false
    /// When the block carrying this move was mined.
    ///
    /// **Optional, and the room draws nothing rather than guessing.** A block
    /// number is the only clock a log carries and it is not a time to anybody,
    /// which is what made these the one undated rows in the app. The header
    /// read that fills this is bounded, so a move older than the window
    /// legitimately has no time — a different thing from one at the epoch.
    var timestamp: Date?
    /// A time INTERPOLATED between two headers we read, for a block outside the
    /// bounded header window.
    ///
    /// **Kept apart from `timestamp` on purpose.** They are different grades of
    /// fact and the room draws them differently: a read timestamp carries a
    /// clock, an estimate is stated to the day. Merging them would let a
    /// derived minute render exactly as confidently as a measured one, which is
    /// the §83 failure in the field most likely to be believed.
    var estimatedAt: Date?
    /// What the payer actually spent on gas — `gasUsed × effectiveGasPrice`,
    /// both off the receipt this sweep already fetches, so it costs no read.
    ///
    /// It is what makes sponsorship concrete: "somebody else paid" is a
    /// sentence, "somebody else paid 0.00006 ETH" is the fact underneath it.
    /// Nil past the receipt window, never zero — an unread fee and a free
    /// transaction must not render alike.
    var feeWei: Decimal?

    var id: String { hash + (incoming ? "-in" : "-out") }
    var isSponsored: Bool {
        guard let payer, let sender else { return false }
        return payer.caseInsensitiveCompare(sender) != .orderedSame
    }
}

struct HegotaFrame: Equatable, Sendable, Codable {
    /// EIP-8141 frame modes. Named rather than numbered, because the number is
    /// meaningless on a row and the name is the whole reading.
    enum Mode: String, Sendable, Codable {
        case general, verify, sender, assertion, utxo, unknown

        init(wire: Int) {
            switch wire {
            case 0: self = .general
            case 1: self = .verify
            case 2: self = .sender
            case 3: self = .assertion
            case 5: self = .utxo
            default: self = .unknown
            }
        }

        var label: String {
            switch self {
            case .general:   return String(localized: "Call")
            case .verify:    return String(localized: "Verify")
            case .sender:    return String(localized: "Send")
            case .assertion: return String(localized: "Check")
            // **THE LITERAL TERM (the Nonces ruling, one mode over).**
            // EIP-8312 calls this a UTXO frame and the spec, the RPC and the
            // vault all say UTXO; "Coins" is our friendly word for what it
            // holds, not the name of the step that moved them.
            case .utxo:      return String(localized: "UTXO")
            case .unknown:   return String(localized: "Step")
            }
        }
    }

    let mode: Mode
    let target: String?
    let wei: Decimal
    /// Nil when the receipt could not be paired with the frame — the strip
    /// draws that pip hollow rather than guessing at success.
    let succeeded: Bool?
    let gasUsed: UInt64?
    let stateGasUsed: UInt64?
}

struct HegotaNonceLane: Equatable, Sendable, Identifiable, Codable {
    /// The key itself, as it rides the wire. Short keys are things people typed
    /// (`0xbeef01`, `0x1234` are both on chain); a 40-nibble one is somebody's
    /// address being used as a name.
    let key: String
    let seq: String?
    let lastBlock: UInt64
    /// Sends OBSERVED — the moves whose transactions named this key.
    ///
    /// It undercounts by construction, which is why `counter` exists beside it:
    /// a send that moved no ETH emits no transfer log, so this can only ever
    /// see the paying ones.
    let sends: Int
    /// The chain's OWN counter for this key, off the nonce manager's storage
    /// (§509). Nil when the read did not answer — never zero, since a key the
    /// room is listing has by definition been sent on at least once, and a
    /// nil-as-zero would say "never used" about it.
    var counter: UInt64?

    /// What the room should state: the chain's count when we have it, else
    /// what we could see. `countIsExact` is what stops the derived number
    /// being narrated as the chain's.
    var sendCount: Int { counter.map { max(Int($0), sends) } ?? sends }
    var countIsExact: Bool { counter != nil }
    /// Sends on this key that moved no value — the per-key form of §504's
    /// `valuelessSends`. Nil when unknown or zero, the same two silences.
    var valuelessSends: Int? {
        guard let counter else { return nil }
        let gap = Int(counter) - sends
        return gap > 0 ? gap : nil
    }

    var id: String { key }
    var looksLikeAddress: Bool {
        let body = key.hasPrefix("0x") ? String(key.dropFirst(2)) : key
        return body.count == 40
    }
}

/// One watched address, as the room draws it.
///
/// `reached` is the honest third state and the reason nothing here is an
/// Optional-shaped lie: a sweep that could not reach any host leaves every
/// figure nil, and the room says so rather than drawing a balance of zero.
struct HegotaAccount: Equatable, Sendable, Identifiable, Codable {
    let address: String
    var reached = false
    var balanceWei: Decimal?
    var moves: [HegotaMove] = []
    var coins: [HegotaCoin] = []
    /// Nil when a spent bit could not be read — `HegotaCoins.unspent` refuses
    /// the whole set rather than showing money that is already gone.
    var unspent: [HegotaCoin]?
    /// Did the WHOLE chain's unspent set account for exactly what the vault
    /// holds? The coins card draws nothing when this is false.
    var reconciled = false
    var lanes: [HegotaNonceLane] = []
    /// The address's REAL ordinary-nonce counter, off `eth_getTransactionCount`.
    ///
    /// **One cheap read that fixes a figure and earns a new one (2026-08-27).**
    /// Everything else in this room is reconstructed from transfer logs, and a
    /// transaction that moved no ETH emits none — so counting sends from
    /// `moves` UNDERCOUNTS, and on a chain whose whole subject is transactions
    /// that verify, check and call rather than pay, it undercounts exactly the
    /// interesting ones. This is the counter the chain itself keeps.
    ///
    /// Nil when unread, never zero: a fresh address really does have nonce 0,
    /// so a nil-as-zero would say "this address has never sent" about one whose
    /// read simply failed.
    var nonceCount: UInt64?
    /// The whole chain's vault, and this address's proven share of it.
    ///
    /// Free: `readCoinState` already reads every `UtxoCreated` log and every
    /// spent bit — it has to, since conservation only holds across all owners
    /// at once — and until now it kept one Bool out of all that and dropped the
    /// rest. Nil unless the set reconciled.
    var census: HegotaCensus?
    /// True when every block header this sweep read names THIS address as the
    /// producer (§509) — the devnet's sequencer. Free: the headers are already
    /// fetched for their timestamps.
    var producesBlocks = false

    var id: String { address }
    var sponsored: [HegotaMove] { moves.filter(\.isSponsored) }
    var hasCoins: Bool { !(unspent ?? []).isEmpty && reconciled }
    var hasLanes: Bool { !lanes.isEmpty }
    var hasSponsors: Bool { !sponsored.isEmpty }

    /// The transactions whose frames have actually been read, newest first.
    ///
    /// A move with `frames == nil` is one the bounded receipt read did not
    /// reach, and it is EXCLUDED rather than drawn as a transaction that ran no
    /// steps — the same distinction `frames` itself carries, one level up.
    /// Both directions of one transaction land as two moves (out and in) when
    /// an address pays itself, so they are folded by hash here or the scope
    /// would draw one transaction twice.
    var framed: [HegotaMove] {
        var seen = Set<String>()
        return moves.filter { move in
            guard let f = move.frames, !f.isEmpty else { return false }
            return seen.insert(move.hash.lowercased()).inserted
        }
    }

    var hasFrames: Bool { !framed.isEmpty }

    /// Sends the chain counted that no transfer log can show.
    ///
    /// The ordinary nonce counts every transaction this address sent on key 0;
    /// `moves` holds only the ones that moved ETH. The difference is the frame
    /// transactions that verified, checked or called and paid nobody — real
    /// sends, invisible to every other reading in this room.
    ///
    /// **Nil unless the nonce was read, and never negative.** Outgoing moves on
    /// a NAMED key do not touch the ordinary counter, so they are excluded from
    /// the subtraction; if the arithmetic still came out below zero it would
    /// mean an assumption here is wrong, and a negative dressed as a count is a
    /// parse bug wearing a number (`HegotaRoom.split`'s own rule).
    var valuelessSends: Int? {
        guard let nonceCount else { return nil }
        var seen = Set<String>()
        let ordinaryOut = moves.filter { move in
            guard !move.incoming, move.nonceKeys.isEmpty else { return false }
            return seen.insert(move.hash.lowercased()).inserted
        }.count
        let gap = Int(nonceCount) - ordinaryOut
        return gap > 0 ? gap : nil
    }

    /// What the coins are worth in total — nil unless the set reconciled,
    /// because an unreconciled total is a number nobody should read.
    var coinsWei: Decimal? {
        guard reconciled, let unspent else { return nil }
        return HegotaCoins.total(unspent)
    }
}
