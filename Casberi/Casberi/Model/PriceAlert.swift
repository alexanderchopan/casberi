import Foundation

/// A PRICE ALERT ON SOMETHING YOU WATCH (prd §1081).
///
/// Set from a token's or a stock's page, checked on this phone whenever its
/// price is read (a foreground refresh, and the background refresh iOS grants
/// `WalletBackgroundRefresh`). There is no server, so "when it crosses" means
/// "the first read after it crosses", and the setting sheet says so.
///
/// Three kinds, each a sentence a person would say:
/// - **above**: tell me when it rises to `target` (a price). Fires once, then
///   turns itself off — a level you named is news once.
/// - **below**: tell me when it falls to `target` (a price). Once, the same.
/// - **move**: tell me when it moves `target` (a fraction, 0.10 = 10%) in a
///   day, up or down. Stays on, and fires at most once a calendar day.
///
/// Foundation-only: `scripts/price-alert-selftest.sh` compiles it whole.
struct PriceAlert: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case above, below, move }

    var id: UUID = UUID()
    /// The watched row's `sourceRef` (`tokens:<chain>:<address>` or
    /// `stocktwits:sym:<TICKER>`), so an alert outlives a rename.
    var ref: String
    /// What the notification and the Alerts tile call it.
    var name: String
    var kind: Kind
    /// A price for above/below, a fraction for move.
    var target: Double
    var on: Bool = true
    var createdAt: Date = .now
    /// When it last fired, for move's once-a-day rule and the Alerts tile.
    var firedAt: Date? = nil

    /// Whether this read crosses the alert. `price` is the read's price,
    /// `change24h` its day change as a fraction.
    func fires(price: Double, change24h: Double?, now: Date = .now,
               calendar: Calendar = .current) -> Bool {
        guard on, price > 0 else { return false }
        switch kind {
        case .above:
            return price >= target
        case .below:
            return price <= target
        case .move:
            guard let change24h, abs(change24h) >= target else { return false }
            if let firedAt, calendar.isDate(firedAt, inSameDayAs: now) { return false }
            return true
        }
    }

    /// What the alert is after it fires: a level turns off, a move stays on.
    func afterFiring(at now: Date = .now) -> PriceAlert {
        var next = self
        next.firedAt = now
        if kind != .move { next.on = false }
        return next
    }

    /// The choices the sheet offers, from the price now (prd §1081, the
    /// list that replaced the number pad): 10% and 25% above, 10% below, and
    /// a 10% day move. Each is a real level computed from a real price.
    static func choices(ref: String, name: String, price: Double) -> [PriceAlert] {
        guard price > 0 else { return [] }
        return [
            PriceAlert(ref: ref, name: name, kind: .above, target: price * 1.10),
            PriceAlert(ref: ref, name: name, kind: .above, target: price * 1.25),
            PriceAlert(ref: ref, name: name, kind: .below, target: price * 0.90),
            PriceAlert(ref: ref, name: name, kind: .move, target: 0.10),
        ]
    }

    /// How far a level sits from the price now, as a signed fraction.
    func distance(from price: Double) -> Double? {
        guard kind != .move, price > 0 else { return nil }
        return target / price - 1
    }
}
