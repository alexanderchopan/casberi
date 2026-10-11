import Foundation

/// A PRICE ALERT ON SOMETHING YOU WATCH (prd §1081).
///
/// Set from a token's or a stock's page, checked on this phone whenever its
/// price is read (a foreground refresh, and the background refresh iOS grants
/// `WalletBackgroundRefresh`). There is no server, so "when it crosses" means
/// "the first read after it crosses", and the setting sheet says so.
///
/// Five kinds, each a sentence a person would say:
/// - **above**: tell me when it rises to `target` (a price). Fires once, then
///   turns itself off — a level you named is news once.
/// - **below**: tell me when it falls to `target` (a price). Once, the same.
/// - **move**: tell me when it moves `target` (a fraction, 0.10 = 10%) in a
///   day, up or down. Stays on, and fires at most once a calendar day.
/// - **volume** (prd §1247): tell me when a token's day volume passes
///   `target` dollars. Tokens only (Dexscreener's pair states it). Stays on,
///   once a calendar day, as a move.
/// - **gasBelow** (prd §1247): tell me when gas on a chain falls to `target`
///   gwei. Its `ref` is the chain's (`GasPrice.ref`), not a watched row's.
///   Once, then off, as a level.
///
/// Since §1247 the alerts ride iCloud key-value storage between your devices
/// (`PriceAlertStore`), merged by id with `merged`: a copy that went off
/// stands against one still on, so a sync never re-arms a fired level.
///
/// Foundation-only: `scripts/markets-selftest.sh` compiles it whole.
struct PriceAlert: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case above, below, move, volume, gasBelow }

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
    /// When the person last changed it by hand (switched it, re-armed it) or
    /// a sweep moved its ref (§1247). Optional so the alerts stored before it
    /// decode unchanged.
    var changedAt: Date? = nil

    /// A move or a volume alert stays on after it fires; a level does not.
    var repeats: Bool { kind == .move || kind == .volume }

    /// The newest fact about this alert, for the sync's merge.
    var stamp: Date { max(createdAt, changedAt ?? .distantPast, firedAt ?? .distantPast) }

    /// Whether this read crosses the alert. `price` is the read's price (gwei
    /// for a gas alert), `change24h` its day change as a fraction, `volume24h`
    /// the token's day volume in dollars when it was read.
    func fires(price: Double, change24h: Double?, volume24h: Double? = nil,
               now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard on, price > 0 else { return false }
        switch kind {
        case .above:
            return price >= target
        case .below, .gasBelow:
            return price <= target
        case .move:
            guard let change24h, abs(change24h) >= target else { return false }
            if let firedAt, calendar.isDate(firedAt, inSameDayAs: now) { return false }
            return true
        case .volume:
            guard let volume24h, volume24h >= target else { return false }
            if let firedAt, calendar.isDate(firedAt, inSameDayAs: now) { return false }
            return true
        }
    }

    /// What the alert is after it fires: a level turns off, a move stays on.
    func afterFiring(at now: Date = .now) -> PriceAlert {
        var next = self
        next.firedAt = now
        if !repeats { next.on = false }
        return next
    }

    /// Two devices' copies of one alert, as one (§1247). A copy that is OFF —
    /// a level that fired, or one switched off — stands against a copy still
    /// ON, unless the on copy was re-armed by hand after the off copy's last
    /// fact: so a device that never saw the crossing cannot sync a fired
    /// level back on, and the person can still turn one on again. Two copies
    /// in the same state: the newest fact wins, and a repeating alert keeps
    /// the latest day it fired from either, so the second device does not
    /// fire it again that day.
    static func merged(_ x: PriceAlert, _ y: PriceAlert) -> PriceAlert {
        if x.on != y.on {
            let (off, on) = x.on ? (y, x) : (x, y)
            if let rearmed = on.changedAt, rearmed > off.stamp { return on }
            return off
        }
        let xNewer = x.stamp >= y.stamp
        var winner = xNewer ? x : y
        let other = xNewer ? y : x
        if let fired = other.firedAt,
           fired > (winner.firedAt ?? .distantPast),
           fired > (winner.changedAt ?? .distantPast) {
            winner.firedAt = fired
        }
        return winner
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
        guard kind == .above || kind == .below, price > 0 else { return nil }
        return target / price - 1
    }

    /// The custom sheet's percent (prd §1247): a move of that size in a day,
    /// up or down, typed as "7" or "7%" or "-7" (the sign is the field's, not
    /// the alert's: a move alert listens both ways). nil for nothing, zero, or
    /// a move of a whole price or more.
    static func movePercent(_ typed: String) -> Double? {
        let cleaned = typed.replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: "+", with: "")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Double(cleaned) else { return nil }
        let fraction = abs(value) / 100
        guard fraction > 0, fraction < 1 else { return nil }
        return fraction
    }

    /// A typed dollar amount ("$5M", "250k", "1,200,000") for the volume
    /// alert, or nil.
    static func dollars(_ typed: String) -> Double? {
        var cleaned = typed.replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        var scale = 1.0
        if let last = cleaned.last, let unit = ["k": 1e3, "m": 1e6, "b": 1e9][String(last)] {
            scale = unit
            cleaned.removeLast()
        }
        guard let value = Double(cleaned.trimmingCharacters(in: .whitespaces)), value > 0 else { return nil }
        return value * scale
    }
}
