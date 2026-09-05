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
        /// Nothing is watched at all.
        ///
        /// **This case exists because its absence was a BLACK SCREEN.** The
        /// seat is in `LiveRoomSources`, which tells the feed "this room has
        /// live content, do not draw the corpus-shaped empty state" — so a nil
        /// head there renders NOTHING, and a deep link can reach this room
        /// before anything is watched. Found on a simulator after a permission
        /// sheet swallowed the tap that would have watched an address, which is
        /// exactly the kind of ordinary accident that reaches a person.
        case unwatched
        /// The chain answered and this address has done nothing on it. The
        /// honest common case: 14 type-`0x6` transactions exist chain-wide.
        case quiet(watching: Int)
        /// The address has transacted, and none of it was a pool spend.
        ///
        /// **THIS CASE EXISTS BECAUSE ITS ABSENCE WAS A SENTENCE THAT
        /// CONTRADICTED THE ROWS UNDER IT (prd §610).** `head` ranked spends
        /// and roots and never looked at `moves`, so an address with sixty
        /// plain transfers on this chain read as `quiet` and the room printed
        /// "Nothing on this chain from the 2 addresses you watch" directly
        /// above a list of their transfers. Reported from a device; nothing
        /// here could have caught it, because every count the head reads was
        /// correct and the room rendered perfectly.
        case moved(count: Int)
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
        // Nothing watched and nothing read: say so, rather than leaving the
        // caller to return nil into a room that suppresses its own empty state.
        if watching <= 0 && accounts.isEmpty && wasReset != true {
            return Head(lede: .unwatched, watching: 0, windowFraction: nil,
                        nullifierCount: 0, frameCount: 0, sponsoredCount: 0)
        }
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
        // **A TRANSACTION IS EVIDENCE, AND IT OUTRANKS QUIET (prd §610).**
        // Below spends, because a spend is what this room is for and says
        // strictly more; above quiet, because quiet is a claim that nothing
        // happened and the rows below the rail are proof that something did.
        let moves = accounts.reduce(0) { $0 + $1.moveCount }
        if moves > 0 { return finish(.moved(count: moves)) }
        return finish(.quiet(watching: max(watching, 1)))
    }

    /// The account shape the head reads. A plain value so this file stays
    /// Foundation-only and the harness can build one without a `ModelContext`.
    struct Account: Equatable, Sendable {
        var nullifierCount: Int
        var frameCount: Int
        var sponsoredCount: Int
        var roots: [PrivacyDevnetRoots.Reference]
        /// How many transactions the walk saw for this address (prd §610).
        ///
        /// **Defaulted, so every existing caller keeps its meaning**, and read
        /// only to separate "did nothing" from "did something that was not a
        /// pool spend" — never to rank, since a transfer is not evidence about
        /// the pool either way.
        var moveCount: Int

        init(nullifierCount: Int = 0, frameCount: Int = 0, sponsoredCount: Int = 0,
             roots: [PrivacyDevnetRoots.Reference] = [], moveCount: Int = 0) {
            self.nullifierCount = nullifierCount
            self.frameCount = frameCount
            self.sponsoredCount = sponsoredCount
            self.roots = roots
            self.moveCount = moveCount
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
        case .unwatched:
            return String(localized: "Watch an address to see what it did on this chain.")
        case .reading:
            return String(localized: "Reading the chain…")
        case .quiet(let watching):
            return watching == 1
                ? String(localized: "Nothing on this chain from the address you watch, yet.")
                : String(localized: "Nothing on this chain from the \(watching) addresses you watch, yet.")
        case .moved(let n):
            // **NO ADDRESS CLAUSE.** `quiet` names the addresses because its
            // whole point is that nothing of theirs exists; here the subject
            // is what happened, and a plural that has to agree with the watch
            // count buys four sentences for no reader.
            return n == 1
                ? String(localized: "One transaction, and it has not spent from the pool.")
                : String(localized: "\(n) transactions, and none has spent from the pool yet.")
        case .spends(let n):
            return n == 1
                ? String(localized: "One spend, on a key that can't be used again.")
                : String(localized: "\(n) spends, each on a key that can't be used again.")
        case .rootLive(_, let sources):
            // **THE SENTENCE SAYS THE STATE; THE RING SAYS THE CLOCK (prd
            // §598).** This carried both — "…for another 4,096 slots" — which
            // is two facts in the largest type on the card, and the second of
            // them in a unit nobody outside this devnet can size. The ring
            // beneath it draws every snapshot at its own age and prints the
            // freshest one's remaining life in words, which is where a clock
            // belongs; the measured slot count travels with it in the caption.
            //
            // `remaining` stays on the case rather than being dropped: it is
            // what RANKS the leading reference in `head`, and the value the
            // head chose is the value the ring's own reading is taken from.
            return sources == 1
                ? String(localized: "A proof here still names a snapshot the chain remembers.")
                : String(localized: "Proofs here name \(sources) snapshots the chain still remembers.")
        case .rootsAged(let count):
            return count == 1
                ? String(localized: "The snapshot this address proved against has left the chain's memory. The transaction stands.")
                : String(localized: "The \(count) snapshots this address proved against have left the chain's memory. The transactions stand.")
        }
    }
}
