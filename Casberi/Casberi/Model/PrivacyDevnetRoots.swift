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

    // MARK: - Words a reader can feel (prd §598)

    /// A slot count as a phrase, hedged.
    ///
    /// **THE RULING THIS AMENDS, and the narrow place it amends it.** §593d
    /// put the seconds conversion at the BOTTOM of the roots list, once, about
    /// the window rather than about anybody's proof — on the reasoning that a
    /// per-row countdown in minutes is one assumption repeated as a fact. That
    /// reasoning held for a row in a list and does NOT hold for the crown: the
    /// room's headline read "for another 4,096 slots", which is a measurement
    /// nobody outside this devnet can size at all, in the largest type on the
    /// card. A number a reader cannot feel is not a more honest number, it is
    /// an unread one.
    ///
    /// So the phrase leads WHERE THE CLOCK IS DRAWN — the ring's own reading
    /// and the roots rows' titles — and three things keep it inside §83:
    ///
    ///   1. It always says **"about"**. Never a bare figure.
    ///   2. The **measured slot count travels with it**, in the line beneath,
    ///      so nothing that was observed is replaced by something that was
    ///      assumed.
    ///   3. The assumption is **named once per surface**
    ///      (`PrivacyDevnetRoomCard.windowNote`), unchanged.
    ///
    /// Deliberately coarse. Ladder rungs, never a decimal: "about 11 hours" is
    /// a claim of the right size, "about 11.4 hours" is a precision this app
    /// does not have and the extra digit is the part somebody would act on.
    static func approximate(slots: UInt64) -> String {
        let seconds = duration(slots: slots)
        if seconds < 60 { return String(localized: "under a minute") }
        // The rungs are coarse on purpose. An hour is an hour rather than
        // "about 60 minutes" — the unit somebody would say out loud.
        if seconds < 3600 {
            let m = Int((seconds / 60).rounded())
            return m == 1 ? String(localized: "about 1 minute")
                          : String(localized: "about \(String(m)) minutes")
        }
        if seconds < 48 * 3600 {
            let h = Int((seconds / 3600).rounded())
            return h == 1 ? String(localized: "about 1 hour")
                          : String(localized: "about \(String(h)) hours")
        }
        let d = Int((seconds / 86_400).rounded())
        return d == 1 ? String(localized: "about 1 day")
                      : String(localized: "about \(String(d)) days")
    }

    /// The same reading at mark scale, where a sentence does not fit.
    ///
    /// **The `~` carries the hedge that "about" carries in the long form** —
    /// it is the one place the word will not fit, and dropping the hedge
    /// rather than the word would turn an estimate into a reading at exactly
    /// the size nobody checks.
    static func approximateShort(slots: UInt64) -> String {
        let seconds = duration(slots: slots)
        if seconds < 60 { return String(localized: "<1m") }
        if seconds < 3600 { return "~\(Int((seconds / 60).rounded()))m" }
        if seconds < 48 * 3600 { return "~\(Int((seconds / 3600).rounded()))h" }
        return "~\(Int((seconds / 86_400).rounded()))d"
    }

    /// What a source is CALLED on screen.
    ///
    /// **A 32-byte source id names nothing** (prd §598). The Roots scope
    /// labelled each lane with `0x1f4a20b8…3c91` in an 84pt mono column, which
    /// is not an identity a reader can hold across a figure, a row and a sheet
    /// — it is the bytes, printed. The bytes are still shown as the row's
    /// SUBTITLE, where an identifier belongs; this is the handle.
    ///
    /// **One set is not "Set 1"** — an ordinal implies a second, so a room with
    /// a single source says "The set" and stops claiming a series that does not
    /// exist. Ordering is `bySource`'s, which is already total, so the number a
    /// source wears cannot change between opens over identical data.
    static func setLabel(_ index: Int, of total: Int) -> String {
        guard total > 1 else { return String(localized: "The set") }
        return String(localized: "Set \(String(index + 1))")
    }

    /// The ordinal a source wears, or nil for one this list does not carry.
    static func setIndex(of source: Data, in references: [Reference]) -> Int? {
        bySource(references).firstIndex { $0.source == source }
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

    // MARK: - What the predeploy actually stored (prd §593d)

    /// The two constants the EIP-8272 predeploy hashes with, READ OFF ITS OWN
    /// DEPLOYED BYTECODE and then confirmed against live state — not from any
    /// specification, because none of this is specified anywhere this project
    /// can reach.
    ///
    /// `eth_getCode` on `0x…8272` returns 144 bytes which disassemble to a
    /// WRITE-ONLY entry point: given 64 bytes of calldata it derives
    /// `sourceId = keccak(caller ‖ calldata[0..32])`, then stores
    /// `keccak(K1 ‖ sourceId ‖ uint64(slot) ‖ root)` at storage key
    /// `keccak(K2 ‖ sourceId ‖ uint64(slot & 0x1fff))`.
    ///
    /// **The `0x1fff` in that mask is where `windowSlots` comes from**, and it
    /// is the same 8192 the constant above states — so the two agree, measured
    /// rather than assumed.
    static let registrationHashDomain = "8f42481679c8e6fefa040974b3c905e0ce3f2e464ba93acdb074a41181617efc"
    static let registrationSlotDomain = "bdc897da2177d260ff5f4be5d4b2aad43f89c3347a305b584fa5a2546d053daa"

    /// The ring index a slot occupies. `slot & (windowSlots - 1)`, which is the
    /// predeploy's own `0x1fff` mask rather than a modulo we chose — and the
    /// reason the window is a power of two at all.
    static func ringIndex(slot: UInt64) -> UInt64 { slot & (windowSlots - 1) }

    /// Where the predeploy keeps this source's entry for this slot.
    ///
    /// Pair it with `registrationValue` and one `eth_getStorageAt`: equal means
    /// the chain really holds the registration this transaction referenced.
    static func registrationKey(sourceID: Data, slot: UInt64,
                                hash: (Data) -> Data) -> Data {
        var pre = bytes(hex: registrationSlotDomain)
        pre.append(padded32(sourceID))
        pre.append(bigEndian64(ringIndex(slot: slot)))
        return hash(pre)
    }

    /// What the predeploy stored there, if this reference was really registered.
    static func registrationValue(sourceID: Data, slot: UInt64, root: Data,
                                  hash: (Data) -> Data) -> Data {
        var pre = bytes(hex: registrationHashDomain)
        pre.append(padded32(sourceID))
        pre.append(bigEndian64(slot))
        pre.append(padded32(root))
        return hash(pre)
    }

    /// **WHAT A MATCH DOES AND DOES NOT PROVE — the whole reason this is a
    /// probe and not a verdict in the room.**
    ///
    /// A match proves the registration is GENUINE: the source, the slot and the
    /// root this transaction named are the ones the chain recorded. It says
    /// NOTHING about whether the reference is still inside the window, because
    /// a ring entry is only overwritten when a NEW registration lands on the
    /// same index — and on a chain this quiet that may never happen. Measured
    /// 2026-09-04: all four root-carrying transactions matched, including two
    /// whose slots left the window more than 14,000 slots ago.
    ///
    /// So `standing(of:headSlot:)` above stays the only answer to "is this
    /// still good", and this pair answers a different question: has our reading
    /// of the wire drifted. That is a nightly assertion, not a card.
    static let registrationCeiling =
        "a match proves the registration is real, never that it is still inside the window"

    /// 32 bytes, left-padded — the wire is quantity-encoded, so a `sourceID` or
    /// a `root` whose first byte is zero arrives 31 bytes long and hashing it
    /// as-is derives a key that matches nothing.
    static func padded32(_ d: Data) -> Data {
        if d.count >= 32 { return Data(d.suffix(32)) }
        return Data(repeating: 0, count: 32 - d.count) + d
    }

    /// A slot as the eight big-endian bytes the predeploy hashes. Eight, never
    /// a full word: the contract writes the slot into memory as a word and then
    /// overwrites all but its last eight bytes, so the preimage is 104 bytes
    /// rather than 128.
    static func bigEndian64(_ v: UInt64) -> Data {
        var out = Data(count: 8)
        for i in 0..<8 { out[7 - i] = UInt8((v >> (8 * UInt64(i))) & 0xff) }
        return out
    }

    /// Bytes from a hex string, with or without an `0x`.
    ///
    /// **An odd length or a non-hex character yields an EMPTY value, never a
    /// partial one.** A half-read domain constant derives a storage key that
    /// matches nothing, which reads as the chain having forgotten a
    /// registration it is still holding — a wrong answer wearing a right one's
    /// clothes. Kept inside this enum rather than as a `Data` extension: a
    /// second hex reader in this tree is how two spellings of one rule drift.
    static func bytes(hex: String) -> Data {
        var s = Substring(hex)
        if s.hasPrefix("0x") || s.hasPrefix("0X") { s = s.dropFirst(2) }
        guard s.count % 2 == 0 else { return Data() }
        var out = Data(); out.reserveCapacity(s.count / 2)
        var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2)
            guard let b = UInt8(s[i..<j], radix: 16) else { return Data() }
            out.append(b)
            i = j
        }
        return out
    }
}
