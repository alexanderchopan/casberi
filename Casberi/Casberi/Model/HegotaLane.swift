import Foundation

/// WHICH LANE A SEND TAKES (EIP-8250, 2026-09-24).
///
/// A keyed nonce exists so two sends do not have to wait for each other: two
/// transactions from one sender on disjoint keys are both valid, in either
/// order. `HegotaSend` hardcoded `nonceKeys: [0]` from §525 until now, so every
/// send this app made sat in one lane and the second one queued behind the
/// first — the exact thing the mechanism is for was unreachable.
///
/// ## WHY THIS IS NOT A PICKER
///
/// A lane is bookkeeping, not a choice anybody wants to make: nobody sending
/// 0.001 ETH has an opinion about which nonce key it occupies. So the app picks,
/// and the person sees only that a second send does not wait. That also keeps
/// §83 honest — a control offering a choice with no consequence a person can
/// judge is a control that should not exist.
///
/// ## WHY IT REMEMBERS, AND WHAT THE CHAIN CANNOT TELL US
///
/// A lane's counter lives in the nonce-manager predeploy's storage, and that
/// storage only moves when a transaction MINES. Two sends on one lane inside a
/// block therefore both read the same counter, and the second is refused. So
/// the chain's number is a FLOOR, not the answer: this type holds what it has
/// already handed out per lane and takes whichever is higher. A restart loses
/// that memory, which is correct rather than unfortunate — after a restart the
/// only trustworthy number is the chain's.
///
/// Foundation-only BY DESIGN so `hegota-lane-selftest.sh` drives it whole.
struct HegotaLane: Equatable {

    /// The lanes this app will use. Lane 0 stays first so a single send is
    /// indistinguishable from what shipped before, and §504's cheap
    /// `eth_getTransactionCount` read still answers the common case.
    ///
    /// Four is a judgement, not a measurement: it is enough that a person
    /// tapping send repeatedly does not queue, and small enough that the room's
    /// lane list stays readable. Widening it costs nothing but a longer list.
    static let all: [UInt64] = [0, 1, 2, 3]

    /// The next sequence this app has handed out for a lane, per address.
    /// Keyed by lowercased address, because an address arrives from the
    /// Keychain in whatever case it was stored in.
    private var handedOut: [String: [UInt64: UInt64]] = [:]

    /// Which lane the last send took, per address, so the next one moves on.
    private var lastLane: [String: Int] = [:]

    init() {}

    /// The lane the next send should take: the one after the last, wrapping.
    ///
    /// Rotating rather than "the first free lane" on purpose — freeness is not
    /// knowable without a pending model this chain's seat does not have, and a
    /// rotation gives the same property (consecutive sends never share a lane)
    /// without pretending to know something it cannot read.
    mutating func nextLane(for address: String) -> UInt64 {
        let key = address.lowercased()
        let position = ((lastLane[key] ?? -1) + 1) % Self.all.count
        lastLane[key] = position
        return Self.all[position]
    }

    /// The sequence to sign with on `lane`, given what the chain currently
    /// reports for it.
    ///
    /// `chainSequence` is a FLOOR: the storage slot only advances when a send
    /// mines, so a second send on one lane in the same block reads the same
    /// number the first did. Taking the higher of the chain's number and what
    /// this type has already issued is what stops the second being refused.
    ///
    /// Passing nil means the chain could not be read; this returns nil rather
    /// than falling back to its own memory, because a remembered number with
    /// no chain reading behind it could be arbitrarily stale — that is §83's
    /// rule about never showing a figure you cannot stand behind, applied to
    /// one you would SIGN.
    mutating func sequence(for address: String,
                           lane: UInt64,
                           chainSequence: UInt64?) -> UInt64? {
        guard let chainSequence else { return nil }
        let key = address.lowercased()
        let issued = handedOut[key]?[lane]
        let next = max(chainSequence, issued ?? chainSequence)
        handedOut[key, default: [:]][lane] = next + 1
        return next
    }

    /// Forget one address's memory — after a failed send, whose sequence was
    /// never spent. Without this a refused send would leave a hole every later
    /// send on that lane sits behind, and the lane would be dead until restart.
    mutating func forget(address: String) {
        let key = address.lowercased()
        handedOut[key] = nil
        lastLane[key] = nil
    }
}
