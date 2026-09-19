import Foundation

/// **WHAT A ROOM HELD, OVER TIME (prd §683).**
///
/// The wallet-family rooms — Wallet, Vibenet, Hegotá, Frames, the Privacy
/// devnet — all draw the same Home: a caption, a number, a change, a line, and
/// the range chips over it. The line needs a dated series, and until now every
/// room solved that differently or not at all: the Wallet keeps
/// `WalletStore.ValueSample`s, vibenet keeps `VibenetValueSample`s, Hegotá
/// derives one by walking its moves backwards from the balance, and the
/// Privacy and Frames devnets kept nothing, which is why their Homes had no
/// line to draw.
///
/// Two ways to get a series, and the choice is a fact about the chain:
///
///   * **DERIVE** it, where every move carries its amount (Hegotá). Exact, and
///     it reaches back as far as the moves do.
///   * **SAMPLE** it — this store — where they do not. A Privacy move carries
///     frames, spend keys and roots and NO wei, because the amount is the
///     thing the pool hides. So the balance is recorded per read. That is also
///     why a shield shows as a dip: value left the address for the pool, and
///     the next sample is lower.
///
/// Samples are `WalletStore.ValueSample` deliberately, not a new type: that is
/// what `WalletRange.offered`/`clip` and `TokenChart.from(samples:)` already
/// take, so a room that records here gets the 7d / 30d / since-watched chips
/// and the plot with no further work. Its `usd` field carries the ROOM'S OWN
/// UNIT — a devnet's native ETH, not dollars — and the crown spells it through
/// its own `format`. The name is the Wallet's and is left alone rather than
/// renamed across the app for one reader's comfort.
enum RoomValueHistory {

    /// Longest a room keeps: about a day of two-minute reads, or a month of
    /// hourly ones. Bounded because this rides `UserDefaults` and a room that
    /// is left open should not grow without limit.
    static let cap = 720

    /// **A DERIVED LINE IS A DATED LINE (2026-09-10).**
    ///
    /// Hegotá and Frames reconstruct their history by walking each move's
    /// amount backwards from the balance, and both shipped that as a bare
    /// `[Double]` — no dates, so no window to clip and no range chips, which
    /// left two of the five wallet-family Homes wearing a different crown from
    /// the other three. But a move on both chains carries a `timestamp`, so
    /// the walk can date every point it produces and the whole family takes
    /// one path.
    ///
    /// `undo` is what to ADD to the running balance to step back over a move —
    /// the caller owns that sign, because the two chains state it differently
    /// (Frames holds a signed delta, Hegotá an amount plus a direction and a
    /// fee). Newest first.
    ///
    /// **All or nothing, for three reasons rather than one:** a missing
    /// amount, a missing date, and — the one that shipped as a bug — a point
    /// below zero. A balance cannot be negative, so a negative point proves
    /// the walk ran off the end of a truncated history and every point before
    /// it is a story about money the account never had. Clamping it to zero
    /// (which is what Hegotá did) is worse than abandoning it: the line then
    /// starts at a floor nobody observed and reports the growth off it as a
    /// real percentage — "+860.3%" on a devnet account, seen on the simulator.
    static func derived(balance: Decimal,
                        undoNewestFirst: [(undo: Decimal?, at: Date?)],
                        unit: Decimal,
                        now: Date = .now) -> [WalletStore.ValueSample] {
        guard !undoNewestFirst.isEmpty else { return [] }
        func eth(_ d: Decimal) -> Double { NSDecimalNumber(decimal: d / unit).doubleValue }
        var running = balance
        var out: [WalletStore.ValueSample] = [.init(at: now, usd: eth(running))]
        for move in undoNewestFirst {
            guard let undo = move.undo, let at = move.at else { return [] }
            running += undo
            if running < 0 { return [] }
            out.append(.init(at: at, usd: eth(running)))
        }
        guard out.count >= 2 else { return [] }
        // Oldest first, and never out of order: a chain that returns two moves
        // with the same second must not produce a line that goes backwards.
        return out.reversed().sorted { $0.at < $1.at }
    }

    /// Record one reading. **Writes only when the value actually moved**, so an
    /// idle room does not fill the store with a flat line — and so the first
    /// sample after a change is adjacent to the change rather than buried in
    /// a run of identical points.
    static func note(room: String, address: String, value: Double, at: Date = .now) {
        var book = book(room: room)
        let key = address.lowercased()
        var series = book[key] ?? []
        if let last = series.last, abs(last.usd - value) < 1e-12 { return }
        series.append(WalletStore.ValueSample(at: at, usd: value))
        if series.count > cap { series.removeFirst(series.count - cap) }
        book[key] = series
        write(book, room: room)
    }

    static func note(room: String, values: [(address: String, value: Double)], at: Date = .now) {
        for v in values { note(room: room, address: v.address, value: v.value, at: at) }
    }

    /// One address's series, oldest first.
    static func samples(room: String, address: String) -> [WalletStore.ValueSample] {
        book(room: room)[address.lowercased()] ?? []
    }

    /// The series across several addresses, summed point by point.
    ///
    /// **Only addresses that have a series of their own take part**, and the
    /// sum is taken over the SHORTEST of them: an address whose readings began
    /// later would otherwise make the total look like a collapse at the moment
    /// it joined, which is a drop nobody's money made (§83).
    static func combined(room: String, addresses: [String]) -> [WalletStore.ValueSample] {
        let serieses = addresses.map { samples(room: room, address: $0) }.filter { $0.count >= 2 }
        guard !serieses.isEmpty else { return [] }
        if serieses.count == 1 { return serieses[0] }
        let n = serieses.map(\.count).min() ?? 0
        guard n >= 2 else { return [] }
        return (0..<n).map { i in
            let slice = serieses.map { $0[$0.count - n + i] }
            return WalletStore.ValueSample(at: slice.map(\.at).max() ?? .now,
                                           usd: slice.reduce(0) { $0 + $1.usd })
        }
    }

    /// The demo's own history, written to the same key a real read writes, so
    /// a room reads ONE code path in both modes.
    static func installDemo(room: String, book: [String: [WalletStore.ValueSample]]) {
        var lowered: [String: [WalletStore.ValueSample]] = [:]
        for (address, series) in book { lowered[address.lowercased()] = series }
        write(lowered, room: room)
    }

    static func forget(room: String) {
        UserDefaults.standard.removeObject(forKey: key(room))
        UserDefaults.standard.removeObject(forKey: chainKey(room))
    }

    /// **A SAMPLED LINE BELONGS TO THE CHAIN IT WAS SAMPLED ON (prd §837).**
    ///
    /// A devnet is relaunched from genesis and the balances it held are gone —
    /// but this store is `UserDefaults` and survives, so the crown goes on
    /// plotting the dead chain's readings against the new one's. Reported from
    /// a device on the Privacy devnet: "Nothing on this chain from the 4
    /// addresses you watch, yet." over 1.0000 ETH and a red line falling
    /// 983,579 ETH to the floor. The sentence read the live walk, the crown
    /// read this book, and nothing reconciled them.
    ///
    /// **Only a SAMPLED room needs this.** Hegotá and Frames DERIVE their line
    /// from the moves, so a relaunch takes the moves and the line together;
    /// Privacy samples, because its moves carry no wei, and a sample outlives
    /// the chain that produced it.
    ///
    /// **Stamped here rather than cleared at the relaunch, and that is the
    /// repair.** A clear wired into the moment the genesis changes fixes every
    /// future relaunch and no device that has already crossed one — and the
    /// phone this was reported from crossed it weeks ago. A stamp is checked
    /// on every read instead, so a book with no stamp is a book from before
    /// this rule and is dropped once.
    ///
    /// `chain` is whatever identifies the chain to the caller — the Privacy
    /// seat passes its observed genesis hash. Compared case-insensitively
    /// because an RPC's hex casing is not a fact about the chain.
    static func fence(room: String, chain: String) {
        guard !belongs(stamp: UserDefaults.standard.string(forKey: chainKey(room)),
                       chain: chain) else { return }
        UserDefaults.standard.removeObject(forKey: key(room))
        UserDefaults.standard.set(chain, forKey: chainKey(room))
    }

    /// Whether a stamped book belongs to the chain being read now.
    ///
    /// Split out of `fence` so it can be DRIVEN: the decision is the whole of
    /// the rule and the rest is two `UserDefaults` calls, and a harness that
    /// had to write defaults to reach it would not be run. Its two cases are
    /// the ones that matter — **an absent stamp never belongs**, which is what
    /// repairs a device that crossed the relaunch before this rule existed,
    /// and casing is not a fact about a chain, because an RPC's hex is its own
    /// choice.
    static func belongs(stamp: String?, chain: String) -> Bool {
        guard let stamp else { return false }
        return stamp.caseInsensitiveCompare(chain) == .orderedSame
    }

    // MARK: - Storage

    private static func key(_ room: String) -> String { "room.value.history.\(room)" }
    private static func chainKey(_ room: String) -> String {
        "room.value.history.\(room).chain"
    }

    private static func book(room: String) -> [String: [WalletStore.ValueSample]] {
        guard let data = UserDefaults.standard.data(forKey: key(room)),
              let out = try? JSONDecoder().decode([String: [WalletStore.ValueSample]].self, from: data)
        else { return [:] }
        return out
    }

    private static func write(_ book: [String: [WalletStore.ValueSample]], room: String) {
        guard let data = try? JSONEncoder().encode(book) else { return }
        UserDefaults.standard.set(data, forKey: key(room))
    }
}
