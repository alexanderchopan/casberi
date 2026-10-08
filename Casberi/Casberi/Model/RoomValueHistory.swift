import Foundation

/// **WHAT A ROOM HELD, OVER TIME (prd §683).**
///
/// The wallet-family rooms — Wallet, Frames, Logos — all draw the same Home:
/// a caption, a number, a change, a line, and the range chips over it. The
/// line needs a dated series, and every room solved that differently or not
/// at all until this store: the Wallet keeps `WalletStore.ValueSample`s, and
/// the devnets kept nothing, which is why their Homes had no line to draw.
///
/// Two ways to get a series, and the choice is a fact about the chain:
///
///   * **DERIVE** it, where every move carries its amount (Frames). Exact, and
///     it reaches back as far as the moves do.
///   * **SAMPLE** it — this store — where they do not, so the balance is
///     recorded per read (Logos).
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
    /// A devnet that reconstructs its history by walking each move's amount
    /// backwards from the balance shipped that as a bare `[Double]` — no
    /// dates, so no window to clip and no range chips, which left its Home
    /// wearing a different crown from the rest of the family. But a move
    /// carries a `timestamp`, so the walk can date every point it produces and
    /// the whole family takes one path.
    ///
    /// `undo` is what to ADD to the running balance to step back over a move —
    /// the caller owns that sign, because a chain states it its own way
    /// (Frames holds a signed delta). Newest first.
    ///
    /// **All or nothing, for three reasons rather than one:** a missing
    /// amount, a missing date, and — the one that shipped as a bug — a point
    /// below zero. A balance cannot be negative, so a negative point proves
    /// the walk ran off the end of a truncated history and every point before
    /// it is a story about money the account never had. Clamping it to zero
    /// (which a devnet room once did) is worse than abandoning it: the line then
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

    /// Drop one series, so the line starts again from the next reading — for
    /// a total whose MEMBERS changed (an app hidden), where joining the old
    /// line to the new one would draw a move nobody's money made (§83).
    static func forget(room: String, address: String) {
        var book = book(room: room)
        guard book.removeValue(forKey: address.lowercased()) != nil else { return }
        write(book, room: room)
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

    // MARK: - Storage

    private static func key(_ room: String) -> String { "room.value.history.\(room)" }

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
