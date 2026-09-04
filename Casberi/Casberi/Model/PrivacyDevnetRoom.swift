import Foundation

/// What the Ethrex Privacy room LEADS with, and what it refuses to say
/// (prd §593).
///
/// Foundation-only by design so `scripts/privacy-selftest.sh` compiles it
/// WHOLE. `PrivacyDevnetRoomSource` is the `@MainActor` half that reads live
/// state; every judgement lives here.
///
/// **THE HEAD IS NEVER NIL WHILE THE SEAT IS CONNECTED, and that is the single
/// most load-bearing rule in this file.** This seat lands NO `Thing` ever, so
/// its rows are always zero and the head is the room's entire content — a nil
/// head is not an empty room, it is a BLACK SCREEN, which is how the Hegotá
/// room reached a device four times. Every branch below returns a head; the
/// only question is what it says.
enum PrivacyDevnetRoom {

    /// What the room says at the top.
    enum Lede: Equatable, Sendable {
        /// No read has landed yet. Not an error — the first sweep has not run.
        case reading(watching: Int)
        /// The chain answered and this address has done nothing on it. The
        /// honest common case: 14 type-`0x6` transactions exist chain-wide.
        case quiet(watching: Int)
        /// A root reference is live, with this many slots left in its window.
        /// The reading this seat exists for.
        case rootLive(remaining: UInt64, sources: Int)
        /// Every referenced root has left the window. **Not a failure** — the
        /// proofs were valid when they landed and the transactions are settled.
        case rootsAged(count: Int)
        /// Spend keys used, but no root referenced. Real and common: 10 of 14
        /// measured transactions carry an empty `recentRootReferences`.
        case spends(nullifiers: Int)
        /// The chain was relaunched from genesis and everything it held is
        /// gone. Outranks every reading below it, because each of those would
        /// otherwise describe a chain that no longer exists (§522's ruling,
        /// and §515a's report — a wiped devnet reads as "nothing has landed
        /// here" forever).
        case relaunched
    }

    struct Head: Equatable, Sendable {
        var lede: Lede
        var watching: Int
        /// Drawn only when a root is live. A meter over an aged root would
        /// read as "nearly empty" when the truth is "there is nothing to
        /// measure" (`PrivacyDevnetRoots.fraction`'s own rule).
        var windowFraction: Double?
        var nullifierCount: Int
        var frameCount: Int
        var sponsoredCount: Int
    }

    /// Compose the head.
    ///
    /// **Ranked, and the order is a ruling.** A relaunch outranks everything
    /// because it invalidates everything; a LIVE root outranks an aged one
    /// because only the live one has a clock somebody might act on; spends
    /// outrank quiet because a spend is something this address did.
    ///
    /// `wasReset` is `Bool?` on purpose — nil means nothing has been observed,
    /// which is not the same as observing that the chain is fine, and only a
    /// definite `true` may claim a relaunch.
    static func head(accounts: [Account], watching: Int, hasRead: Bool,
                     headSlot: UInt64, wasReset: Bool?) -> Head {
        let nullifiers = accounts.reduce(0) { $0 + $1.nullifierCount }
        let frames = accounts.reduce(0) { $0 + $1.frameCount }
        let sponsored = accounts.reduce(0) { $0 + $1.sponsoredCount }
        let refs = accounts.flatMap(\.roots)

        func finish(_ lede: Lede, fraction: Double? = nil) -> Head {
            Head(lede: lede, watching: max(watching, 1), windowFraction: fraction,
                 nullifierCount: nullifiers, frameCount: frames,
                 sponsoredCount: sponsored)
        }

        if wasReset == true { return finish(.relaunched) }
        // **ACCOUNTS ARE THEMSELVES EVIDENCE OF A READ** (Hegotá's lesson):
        // keying only on `hasRead` draws "Reading the chain…" over a fully
        // populated room after a snapshot is restored.
        guard hasRead || !accounts.isEmpty else {
            return finish(.reading(watching: max(watching, 1)))
        }

        if !refs.isEmpty {
            // The one with the MOST window left leads — it is the reference a
            // person still has time to care about. Ties break on the slot so
            // the choice is total and the card cannot reshuffle between opens.
            let live = refs.compactMap { r -> (PrivacyDevnetRoots.Reference, UInt64)? in
                guard let left = PrivacyDevnetRoots.remaining(r, headSlot: headSlot) else { return nil }
                return (r, left)
            }
            if let best = live.max(by: { a, b in
                a.1 == b.1 ? a.0.slot < b.0.slot : a.1 < b.1
            }) {
                let sources = Set(refs.map(\.sourceID)).count
                return finish(.rootLive(remaining: best.1, sources: sources),
                              fraction: PrivacyDevnetRoots.fraction(best.0, headSlot: headSlot))
            }
            return finish(.rootsAged(count: refs.count))
        }
        if nullifiers > 0 { return finish(.spends(nullifiers: nullifiers)) }
        return finish(.quiet(watching: max(watching, 1)))
    }

    /// The account shape the head reads. A plain value so this file stays
    /// Foundation-only and the harness can build one without a `ModelContext`.
    struct Account: Equatable, Sendable {
        var nullifierCount: Int
        var frameCount: Int
        var sponsoredCount: Int
        var roots: [PrivacyDevnetRoots.Reference]

        init(nullifierCount: Int = 0, frameCount: Int = 0, sponsoredCount: Int = 0,
             roots: [PrivacyDevnetRoots.Reference] = []) {
            self.nullifierCount = nullifierCount
            self.frameCount = frameCount
            self.sponsoredCount = sponsoredCount
            self.roots = roots
        }
    }

    /// The head's sentence.
    ///
    /// **No figure here is a price and none is a count of money** — test ETH
    /// has no market, so every number below is a count of events or a number
    /// of slots, and nothing may be rendered as a currency.
    static func sentence(_ head: Head) -> String {
        switch head.lede {
        case .relaunched:
            return String(localized: "This devnet was relaunched from genesis, so everything it held is gone. The addresses you watch are still yours.")
        case .reading:
            return String(localized: "Reading the chain…")
        case .quiet(let watching):
            return watching == 1
                ? String(localized: "Nothing on this chain from the address you watch, yet.")
                : String(localized: "Nothing on this chain from the \(watching) addresses you watch, yet.")
        case .spends(let n):
            return n == 1
                ? String(localized: "One spend, on a key that can't be used again.")
                : String(localized: "\(n) spends, each on a key that can't be used again.")
        case .rootLive(let remaining, let sources):
            // SLOTS, not minutes: the slot count is measured and the seconds
            // are an assumption about this devnet's slot time.
            let slots = remaining == 1
                ? String(localized: "1 slot")
                : String(localized: "\(remaining) slots")
            return sources == 1
                ? String(localized: "A proof here still names a snapshot the chain remembers, for another \(slots).")
                : String(localized: "Proofs here name \(sources) snapshots, the freshest good for another \(slots).")
        case .rootsAged(let count):
            return count == 1
                ? String(localized: "The snapshot this address proved against has left the chain's memory. The transaction stands.")
                : String(localized: "The \(count) snapshots this address proved against have left the chain's memory. The transactions stand.")
        }
    }
}
