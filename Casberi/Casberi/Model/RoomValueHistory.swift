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
