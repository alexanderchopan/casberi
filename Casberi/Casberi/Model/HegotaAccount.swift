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
    let sends: Int

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

    var id: String { address }
    var sponsored: [HegotaMove] { moves.filter(\.isSponsored) }
    var hasCoins: Bool { !(unspent ?? []).isEmpty && reconciled }
    var hasLanes: Bool { !lanes.isEmpty }
    var hasSponsors: Bool { !sponsored.isEmpty }

    /// What the coins are worth in total — nil unless the set reconciled,
    /// because an unreconciled total is a number nobody should read.
    var coinsWei: Decimal? {
        guard reconciled, let unspent else { return nil }
        return HegotaCoins.total(unspent)
    }
}
