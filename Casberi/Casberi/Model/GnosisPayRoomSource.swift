import Foundation
import SwiftData

/// The Gnosis Pay room head's reading half (2026-08-10, prd §348) — landed
/// rows turned into the card's own value, with every judgement left to
/// `GnosisPayRoom`.
///
/// The split is `CursorRoomSource`'s. Everything that could be wrong in a way
/// that still renders perfectly — currencies summed into one figure, a spend
/// with no readable amount counted as zero, a month-on-month claim made against
/// a window the room never observed — lives on the other side of that line, in
/// a file the harness compiles whole.
enum GnosisPayRoomSource {

    /// The bridge's own source name, taken from the bridge rather than spelled
    /// again — see `PeerBridge.sourceName`.
    static let source = GnosisPayBridge.sourceName

    /// The card draws at most this many currency rows. A Gnosis Pay account can
    /// hold three (EURe, GBPe, USDCe) and the cap is deliberately all of them:
    /// unlike a rail or a repository board, this set is closed and small, so
    /// there is nothing to hide behind a "1 more".
    static let rowCap = 3

    /// The head, or nil when there is nothing worth drawing.
    @MainActor
    static func compose(things: [Thing] = [], now: Date = .now) -> GnosisPayRoom? {
        // Live at the BOUNDARY, before any stored property is read
        // (corollary 4).
        let rows = things.live.filter { $0.source == source }
        guard !rows.isEmpty else { return nil }
        let room = GnosisPayRoom.compose(spends: rows.map(sighting), now: now)
        return room.isEmpty ? nil : room
    }

    /// One landed row, reduced to what the head reads. The ONLY place a `Thing`
    /// is touched.
    ///
    /// `priceValue`/`priceCurrency` are read as DATA — never `transferAmount`,
    /// which is the token-denominated display string ("12.4 EURe") and would
    /// have to be parsed back apart, and never the title, which is prose.
    @MainActor
    private static func sighting(_ thing: Thing) -> GnosisPayRoom.Sighting {
        GnosisPayRoom.Sighting(amount: thing.priceValue,
                               currency: thing.priceCurrency,
                               at: thing.capturedAt)
    }

    /// The probe's lines — driven by `-gnosisPayRoomProbe`, calling the REAL
    /// `compose`. `now` is taken so a run can be composed against a fixed clock
    /// and the window boundaries checked.
    ///
    /// It exists because a thin or empty head has FIVE causes that render as
    /// one silence, and only the last two are bugs:
    ///
    ///   1. no wallet is watched, or none of them is a card account — most
    ///      wallets hold no Gnosis Pay card, which is why the seat is gated on
    ///      a SPEND rather than on a watch;
    ///   2. the card exists and was not used in the last 30 days — a real
    ///      answer the card states out loud;
    ///   3. the room is younger than 60 days, so no comparison is possible and
    ///      `prior` is nil throughout — correct, and easily read as a missing
    ///      feature;
    ///   4. every spend landed with no `priceValue`, which means the token's
    ///      decimals never resolved and every amount is unreadable while the
    ///      rows still show a title;
    ///   5. `priceCurrency` missing while the amount is there, which drops the
    ///      spend from every total with nothing on screen to say so.
    @MainActor
    static func probeLines(things: [Thing], now: Date = .now) -> [String] {
        let rows = things.live.filter { $0.source == source }
        let sightings = rows.map(sighting)
        var out: [String] = [
            "gnosisPayRoom| source=\(source) handed=\(things.count) gpRows=\(rows.count)"
                + " windowDays=\(GnosisPayRoom.windowDays)"
                + " windowFrom=\(GnosisPayRoom.windowStart(now, back: 1).formatted(.iso8601))"
                + " priorFrom=\(GnosisPayRoom.windowStart(now, back: 2).formatted(.iso8601))",
        ]
        // Every spend as data, newest first — the pairing of amount AND
        // currency is the tell, since either one missing silently removes the
        // row from the total while the row itself draws perfectly.
        for sight in sightings.sorted(by: { $0.at > $1.at }) {
            let window = sight.at >= GnosisPayRoom.windowStart(now, back: 1) ? "window"
                : (sight.at >= GnosisPayRoom.windowStart(now, back: 2) ? "prior" : "older")
            out.append("gnosisPaySpend| amount=\(sight.amount.map { String($0) } ?? "UNREADABLE")"
                       + " currency=\(sight.currency ?? "NONE")"
                       + " in=\(window)"
                       + " at=\(sight.at.formatted(.iso8601))")
        }
        guard let room = compose(things: things, now: now) else {
            out.append("compose=nil — no card (no card account among the watched"
                       + " wallets, so nothing has ever settled)")
            return out
        }
        out.append("headline=\(GnosisPayRoom.headline(room))")
        out.append("note=\(GnosisPayRoom.note(room))")
        out.append("footnote=\(GnosisPayRoom.footnote(room, now: now) ?? "none")")
        out.append("totals| currencies=\(room.currencies.count) windowSpends=\(room.spends)"
                   + " unpriced=\(room.unpriced) allTime=\(room.allTime)"
                   + " oldest=\(room.oldest?.formatted(.iso8601) ?? "none")"
                   + " knowsPrior=\(GnosisPayRoom.knowsPriorWindow(oldest: room.oldest, now: now) ? "YES" : "no — no comparison will be claimed")")
        // The history strip, which supersedes `FeedInsight.cardMonths`. An
        // EMPTY strip has three causes and only the last is a bug: fewer than
        // two months of history, a lead currency whose own months are thin
        // while another currency's are not, or a month key that failed to
        // resolve. The counts say which.
        out.append("gnosisPayHistory| months=\(room.months.count)"
                   + " hidden=\(room.monthsHidden)"
                   + " otherCurrency=\(room.monthsOtherCurrency)"
                   + " caption=\(GnosisPayRoom.historyNote(room) ?? "none")")
        let peak = room.months.map(\.total).max() ?? 0
        for month in room.months {
            out.append("gnosisPayMonth| \(GnosisPayRoom.monthLabel(month.start))"
                       + " (key=\(month.key))"
                       + " total=\(month.total) spends=\(month.spends)"
                       + " share=\(String(format: "%.2f", GnosisPayRoom.monthShare(total: month.total, of: peak)))")
        }
        let top = room.lead?.spends ?? 0
        for currency in room.currencies.prefix(rowCap) {
            out.append("gnosisPayCurrency| \(currency.code)"
                       + " · \(GnosisPayRoom.currencyLine(currency))"
                       + " · prior=\(currency.prior.map { String($0) } ?? "unknown")"
                       + " · delta=\(GnosisPayRoom.deltaLabel(currency) ?? "none")"
                       + " · share=\(String(format: "%.2f", GnosisPayRoom.share(spends: currency.spends, of: top)))")
        }
        return out
    }
}
