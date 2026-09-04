import Foundation

/// EIP-8272 RECENT ROOTS — the reading no other seat in this app can draw
/// (prd §593, 2026-09-04).
///
/// A shielded spend proves membership of an anonymity set, and a proof is made
/// against ONE snapshot of that set: its root. The chain keeps a bounded ring
/// of recent roots, so a proof is only acceptable while the root it names is
/// still in the ring. This file is that arithmetic and nothing else.
///
/// **Everything here is measured, on 2026-09-04, against `rpc1.privacy.ethrex.xyz`.**
///
/// **The predeploy exists only here.** `0x…8272` carries 144 bytes on chain
/// 8141 and NO CODE on Hegotá or Frames, so Hegotá's `RootReference` type has
/// never been exercised by any chain — which is why its `sourceID` is a
/// `UInt64` that cannot hold the 32-byte value this chain really carries
/// (prd §593a). Widths here are `Data` for exactly that reason.
///
/// **`0x4b` is SLOT, and it was measured rather than assumed.** An `eth_call`
/// over init code that executes the single opcode and returns its stack word,
/// compared against `NUMBER` on the same call: privacy 14,450 vs 14,432,
/// hegota 419,486 vs 419,465, frames 95,974 vs 90,751. Slot ≥ block always and
/// the gap is missed slots. The neighbouring byte `0x4e` is NOT an opcode —
/// invalid on all three chains — which was believed from reading the pool's
/// bytecode and refuted by the probe.
///
/// **The window is 8192 slots, and that is read off the predeploy's own code**
/// rather than off a spec: it masks the slot with `0x1fff` before deriving a
/// storage slot, and `0x1fff` is 8191. At 12s slots that is ~27.3 hours.
///
/// Foundation-only by design so `scripts/privacy-selftest.sh` compiles it WHOLE.
/// Every failure it catches renders as an ordinary card: a root reported live
/// when it has aged out, an expiry counted from the wrong end of the ring, or a
/// window that wraps and reports a fresh root as ancient.
enum PrivacyDevnetRoots {

    /// The ring's size, from the predeploy's own `0x1fff` mask.
    static let windowSlots: UInt64 = 8192

    /// Seconds per slot. Ethereum's own, and the only number here NOT measured
    /// on this chain — a devnet may run a different slot time, and if it does
    /// every duration below is wrong by that ratio while every SLOT COUNT stays
    /// right. That is why `remaining(…)` returns slots and `duration(…)` is a
    /// separate, clearly-labelled conversion the caller may decline to use.
    static let secondsPerSlot: UInt64 = 12

    /// One reference, as it rides the transaction envelope.
    ///
    /// All three are `Data`, not integers, and `sourceID` is the one that
    /// matters: it is 32 bytes on the wire (`b08f1575…51c26e20`), so the
    /// sibling seat's `UInt64` cannot hold it.
    struct Reference: Equatable, Sendable {
        var sourceID: Data
        var slot: UInt64
        var root: Data

        init(sourceID: Data, slot: UInt64, root: Data) {
            self.sourceID = sourceID
            self.slot = slot
            self.root = root
        }
    }

    /// Where a referenced root stands against the ring right now.
    ///
    /// **`aged` is not a failure.** A proof made against a root that has since
    /// left the window was perfectly valid when it landed, and the transaction
    /// carrying it is settled. This says the root can no longer be REFERENCED
    /// by a new proof, never that anything went wrong — which is why the room
    /// draws it and no notification fires on it.
    enum Standing: Equatable, Sendable {
        /// Still inside the ring, with this many slots left before it leaves.
        case live(remaining: UInt64)
        /// Out of the ring — this many slots past its last acceptable one.
        case aged(by: UInt64)
        /// The reference names a slot AHEAD of the chain's own. Not "fresh":
        /// it means the head we compared against is stale (a lagging RPC, or a
        /// read taken before a reorg settled), so no honest claim can be made.
        case ahead
    }

    /// Where `reference` stands against a head slot.
    ///
    /// **The comparison is on SLOTS, never on block numbers**, and the two are
    /// not interchangeable — measured, frames runs 5,223 slots ahead of its own
    /// block height. A card that compared a `slot` field against `eth_blockNumber`
    /// would report a live root as long-expired on any chain that has ever
    /// missed a slot, and would be silently correct on one that never had.
    static func standing(of reference: Reference, headSlot: UInt64) -> Standing {
        if reference.slot > headSlot { return .ahead }
        let age = headSlot - reference.slot
        // The root registered exactly `windowSlots - 1` ago is the OLDEST one
        // still acceptable, so `age == windowSlots` is the first aged slot.
        // Off by one here reads as a root expiring a slot early or living a
        // slot too long — invisible except to somebody watching the boundary,
        // which is the only person this card is for.
        if age >= windowSlots { return .aged(by: age - windowSlots + 1) }
        return .live(remaining: windowSlots - age)
    }

    /// Slots left before `reference` leaves the ring, or nil when it already
    /// has or when the head is behind it.
    static func remaining(_ reference: Reference, headSlot: UInt64) -> UInt64? {
        if case .live(let r) = standing(of: reference, headSlot: headSlot) { return r }
        return nil
    }

    /// A slot count as a duration.
    ///
    /// Separate from `remaining` on purpose: the slot count is measured and the
    /// seconds are an assumption about this devnet's slot time (see
    /// `secondsPerSlot`). A caller that wants to state only what is known can
    /// use the count and skip this.
    static func duration(slots: UInt64) -> TimeInterval {
        TimeInterval(slots * secondsPerSlot)
    }

    /// How full the ring is for a given reference, 0…1, for a meter.
    ///
    /// 1 means just registered, 0 means about to leave. Returns nil rather than
    /// 0 for an aged or ahead reference, because a meter reading empty and a
    /// meter with nothing to say are different claims and the second must not
    /// be drawn as the first.
    static func fraction(_ reference: Reference, headSlot: UInt64) -> Double? {
        guard let left = remaining(reference, headSlot: headSlot) else { return nil }
        return Double(left) / Double(windowSlots)
    }

    /// The distinct sources referenced across a set of transactions, newest
    /// slot first.
    ///
    /// **Grouped by `sourceID`, which is the thing a person can recognise** —
    /// two roots from one source are two snapshots of ONE set, and listing them
    /// flat reads as two unrelated anonymity sets. Ties break on the root bytes
    /// so the order is TOTAL: a card that reshuffles between opens over
    /// identical data reads as broken (`agent-panel-selftest`'s standing rule).
    static func bySource(_ references: [Reference]) -> [(source: Data, newest: Reference, count: Int)] {
        var groups: [Data: [Reference]] = [:]
        for r in references { groups[r.sourceID, default: []].append(r) }
        return groups.map { source, refs in
            let newest = refs.max { a, b in
                a.slot == b.slot ? a.root.lexicographicallyPrecedes(b.root) : a.slot < b.slot
            }!
            return (source: source, newest: newest, count: refs.count)
        }
        .sorted { a, b in
            if a.newest.slot != b.newest.slot { return a.newest.slot > b.newest.slot }
            if a.count != b.count { return a.count > b.count }
            return a.source.lexicographicallyPrecedes(b.source)
        }
    }

    /// The narrowest a nullifier can be, in bytes.
    ///
    /// 16 bytes = 128 bits. Everything above it is a value nobody picked;
    /// everything below is a number somebody typed.
    static let nullifierFloor = 16

    /// Whether a nonce key is a NULLIFIER rather than a named nonce channel.
    ///
    /// **Non-zero is NOT the test, and assuming it was over-counted on the real
    /// chain.** EIP-8250 keys are a namespace, and this devnet uses them as one:
    /// the measured keys include `0x81410003`, `0x82500001`, `0x82502001` and
    /// `0x78050000` — four-byte values numbered after the EIPs under test
    /// (8141, 8250, 7805). Those are channels somebody chose, and counting them
    /// lights the Nullifiers scope for an address that has never touched the
    /// pool. Found by running the walk against the live chain and reading the
    /// result, not from the code.
    ///
    /// A real nullifier is derived from a hash and fills its width: every one
    /// measured on this chain is 31 or 32 bytes. So the discriminator is SIZE,
    /// and it is measured on the significant bytes — the wire is
    /// quantity-encoded, so `0x0cca26d3…` arrives with its leading zero
    /// stripped and a raw-length test would drop exactly that case.
    ///
    /// `0x0` fails this for free, being both zero and short.
    static func isNullifier(_ key: Data) -> Bool {
        var significant = key
        while significant.first == 0 { significant.removeFirst() }
        return significant.count >= nullifierFloor
    }

    /// Whether the scope has anything to draw. A watched address that has never
    /// referenced a root gets no chip, rather than an empty page — which is
    /// also the honest common case, since most transactions on this chain carry
    /// an empty `recentRootReferences` (measured: 10 of 14).
    static func present(_ references: [Reference]) -> Bool { !references.isEmpty }
}
