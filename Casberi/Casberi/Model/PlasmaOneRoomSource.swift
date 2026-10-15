import Foundation
import SwiftData

/// The Plasma One room head's reading half (2026-10-15, prd §1311) — landed
/// day rows turned into the shared card head, with every judgement left to
/// `CardSpendRoom`. MetaMask Card's split exactly; what differs is stated:
///
/// - **The unit is a DAY.** Each row is one day's settlement
///   (`PlasmaOneCard`'s header), so the head is composed with
///   `.settledDay` and every count it draws reads "N days of spending". The
///   totals are untouched — a day's money is the same money.
/// - **The card's balance rides along**, read off the card contract at the last
///   sync. It is the only onchain card whose balance is one plain read, and it
///   is never added to the window's total.
enum PlasmaOneRoomSource {

    static let source = PlasmaOneCard.source

    static let rowCap = CardSpendRoom.rowCap

    /// The head, or nil when there is nothing worth drawing.
    @MainActor
    static func compose(things: [Thing] = [], now: Date = .now) -> CardSpendRoom? {
        let rows = things.live.filter { CardSpendSeat.isSpend($0, seat: source) }
        guard !rows.isEmpty else { return nil }
        var room = CardSpendRoom.compose(spends: rows.map(sighting), now: now,
                                         unit: .settledDay)
        guard !room.isEmpty else { return nil }
        let watched = Set(WalletStore.shared.addresses.map { $0.address.lowercased() })
        if let b = PlasmaOneCard.balance(watched: watched) {
            room.balance = .init(amount: b.amount, code: "USD", at: b.at)
        }
        return room
    }

    /// One landed day, reduced to what the head reads — `priceValue` and
    /// `priceCurrency` as data, never the title.
    @MainActor
    private static func sighting(_ thing: Thing) -> CardSpendRoom.Sighting {
        CardSpendRoom.Sighting(amount: thing.priceValue,
                               currency: thing.priceCurrency,
                               at: thing.capturedAt)
    }

    /// `-plasmaOneRoomProbe YES` — the head's whole reading, one line each,
    /// off the REAL `compose`.
    @MainActor
    static func probeLines(things: [Thing], now: Date = .now) -> [String] {
        let rows = things.live.filter { CardSpendSeat.isSpend($0, seat: source) }
        var out = ["plasmaOneRoom| handed=\(things.count) days=\(rows.count)"]
        for row in rows.sorted(by: { $0.capturedAt > $1.capturedAt }) {
            out.append("plasmaOneDay| amount=\(row.priceValue.map { String($0) } ?? "UNREADABLE")"
                       + " currency=\(row.priceCurrency ?? "NONE")"
                       + " at=\(row.capturedAt.formatted(.iso8601))")
        }
        guard let room = compose(things: things, now: now) else {
            out.append("compose=nil — no day has settled for a watched wallet")
            return out
        }
        out.append("headline=\(CardSpendRoom.headline(room))")
        out.append("note=\(CardSpendRoom.note(room))")
        out.append("balance=\(room.balance.map { CardSpendRoom.balanceLine($0) } ?? "none")")
        out.append("footnote=\(CardSpendRoom.footnote(room, now: now) ?? "none")")
        for currency in room.currencies.prefix(rowCap) {
            out.append("plasmaOneCurrency| \(currency.code) · "
                       + CardSpendRoom.currencyLine(currency, unit: room.unit))
        }
        return out
    }
}
