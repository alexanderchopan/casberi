import Foundation

/// WHAT THE FRAMES DEVNET ITSELF IS DOING — relaunched, stalled, final — and
/// what became of a transaction this phone broadcast (prd §728). Foundation-only
/// BY DESIGN so `scripts/frames-tx-selftest.sh` compiles it whole.
///
/// ## WHY THIS FILE EXISTS
///
/// Measured 2026-09-13: all three RPC hosts reported the same head, block
/// 75,685, whose timestamp was **142,463 seconds old** — the chain had made no
/// block for about 39 hours. Every read in the room answered perfectly, so the
/// room drew a healthy balance over a chain that was not running, and a send
/// made then would have sat "Sending…" and faded out with no reason given.
/// `NotifyPlan`'s own note had already named the other half: "Frames has the
/// same claim and no reset detection of its own". Both are readings of three
/// headers the seat was not asking for.
///
/// Every rule below is pure and takes its clock as a parameter, because
/// nothing on this machine can make a devnet stall, relaunch or finalize on
/// demand — the harness is the only proof these hold.
enum FramesChainWatch {

    // MARK: - Relaunch

    /// **A STORED BASELINE, NOT A SHIPPED CONSTANT** — the divergence from the
    /// Privacy seat, and this chain's history is the reason. Privacy compares
    /// against a genesis pinned in the build, so after a relaunch it says
    /// "relaunched" until an app update re-pins it. This chain relaunched on
    /// 2026-09-07 ten days after it opened; a pinned constant would make every
    /// install built before the next relaunch say so forever. So the first
    /// genesis an install sees is adopted silently, a different one is a
    /// relaunch observed NOW, and the new one becomes the baseline in the same
    /// step — which is also what keeps a second relaunch news.
    enum Genesis: Equatable, Sendable {
        /// Nothing usable came back. Never a verdict.
        case unread
        /// No baseline yet: take this one without saying anything, because an
        /// install that first reads after a relaunch has lost nothing.
        case adopt(String)
        case same
        case relaunched(String)
    }

    static func verdict(baseline: String?, observed: String?) -> Genesis {
        guard let observed, observed.count == 66, observed.hasPrefix("0x"),
              observed.dropFirst(2).allSatisfy(\.isHexDigit) else { return .unread }
        guard let baseline, !baseline.isEmpty else { return .adopt(observed) }
        return baseline.caseInsensitiveCompare(observed) == .orderedSame
            ? .same : .relaunched(observed)
    }

    /// How long a relaunch stays the reason the room looks the way it does.
    /// The same week `NotifyDevnet.resetWindow` announces it for — a room that
    /// stopped explaining before the notification stopped being sayable would
    /// land somebody on a room that no longer explains itself.
    static let sayRelaunchFor: TimeInterval = 7 * 86_400

    // MARK: - Stall

    /// **TEN MINUTES, which is a hundred slots.** Measured: this chain makes a
    /// block every 6 seconds (100 headers spanned 600 seconds), so a head this
    /// old is not a slow block or a missed slot, it is a chain that has
    /// stopped. Short enough to be the reason a send is not landing, long
    /// enough that a handful of missed proposals never reads as an outage.
    static let stallAfter: TimeInterval = 10 * 60

    /// **WHEN THIS DEVICE FIRST SAW THE CHAIN'S CURRENT HEAD NUMBER.** The same
    /// number keeps its first sighting; a new one starts a new sighting; an
    /// unread head changes nothing.
    static func headSince(previousBlock: UInt64?, previousSince: Date?,
                          observedBlock: UInt64?, now: Date) -> (block: UInt64?, since: Date?) {
        guard let observedBlock else { return (previousBlock, previousSince) }
        if observedBlock == previousBlock, let previousSince { return (observedBlock, previousSince) }
        return (observedBlock, now)
    }

    /// **A STALL IS A HEAD NUMBER THAT STOPPED MOVING, NOT AN OLD TIMESTAMP.**
    ///
    /// The first cut read the head's TIMESTAMP age, and a measurement the same
    /// day proved it wrong in the direction that matters: after the 39-hour
    /// stall the chain resumed by catching up — making real blocks, carrying
    /// real transactions, stamped with slots from a day and a half earlier. The
    /// timestamp rule said "Stalled for 40 hours, nothing sent now can land"
    /// while six transactions this pass sent landed within minutes.
    ///
    /// So the stall is OBSERVED: this device must have seen the same head number
    /// for longer than `stallAfter`. Until it has, nothing is claimed — a head
    /// first seen a moment ago is not evidence either way (§515a). Once it has,
    /// the age said is the longer of what was watched and the head block's own
    /// age, since a chain with no newer block has made nothing since that one.
    static func stallAge(headAt: Date?, headSince: Date?, now: Date) -> TimeInterval? {
        guard let headSince else { return nil }
        let watched = now.timeIntervalSince(headSince)
        guard watched > stallAfter else { return nil }
        let made = headAt.map { now.timeIntervalSince($0) } ?? 0
        return max(watched, made)
    }

    /// What the room says instead of nothing, ranked. **A relaunch outranks a
    /// stall**: a stalled chain still holds everything it held, a relaunched
    /// one does not, and a room that said "stalled" over a wipe would be
    /// telling somebody to wait for money that is gone.
    enum Alert: Equatable, Sendable {
        case relaunched(observedAt: Date)
        case stalled(age: TimeInterval)
    }

    static func alert(relaunchObservedAt: Date?, headAt: Date?, headSince: Date?, now: Date) -> Alert? {
        if let seen = relaunchObservedAt {
            let age = now.timeIntervalSince(seen)
            if age >= 0, age <= sayRelaunchFor { return .relaunched(observedAt: seen) }
        }
        if let age = stallAge(headAt: headAt, headSince: headSince, now: now) { return .stalled(age: age) }
        return nil
    }

    /// The slot's headline row — `stat24`, one line, so a phrase and never a
    /// sentence. **It says when WE saw the relaunch**, never when the chain
    /// restarted, which this device cannot know.
    static func headline(_ alert: Alert, now: Date) -> String {
        switch alert {
        case .relaunched(let seen):
            let days = Int(max(0, now.timeIntervalSince(seen)) / 86_400)
            switch days {
            case 0:  return String(localized: "Relaunched today")
            case 1:  return String(localized: "Relaunched yesterday")
            default: return String(localized: "Relaunched \(String(days)) days ago")
            }
        case .stalled(let age):
            let minutes = Int(age / 60)
            if minutes < 60 { return String(localized: "Stalled for \(String(minutes)) minutes") }
            let hours = minutes / 60
            if hours < 48 { return String(localized: "Stalled for \(String(hours)) hours") }
            return String(localized: "Stalled for \(String(hours / 24)) days")
        }
    }

    /// The one sentence under the headline, saying what it CHANGES.
    static func consequence(_ alert: Alert) -> String {
        switch alert {
        case .relaunched:
            return String(localized: "The chain started again from genesis, so what it held before is gone.")
        case .stalled:
            return String(localized: "No new blocks, so nothing sent now can land until it resumes.")
        }
    }

    // MARK: - Finality

    /// Whether a transaction's block is at or below the chain's own finalized
    /// head. **Nil when that head was not read** — "not final" is a claim
    /// about the chain, and an unread tag is not one.
    static func isFinal(block: UInt64, finalized: UInt64?) -> Bool? {
        guard let finalized else { return nil }
        return block <= finalized
    }

    // MARK: - A transaction this phone sent

    /// What one host said about a hash.
    enum Sighting: Equatable, Sendable {
        /// Answered `null`: this host does not have it.
        case absent
        /// Has it, with no block — waiting in its pool.
        case pooled
        /// Has it in a block.
        case mined
    }

    enum PendingState: String, Equatable, Sendable {
        /// Accepted by the node we sent it to, and nothing more is known yet.
        case sending
        /// A node holds it in its pool.
        case queued
        /// A block carries it; the room's next read will list it.
        case mined
        /// Every host answered and none has it. It will not land.
        case dropped
        /// Past its own deadline frame. It CANNOT land — any block made from
        /// now on has a later timestamp than the deadline allows.
        case expired

        /// A final word: the row may stop being watched once it has said it.
        var isFinal: Bool { self == .dropped || self == .expired }
    }

    /// Three slots. A node that accepted a transaction has it in its own pool
    /// immediately, but the other two only learn of it by announcement, so a
    /// hash nobody holds this soon is propagation, not loss.
    static let droppedAfter: TimeInterval = 18

    /// Two slots of clock disagreement between this device and the chain.
    static let deadlineGrace: TimeInterval = 12

    /// How long a dropped or expired row keeps saying so before it goes.
    static let finalWordFor: TimeInterval = 45

    /// **ONE ANSWER FROM EVERY HOST'S SIGHTING, and the order is the ruling.**
    ///
    /// 1. `mined` wins outright: a block is the chain agreeing.
    /// 2. `expired` next, from the device clock and the transaction's own
    ///    deadline — it outranks a pool sighting because a node must drop a
    ///    transaction past its deadline, so a host still reporting it pooled
    ///    is reporting something that can never land.
    /// 3. `queued` when any host holds it.
    /// 4. `dropped` ONLY when every host answered, every one said absent, and
    ///    enough time has passed for propagation. **A host that did not answer
    ///    is not a host that said no** (§515a), so one silence keeps it
    ///    `sending`.
    static func pendingState(sentAt: Date, deadline: Date?, now: Date,
                             sightings: [Sighting?]) -> PendingState {
        if sightings.contains(.mined) { return .mined }
        if let deadline, now.timeIntervalSince(deadline) > deadlineGrace { return .expired }
        if sightings.contains(.pooled) { return .queued }
        let answered = sightings.compactMap { $0 }
        if !sightings.isEmpty, answered.count == sightings.count,
           answered.allSatisfy({ $0 == .absent }),
           now.timeIntervalSince(sentAt) > droppedAfter {
            return .dropped
        }
        return .sending
    }

    /// The pending row's second line.
    ///
    /// **The countdown is to the deadline, and only while it can still land.**
    /// Minutes and seconds, because the window is minutes long and the second
    /// is what somebody watching a send is counting.
    static func pendingLine(state: PendingState, deadline: Date?, now: Date) -> String {
        switch state {
        case .sending:
            return String(localized: "Sending\u{2026}")
        case .queued:
            guard let deadline else { return String(localized: "Waiting for a block") }
            let left = max(0, Int(deadline.timeIntervalSince(now)))
            let clock = String(format: "%d:%02d", left / 60, left % 60)
            return String(localized: "Waiting for a block · \(clock) left")
        case .mined:
            return String(localized: "In a block")
        case .dropped:
            return String(localized: "Dropped by the network. It won't land.")
        case .expired:
            return String(localized: "Past its deadline. It can't land now.")
        }
    }

    /// One host's `eth_getTransactionByHash` answer as a sighting. `answered`
    /// false means the host itself did not respond, which is nil — never
    /// `.absent`.
    static func sighting(answered: Bool, transaction: [String: Any]?) -> Sighting? {
        guard answered else { return nil }
        guard let transaction else { return .absent }
        if let block = transaction["blockNumber"] as? String, !block.isEmpty { return .mined }
        return .pooled
    }
}
